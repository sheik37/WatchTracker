"""Endpoint de synchronisation complète (/sync/snapshot)."""

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query

import auth_service
import episode_crud
import watchlist_crud
from deps import get_current_user_id
from schemas import SyncSnapshotOut

router = APIRouter()


@router.get("/sync/snapshot", response_model=SyncSnapshotOut)
def get_sync_snapshot(
    since: Optional[int] = Query(default=None, ge=0),
    user_id: int = Depends(get_current_user_id),
) -> SyncSnapshotOut:
    since_dt = auth_service._millis_to_utc(since)
    return SyncSnapshotOut(
        snapshot_at=int(datetime.now(timezone.utc).timestamp() * 1000),
        watchlist=watchlist_crud.list_watchlist_since(user_id, since=since_dt),
        episode_progress=episode_crud.list_all_episode_progress_since(
            user_id, since_dt
        ),
        watchlist_tombstones=watchlist_crud.list_watchlist_tombstones_since(
            user_id, since_dt
        ),
        episode_progress_tombstones=episode_crud.list_episode_progress_tombstones_since(
            user_id, since_dt
        ),
    )
