import json
import re
import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from db import cursor
from schemas import (
    AnimeStructureIn,
    EpisodeProgressItemIn,
    WatchlistItemIn,
)

TOKEN_TTL_HOURS = int(os.getenv("AUTH_TOKEN_TTL_HOURS", "720"))


def normalize_title(value: str) -> str:
    return re.sub(r"[\W_]+", "", value.lower(), flags=re.UNICODE)


def _normalize_payload(value: Any) -> Any:
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value
    return value


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


def _issue_token(cur, user_id: int) -> str:
    token = secrets.token_urlsafe(48)
    expires_at = datetime.now(timezone.utc) + timedelta(hours=TOKEN_TTL_HOURS)
    cur.execute(
        """
        INSERT INTO auth_tokens (token, user_id, expires_at)
        VALUES (%s, %s, %s)
        """,
        (token, user_id, expires_at),
    )
    return token


def purge_expired_tokens() -> int:
    with cursor() as cur:
        cur.execute(
            """
            DELETE FROM auth_tokens
            WHERE expires_at <= now()
            """
        )
        return cur.rowcount


def revoke_auth_token(token: str) -> bool:
    with cursor() as cur:
        cur.execute(
            """
            UPDATE auth_tokens
            SET revoked_at = now()
            WHERE token = %s
              AND revoked_at IS NULL
              AND expires_at > now()
            """,
            (token,),
        )
        return cur.rowcount > 0


def register_user(username: str, password: str) -> dict[str, Any]:
    normalized_username = username.strip().lower()
    with cursor() as cur:
        cur.execute("SELECT id FROM users WHERE username = %s LIMIT 1", (normalized_username,))
        if cur.fetchone() is not None:
            raise ValueError("username_already_exists")
        password_hash = _hash_password(password)
        cur.execute(
            """
            INSERT INTO users (username, password_hash)
            VALUES (%s, %s)
            RETURNING id
            """,
            (normalized_username, password_hash),
        )
        user_id = cur.fetchone()["id"]
        token = _issue_token(cur, user_id)
        return {"token": token}


def login_user(username: str, password: str) -> Optional[dict[str, Any]]:
    normalized_username = username.strip().lower()
    with cursor() as cur:
        cur.execute(
            """
            SELECT id, password_hash
            FROM users
            WHERE username = %s
            LIMIT 1
            """,
            (normalized_username,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        if not _verify_password(password, row["password_hash"]):
            return None
        token = _issue_token(cur, row["id"])
        return {"token": token}


def get_user_id_from_token(token: str) -> Optional[int]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT user_id
            FROM auth_tokens
            WHERE token = %s
              AND revoked_at IS NULL
              AND expires_at > now()
            LIMIT 1
            """,
            (token,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        cur.execute(
            """
            UPDATE auth_tokens
            SET last_used_at = now()
            WHERE token = %s
            """,
            (token,),
        )
        return row["user_id"]


def list_watchlist(user_id: int, content_category: Optional[str] = None) -> list[dict[str, Any]]:
    if content_category:
        with cursor() as cur:
            cur.execute(
                """
                SELECT id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at
                FROM watchlist
                WHERE user_id = %s AND content_category = %s
                ORDER BY added_at DESC
                """,
                (user_id, content_category),
            )
            return list(cur.fetchall())

    with cursor() as cur:
        cur.execute(
            """
            SELECT id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at
            FROM watchlist
            WHERE user_id = %s
            ORDER BY added_at DESC
            """,
            (user_id,),
        )
        return list(cur.fetchall())


def upsert_watchlist(user_id: int, item: WatchlistItemIn) -> dict[str, Any]:
    with cursor() as cur:
        cur.execute(
            """
            INSERT INTO watchlist (user_id, id, title, poster_path, media_type, content_category, content_status, total_episodes)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id, id, media_type)
            DO UPDATE SET
                title = EXCLUDED.title,
                poster_path = EXCLUDED.poster_path,
                content_category = EXCLUDED.content_category,
                content_status = EXCLUDED.content_status,
                total_episodes = EXCLUDED.total_episodes
            RETURNING id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at
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
            SET content_status = %s
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            RETURNING id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at
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
            SET total_episodes = %s
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            RETURNING id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at
            """,
            (total_episodes, user_id, media_id, media_type, content_category),
        )
        row = cur.fetchone()
        return dict(row) if row else None


def list_episode_progress(user_id: int, media_id: int) -> list[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT media_id, season_number, episode_number, is_watched, updated_at
            FROM episode_progress
            WHERE user_id = %s AND media_id = %s
            ORDER BY season_number, episode_number
            """,
            (user_id, media_id),
        )
        return list(cur.fetchall())


def list_all_episode_progress(user_id: int) -> list[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT media_id, season_number, episode_number, is_watched, updated_at
            FROM episode_progress
            WHERE user_id = %s
            ORDER BY media_id, season_number, episode_number
            """,
            (user_id,),
        )
        return list(cur.fetchall())


def replace_episode_progress(user_id: int, media_id: int, items: list[EpisodeProgressItemIn]) -> None:
    if not items:
        return
    with cursor() as cur:
        for item in items:
            cur.execute(
                """
                INSERT INTO episode_progress (user_id, media_id, season_number, episode_number, is_watched)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (user_id, media_id, season_number, episode_number)
                DO UPDATE SET is_watched = EXCLUDED.is_watched, updated_at = CURRENT_DATE
                """,
                (user_id, media_id, item.season_number, item.episode_number, item.is_watched),
            )


def list_anime_structures() -> list[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT normalized_title, season, season_year, payload_json, updated_at
            FROM anime_structures
            ORDER BY normalized_title
            """
        )
        rows = list(cur.fetchall())
        for row in rows:
            row["payload_json"] = _normalize_payload(row.get("payload_json"))
        return rows


def get_anime_structure(normalized_title: str) -> Optional[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT normalized_title, season, season_year, payload_json, updated_at
            FROM anime_structures
            WHERE normalized_title = %s
            LIMIT 1
            """,
            (normalized_title,),
        )
        row = cur.fetchone()
        if not row:
            return None
        row = dict(row)
        row["payload_json"] = _normalize_payload(row.get("payload_json"))
        return row


def upsert_anime_structure(item: AnimeStructureIn) -> dict[str, Any]:
    normalized_title = normalize_title(item.title)
    payload_json = item.model_dump()

    with cursor() as cur:
        cur.execute(
            """
            INSERT INTO anime_structures (normalized_title, season, season_year, payload_json)
            VALUES (%s, %s, %s, %s::jsonb)
            ON CONFLICT (normalized_title)
            DO UPDATE SET
                season = EXCLUDED.season,
                season_year = EXCLUDED.season_year,
                payload_json = EXCLUDED.payload_json,
                updated_at = CURRENT_DATE
            RETURNING normalized_title, season, season_year, payload_json, updated_at
            """,
            (normalized_title, item.season, item.season_year, json.dumps(payload_json)),
        )
        row = dict(cur.fetchone())
        row["payload_json"] = _normalize_payload(row.get("payload_json"))
        return row
