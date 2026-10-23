"""Accès base de données pour la progression épisode par épisode."""

from datetime import datetime, timezone
from typing import Any, Optional

from db import cursor
from schemas import EpisodeProgressItemIn


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
            SELECT media_id, season_number, episode_number, is_watched, updated_at, sync_updated_at
            FROM episode_progress
            WHERE user_id = %s AND media_id = %s"""
            + since_clause
            + """
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
            SELECT media_id, season_number, episode_number, is_watched, updated_at, sync_updated_at
            FROM episode_progress
            WHERE user_id = %s"""
            + since_clause
            + """
            ORDER BY media_id, season_number, episode_number
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
            WHERE user_id = %s"""
            + since_clause
            + """
            ORDER BY deleted_at DESC
            """,
            tuple(params),
        )
        return list(cur.fetchall())


def list_episode_progress_tombstones(user_id: int) -> list[dict[str, Any]]:
    return list_episode_progress_tombstones_since(user_id, None)


def replace_episode_progress(
    user_id: int, media_id: int, items: list[EpisodeProgressItemIn]
) -> None:
    if not items:
        return
    with cursor() as cur:
        for item in items:
            if item.is_watched:
                _set_episode_watched(
                    cur,
                    user_id=user_id,
                    media_id=media_id,
                    season_number=item.season_number,
                    episode_number=item.episode_number,
                    allow_rewatch=False,
                )
            else:
                _set_episode_unwatched(
                    cur,
                    user_id=user_id,
                    media_id=media_id,
                    season_number=item.season_number,
                    episode_number=item.episode_number,
                )


def rewatch_episode_progress(
    user_id: int,
    media_id: int,
    season_number: int,
    episode_number: int,
) -> None:
    with cursor() as cur:
        _set_episode_watched(
            cur,
            user_id=user_id,
            media_id=media_id,
            season_number=season_number,
            episode_number=episode_number,
            allow_rewatch=True,
        )


def rewatch_episode_season(
    user_id: int,
    media_id: int,
    season_number: int,
    episode_numbers: list[int],
) -> None:
    unique_numbers = sorted({n for n in episode_numbers if n > 0})
    if not unique_numbers:
        return
    with cursor() as cur:
        for episode_number in unique_numbers:
            _set_episode_watched(
                cur,
                user_id=user_id,
                media_id=media_id,
                season_number=season_number,
                episode_number=episode_number,
                allow_rewatch=True,
            )


def _set_episode_watched(
    cur,
    *,
    user_id: int,
    media_id: int,
    season_number: int,
    episode_number: int,
    allow_rewatch: bool,
    watched_at: Optional[datetime] = None,
) -> None:
    event_at = watched_at or datetime.now(timezone.utc)
    cur.execute(
        """
        SELECT is_watched, updated_at, sync_updated_at
        FROM episode_progress
        WHERE user_id = %s AND media_id = %s AND season_number = %s AND episode_number = %s
        LIMIT 1
        FOR UPDATE
        """,
        (user_id, media_id, season_number, episode_number),
    )
    row = cur.fetchone()
    already_watched = bool(row and row["is_watched"])
    if already_watched and not allow_rewatch:
        return
    first_watched_at = row["updated_at"] if already_watched else event_at
    cur.execute(
        """
        INSERT INTO episode_watch_events (
            user_id, media_id, season_number, episode_number, watched_at, created_at
        )
        VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (user_id, media_id, season_number, episode_number, event_at, event_at),
    )
    cur.execute(
        """
        DELETE FROM episode_progress_tombstones
        WHERE user_id = %s AND media_id = %s AND season_number = %s AND episode_number = %s
        """,
        (user_id, media_id, season_number, episode_number),
    )
    cur.execute(
        """
        INSERT INTO episode_progress (
            user_id, media_id, season_number, episode_number, is_watched, updated_at, sync_updated_at
        )
        VALUES (%s, %s, %s, %s, TRUE, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (user_id, media_id, season_number, episode_number)
        DO UPDATE SET
            is_watched = TRUE,
            updated_at = CASE
                WHEN episode_progress.is_watched THEN LEAST(episode_progress.updated_at, EXCLUDED.updated_at)
                ELSE EXCLUDED.updated_at
            END,
            sync_updated_at = EXCLUDED.sync_updated_at
        """,
        (user_id, media_id, season_number, episode_number, first_watched_at),
    )


def _set_episode_unwatched(
    cur, *, user_id: int, media_id: int, season_number: int, episode_number: int
) -> None:
    cur.execute(
        """
        DELETE FROM episode_watch_events
        WHERE user_id = %s AND media_id = %s AND season_number = %s AND episode_number = %s
        """,
        (user_id, media_id, season_number, episode_number),
    )
    cur.execute(
        """
        INSERT INTO episode_progress (
            user_id, media_id, season_number, episode_number, is_watched, updated_at, sync_updated_at
        )
        VALUES (%s, %s, %s, %s, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (user_id, media_id, season_number, episode_number)
        DO UPDATE SET
            is_watched = FALSE,
            updated_at = CURRENT_TIMESTAMP,
            sync_updated_at = CURRENT_TIMESTAMP
        """,
        (user_id, media_id, season_number, episode_number),
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
            DELETE FROM episode_watch_events
            WHERE user_id = %s AND media_id = %s AND season_number = %s AND episode_number = %s
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
