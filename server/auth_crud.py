"""Accès base de données pour l'authentification : utilisateurs, tokens,
vérification d'email, réinitialisation de mot de passe et historique des
mots de passe.
"""

import hashlib
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from db import cursor
from security import hash_password as _hash_password
from security import verify_password as _verify_password

TOKEN_TTL_HOURS = int(os.getenv("AUTH_TOKEN_TTL_HOURS", "1"))
REFRESH_TOKEN_TTL_DAYS = int(os.getenv("AUTH_REFRESH_TOKEN_TTL_DAYS", "30"))
EMAIL_VERIFICATION_TTL_HOURS = int(os.getenv("EMAIL_VERIFICATION_TTL_HOURS", "24"))
PASSWORD_RESET_TTL_MINUTES = int(os.getenv("PASSWORD_RESET_TTL_MINUTES", "30"))
AUTH_TOKEN_PURGE_RETENTION_DAYS = int(
    os.getenv("AUTH_TOKEN_PURGE_RETENTION_DAYS", "30")
)
AUTH_REFRESH_TOKEN_PURGE_RETENTION_DAYS = int(
    os.getenv("AUTH_REFRESH_TOKEN_PURGE_RETENTION_DAYS", "30")
)
EMAIL_VERIFICATION_PURGE_RETENTION_DAYS = int(
    os.getenv("EMAIL_VERIFICATION_PURGE_RETENTION_DAYS", "7")
)
PASSWORD_RESET_PURGE_RETENTION_DAYS = int(
    os.getenv("PASSWORD_RESET_PURGE_RETENTION_DAYS", "7")
)
EMAIL_DELIVERY_LOG_RETENTION_DAYS = int(
    os.getenv("EMAIL_DELIVERY_LOG_RETENTION_DAYS", "30")
)
PASSWORD_HISTORY_LIMIT = int(os.getenv("PASSWORD_HISTORY_LIMIT", "5"))


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


def _issue_refresh_token(
    cur, user_id: int, family_id: Optional[str] = None
) -> tuple[str, str]:
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


def _issue_session_tokens(
    cur, user_id: int, family_id: Optional[str] = None
) -> dict[str, Any]:
    access_token = _issue_access_token(cur, user_id)
    refresh_token, resolved_family_id = _issue_refresh_token(
        cur, user_id, family_id=family_id
    )
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
            """,
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
            (
                AUTH_REFRESH_TOKEN_PURGE_RETENTION_DAYS,
                AUTH_REFRESH_TOKEN_PURGE_RETENTION_DAYS,
            ),
        )
        cur.execute(
            """
            DELETE FROM email_verification_tokens
            WHERE expires_at <= now() - make_interval(days => %s)
               OR (
                    used_at IS NOT NULL
                AND used_at <= now() - make_interval(days => %s)
               )
            """,
            (
                EMAIL_VERIFICATION_PURGE_RETENTION_DAYS,
                EMAIL_VERIFICATION_PURGE_RETENTION_DAYS,
            ),
        )
        cur.execute(
            """
            DELETE FROM password_reset_tokens
            WHERE expires_at <= now() - make_interval(days => %s)
               OR (
                    used_at IS NOT NULL
                AND used_at <= now() - make_interval(days => %s)
               )
            """,
            (PASSWORD_RESET_PURGE_RETENTION_DAYS, PASSWORD_RESET_PURGE_RETENTION_DAYS),
        )
        cur.execute(
            """
            DELETE FROM email_delivery_events
            WHERE created_at <= now() - make_interval(days => %s)
            """,
            (EMAIL_DELIVERY_LOG_RETENTION_DAYS,),
        )
        cur.execute("""
            DELETE FROM auth_rate_limit_states
            WHERE last_failure_at <= now() - interval '2 days'
            """)
        return deleted_auth_tokens


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
        cur.execute(
            "SELECT id, email_verified_at FROM users WHERE username = %s LIMIT 1",
            (normalized_email,),
        )
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
            return {
                "user_id": existing_user["id"],
                "email": normalized_email,
                "created_new": False,
            }
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
    return {
        "email": row["username"],
        "token": create_email_verification_token(row["id"]),
    }


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
        new_tokens = _issue_session_tokens(
            cur, row["user_id"], family_id=row["family_id"]
        )
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


def change_password_for_user(
    user_id: int, current_password: str, new_password: str
) -> str:
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


LAST_USED_AT_THROTTLE_SECONDS = 300


def get_user_id_from_token(token: str) -> Optional[int]:
    token_hash = _hash_token(token)
    with cursor() as cur:
        cur.execute(
            """
            SELECT user_id, last_used_at
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
        last_used_at = row["last_used_at"]
        # Optimisation : n'écrire last_used_at que si la dernière mise à
        # jour date de plus de LAST_USED_AT_THROTTLE_SECONDS, pour éviter une
        # écriture à chaque requête authentifiée.
        if last_used_at is None or (
            datetime.now(timezone.utc) - _as_aware_utc(last_used_at)
            >= timedelta(seconds=LAST_USED_AT_THROTTLE_SECONDS)
        ):
            cur.execute(
                """
                UPDATE auth_tokens
                SET last_used_at = now()
                WHERE token_hash = %s
                """,
                (token_hash,),
            )
        return row["user_id"]


def _as_aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
