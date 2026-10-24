"""Point d'entrée FastAPI : création de l'application, lifespan, middleware
de sécurité, et inclusion des routers par domaine."""

import asyncio
import os
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Request
from starlette.responses import RedirectResponse

from auth_crud import purge_expired_tokens
from db import initialize_schema
from deps import get_current_user_id  # noqa: F401 (réexporté pour dependency_overrides)
from routers import auth_router, health_router, sync_router, watchlist_router

TOKEN_CLEANUP_INTERVAL_SECONDS = int(
    os.getenv("AUTH_TOKEN_CLEANUP_INTERVAL_SECONDS", "3600")
)


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
    forwarded_proto = (
        request.headers.get("x-forwarded-proto", "").split(",")[0].strip().lower()
    )
    forwarded_port = request.headers.get("x-forwarded-port", "").split(",")[0].strip()
    scheme = request.url.scheme.lower()
    host = request.headers.get("host", "").split(":")[0].lower()
    is_local_host = host in {"127.0.0.1", "localhost", "::1"}
    is_external_http = (
        forwarded_port == "80"
        or forwarded_proto == "http"
        or (not forwarded_proto and not forwarded_port and scheme == "http")
    )
    is_external_https = (
        forwarded_port == "443"
        or forwarded_proto == "https"
        or (not forwarded_proto and not forwarded_port and scheme == "https")
    )

    if is_external_http and not is_local_host:
        response = RedirectResponse(
            url=str(request.url.replace(scheme="https")), status_code=308
        )
    else:
        response = await call_next(request)

    if is_external_https:
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains"
        )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    if request.url.path.startswith("/auth/reset-password"):
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
        )
    else:
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"
        )
    return response


app.include_router(health_router.router)
app.include_router(auth_router.router)
app.include_router(watchlist_router.router)
app.include_router(sync_router.router)
