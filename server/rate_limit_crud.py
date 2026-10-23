"""Accès base de données pour le rate limiting applicatif et l'envoi d'emails.

Regroupe les tables ``auth_rate_limit_states`` (anti-bruteforce register/login/
resend/forgot) et ``email_delivery_events`` (quota d'envoi d'emails Brevo).
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from db import cursor


def reserve_email_delivery_slot(
    email_type: str, daily_limit: int
) -> Optional[dict[str, int]]:
    if daily_limit <= 0:
        return None
    with cursor() as cur:
        cur.execute("LOCK TABLE email_delivery_events IN SHARE ROW EXCLUSIVE MODE")
        cur.execute("""
            SELECT COUNT(*) AS sent_count
            FROM email_delivery_events
            WHERE quota_day = CURRENT_DATE
              AND status IN ('reserved', 'sent')
            """)
        sent_count = int(cur.fetchone()["sent_count"])
        if sent_count >= daily_limit:
            return None
        cur.execute(
            """
            INSERT INTO email_delivery_events (email_type, status)
            VALUES (%s, 'reserved')
            RETURNING id
            """,
            (email_type,),
        )
        slot_id = int(cur.fetchone()["id"])
        return {"slot_id": slot_id, "count_after_reservation": sent_count + 1}


def complete_email_delivery_slot(slot_id: int, delivered: bool) -> None:
    status = "sent" if delivered else "failed"
    with cursor() as cur:
        cur.execute(
            """
            UPDATE email_delivery_events
            SET status = %s,
                updated_at = now()
            WHERE id = %s
            """,
            (status, slot_id),
        )


def get_rate_limit_retry_after(
    endpoint: str, scope_key: str
) -> tuple[float, Optional[int]]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT blocked_until
            FROM auth_rate_limit_states
            WHERE endpoint = %s
              AND scope_key = %s
              AND blocked_until IS NOT NULL
              AND blocked_until > now()
            LIMIT 1
            """,
            (endpoint, scope_key),
        )
        row = cur.fetchone()
        if row is None:
            return 0.0, None
        blocked_until = row["blocked_until"]
        now = datetime.now(timezone.utc)
        remaining = (blocked_until - now).total_seconds()
        if remaining <= 0:
            return 0.0, None
        return remaining, int(blocked_until.timestamp())


def register_rate_limit_failure(
    endpoint: str,
    scope_key: str,
    window_seconds: int,
    free_attempts: int,
    base_delay_seconds: float,
    max_delay_seconds: float,
) -> tuple[float, int, Optional[int]]:
    now = datetime.now(timezone.utc)
    with cursor() as cur:
        cur.execute(
            """
            SELECT failure_count, first_failure_at, last_failure_at, blocked_until
            FROM auth_rate_limit_states
            WHERE endpoint = %s
              AND scope_key = %s
            FOR UPDATE
            """,
            (endpoint, scope_key),
        )
        row = cur.fetchone()
        if row is None:
            failure_count = 0
            blocked_until = None
            first_failure_at = now
        else:
            failure_count = int(row["failure_count"])
            first_failure_at = row["first_failure_at"] or now
            last_failure_at = row["last_failure_at"]
            blocked_until = row["blocked_until"]
            if (
                last_failure_at is None
                or (now - last_failure_at).total_seconds() > window_seconds
            ):
                failure_count = 0
                blocked_until = None
                first_failure_at = now
        failure_count += 1
        delay = 0.0
        if failure_count > free_attempts:
            exponent = failure_count - free_attempts - 1
            delay = min(max_delay_seconds, base_delay_seconds * (2**exponent))
            candidate_blocked_until = now + timedelta(seconds=delay)
            if blocked_until is None or candidate_blocked_until > blocked_until:
                blocked_until = candidate_blocked_until
        cur.execute(
            """
            INSERT INTO auth_rate_limit_states (
                endpoint, scope_key, failure_count, first_failure_at, last_failure_at, blocked_until
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (endpoint, scope_key)
            DO UPDATE SET
                failure_count = EXCLUDED.failure_count,
                last_failure_at = EXCLUDED.last_failure_at,
                blocked_until = EXCLUDED.blocked_until
            """,
            (endpoint, scope_key, failure_count, first_failure_at, now, blocked_until),
        )
        remaining_attempts = max(0, free_attempts - failure_count)
        blocked_until_epoch = (
            int(blocked_until.timestamp())
            if blocked_until is not None and blocked_until > now
            else None
        )
        return delay, remaining_attempts, blocked_until_epoch


def register_rate_limit_success(endpoint: str, scope_key: str) -> None:
    with cursor() as cur:
        cur.execute(
            """
            DELETE FROM auth_rate_limit_states
            WHERE endpoint = %s
              AND scope_key = %s
            """,
            (endpoint, scope_key),
        )
