"""Endpoint de synchronisation complète (/sync/snapshot)."""

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query

import auth_service
import sync_crud
from deps import get_current_user_id
from schemas import SyncSnapshotOut

router = APIRouter()


@router.get("/sync/snapshot", response_model=SyncSnapshotOut)
def get_sync_snapshot(
    since: Optional[int] = Query(default=None, ge=0),
    user_id: int = Depends(get_current_user_id),
) -> SyncSnapshotOut:
    since_dt = auth_service._millis_to_utc(since)
    data = sync_crud.get_sync_snapshot_data(user_id, since_dt)
    return SyncSnapshotOut(
        snapshot_at=int(datetime.now(timezone.utc).timestamp() * 1000),
        watchlist=data["watchlist"],
        episode_progress=data["episode_progress"],
        watchlist_tombstones=data["watchlist_tombstones"],
        episode_progress_tombstones=data["episode_progress_tombstones"],
    )
