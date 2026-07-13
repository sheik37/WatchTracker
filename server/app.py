from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import asyncio
import base64
from collections import deque
from dataclasses import dataclass, field
import html
import hmac
import hashlib
import json
import logging
import math
import os
import struct
import time
from typing import Optional
from urllib import request as urllib_request
from urllib import parse as urllib_parse
from starlette.responses import RedirectResponse

from db import initialize_schema
from crud import (
    complete_email_delivery_slot,
    create_email_verification_token,
    create_password_reset_token_for_email,
    create_verification_token_for_email,
    delete_user_by_id,
    get_user_profile,
    get_user_id_from_token,
    delete_watchlist,
    get_anime_structure,
    list_all_episode_progress,
    authenticate_user,
    issue_session_tokens_for_user,
    list_anime_structures,
    list_episode_progress,
    list_watchlist,
    normalize_title,
    purge_expired_tokens,
    get_rate_limit_retry_after,
    register_rate_limit_failure,
    register_rate_limit_success,
    register_user,
    reserve_email_delivery_slot,
    revoke_refresh_token,
    rotate_refresh_token,
    reset_password_with_token,
    verify_email_token,
    revoke_auth_token,
    replace_episode_progress,
    update_watch_status,
    update_watch_total,
    upsert_anime_structure,
    upsert_watchlist,
)
from schemas import (
    AuthLoginIn,
    AuthForgotPasswordIn,
    AuthLogoutIn,
    AuthMeOut,
    AuthRefreshIn,
    AuthResetPasswordIn,
    AuthRegisterIn,
    AuthRegisterOut,
    AuthResendVerificationIn,
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
        self._ip_failures: dict[str, deque[float]] = {}
        self._ip_last_alert_at: dict[str, float] = {}
        self._lock = asyncio.Lock()

    async def get_retry_after(self, endpoint: str, ip: str) -> tuple[float, Optional[int]]:
        return get_rate_limit_retry_after(endpoint, ip)

    async def register_failure(self, endpoint: str, ip: str) -> tuple[float, int, Optional[int], int, bool]:
        now = time.time()
        delay, remaining_attempts, blocked_until = register_rate_limit_failure(
            endpoint=endpoint,
            scope_key=ip,
            window_seconds=self.window_seconds,
            free_attempts=self.free_attempts,
            base_delay_seconds=self.base_delay_seconds,
            max_delay_seconds=self.max_delay_seconds,
        )
        async with self._lock:
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
        register_rate_limit_success(endpoint, ip)


auth_rate_limiter = _AuthRateLimiter()
BREVO_API_URL = "https://api.brevo.com/v3/smtp/email"
BREVO_API_KEY = os.getenv("BREVO_API_KEY", "").strip()
BREVO_SENDER_EMAIL = os.getenv("BREVO_SENDER_EMAIL", "").strip()
BREVO_SENDER_NAME = os.getenv("BREVO_SENDER_NAME", "WatchTracker").strip() or "WatchTracker"
RESET_PASSWORD_LINK_BASE_URL = os.getenv("RESET_PASSWORD_LINK_BASE_URL", "").strip()
_EMAIL_DAILY_SEND_LIMIT_RAW = os.getenv("EMAIL_DAILY_SEND_LIMIT", "").strip()
EMAIL_DAILY_SEND_LIMIT = int(_EMAIL_DAILY_SEND_LIMIT_RAW) if _EMAIL_DAILY_SEND_LIMIT_RAW else None
EMAIL_DAILY_ALERT_THRESHOLDS = (70, 85, 95)
ADMIN_BOOTSTRAP_EMAIL = os.getenv("ADMIN_BOOTSTRAP_EMAIL", "").strip().lower()
ADMIN_2FA_EMAIL = os.getenv("ADMIN_2FA_EMAIL", "").strip().lower() or ADMIN_BOOTSTRAP_EMAIL or "admin@watchtracker.net"
ADMIN_2FA_TOTP_SECRET = os.getenv("ADMIN_2FA_TOTP_SECRET", "").strip()
ADMIN_2FA_TOTP_WINDOW_STEPS = int(os.getenv("ADMIN_2FA_TOTP_WINDOW_STEPS", "1"))
ADMIN_2FA_TOTP_PERIOD_SECONDS = int(os.getenv("ADMIN_2FA_TOTP_PERIOD_SECONDS", "30"))
ADMIN_2FA_TOTP_DIGITS = int(os.getenv("ADMIN_2FA_TOTP_DIGITS", "6"))


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


def _email_rate_key(email: str) -> str:
    return f"email:{email.strip().lower()}"


def _clean_otp_code(value: Optional[str]) -> str:
    if value is None:
        return ""
    return "".join(ch for ch in value if ch.isdigit())


def _admin_2fa_required_for_email(email: str) -> bool:
    normalized_email = email.strip().lower()
    return bool(ADMIN_2FA_EMAIL and normalized_email == ADMIN_2FA_EMAIL)


def _verify_admin_totp_code(code: str) -> bool:
    try:
        secret = ADMIN_2FA_TOTP_SECRET.replace(" ", "").upper()
        key = base64.b32decode(secret, casefold=True)
    except Exception:
        return False
    if not code.isdigit() or len(code) != ADMIN_2FA_TOTP_DIGITS:
        return False
    now_counter = int(time.time() // ADMIN_2FA_TOTP_PERIOD_SECONDS)
    for offset in range(-ADMIN_2FA_TOTP_WINDOW_STEPS, ADMIN_2FA_TOTP_WINDOW_STEPS + 1):
        counter = now_counter + offset
        if counter < 0:
            continue
        msg = struct.pack(">Q", counter)
        digest = hmac.new(key, msg, hashlib.sha1).digest()
        truncated = digest[digest[-1] & 0x0F : (digest[-1] & 0x0F) + 4]
        binary_code = struct.unpack(">I", truncated)[0] & 0x7FFFFFFF
        expected = str(binary_code % (10 ** ADMIN_2FA_TOTP_DIGITS)).zfill(ADMIN_2FA_TOTP_DIGITS)
        if hmac.compare_digest(expected, code):
            return True
    return False


async def _get_auth_retry_after(endpoint: str, ip: str, email: str) -> tuple[float, Optional[int]]:
    ip_retry_after, ip_reset = await auth_rate_limiter.get_retry_after(endpoint, ip)
    email_retry_after, email_reset = await auth_rate_limiter.get_retry_after(endpoint, _email_rate_key(email))
    if email_retry_after > ip_retry_after:
        return email_retry_after, email_reset
    return ip_retry_after, ip_reset


async def _register_auth_failure(endpoint: str, ip: str, email: str) -> tuple[float, int, Optional[int], int, bool]:
    ip_result = await auth_rate_limiter.register_failure(endpoint, ip)
    await auth_rate_limiter.register_failure(endpoint, _email_rate_key(email))
    return ip_result


async def _register_auth_success(endpoint: str, ip: str, email: str) -> None:
    await auth_rate_limiter.register_success(endpoint, ip)
    await auth_rate_limiter.register_success(endpoint, _email_rate_key(email))


def _send_brevo_email(payload: dict, email_type: str) -> None:
    if not BREVO_API_KEY or not BREVO_SENDER_EMAIL:
        raise RuntimeError("Brevo email settings are missing")
    slot_id: Optional[int] = None
    count_after_reservation: Optional[int] = None
    if EMAIL_DAILY_SEND_LIMIT is not None and EMAIL_DAILY_SEND_LIMIT > 0:
        slot = reserve_email_delivery_slot(email_type, EMAIL_DAILY_SEND_LIMIT)
        if slot is None:
            raise RuntimeError("email_daily_limit_reached")
        slot_id = slot["slot_id"]
        count_after_reservation = slot["count_after_reservation"]
        usage_percent = int((count_after_reservation * 100) / EMAIL_DAILY_SEND_LIMIT)
        for threshold in EMAIL_DAILY_ALERT_THRESHOLDS:
            if usage_percent >= threshold and count_after_reservation == math.ceil((EMAIL_DAILY_SEND_LIMIT * threshold) / 100):
                _auth_log(
                    logging.WARNING,
                    "email_daily_quota_threshold",
                    email_type=email_type,
                    threshold_percent=threshold,
                    sent_today=count_after_reservation,
                    daily_limit=EMAIL_DAILY_SEND_LIMIT,
                )
    req = urllib_request.Request(
        BREVO_API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "accept": "application/json",
            "api-key": BREVO_API_KEY,
            "content-type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib_request.urlopen(req, timeout=10):
            pass
    except Exception:
        if slot_id is not None:
            complete_email_delivery_slot(slot_id, delivered=False)
        raise
    if slot_id is not None:
        complete_email_delivery_slot(slot_id, delivered=True)


def _send_verification_email(email: str, verify_link: str) -> None:
    payload = {
        "sender": {
            "name": BREVO_SENDER_NAME,
            "email": BREVO_SENDER_EMAIL,
        },
        "to": [{"email": email}],
        "subject": "Active ton compte WatchTracker",
        "htmlContent": (
            "<p>Bienvenue sur WatchTracker 👋</p>"
            "<p>Pour activer ton compte, clique sur le lien ci-dessous :</p>"
            f"<p><a href=\"{verify_link}\">{verify_link}</a></p>"
            "<p>Si tu n'es pas à l'origine de cette inscription, ignore cet email.</p>"
        ),
    }
    _send_brevo_email(payload, email_type="verification")


def _build_password_reset_link(request: Request, reset_token: str) -> str:
    if RESET_PASSWORD_LINK_BASE_URL:
        base_url = RESET_PASSWORD_LINK_BASE_URL.rstrip("/")
    else:
        base_url = str(request.base_url).rstrip("/")
    encoded_token = urllib_parse.quote(reset_token, safe="")
    return f"{base_url}/auth/reset-password?token={encoded_token}"


def _send_password_reset_email(email: str, reset_link: str) -> None:
    payload = {
        "sender": {
            "name": BREVO_SENDER_NAME,
            "email": BREVO_SENDER_EMAIL,
        },
        "to": [{"email": email}],
        "subject": "Réinitialisation de ton mot de passe WatchTracker",
        "htmlContent": (
            "<p>Une demande de réinitialisation de mot de passe a été reçue.</p>"
            "<p>Clique sur le lien ci-dessous pour choisir un nouveau mot de passe :</p>"
            f"<p><a href=\"{reset_link}\">{reset_link}</a></p>"
            "<p>Ce lien expire rapidement. Si tu n'es pas à l'origine de cette demande, ignore cet email.</p>"
        ),
    }
    _send_brevo_email(payload, email_type="password_reset")


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
    if request.url.path.startswith("/auth/reset-password"):
        response.headers["Content-Security-Policy"] = "default-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
    else:
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


@app.post("/auth/register", response_model=AuthRegisterOut, status_code=201)
async def auth_register(payload: AuthRegisterIn, request: Request) -> AuthRegisterOut:
    ip = _client_ip(request)
    email = payload.email.strip().lower()
    retry_after, reset_epoch = await _get_auth_retry_after("register", ip, email)
    if retry_after > 0:
        _auth_log(
            logging.WARNING,
            "auth_rate_limited",
            endpoint="register",
            ip=ip,
            email=email,
            retry_after=int(retry_after) + 1,
        )
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=_rate_limit_headers(retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch),
        )

    try:
        user: Optional[dict] = None
        user = register_user(payload.email, payload.password)
        verification_token = create_email_verification_token(user["user_id"])
        verify_link = f"{str(request.base_url).rstrip('/')}/auth/verify-email?token={verification_token}"
        _send_verification_email(user["email"], verify_link)
    except ValueError as exc:
        delay, remaining_attempts, blocked_until, ip_failures, should_alert = await _register_auth_failure("register", ip, email)
        _auth_log(
            logging.WARNING,
            "auth_register_failed",
            ip=ip,
            email=email,
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
        if str(exc) == "email_already_exists":
            raise HTTPException(
                status_code=409,
                detail="Email already exists",
                headers=_rate_limit_headers(
                    remaining_attempts=remaining_attempts,
                    retry_after_seconds=delay if delay > 0 else None,
                    reset_epoch_seconds=blocked_until,
                ),
            )
        if str(exc) == "password_too_short":
            raise HTTPException(status_code=400, detail="Password must contain at least 10 characters")
        if str(exc) == "password_too_weak":
            raise HTTPException(status_code=400, detail="Password must include lower, upper, digit, and symbol")
        if str(exc) == "password_reused":
            raise HTTPException(status_code=400, detail="Password was already used recently")
        raise
    except Exception as exc:
        if user is not None and user.get("created_new"):
            delete_user_by_id(user["user_id"])
        if isinstance(exc, RuntimeError) and str(exc) == "email_daily_limit_reached":
            _auth_log(logging.ERROR, "email_quota_limit_reached", endpoint="register", ip=ip, email=email)
            raise HTTPException(status_code=503, detail="Daily email limit reached")
        _auth_log(logging.ERROR, "auth_register_failed", ip=ip, email=email, reason="email_delivery_failed")
        raise HTTPException(status_code=503, detail="Email delivery failed")
    await _register_auth_success("register", ip, email)
    _auth_log(logging.INFO, "auth_register_success", ip=ip, email=email)
    return AuthRegisterOut(message="Verification email sent")


@app.post("/auth/login", response_model=AuthTokenOut)
async def auth_login(payload: AuthLoginIn, request: Request) -> AuthTokenOut:
    ip = _client_ip(request)
    email = payload.email.strip().lower()
    retry_after, reset_epoch = await _get_auth_retry_after("login", ip, email)
    if retry_after > 0:
        _auth_log(
            logging.WARNING,
            "auth_rate_limited",
            endpoint="login",
            ip=ip,
            email=email,
            retry_after=int(retry_after) + 1,
        )
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=_rate_limit_headers(retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch),
        )

    try:
        user = authenticate_user(payload.email, payload.password)
    except ValueError as exc:
        if str(exc) == "email_not_verified":
            _auth_log(logging.WARNING, "auth_login_failed", ip=ip, email=email, reason="email_not_verified")
            raise HTTPException(status_code=403, detail="Email not verified")
        raise
    if user is None:
        delay, remaining_attempts, blocked_until, ip_failures, should_alert = await _register_auth_failure("login", ip, email)
        _auth_log(
            logging.WARNING,
            "auth_login_failed",
            ip=ip,
            email=email,
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
    if _admin_2fa_required_for_email(email):
        if not ADMIN_2FA_TOTP_SECRET:
            _auth_log(logging.ERROR, "auth_login_failed", ip=ip, email=email, reason="admin_2fa_misconfigured")
            raise HTTPException(status_code=503, detail="Admin two-factor authentication is not configured")
        otp_code = _clean_otp_code(payload.otp_code)
        if not _verify_admin_totp_code(otp_code):
            delay, remaining_attempts, blocked_until, ip_failures, should_alert = await _register_auth_failure("login", ip, email)
            _auth_log(
                logging.WARNING,
                "auth_login_failed",
                ip=ip,
                email=email,
                reason="invalid_2fa_code",
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
            detail = "Two-factor code required" if not otp_code else "Invalid two-factor code"
            raise HTTPException(
                status_code=401,
                detail=detail,
                headers=_rate_limit_headers(
                    remaining_attempts=remaining_attempts,
                    retry_after_seconds=delay if delay > 0 else None,
                    reset_epoch_seconds=blocked_until,
                ),
            )
    token = issue_session_tokens_for_user(user["user_id"])
    await _register_auth_success("login", ip, email)
    _auth_log(logging.INFO, "auth_login_success", ip=ip, email=email)
    return AuthTokenOut(
        token=token["access_token"],
        access_token=token["access_token"],
        refresh_token=token["refresh_token"],
        expires_in_seconds=token["expires_in_seconds"],
    )


@app.post("/auth/refresh", response_model=AuthTokenOut)
async def auth_refresh(payload: AuthRefreshIn, request: Request) -> AuthTokenOut:
    ip = _client_ip(request)
    retry_after, reset_epoch = await auth_rate_limiter.get_retry_after("refresh", ip)
    if retry_after > 0:
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=_rate_limit_headers(retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch),
        )
    token = rotate_refresh_token(payload.refresh_token)
    if token is None:
        _, _, blocked_until, _, _ = await auth_rate_limiter.register_failure("refresh", ip)
        raise HTTPException(
            status_code=401,
            detail="Invalid refresh token",
            headers=_rate_limit_headers(reset_epoch_seconds=blocked_until),
        )
    await auth_rate_limiter.register_success("refresh", ip)
    return AuthTokenOut(
        token=token["access_token"],
        access_token=token["access_token"],
        refresh_token=token["refresh_token"],
        expires_in_seconds=token["expires_in_seconds"],
    )


@app.get("/auth/verify-email")
def auth_verify_email(token: str = Query(min_length=20)) -> dict[str, str]:
    if verify_email_token(token):
        return {"message": "Email verified. You can now log in."}
    raise HTTPException(status_code=400, detail="Invalid or expired verification token")


@app.post("/auth/resend-verification", response_model=AuthRegisterOut, status_code=202)
async def auth_resend_verification(payload: AuthResendVerificationIn, request: Request) -> AuthRegisterOut:
    ip = _client_ip(request)
    email = payload.email.strip().lower()
    retry_after, reset_epoch = await _get_auth_retry_after("resend_verification", ip, email)
    if retry_after > 0:
        _auth_log(
            logging.WARNING,
            "auth_rate_limited",
            endpoint="resend_verification",
            ip=ip,
            email=email,
            retry_after=int(retry_after) + 1,
        )
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=_rate_limit_headers(retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch),
        )

    row = create_verification_token_for_email(email)
    if row is not None:
        verify_link = f"{str(request.base_url).rstrip('/')}/auth/verify-email?token={row['token']}"
        try:
            _send_verification_email(row["email"], verify_link)
        except Exception as exc:
            if isinstance(exc, RuntimeError) and str(exc) == "email_daily_limit_reached":
                _auth_log(logging.ERROR, "email_quota_limit_reached", endpoint="resend_verification", ip=ip, email=email)
            else:
                _auth_log(logging.ERROR, "auth_resend_verification_failed", ip=ip, email=email, reason="email_delivery_failed")
    await _register_auth_failure("resend_verification", ip, email)
    return AuthRegisterOut(
        message=(
            "Si un compte non vérifié existe pour cet email, "
            "un nouvel email de vérification a été envoyé."
        )
    )


@app.post("/auth/forgot-password", response_model=AuthRegisterOut, status_code=202)
async def auth_forgot_password(payload: AuthForgotPasswordIn, request: Request) -> AuthRegisterOut:
    ip = _client_ip(request)
    email = payload.email.strip().lower()
    retry_after, reset_epoch = await _get_auth_retry_after("forgot_password", ip, email)
    if retry_after > 0:
        _auth_log(
            logging.WARNING,
            "auth_rate_limited",
            endpoint="forgot_password",
            ip=ip,
            email=email,
            retry_after=int(retry_after) + 1,
        )
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=_rate_limit_headers(retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch),
        )

    row = create_password_reset_token_for_email(email)
    if row is not None:
        try:
            reset_link = _build_password_reset_link(request, row["token"])
            _send_password_reset_email(row["email"], reset_link)
        except Exception as exc:
            if isinstance(exc, RuntimeError) and str(exc) == "email_daily_limit_reached":
                _auth_log(logging.ERROR, "email_quota_limit_reached", endpoint="forgot_password", ip=ip, email=email)
            else:
                _auth_log(logging.ERROR, "auth_forgot_password_failed", ip=ip, email=email, reason="email_delivery_failed")
    await _register_auth_failure("forgot_password", ip, email)
    return AuthRegisterOut(message="Si un compte existe pour cet email, un email de réinitialisation a été envoyé.")


def _render_reset_password_page(token: str, message: Optional[str] = None, is_error: bool = False) -> str:
    escaped_token = html.escape(token, quote=True)
    escaped_message = html.escape(message, quote=True) if message else ""
    message_style = "color:#b91c1c;" if is_error else "color:#166534;"
    message_html = f"<p style=\"{message_style}\">{escaped_message}</p>" if message else ""
    return f"""<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Réinitialiser le mot de passe</title>
</head>
<body>
  <main>
    <h1>Réinitialiser ton mot de passe</h1>
    {message_html}
    <form method="post" action="/auth/reset-password/confirm">
      <input type="hidden" name="token" value="{escaped_token}" />
      <label for="password">Nouveau mot de passe</label><br />
      <input id="password" name="password" type="password" minlength="10" maxlength="128" required /><br /><br />
      <label for="confirm_password">Confirmer le mot de passe</label><br />
      <input id="confirm_password" name="confirm_password" type="password" minlength="10" maxlength="128" required /><br /><br />
      <button type="submit">Mettre à jour le mot de passe</button>
    </form>
  </main>
</body>
</html>"""


def _render_reset_password_success_page(message: str) -> str:
    escaped_message = html.escape(message, quote=True)
    return f"""<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Mot de passe mis à jour</title>
</head>
<body>
  <main>
    <h1>Mot de passe mis à jour</h1>
    <p style="color:#166534;">{escaped_message}</p>
  </main>
</body>
</html>"""


@app.get("/auth/reset-password", response_class=HTMLResponse)
def auth_reset_password_page(token: str = Query(min_length=20)) -> str:
    return _render_reset_password_page(token)


@app.post("/auth/reset-password/confirm", response_class=HTMLResponse)
async def auth_reset_password_confirm(request: Request) -> HTMLResponse:
    raw_body = await request.body()
    form_data = urllib_parse.parse_qs(raw_body.decode("utf-8"), keep_blank_values=True)
    token = form_data.get("token", [""])[0]
    password = form_data.get("password", [""])[0]
    confirm_password = form_data.get("confirm_password", [""])[0]

    if len(token) < 20:
        return HTMLResponse(
            _render_reset_password_page("", "Lien invalide ou expiré.", is_error=True),
            status_code=400,
        )
    if len(password) < 10 or len(password) > 128:
        return HTMLResponse(
            _render_reset_password_page(token, "Le mot de passe doit contenir entre 10 et 128 caractères.", is_error=True),
            status_code=400,
        )
    if len(confirm_password) < 10 or len(confirm_password) > 128:
        return HTMLResponse(
            _render_reset_password_page(token, "Le mot de passe doit contenir entre 10 et 128 caractères.", is_error=True),
            status_code=400,
        )
    if password != confirm_password:
        return HTMLResponse(
            _render_reset_password_page(token, "Les mots de passe ne correspondent pas.", is_error=True),
            status_code=400,
        )
    reset_result = reset_password_with_token(token, password)
    if reset_result == "password_too_short":
        return HTMLResponse(
            _render_reset_password_page(token, "Le mot de passe doit contenir au moins 10 caractères.", is_error=True),
            status_code=400,
        )
    if reset_result == "password_too_weak":
        return HTMLResponse(
            _render_reset_password_page(token, "Le mot de passe doit inclure minuscule, majuscule, chiffre et symbole.", is_error=True),
            status_code=400,
        )
    if reset_result == "same_as_current":
        _auth_log(logging.WARNING, "auth_reset_password_blocked", reason="same_as_current_password")
        return HTMLResponse(
            _render_reset_password_page(token, "Le nouveau mot de passe doit être différent de l'actuel.", is_error=True),
            status_code=400,
        )
    if reset_result == "password_reused":
        _auth_log(logging.WARNING, "auth_reset_password_blocked", reason="password_reused")
        return HTMLResponse(
            _render_reset_password_page(token, "Ce mot de passe a déjà été utilisé récemment.", is_error=True),
            status_code=400,
        )
    if reset_result != "updated":
        return HTMLResponse(
            _render_reset_password_page(token, "Lien invalide ou expiré.", is_error=True),
            status_code=400,
        )
    return HTMLResponse(
        _render_reset_password_success_page("Tu peux maintenant te connecter."),
        status_code=200,
    )


@app.post("/auth/reset-password", response_model=AuthRegisterOut)
def auth_reset_password(payload: AuthResetPasswordIn) -> AuthRegisterOut:
    reset_result = reset_password_with_token(payload.token, payload.password)
    if reset_result == "password_too_short":
        raise HTTPException(status_code=400, detail="Password must contain at least 10 characters")
    if reset_result == "password_too_weak":
        raise HTTPException(status_code=400, detail="Password must include lower, upper, digit, and symbol")
    if reset_result == "same_as_current":
        _auth_log(logging.WARNING, "auth_reset_password_blocked", reason="same_as_current_password")
        raise HTTPException(status_code=400, detail="New password must be different from current password")
    if reset_result == "password_reused":
        _auth_log(logging.WARNING, "auth_reset_password_blocked", reason="password_reused")
        raise HTTPException(status_code=400, detail="Password was already used recently")
    if reset_result != "updated":
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")
    return AuthRegisterOut(message="Password has been reset. You can now log in.")


@app.post("/auth/logout", status_code=204)
def auth_logout(
    payload: Optional[AuthLogoutIn] = None,
    user_id: int = Depends(get_current_user_id),
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> None:
    _ = user_id
    if credentials is None:
        raise HTTPException(status_code=401, detail="Missing bearer token")
    if not revoke_auth_token(credentials.credentials):
        _auth_log(logging.WARNING, "auth_logout_failed", user_id=user_id, reason="invalid_token")
        raise HTTPException(status_code=401, detail="Invalid token")
    if payload is not None and payload.refresh_token:
        revoke_refresh_token(payload.refresh_token)
    _auth_log(logging.INFO, "auth_logout_success", user_id=user_id)


@app.get("/auth/me", response_model=AuthMeOut)
def auth_me(user_id: int = Depends(get_current_user_id)) -> AuthMeOut:
    profile = get_user_profile(user_id)
    if profile is None:
        raise HTTPException(status_code=404, detail="User not found")
    return AuthMeOut(**profile)


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
