from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import asyncio
from collections import deque
from dataclasses import dataclass, field
import logging
import math
import os
import time
from typing import Optional
from starlette.responses import RedirectResponse

from db import initialize_schema
from crud import (
    get_user_id_from_token,
    delete_watchlist,
    get_anime_structure,
    list_all_episode_progress,
    login_user,
    list_anime_structures,
    list_episode_progress,
    list_watchlist,
    normalize_title,
    purge_expired_tokens,
    register_user,
    revoke_auth_token,
    replace_episode_progress,
    update_watch_status,
    update_watch_total,
    upsert_anime_structure,
    upsert_watchlist,
)
from schemas import (
    AuthLoginIn,
    AuthRegisterIn,
    AuthTokenOut,
    AnimeStructureIn,
    EpisodeProgressItemIn,
    HealthResponse,
    SyncSnapshotOut,
    WatchlistItemIn,
    WatchlistStatusUpdate,
    WatchlistTotalUpdate,
)

bearer_scheme = HTTPBearer(auto_error=False)
TOKEN_CLEANUP_INTERVAL_SECONDS = int(os.getenv("AUTH_TOKEN_CLEANUP_INTERVAL_SECONDS", "3600"))
AUTH_ALERT_WINDOW_SECONDS = int(os.getenv("AUTH_ALERT_WINDOW_SECONDS", "300"))
AUTH_ALERT_FAILURE_THRESHOLD = int(os.getenv("AUTH_ALERT_FAILURE_THRESHOLD", "10"))
AUTH_LOGGER = logging.getLogger("watchtracker.auth")


@dataclass
class _RateLimitState:
    failures: deque[float] = field(default_factory=deque)
    blocked_until: float = 0.0


class _AuthRateLimiter:
    def __init__(self) -> None:
        self.window_seconds = int(os.getenv("AUTH_RATE_LIMIT_WINDOW_SECONDS", "300"))
        self.free_attempts = int(os.getenv("AUTH_RATE_LIMIT_FREE_ATTEMPTS", "3"))
        self.base_delay_seconds = float(os.getenv("AUTH_RATE_LIMIT_BASE_DELAY_SECONDS", "3"))
        self.max_delay_seconds = float(os.getenv("AUTH_RATE_LIMIT_MAX_DELAY_SECONDS", "300"))
        self._states: dict[tuple[str, str], _RateLimitState] = {}
        self._ip_failures: dict[str, deque[float]] = {}
        self._ip_last_alert_at: dict[str, float] = {}
        self._lock = asyncio.Lock()

    def _prune(self, state: _RateLimitState, now: float) -> None:
        min_ts = now - self.window_seconds
        while state.failures and state.failures[0] < min_ts:
            state.failures.popleft()

    async def get_retry_after(self, endpoint: str, ip: str) -> tuple[float, Optional[int]]:
        now = time.time()
        key = (endpoint, ip)
        async with self._lock:
            state = self._states.get(key)
            if state is None:
                return 0.0, None
            self._prune(state, now)
            remaining = state.blocked_until - now
            if not state.failures and remaining <= 0:
                self._states.pop(key, None)
            if remaining <= 0:
                return 0.0, None
            return remaining, math.ceil(state.blocked_until)

    async def register_failure(self, endpoint: str, ip: str) -> tuple[float, int, Optional[int], int, bool]:
        now = time.time()
        key = (endpoint, ip)
        async with self._lock:
            state = self._states.setdefault(key, _RateLimitState())
            self._prune(state, now)
            state.failures.append(now)
            attempts = len(state.failures)
            delay = 0.0
            if attempts > self.free_attempts:
                exponent = attempts - self.free_attempts - 1
                delay = min(self.max_delay_seconds, self.base_delay_seconds * (2**exponent))
                state.blocked_until = max(state.blocked_until, now + delay)
            remaining_attempts = max(0, self.free_attempts - attempts)
            blocked_until = math.ceil(state.blocked_until) if state.blocked_until > now else None
            ip_state = self._ip_failures.setdefault(ip, deque())
            min_alert_ts = now - AUTH_ALERT_WINDOW_SECONDS
            while ip_state and ip_state[0] < min_alert_ts:
                ip_state.popleft()
            ip_state.append(now)
            ip_failures = len(ip_state)
            last_alert_at = self._ip_last_alert_at.get(ip, 0.0)
            should_alert = ip_failures >= AUTH_ALERT_FAILURE_THRESHOLD and (now - last_alert_at) >= AUTH_ALERT_WINDOW_SECONDS
            if should_alert:
                self._ip_last_alert_at[ip] = now
            return delay, remaining_attempts, blocked_until, ip_failures, should_alert

    async def register_success(self, endpoint: str, ip: str) -> None:
        key = (endpoint, ip)
        async with self._lock:
            self._states.pop(key, None)


auth_rate_limiter = _AuthRateLimiter()


def _auth_log(level: int, event: str, **fields: object) -> None:
    parts = [f"event={event}"]
    for key, value in fields.items():
        parts.append(f"{key}={value}")
    AUTH_LOGGER.log(level, " ".join(parts))


def _rate_limit_headers(
    remaining_attempts: Optional[int] = None,
    retry_after_seconds: Optional[float] = None,
    reset_epoch_seconds: Optional[int] = None,
) -> dict[str, str]:
    headers: dict[str, str] = {}
    if remaining_attempts is not None:
        headers["X-Auth-Attempts-Remaining"] = str(remaining_attempts)
    if retry_after_seconds is not None and retry_after_seconds > 0:
        headers["Retry-After"] = str(int(retry_after_seconds) + 1)
    if reset_epoch_seconds is not None:
        headers["X-RateLimit-Reset"] = str(reset_epoch_seconds)
    return headers


def _client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for", "")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip() or "unknown"
    return request.client.host if request.client is not None else "unknown"


async def _token_cleanup_loop() -> None:
    while True:
        await asyncio.sleep(TOKEN_CLEANUP_INTERVAL_SECONDS)
        purge_expired_tokens()


@asynccontextmanager
async def lifespan(_: FastAPI):
    token_cleanup_task: Optional[asyncio.Task] = None
    if os.getenv("RUN_MIGRATIONS", "false").lower() == "true":
        initialize_schema()
    purge_expired_tokens()
    if TOKEN_CLEANUP_INTERVAL_SECONDS > 0:
        token_cleanup_task = asyncio.create_task(_token_cleanup_loop())
    try:
        yield
    finally:
        if token_cleanup_task is not None:
            token_cleanup_task.cancel()
            try:
                await token_cleanup_task
            except asyncio.CancelledError:
                pass


app = FastAPI(title="WatchTracker API", version="0.1.0", lifespan=lifespan)


@app.middleware("http")
async def enforce_https_and_security_headers(request: Request, call_next):
    forwarded_proto = (request.headers.get("x-forwarded-proto", "").split(",")[0].strip().lower())
    forwarded_port = (request.headers.get("x-forwarded-port", "").split(",")[0].strip())
    scheme = request.url.scheme.lower()
    host = request.headers.get("host", "").split(":")[0].lower()
    is_local_host = host in {"127.0.0.1", "localhost", "::1"}
    is_external_http = forwarded_port == "80" or forwarded_proto == "http" or (
        not forwarded_proto and not forwarded_port and scheme == "http"
    )
    is_external_https = forwarded_port == "443" or forwarded_proto == "https" or (
        not forwarded_proto and not forwarded_port and scheme == "https"
    )

    if is_external_http and not is_local_host:
        response = RedirectResponse(url=str(request.url.replace(scheme="https")), status_code=308)
    else:
        response = await call_next(request)

    if is_external_https:
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
    return response


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok")


def get_current_user_id(credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme)) -> int:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Missing bearer token")
    user_id = get_user_id_from_token(credentials.credentials)
    if user_id is None:
        raise HTTPException(status_code=401, detail="Invalid token")
    return user_id


@app.post("/auth/register", response_model=AuthTokenOut, status_code=201)
async def auth_register(payload: AuthRegisterIn, request: Request) -> AuthTokenOut:
    ip = _client_ip(request)
    username = payload.username.strip().lower()
    retry_after, reset_epoch = await auth_rate_limiter.get_retry_after("register", ip)
    if retry_after > 0:
        _auth_log(
            logging.WARNING,
            "auth_rate_limited",
            endpoint="register",
            ip=ip,
            username=username,
            retry_after=int(retry_after) + 1,
        )
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=_rate_limit_headers(retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch),
        )

    try:
        token = register_user(payload.username, payload.password)
    except ValueError as exc:
        delay, remaining_attempts, blocked_until, ip_failures, should_alert = await auth_rate_limiter.register_failure("register", ip)
        _auth_log(
            logging.WARNING,
            "auth_register_failed",
            ip=ip,
            username=username,
            reason=str(exc),
            attempts_remaining=remaining_attempts,
            retry_after=(int(delay) + 1) if delay > 0 else 0,
            ip_failures=ip_failures,
        )
        if should_alert:
            _auth_log(
                logging.ERROR,
                "AUTH_ALERT",
                alert="repeated_auth_failures",
                ip=ip,
                endpoint="register",
                failures_in_window=ip_failures,
                window_seconds=AUTH_ALERT_WINDOW_SECONDS,
            )
        if str(exc) == "username_already_exists":
            raise HTTPException(
                status_code=409,
                detail="Username already exists",
                headers=_rate_limit_headers(
                    remaining_attempts=remaining_attempts,
                    retry_after_seconds=delay if delay > 0 else None,
                    reset_epoch_seconds=blocked_until,
                ),
            )
        raise
    await auth_rate_limiter.register_success("register", ip)
    _auth_log(logging.INFO, "auth_register_success", ip=ip, username=username)
    return AuthTokenOut(token=token["token"])


@app.post("/auth/login", response_model=AuthTokenOut)
async def auth_login(payload: AuthLoginIn, request: Request) -> AuthTokenOut:
    ip = _client_ip(request)
    username = payload.username.strip().lower()
    retry_after, reset_epoch = await auth_rate_limiter.get_retry_after("login", ip)
    if retry_after > 0:
        _auth_log(
            logging.WARNING,
            "auth_rate_limited",
            endpoint="login",
            ip=ip,
            username=username,
            retry_after=int(retry_after) + 1,
        )
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=_rate_limit_headers(retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch),
        )

    token = login_user(payload.username, payload.password)
    if token is None:
        delay, remaining_attempts, blocked_until, ip_failures, should_alert = await auth_rate_limiter.register_failure("login", ip)
        _auth_log(
            logging.WARNING,
            "auth_login_failed",
            ip=ip,
            username=username,
            reason="invalid_credentials",
            attempts_remaining=remaining_attempts,
            retry_after=(int(delay) + 1) if delay > 0 else 0,
            ip_failures=ip_failures,
        )
        if should_alert:
            _auth_log(
                logging.ERROR,
                "AUTH_ALERT",
                alert="repeated_auth_failures",
                ip=ip,
                endpoint="login",
                failures_in_window=ip_failures,
                window_seconds=AUTH_ALERT_WINDOW_SECONDS,
            )
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials",
            headers=_rate_limit_headers(
                remaining_attempts=remaining_attempts,
                retry_after_seconds=delay if delay > 0 else None,
                reset_epoch_seconds=blocked_until,
            ),
        )
    await auth_rate_limiter.register_success("login", ip)
    _auth_log(logging.INFO, "auth_login_success", ip=ip, username=username)
    return AuthTokenOut(token=token["token"])


@app.post("/auth/logout", status_code=204)
def auth_logout(
    user_id: int = Depends(get_current_user_id),
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> None:
    _ = user_id
    if credentials is None:
        raise HTTPException(status_code=401, detail="Missing bearer token")
    if not revoke_auth_token(credentials.credentials):
        _auth_log(logging.WARNING, "auth_logout_failed", user_id=user_id, reason="invalid_token")
        raise HTTPException(status_code=401, detail="Invalid token")
    _auth_log(logging.INFO, "auth_logout_success", user_id=user_id)


@app.get("/watchlist")
def get_watchlist(
    content_category: Optional[str] = Query(default=None),
    user_id: int = Depends(get_current_user_id),
) -> list[dict]:
    return list_watchlist(user_id, content_category)


@app.get("/sync/snapshot", response_model=SyncSnapshotOut)
def get_sync_snapshot(user_id: int = Depends(get_current_user_id)) -> SyncSnapshotOut:
    return SyncSnapshotOut(
        watchlist=list_watchlist(user_id),
        episode_progress=list_all_episode_progress(user_id),
    )


@app.post("/watchlist", status_code=201)
def create_watchlist_item(item: WatchlistItemIn, user_id: int = Depends(get_current_user_id)) -> dict:
    return upsert_watchlist(user_id, item)


@app.patch("/watchlist/{media_id}/{media_type}/{content_category}/status")
def patch_watch_status(
    media_id: int,
    media_type: str,
    content_category: str,
    payload: WatchlistStatusUpdate,
    user_id: int = Depends(get_current_user_id),
) -> dict:
    row = update_watch_status(user_id, media_id, media_type, content_category, payload.content_status)
    if row is None:
        raise HTTPException(status_code=404, detail="Watchlist item not found")
    return row


@app.patch("/watchlist/{media_id}/{media_type}/{content_category}/total-episodes")
def patch_watch_total(
    media_id: int,
    media_type: str,
    content_category: str,
    payload: WatchlistTotalUpdate,
    user_id: int = Depends(get_current_user_id),
) -> dict:
    row = update_watch_total(user_id, media_id, media_type, content_category, payload.total_episodes)
    if row is None:
        raise HTTPException(status_code=404, detail="Watchlist item not found")
    return row


@app.delete("/watchlist/{media_id}/{media_type}/{content_category}", status_code=204)
def remove_watchlist_item(
    media_id: int,
    media_type: str,
    content_category: str,
    user_id: int = Depends(get_current_user_id),
) -> None:
    delete_watchlist(user_id, media_id, media_type, content_category)


@app.get("/episode-progress/{media_id}")
def get_episode_progress(media_id: int, user_id: int = Depends(get_current_user_id)) -> list[dict]:
    return list_episode_progress(user_id, media_id)


@app.put("/episode-progress/{media_id}", status_code=204)
def put_episode_progress(
    media_id: int,
    items: list[EpisodeProgressItemIn],
    user_id: int = Depends(get_current_user_id),
) -> None:
    replace_episode_progress(user_id, media_id, items)


@app.get("/anime-structures")
def get_anime_structures(user_id: int = Depends(get_current_user_id)) -> list[dict]:
    _ = user_id
    return list_anime_structures()


@app.get("/anime-structures/{title}")
def get_anime_structure_by_title(title: str, user_id: int = Depends(get_current_user_id)) -> dict:
    _ = user_id
    row = get_anime_structure(normalize_title(title))
    if row is None:
        raise HTTPException(status_code=404, detail="Anime structure not found")
    return row


@app.put("/anime-structures")
def put_anime_structure(item: AnimeStructureIn, user_id: int = Depends(get_current_user_id)) -> dict:
    _ = user_id
    return upsert_anime_structure(item)
