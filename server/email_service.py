"""Envoi des emails transactionnels (vérification de compte, réinitialisation
de mot de passe) via l'API Brevo, avec suivi du quota d'envoi journalier.
"""

import json
import logging
import math
import os
from typing import Optional
from urllib import parse as urllib_parse
from urllib import request as urllib_request

from fastapi import Request

import auth_service
from rate_limit_crud import complete_email_delivery_slot, reserve_email_delivery_slot

BREVO_API_URL = "https://api.brevo.com/v3/smtp/email"
BREVO_API_KEY = os.getenv("BREVO_API_KEY", "").strip()
BREVO_SENDER_EMAIL = os.getenv("BREVO_SENDER_EMAIL", "").strip()
BREVO_SENDER_NAME = (
    os.getenv("BREVO_SENDER_NAME", "WatchTracker").strip() or "WatchTracker"
)
RESET_PASSWORD_LINK_BASE_URL = os.getenv("RESET_PASSWORD_LINK_BASE_URL", "").strip()
_EMAIL_DAILY_SEND_LIMIT_RAW = os.getenv("EMAIL_DAILY_SEND_LIMIT", "").strip()
EMAIL_DAILY_SEND_LIMIT = (
    int(_EMAIL_DAILY_SEND_LIMIT_RAW) if _EMAIL_DAILY_SEND_LIMIT_RAW else None
)
EMAIL_DAILY_ALERT_THRESHOLDS = (70, 85, 95)


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
            if usage_percent >= threshold and count_after_reservation == math.ceil(
                (EMAIL_DAILY_SEND_LIMIT * threshold) / 100
            ):
                auth_service._auth_log(
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
            f'<p><a href="{verify_link}">{verify_link}</a></p>'
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
            f'<p><a href="{reset_link}">{reset_link}</a></p>'
            "<p>Ce lien expire rapidement. Si tu n'es pas à l'origine de cette demande, ignore cet email.</p>"
        ),
    }
    _send_brevo_email(payload, email_type="password_reset")
