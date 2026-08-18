import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from psycopg2.extras import execute_values

from db import cursor
from schemas import (
    EpisodeProgressItemIn,
    WatchlistItemIn,
)

TOKEN_TTL_HOURS = int(os.getenv("AUTH_TOKEN_TTL_HOURS", "1"))
REFRESH_TOKEN_TTL_DAYS = int(os.getenv("AUTH_REFRESH_TOKEN_TTL_DAYS", "30"))
EMAIL_VERIFICATION_TTL_HOURS = int(os.getenv("EMAIL_VERIFICATION_TTL_HOURS", "24"))
PASSWORD_RESET_TTL_MINUTES = int(os.getenv("PASSWORD_RESET_TTL_MINUTES", "30"))
AUTH_TOKEN_PURGE_RETENTION_DAYS = int(os.getenv("AUTH_TOKEN_PURGE_RETENTION_DAYS", "30"))
AUTH_REFRESH_TOKEN_PURGE_RETENTION_DAYS = int(os.getenv("AUTH_REFRESH_TOKEN_PURGE_RETENTION_DAYS", "30"))
EMAIL_VERIFICATION_PURGE_RETENTION_DAYS = int(os.getenv("EMAIL_VERIFICATION_PURGE_RETENTION_DAYS", "7"))
PASSWORD_RESET_PURGE_RETENTION_DAYS = int(os.getenv("PASSWORD_RESET_PURGE_RETENTION_DAYS", "7"))
EMAIL_DELIVERY_LOG_RETENTION_DAYS = int(os.getenv("EMAIL_DELIVERY_LOG_RETENTION_DAYS", "30"))
PASSWORD_HISTORY_LIMIT = int(os.getenv("PASSWORD_HISTORY_LIMIT", "5"))


def _hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    rounds = 150_000
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), rounds).hex()
    return f"pbkdf2_sha256${rounds}${salt}${digest}"


def _verify_password(password: str, encoded: str) -> bool:
    try:
        algo, rounds_text, salt, digest = encoded.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        rounds = int(rounds_text)
    except (ValueError, TypeError):
        return False
    check = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), rounds).hex()
    return hmac.compare_digest(check, digest)


def _validate_password_policy(password: str) -> Optional[str]:
    if len(password) < 10:
        return "password_too_short"
    has_lower = any(ch.islower() for ch in password)
    has_upper = any(ch.isupper() for ch in password)
    has_digit = any(ch.isdigit() for ch in password)
    has_symbol = any(not ch.isalnum() for ch in password)
    if not (has_lower and has_upper and has_digit and has_symbol):
        return "password_too_weak"
    return None


def _is_password_reused(cur, user_id: int, password: str) -> bool:
    cur.execute(
        """
        SELECT password_hash
        FROM password_history
        WHERE user_id = %s
        ORDER BY created_at DESC
        LIMIT %s
        """,
        (user_id, PASSWORD_HISTORY_LIMIT),
    )
    rows = cur.fetchall()
    return any(_verify_password(password, row["password_hash"]) for row in rows)


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _issue_access_token(cur, user_id: int) -> str:
    access_token = secrets.token_urlsafe(48)
    token_hash = _hash_token(access_token)
    expires_at = datetime.now(timezone.utc) + timedelta(hours=TOKEN_TTL_HOURS)
    cur.execute(
        """
        INSERT INTO auth_tokens (token_hash, user_id, expires_at)
        VALUES (%s, %s, %s)
        """,
        (token_hash, user_id, expires_at),
    )
    return access_token


def _issue_refresh_token(cur, user_id: int, family_id: Optional[str] = None) -> tuple[str, str]:
    refresh_token = secrets.token_urlsafe(48)
    token_hash = _hash_token(refresh_token)
    resolved_family_id = family_id or secrets.token_hex(16)
    expires_at = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_TTL_DAYS)
    cur.execute(
        """
        INSERT INTO auth_refresh_tokens (token_hash, user_id, family_id, expires_at)
        VALUES (%s, %s, %s, %s)
        """,
        (token_hash, user_id, resolved_family_id, expires_at),
    )
    return refresh_token, resolved_family_id


def _issue_session_tokens(cur, user_id: int, family_id: Optional[str] = None) -> dict[str, Any]:
    access_token = _issue_access_token(cur, user_id)
    refresh_token, resolved_family_id = _issue_refresh_token(cur, user_id, family_id=family_id)
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "family_id": resolved_family_id,
        "expires_in_seconds": TOKEN_TTL_HOURS * 3600,
    }


def purge_expired_tokens() -> int:
    with cursor() as cur:
        cur.execute(
            """
            DELETE FROM auth_tokens
            WHERE expires_at <= now() - make_interval(days => %s)
               OR (
                    revoked_at IS NOT NULL
                AND revoked_at <= now() - make_interval(days => %s)
               )
            """
            ,
            (AUTH_TOKEN_PURGE_RETENTION_DAYS, AUTH_TOKEN_PURGE_RETENTION_DAYS),
        )
        deleted_auth_tokens = cur.rowcount
        cur.execute(
            """
            DELETE FROM auth_refresh_tokens
            WHERE expires_at <= now() - make_interval(days => %s)
               OR (
                    revoked_at IS NOT NULL
                AND revoked_at <= now() - make_interval(days => %s)
               )
            """,
            (AUTH_REFRESH_TOKEN_PURGE_RETENTION_DAYS, AUTH_REFRESH_TOKEN_PURGE_RETENTION_DAYS),
        )
        cur.execute(
            """
            DELETE FROM email_verification_tokens
            WHERE expires_at <= now() - make_interval(days => %s)
               OR (
                    used_at IS NOT NULL
                AND used_at <= now() - make_interval(days => %s)
               )
            """
            ,
            (EMAIL_VERIFICATION_PURGE_RETENTION_DAYS, EMAIL_VERIFICATION_PURGE_RETENTION_DAYS),
        )
        cur.execute(
            """
            DELETE FROM password_reset_tokens
            WHERE expires_at <= now() - make_interval(days => %s)
               OR (
                    used_at IS NOT NULL
                AND used_at <= now() - make_interval(days => %s)
               )
            """
            ,
            (PASSWORD_RESET_PURGE_RETENTION_DAYS, PASSWORD_RESET_PURGE_RETENTION_DAYS),
        )
        cur.execute(
            """
            DELETE FROM email_delivery_events
            WHERE created_at <= now() - make_interval(days => %s)
            """,
            (EMAIL_DELIVERY_LOG_RETENTION_DAYS,),
        )
        cur.execute(
            """
            DELETE FROM auth_rate_limit_states
            WHERE last_failure_at <= now() - interval '2 days'
            """
        )
        return deleted_auth_tokens


def reserve_email_delivery_slot(email_type: str, daily_limit: int) -> Optional[dict[str, int]]:
    if daily_limit <= 0:
        return None
    with cursor() as cur:
        cur.execute("LOCK TABLE email_delivery_events IN SHARE ROW EXCLUSIVE MODE")
        cur.execute(
            """
            SELECT COUNT(*) AS sent_count
            FROM email_delivery_events
            WHERE quota_day = CURRENT_DATE
              AND status IN ('reserved', 'sent')
            """
        )
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


def get_rate_limit_retry_after(endpoint: str, scope_key: str) -> tuple[float, Optional[int]]:
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
            if last_failure_at is None or (now - last_failure_at).total_seconds() > window_seconds:
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
        blocked_until_epoch = int(blocked_until.timestamp()) if blocked_until is not None and blocked_until > now else None
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


def revoke_auth_token(token: str) -> bool:
    token_hash = _hash_token(token)
    with cursor() as cur:
        cur.execute(
            """
            UPDATE auth_tokens
            SET revoked_at = now()
            WHERE token_hash = %s
              AND revoked_at IS NULL
              AND expires_at > now()
            """,
            (token_hash,),
        )
        return cur.rowcount > 0


def revoke_refresh_token(refresh_token: str) -> bool:
    token_hash = _hash_token(refresh_token)
    with cursor() as cur:
        cur.execute(
            """
            UPDATE auth_refresh_tokens
            SET revoked_at = now()
            WHERE token_hash = %s
              AND revoked_at IS NULL
              AND expires_at > now()
            """,
            (token_hash,),
        )
        return cur.rowcount > 0


def revoke_all_user_sessions(cur, user_id: int) -> None:
    cur.execute(
        """
        UPDATE auth_tokens
        SET revoked_at = now()
        WHERE user_id = %s
          AND revoked_at IS NULL
        """,
        (user_id,),
    )
    cur.execute(
        """
        UPDATE auth_refresh_tokens
        SET revoked_at = now()
        WHERE user_id = %s
          AND revoked_at IS NULL
        """,
        (user_id,),
    )


def register_user(email: str, password: str) -> dict[str, Any]:
    normalized_email = email.strip().lower()
    policy_error = _validate_password_policy(password)
    if policy_error is not None:
        raise ValueError(policy_error)
    with cursor() as cur:
        cur.execute("SELECT id, email_verified_at FROM users WHERE username = %s LIMIT 1", (normalized_email,))
        existing_user = cur.fetchone()
        if existing_user is not None:
            if existing_user["email_verified_at"] is not None:
                raise ValueError("email_already_exists")
            if _is_password_reused(cur, existing_user["id"], password):
                raise ValueError("password_reused")
            password_hash = _hash_password(password)
            cur.execute(
                """
                UPDATE users
                SET password_hash = %s
                WHERE id = %s
                """,
                (password_hash, existing_user["id"]),
            )
            cur.execute(
                """
                INSERT INTO password_history (user_id, password_hash)
                VALUES (%s, %s)
                """,
                (existing_user["id"], password_hash),
            )
            return {"user_id": existing_user["id"], "email": normalized_email, "created_new": False}
        password_hash = _hash_password(password)
        cur.execute(
            """
            INSERT INTO users (username, password_hash)
            VALUES (%s, %s)
            RETURNING id
            """,
            (normalized_email, password_hash),
        )
        user_id = cur.fetchone()["id"]
        cur.execute(
            """
            INSERT INTO password_history (user_id, password_hash)
            VALUES (%s, %s)
            """,
            (user_id, password_hash),
        )
        return {"user_id": user_id, "email": normalized_email, "created_new": True}


def delete_user_by_id(user_id: int) -> None:
    with cursor() as cur:
        cur.execute(
            """
            DELETE FROM users
            WHERE id = %s
            """,
            (user_id,),
        )


def authenticate_user(email: str, password: str) -> Optional[dict[str, Any]]:
    normalized_email = email.strip().lower()
    with cursor() as cur:
        cur.execute(
            """
            SELECT id, password_hash, email_verified_at
            FROM users
            WHERE username = %s
            LIMIT 1
            """,
            (normalized_email,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        if not _verify_password(password, row["password_hash"]):
            return None
        if row["email_verified_at"] is None:
            raise ValueError("email_not_verified")
        return {"user_id": row["id"], "email": normalized_email}


def issue_session_tokens_for_user(user_id: int) -> dict[str, Any]:
    with cursor() as cur:
        return _issue_session_tokens(cur, user_id)


def create_email_verification_token(user_id: int) -> str:
    token = secrets.token_urlsafe(48)
    token_hash = _hash_token(token)
    with cursor() as cur:
        cur.execute(
            """
            DELETE FROM email_verification_tokens
            WHERE user_id = %s
              AND used_at IS NULL
            """,
            (user_id,),
        )
        cur.execute(
            """
            INSERT INTO email_verification_tokens (token_hash, user_id, expires_at)
            VALUES (%s, %s, now() + make_interval(hours => %s))
            """,
            (token_hash, user_id, EMAIL_VERIFICATION_TTL_HOURS),
        )
    return token


def verify_email_token(token: str) -> bool:
    token_hash = _hash_token(token)
    with cursor() as cur:
        cur.execute(
            """
            SELECT user_id
            FROM email_verification_tokens
            WHERE token_hash = %s
              AND used_at IS NULL
              AND expires_at > now()
            LIMIT 1
            """,
            (token_hash,),
        )
        row = cur.fetchone()
        if row is None:
            return False
        user_id = row["user_id"]
        cur.execute(
            """
            UPDATE users
            SET email_verified_at = now()
            WHERE id = %s
            """,
            (user_id,),
        )
        cur.execute(
            """
            UPDATE email_verification_tokens
            SET used_at = now()
            WHERE token_hash = %s
            """,
            (token_hash,),
        )
        return True


def create_verification_token_for_email(email: str) -> Optional[dict[str, str]]:
    normalized_email = email.strip().lower()
    with cursor() as cur:
        cur.execute(
            """
            SELECT id, username
            FROM users
            WHERE username = %s
              AND email_verified_at IS NULL
            LIMIT 1
            """,
            (normalized_email,),
        )
        row = cur.fetchone()
        if row is None:
            return None
    return {"email": row["username"], "token": create_email_verification_token(row["id"])}


def create_password_reset_token_for_email(email: str) -> Optional[dict[str, str]]:
    normalized_email = email.strip().lower()
    token = secrets.token_urlsafe(48)
    token_hash = _hash_token(token)
    with cursor() as cur:
        cur.execute(
            """
            SELECT id, username
            FROM users
            WHERE username = %s
              AND email_verified_at IS NOT NULL
            LIMIT 1
            """,
            (normalized_email,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        cur.execute(
            """
            DELETE FROM password_reset_tokens
            WHERE user_id = %s
              AND used_at IS NULL
            """,
            (row["id"],),
        )
        cur.execute(
            """
            INSERT INTO password_reset_tokens (token_hash, user_id, expires_at)
            VALUES (%s, %s, now() + make_interval(mins => %s))
            """,
            (token_hash, row["id"], PASSWORD_RESET_TTL_MINUTES),
        )
    return {"email": row["username"], "token": token}


def rotate_refresh_token(refresh_token: str) -> Optional[dict[str, Any]]:
    token_hash = _hash_token(refresh_token)
    with cursor() as cur:
        cur.execute(
            """
            SELECT token_hash, user_id, family_id
            FROM auth_refresh_tokens
            WHERE token_hash = %s
              AND revoked_at IS NULL
              AND expires_at > now()
            LIMIT 1
            FOR UPDATE
            """,
            (token_hash,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        new_tokens = _issue_session_tokens(cur, row["user_id"], family_id=row["family_id"])
        new_refresh_hash = _hash_token(new_tokens["refresh_token"])
        cur.execute(
            """
            UPDATE auth_refresh_tokens
            SET revoked_at = now(),
                replaced_by_token_hash = %s
            WHERE token_hash = %s
            """,
            (new_refresh_hash, token_hash),
        )
        return new_tokens


def reset_password_with_token(token: str, password: str) -> str:
    token_hash = _hash_token(token)
    policy_error = _validate_password_policy(password)
    if policy_error is not None:
        return policy_error
    password_hash = _hash_password(password)
    with cursor() as cur:
        cur.execute(
            """
            SELECT prt.user_id, u.password_hash
            FROM password_reset_tokens prt
            JOIN users u ON u.id = prt.user_id
            WHERE prt.token_hash = %s
              AND prt.used_at IS NULL
              AND prt.expires_at > now()
            LIMIT 1
            """,
            (token_hash,),
        )
        row = cur.fetchone()
        if row is None:
            return "invalid_or_expired"
        if _verify_password(password, row["password_hash"]):
            return "same_as_current"
        if _is_password_reused(cur, row["user_id"], password):
            return "password_reused"
        user_id = row["user_id"]
        cur.execute(
            """
            UPDATE users
            SET password_hash = %s
            WHERE id = %s
            """,
            (password_hash, user_id),
        )
        cur.execute(
            """
            UPDATE password_reset_tokens
            SET used_at = now()
            WHERE token_hash = %s
            """,
            (token_hash,),
        )
        revoke_all_user_sessions(cur, user_id)
        cur.execute(
            """
            INSERT INTO password_history (user_id, password_hash)
            VALUES (%s, %s)
            """,
            (user_id, password_hash),
        )
        return "updated"


def change_password_for_user(user_id: int, current_password: str, new_password: str) -> str:
    policy_error = _validate_password_policy(new_password)
    if policy_error is not None:
        return policy_error
    new_password_hash = _hash_password(new_password)
    with cursor() as cur:
        cur.execute(
            """
            SELECT password_hash
            FROM users
            WHERE id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = cur.fetchone()
        if row is None:
            return "user_not_found"
        if not _verify_password(current_password, row["password_hash"]):
            return "current_password_invalid"
        if _verify_password(new_password, row["password_hash"]):
            return "same_as_current"
        if _is_password_reused(cur, user_id, new_password):
            return "password_reused"
        cur.execute(
            """
            UPDATE users
            SET password_hash = %s
            WHERE id = %s
            """,
            (new_password_hash, user_id),
        )
        cur.execute(
            """
            INSERT INTO password_history (user_id, password_hash)
            VALUES (%s, %s)
            """,
            (user_id, new_password_hash),
        )
        revoke_all_user_sessions(cur, user_id)
        return "updated"


def get_user_id_from_token(token: str) -> Optional[int]:
    token_hash = _hash_token(token)
    with cursor() as cur:
        cur.execute(
            """
            SELECT user_id
            FROM auth_tokens
            WHERE token_hash = %s
              AND revoked_at IS NULL
              AND expires_at > now()
            LIMIT 1
            """,
            (token_hash,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        cur.execute(
            """
            UPDATE auth_tokens
            SET last_used_at = now()
            WHERE token_hash = %s
            """,
            (token_hash,),
        )
        return row["user_id"]


def get_user_profile(user_id: int) -> Optional[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT id, username, display_name
            FROM users
            WHERE id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        return {
            "user_id": row["id"],
            "email": row["username"],
            "display_name": row["display_name"],
        }


def update_user_display_name(user_id: int, display_name: Optional[str]) -> Optional[dict[str, Any]]:
    normalized_display_name = display_name.strip() if isinstance(display_name, str) else None
    if normalized_display_name == "":
        normalized_display_name = None
    with cursor() as cur:
        cur.execute(
            """
            UPDATE users
            SET display_name = %s
            WHERE id = %s
            RETURNING id, username, display_name
            """,
            (normalized_display_name, user_id),
        )
        row = cur.fetchone()
        if row is None:
            return None
        return {
            "user_id": row["id"],
            "email": row["username"],
            "display_name": row["display_name"],
        }


def list_watchlist(user_id: int, content_category: Optional[str] = None) -> list[dict[str, Any]]:
    return list_watchlist_since(user_id, content_category, None)


def list_watchlist_since(
    user_id: int,
    content_category: Optional[str] = None,
    since: Optional[datetime] = None,
) -> list[dict[str, Any]]:
    params: list[Any] = [user_id]
    since_clause = ""
    if since is not None:
        params.append(since)
        since_clause = " AND updated_at > %s"
    if content_category:
        params.append(content_category)
        with cursor() as cur:
            cur.execute(
                """
                SELECT id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at, updated_at
                FROM watchlist
                WHERE user_id = %s""" + since_clause + """
                  AND content_category = %s
                ORDER BY added_at DESC
                """,
                tuple(params),
            )
            return list(cur.fetchall())

    with cursor() as cur:
        cur.execute(
            """
            SELECT id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at, updated_at
            FROM watchlist
            WHERE user_id = %s""" + since_clause + """
            ORDER BY added_at DESC
            """,
            tuple(params),
        )
        return list(cur.fetchall())


def upsert_watchlist(user_id: int, item: WatchlistItemIn) -> dict[str, Any]:
    with cursor() as cur:
        cur.execute(
            """
            DELETE FROM watchlist_tombstones
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            """,
            (user_id, item.id, item.media_type, item.content_category),
        )
        cur.execute(
            """
            INSERT INTO watchlist (user_id, id, title, poster_path, media_type, content_category, content_status, total_episodes, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id, id, media_type, content_category)
            DO UPDATE SET
                title = EXCLUDED.title,
                poster_path = EXCLUDED.poster_path,
                content_status = EXCLUDED.content_status,
                total_episodes = EXCLUDED.total_episodes,
                updated_at = CURRENT_TIMESTAMP
            RETURNING id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at, updated_at
            """,
            (
                user_id,
                item.id,
                item.title,
                item.poster_path,
                item.media_type,
                item.content_category,
                item.content_status,
                item.total_episodes,
            ),
        )
        return dict(cur.fetchone())


def delete_watchlist(user_id: int, media_id: int, media_type: str, content_category: str) -> None:
    with cursor() as cur:
        cur.execute(
            """
            INSERT INTO watchlist_tombstones (user_id, id, media_type, content_category, deleted_at)
            VALUES (%s, %s, %s, %s, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id, id, media_type, content_category)
            DO UPDATE SET deleted_at = EXCLUDED.deleted_at
            """,
            (user_id, media_id, media_type, content_category),
        )
        cur.execute(
            """
            DELETE FROM watchlist
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            """,
            (user_id, media_id, media_type, content_category),
        )


def update_watch_status(user_id: int, media_id: int, media_type: str, content_category: str, content_status: str) -> Optional[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            UPDATE watchlist
            SET content_status = %s, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            RETURNING id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at, updated_at
            """,
            (content_status, user_id, media_id, media_type, content_category),
        )
        row = cur.fetchone()
        return dict(row) if row else None


def update_watch_total(user_id: int, media_id: int, media_type: str, content_category: str, total_episodes: int) -> Optional[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            UPDATE watchlist
            SET total_episodes = %s, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            RETURNING id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at, updated_at
            """,
            (total_episodes, user_id, media_id, media_type, content_category),
        )
        row = cur.fetchone()
        return dict(row) if row else None


def list_episode_progress(user_id: int, media_id: int) -> list[dict[str, Any]]:
    return list_episode_progress_since(user_id, media_id, None)


def list_episode_progress_since(
    user_id: int,
    media_id: int,
    since: Optional[datetime] = None,
) -> list[dict[str, Any]]:
    with cursor() as cur:
        params: list[Any] = [user_id, media_id]
        since_clause = ""
        if since is not None:
            params.append(since)
            since_clause = " AND updated_at > %s"
        cur.execute(
            """
            SELECT media_id, season_number, episode_number, is_watched, updated_at
            FROM episode_progress
            WHERE user_id = %s AND media_id = %s""" + since_clause + """
            ORDER BY season_number, episode_number
            """,
            tuple(params),
        )
        return list(cur.fetchall())


def list_all_episode_progress(user_id: int) -> list[dict[str, Any]]:
    return list_all_episode_progress_since(user_id, None)


def list_all_episode_progress_since(
    user_id: int,
    since: Optional[datetime] = None,
) -> list[dict[str, Any]]:
    with cursor() as cur:
        params: list[Any] = [user_id]
        since_clause = ""
        if since is not None:
            params.append(since)
            since_clause = " AND updated_at > %s"
        cur.execute(
            """
            SELECT media_id, season_number, episode_number, is_watched, updated_at
            FROM episode_progress
            WHERE user_id = %s""" + since_clause + """
            ORDER BY media_id, season_number, episode_number
            """,
            tuple(params),
        )
        return list(cur.fetchall())


def list_watchlist_tombstones(user_id: int) -> list[dict[str, Any]]:
    return list_watchlist_tombstones_since(user_id, None)


def list_watchlist_tombstones_since(
    user_id: int,
    since: Optional[datetime] = None,
) -> list[dict[str, Any]]:
    with cursor() as cur:
        params: list[Any] = [user_id]
        since_clause = ""
        if since is not None:
            params.append(since)
            since_clause = " AND deleted_at > %s"
        cur.execute(
            """
            SELECT id, media_type, content_category, deleted_at
            FROM watchlist_tombstones
            WHERE user_id = %s""" + since_clause + """
            ORDER BY deleted_at DESC
            """,
            tuple(params),
        )
        return list(cur.fetchall())


def list_episode_progress_tombstones_since(
    user_id: int,
    since: Optional[datetime] = None,
) -> list[dict[str, Any]]:
    with cursor() as cur:
        params: list[Any] = [user_id]
        since_clause = ""
        if since is not None:
            params.append(since)
            since_clause = " AND deleted_at > %s"
        cur.execute(
            """
            SELECT media_id, season_number, episode_number, deleted_at
            FROM episode_progress_tombstones
            WHERE user_id = %s""" + since_clause + """
            ORDER BY deleted_at DESC
            """,
            tuple(params),
        )
        return list(cur.fetchall())


def list_episode_progress_tombstones(user_id: int) -> list[dict[str, Any]]:
    return list_episode_progress_tombstones_since(user_id, None)


def replace_episode_progress(user_id: int, media_id: int, items: list[EpisodeProgressItemIn]) -> None:
    if not items:
        return
    values = [
        (user_id, media_id, item.season_number, item.episode_number, item.is_watched)
        for item in items
    ]
    with cursor() as cur:
        execute_values(
            cur,
            """
            INSERT INTO episode_progress (user_id, media_id, season_number, episode_number, is_watched)
            VALUES %s
            ON CONFLICT (user_id, media_id, season_number, episode_number)
            DO UPDATE SET is_watched = EXCLUDED.is_watched, updated_at = CURRENT_TIMESTAMP
            """,
            values,
        )


def delete_episode_progress(
    user_id: int,
    media_id: int,
    season_number: int,
    episode_number: int,
) -> None:
    with cursor() as cur:
        cur.execute(
            """
            INSERT INTO episode_progress_tombstones (user_id, media_id, season_number, episode_number, deleted_at)
            VALUES (%s, %s, %s, %s, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id, media_id, season_number, episode_number)
            DO UPDATE SET deleted_at = EXCLUDED.deleted_at
            """,
            (user_id, media_id, season_number, episode_number),
        )
        cur.execute(
            """
            DELETE FROM episode_progress
            WHERE user_id = %s AND media_id = %s AND season_number = %s AND episode_number = %s
            """,
            (user_id, media_id, season_number, episode_number),
        )
