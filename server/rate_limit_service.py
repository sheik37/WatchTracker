"""Rate limiting pour les endpoints d'authentification.

Factorise la logique de rate limiting (compteur d'échecs par IP/email,
calcul du délai avant nouvelle tentative) partagée entre les endpoints
register/login/resend-verification/forgot-password.
"""

import asyncio
import logging
import os
import time
from collections import deque
from typing import Optional

from fastapi import HTTPException

import auth_service
from rate_limit_crud import (
    get_rate_limit_retry_after,
    register_rate_limit_failure,
    register_rate_limit_success,
)

AUTH_ALERT_WINDOW_SECONDS = int(os.getenv("AUTH_ALERT_WINDOW_SECONDS", "300"))
AUTH_ALERT_FAILURE_THRESHOLD = int(os.getenv("AUTH_ALERT_FAILURE_THRESHOLD", "10"))


class _AuthRateLimiter:
    def __init__(self) -> None:
        self.window_seconds = int(os.getenv("AUTH_RATE_LIMIT_WINDOW_SECONDS", "300"))
        self.free_attempts = int(os.getenv("AUTH_RATE_LIMIT_FREE_ATTEMPTS", "3"))
        self.base_delay_seconds = float(
            os.getenv("AUTH_RATE_LIMIT_BASE_DELAY_SECONDS", "3")
        )
        self.max_delay_seconds = float(
            os.getenv("AUTH_RATE_LIMIT_MAX_DELAY_SECONDS", "300")
        )
        self._ip_failures: dict[str, deque[float]] = {}
        self._ip_last_alert_at: dict[str, float] = {}
        self._lock = asyncio.Lock()

    async def get_retry_after(
        self, endpoint: str, ip: str
    ) -> tuple[float, Optional[int]]:
        return get_rate_limit_retry_after(endpoint, ip)

    async def register_failure(
        self, endpoint: str, ip: str
    ) -> tuple[float, int, Optional[int], int, bool]:
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
            should_alert = (
                ip_failures >= AUTH_ALERT_FAILURE_THRESHOLD
                and (now - last_alert_at) >= AUTH_ALERT_WINDOW_SECONDS
            )
            if should_alert:
                self._ip_last_alert_at[ip] = now
            return delay, remaining_attempts, blocked_until, ip_failures, should_alert

    async def register_success(self, endpoint: str, ip: str) -> None:
        register_rate_limit_success(endpoint, ip)


auth_rate_limiter = _AuthRateLimiter()


def _email_rate_key(email: str) -> str:
    return f"email:{email.strip().lower()}"


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


async def _get_auth_retry_after(
    endpoint: str, ip: str, email: str
) -> tuple[float, Optional[int]]:
    ip_retry_after, ip_reset = await auth_rate_limiter.get_retry_after(endpoint, ip)
    email_retry_after, email_reset = await auth_rate_limiter.get_retry_after(
        endpoint, _email_rate_key(email)
    )
    if email_retry_after > ip_retry_after:
        return email_retry_after, email_reset
    return ip_retry_after, ip_reset


async def _register_auth_failure(
    endpoint: str, ip: str, email: str
) -> tuple[float, int, Optional[int], int, bool]:
    ip_result = await auth_rate_limiter.register_failure(endpoint, ip)
    await auth_rate_limiter.register_failure(endpoint, _email_rate_key(email))
    return ip_result


async def _register_auth_success(endpoint: str, ip: str, email: str) -> None:
    await auth_rate_limiter.register_success(endpoint, ip)
    await auth_rate_limiter.register_success(endpoint, _email_rate_key(email))


async def enforce_auth_rate_limit(endpoint: str, ip: str, email: str) -> None:
    """Helper commun : lève HTTPException 429 si le rate limit est atteint.

    Factorise la logique dupliquée entre register/login/resend/forgot qui
    vérifiait le délai de nouvelle tentative puis levait la même exception.
    """
    retry_after, reset_epoch = await _get_auth_retry_after(endpoint, ip, email)
    if retry_after > 0:
        auth_service._auth_log(
            logging.WARNING,
            "auth_rate_limited",
            endpoint=endpoint,
            ip=ip,
            email=email,
            retry_after=int(retry_after) + 1,
        )
        raise HTTPException(
            status_code=429,
            detail="Too many attempts. Try again later.",
            headers=_rate_limit_headers(
                retry_after_seconds=retry_after, reset_epoch_seconds=reset_epoch
            ),
        )
