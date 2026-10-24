"""Services d'authentification transverses : logging structuré, helpers
requête HTTP, et vérification TOTP pour le compte admin protégé par 2FA.
"""

import base64
import hashlib
import hmac
import logging
import os
import struct
import time
from datetime import datetime, timezone
from typing import Optional

from fastapi import Request

AUTH_LOGGER = logging.getLogger("watchtracker.auth")

ADMIN_BOOTSTRAP_EMAIL = os.getenv("ADMIN_BOOTSTRAP_EMAIL", "").strip().lower()
ADMIN_2FA_EMAIL = (
    os.getenv("ADMIN_2FA_EMAIL", "").strip().lower()
    or ADMIN_BOOTSTRAP_EMAIL
    or "admin@watchtracker.net"
)
ADMIN_2FA_TOTP_SECRET = os.getenv("ADMIN_2FA_TOTP_SECRET", "").strip()
ADMIN_2FA_TOTP_WINDOW_STEPS = int(os.getenv("ADMIN_2FA_TOTP_WINDOW_STEPS", "1"))
ADMIN_2FA_TOTP_PERIOD_SECONDS = int(os.getenv("ADMIN_2FA_TOTP_PERIOD_SECONDS", "30"))
ADMIN_2FA_TOTP_DIGITS = int(os.getenv("ADMIN_2FA_TOTP_DIGITS", "6"))


def _auth_log(level: int, event: str, **fields: object) -> None:
    parts = [f"event={event}"]
    for key, value in fields.items():
        parts.append(f"{key}={value}")
    AUTH_LOGGER.log(level, " ".join(parts))


def _client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for", "")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip() or "unknown"
    return request.client.host if request.client is not None else "unknown"


def _millis_to_utc(value: Optional[int]) -> Optional[datetime]:
    if value is None:
        return None
    return datetime.fromtimestamp(value / 1000, tz=timezone.utc)


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
        expected = str(binary_code % (10**ADMIN_2FA_TOTP_DIGITS)).zfill(
            ADMIN_2FA_TOTP_DIGITS
        )
        if hmac.compare_digest(expected, code):
            return True
    return False
