"""Accès base de données pour la watchlist (films/séries/anime)."""

from contextlib import nullcontext
from datetime import datetime, timezone
from typing import Any, Optional

from db import cursor
from query_helpers import since_clause
from schemas import WatchlistItemIn


def list_watchlist_since(
    user_id: int,
    content_category: Optional[str] = None,
    since: Optional[datetime] = None,
    cur: Optional[Any] = None,
) -> list[dict[str, Any]]:
    # ``cur`` permet de réutiliser une connexion/transaction déjà ouverte
    # (voir sync_crud.get_sync_snapshot_data) au lieu d'en ouvrir une nouvelle.
    params: list[Any] = [user_id]
    clause = since_clause("updated_at", since, params)
    with nullcontext(cur) if cur is not None else cursor() as c:
        if content_category:
            params.append(content_category)
            c.execute(
                """
                SELECT id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at, updated_at
                FROM watchlist
                WHERE user_id = %s"""
                + clause
                + """
                  AND content_category = %s
                ORDER BY added_at DESC
                """,
                tuple(params),
            )
            return list(c.fetchall())

        c.execute(
            """
            SELECT id, title, poster_path, media_type, content_category, content_status, total_episodes, added_at, updated_at
            FROM watchlist
            WHERE user_id = %s"""
            + clause
            + """
            ORDER BY added_at DESC
            """,
            tuple(params),
        )
        return list(c.fetchall())


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


def delete_watchlist(
    user_id: int, media_id: int, media_type: str, content_category: str
) -> None:
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


def update_watch_status(
    user_id: int,
    media_id: int,
    media_type: str,
    content_category: str,
    content_status: str,
) -> Optional[dict[str, Any]]:
    with cursor() as cur:
        cur.execute(
            """
            SELECT content_status
            FROM watchlist
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            LIMIT 1
            FOR UPDATE
            """,
            (user_id, media_id, media_type, content_category),
        )
        existing = cur.fetchone()
        if existing is None:
            return None
        if media_type == "movie":
            if content_status == "not_watched":
                cur.execute(
                    """
                    DELETE FROM movie_watch_events
                    WHERE user_id = %s AND media_id = %s
                    """,
                    (user_id, media_id),
                )
            elif (
                content_status == "watched"
                and (existing["content_status"] or "") != "watched"
            ):
                watched_at = datetime.now(timezone.utc)
                cur.execute(
                    """
                    INSERT INTO movie_watch_events (user_id, media_id, watched_at, created_at)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (user_id, media_id, watched_at, watched_at),
                )
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


def rewatch_movie(
    user_id: int, media_id: int, media_type: str, content_category: str
) -> bool:
    if media_type != "movie":
        return False
    with cursor() as cur:
        cur.execute(
            """
            SELECT id
            FROM watchlist
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            LIMIT 1
            FOR UPDATE
            """,
            (user_id, media_id, media_type, content_category),
        )
        existing = cur.fetchone()
        if existing is None:
            return False
        watched_at = datetime.now(timezone.utc)
        cur.execute(
            """
            INSERT INTO movie_watch_events (user_id, media_id, watched_at, created_at)
            VALUES (%s, %s, %s, %s)
            """,
            (user_id, media_id, watched_at, watched_at),
        )
        cur.execute(
            """
            UPDATE watchlist
            SET content_status = 'watched', updated_at = CURRENT_TIMESTAMP
            WHERE user_id = %s AND id = %s AND media_type = %s AND content_category = %s
            """,
            (user_id, media_id, media_type, content_category),
        )
        return True


def update_watch_total(
    user_id: int,
    media_id: int,
    media_type: str,
    content_category: str,
    total_episodes: int,
) -> Optional[dict[str, Any]]:
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


def list_watchlist_tombstones_since(
    user_id: int,
    since: Optional[datetime] = None,
    cur: Optional[Any] = None,
) -> list[dict[str, Any]]:
    with nullcontext(cur) if cur is not None else cursor() as c:
        params: list[Any] = [user_id]
        clause = since_clause("deleted_at", since, params)
        c.execute(
            """
            SELECT id, media_type, content_category, deleted_at
            FROM watchlist_tombstones
            WHERE user_id = %s"""
            + clause
            + """
            ORDER BY deleted_at DESC
            """,
            tuple(params),
        )
        return list(c.fetchall())
