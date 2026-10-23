"""Accès base de données pour la progression épisode par épisode."""

from contextlib import nullcontext
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
    cur: Optional[Any] = None,
) -> list[dict[str, Any]]:
    with nullcontext(cur) if cur is not None else cursor() as c:
        params: list[Any] = [user_id]
        since_clause = ""
        if since is not None:
            params.append(since)
            since_clause = " AND updated_at > %s"
        c.execute(
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
        return list(c.fetchall())


def list_episode_progress_tombstones_since(
    user_id: int,
    since: Optional[datetime] = None,
    cur: Optional[Any] = None,
) -> list[dict[str, Any]]:
    with nullcontext(cur) if cur is not None else cursor() as c:
        params: list[Any] = [user_id]
        since_clause = ""
        if since is not None:
            params.append(since)
            since_clause = " AND deleted_at > %s"
        c.execute(
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
        return list(c.fetchall())


def list_episode_progress_tombstones(user_id: int) -> list[dict[str, Any]]:
    return list_episode_progress_tombstones_since(user_id, None)


def replace_episode_progress(
    user_id: int, media_id: int, items: list[EpisodeProgressItemIn]
) -> None:
    if not items:
        return
    # Si le payload contient plusieurs entrées pour le même (saison, épisode),
    # seule la dernière est conservée (dernière écriture gagnante), comme le
    # ferait une boucle séquentielle qui écrase la ligne à chaque passage.
    resolved: dict[tuple[int, int], bool] = {}
    key_order: list[tuple[int, int]] = []
    for item in items:
        key = (item.season_number, item.episode_number)
        if key not in resolved:
            key_order.append(key)
        resolved[key] = item.is_watched
    watched_keys = [key for key in key_order if resolved[key]]
    unwatched_keys = [key for key in key_order if not resolved[key]]
    with cursor() as cur:
        if watched_keys:
            _set_episodes_watched_batch(
                cur,
                user_id=user_id,
                media_id=media_id,
                keys=watched_keys,
                allow_rewatch=False,
            )
        if unwatched_keys:
            _set_episodes_unwatched_batch(
                cur, user_id=user_id, media_id=media_id, keys=unwatched_keys
            )


def rewatch_episode_progress(
    user_id: int,
    media_id: int,
    season_number: int,
    episode_number: int,
) -> None:
    with cursor() as cur:
        _set_episodes_watched_batch(
            cur,
            user_id=user_id,
            media_id=media_id,
            keys=[(season_number, episode_number)],
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
        _set_episodes_watched_batch(
            cur,
            user_id=user_id,
            media_id=media_id,
            keys=[(season_number, episode_number) for episode_number in unique_numbers],
            allow_rewatch=True,
        )


def _set_episodes_watched_batch(
    cur,
    *,
    user_id: int,
    media_id: int,
    keys: list[tuple[int, int]],
    allow_rewatch: bool,
    watched_at: Optional[datetime] = None,
) -> None:
    """Marque un lot d'épisodes comme vus en une poignée de requêtes groupées
    au lieu d'une requête par épisode (SELECT ... FOR UPDATE, INSERT, DELETE,
    UPSERT groupés via ``IN``/``VALUES`` multi-lignes).
    """
    if not keys:
        return
    event_at = watched_at or datetime.now(timezone.utc)

    cur.execute(
        """
        SELECT season_number, episode_number, is_watched, updated_at
        FROM episode_progress
        WHERE user_id = %s AND media_id = %s
          AND (season_number, episode_number) IN %s
        FOR UPDATE
        """,
        (user_id, media_id, tuple(keys)),
    )
    existing = {
        (row["season_number"], row["episode_number"]): row for row in cur.fetchall()
    }

    to_process: list[tuple[int, int, Any]] = []
    for season_number, episode_number in keys:
        row = existing.get((season_number, episode_number))
        already_watched = bool(row and row["is_watched"])
        if already_watched and not allow_rewatch:
            continue
        first_watched_at = row["updated_at"] if already_watched else event_at
        to_process.append((season_number, episode_number, first_watched_at))

    if not to_process:
        return

    processed_keys = tuple((s, e) for s, e, _ in to_process)

    event_values_sql = ", ".join(["(%s, %s, %s, %s, %s, %s)"] * len(to_process))
    event_params: list[Any] = []
    for season_number, episode_number, _ in to_process:
        event_params.extend(
            [user_id, media_id, season_number, episode_number, event_at, event_at]
        )
    cur.execute(
        """
        INSERT INTO episode_watch_events (
            user_id, media_id, season_number, episode_number, watched_at, created_at
        )
        VALUES """
        + event_values_sql,
        tuple(event_params),
    )

    cur.execute(
        """
        DELETE FROM episode_progress_tombstones
        WHERE user_id = %s AND media_id = %s
          AND (season_number, episode_number) IN %s
        """,
        (user_id, media_id, processed_keys),
    )

    upsert_values_sql = ", ".join(
        ["(%s, %s, %s, %s, TRUE, %s, CURRENT_TIMESTAMP)"] * len(to_process)
    )
    upsert_params: list[Any] = []
    for season_number, episode_number, first_watched_at in to_process:
        upsert_params.extend(
            [user_id, media_id, season_number, episode_number, first_watched_at]
        )
    cur.execute(
        """
        INSERT INTO episode_progress (
            user_id, media_id, season_number, episode_number, is_watched, updated_at, sync_updated_at
        )
        VALUES """
        + upsert_values_sql
        + """
        ON CONFLICT (user_id, media_id, season_number, episode_number)
        DO UPDATE SET
            is_watched = TRUE,
            updated_at = CASE
                WHEN episode_progress.is_watched THEN LEAST(episode_progress.updated_at, EXCLUDED.updated_at)
                ELSE EXCLUDED.updated_at
            END,
            sync_updated_at = EXCLUDED.sync_updated_at
        """,
        tuple(upsert_params),
    )


def _set_episodes_unwatched_batch(
    cur, *, user_id: int, media_id: int, keys: list[tuple[int, int]]
) -> None:
    """Marque un lot d'épisodes comme non vus (suppression/upsert groupés)."""
    if not keys:
        return
    keys_tuple = tuple(keys)
    cur.execute(
        """
        DELETE FROM episode_watch_events
        WHERE user_id = %s AND media_id = %s
          AND (season_number, episode_number) IN %s
        """,
        (user_id, media_id, keys_tuple),
    )

    values_sql = ", ".join(
        ["(%s, %s, %s, %s, FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"] * len(keys)
    )
    params: list[Any] = []
    for season_number, episode_number in keys:
        params.extend([user_id, media_id, season_number, episode_number])
    cur.execute(
        """
        INSERT INTO episode_progress (
            user_id, media_id, season_number, episode_number, is_watched, updated_at, sync_updated_at
        )
        VALUES """
        + values_sql
        + """
        ON CONFLICT (user_id, media_id, season_number, episode_number)
        DO UPDATE SET
            is_watched = FALSE,
            updated_at = CURRENT_TIMESTAMP,
            sync_updated_at = CURRENT_TIMESTAMP
        """,
        tuple(params),
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
