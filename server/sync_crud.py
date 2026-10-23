"""Lecture groupée pour l'endpoint /sync/snapshot.

Regroupe les 4 lectures (watchlist, progression épisode, tombstones
watchlist, tombstones progression) dans une seule connexion/transaction au
lieu de 4 appels CRUD séquentiels ouvrant chacun leur propre connexion. Cela
garantit une cohérence temporelle du snapshot (toutes les lectures voient le
même état de la base) et réduit le nombre d'allers-retours avec PostgreSQL.
"""

from datetime import datetime
from typing import Any, Optional

import episode_crud
import watchlist_crud
from db import cursor


def get_sync_snapshot_data(
    user_id: int, since: Optional[datetime]
) -> dict[str, list[dict[str, Any]]]:
    with cursor() as cur:
        return {
            "watchlist": watchlist_crud.list_watchlist_since(
                user_id, since=since, cur=cur
            ),
            "episode_progress": episode_crud.list_all_episode_progress_since(
                user_id, since, cur=cur
            ),
            "watchlist_tombstones": watchlist_crud.list_watchlist_tombstones_since(
                user_id, since, cur=cur
            ),
            "episode_progress_tombstones": episode_crud.list_episode_progress_tombstones_since(
                user_id, since, cur=cur
            ),
        }
