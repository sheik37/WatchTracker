"""Endpoints de gestion de la watchlist et de la progression des épisodes."""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

import auth_service
import episode_crud
import watchlist_crud
from deps import get_current_user_id
from schemas import (
    EpisodeProgressItemIn,
    SeasonRewatchIn,
    WatchlistItemIn,
    WatchlistStatusUpdate,
    WatchlistTotalUpdate,
)

router = APIRouter()


@router.get("/watchlist")
def get_watchlist(
    content_category: Optional[str] = Query(default=None),
    since: Optional[int] = Query(default=None, ge=0),
    user_id: int = Depends(get_current_user_id),
) -> list[dict]:
    return watchlist_crud.list_watchlist_since(
        user_id, content_category, auth_service._millis_to_utc(since)
    )


@router.post("/watchlist", status_code=201)
def create_watchlist_item(
    item: WatchlistItemIn, user_id: int = Depends(get_current_user_id)
) -> dict:
    return watchlist_crud.upsert_watchlist(user_id, item)


@router.patch("/watchlist/{media_id}/{media_type}/{content_category}/status")
def patch_watch_status(
    media_id: int,
    media_type: str,
    content_category: str,
    payload: WatchlistStatusUpdate,
    user_id: int = Depends(get_current_user_id),
) -> dict:
    row = watchlist_crud.update_watch_status(
        user_id, media_id, media_type, content_category, payload.content_status
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Watchlist item not found")
    return row


@router.post(
    "/watchlist/{media_id}/{media_type}/{content_category}/rewatch", status_code=204
)
def post_watchlist_rewatch(
    media_id: int,
    media_type: str,
    content_category: str,
    user_id: int = Depends(get_current_user_id),
) -> None:
    if media_type != "movie":
        raise HTTPException(
            status_code=400, detail="Rewatch endpoint is only available for movies"
        )
    ok = watchlist_crud.rewatch_movie(user_id, media_id, media_type, content_category)
    if not ok:
        raise HTTPException(status_code=404, detail="Watchlist item not found")


@router.patch("/watchlist/{media_id}/{media_type}/{content_category}/total-episodes")
def patch_watch_total(
    media_id: int,
    media_type: str,
    content_category: str,
    payload: WatchlistTotalUpdate,
    user_id: int = Depends(get_current_user_id),
) -> dict:
    row = watchlist_crud.update_watch_total(
        user_id, media_id, media_type, content_category, payload.total_episodes
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Watchlist item not found")
    return row


@router.delete("/watchlist/{media_id}/{media_type}/{content_category}", status_code=204)
def remove_watchlist_item(
    media_id: int,
    media_type: str,
    content_category: str,
    user_id: int = Depends(get_current_user_id),
) -> None:
    watchlist_crud.delete_watchlist(user_id, media_id, media_type, content_category)


@router.get("/episode-progress/{media_id}")
def get_episode_progress(
    media_id: int, user_id: int = Depends(get_current_user_id)
) -> list[dict]:
    return episode_crud.list_episode_progress(user_id, media_id)


@router.put("/episode-progress/{media_id}", status_code=204)
def put_episode_progress(
    media_id: int,
    items: list[EpisodeProgressItemIn],
    user_id: int = Depends(get_current_user_id),
) -> None:
    episode_crud.replace_episode_progress(user_id, media_id, items)


@router.post(
    "/episode-progress/{media_id}/{season_number}/{episode_number}/rewatch",
    status_code=204,
)
def post_episode_rewatch(
    media_id: int,
    season_number: int,
    episode_number: int,
    user_id: int = Depends(get_current_user_id),
) -> None:
    if season_number < 0 or episode_number < 1:
        raise HTTPException(status_code=400, detail="Invalid season/episode number")
    episode_crud.rewatch_episode_progress(
        user_id, media_id, season_number, episode_number
    )


@router.post("/episode-progress/{media_id}/rewatch-season", status_code=204)
def post_episode_rewatch_season(
    media_id: int,
    payload: SeasonRewatchIn,
    user_id: int = Depends(get_current_user_id),
) -> None:
    if payload.season_number < 0:
        raise HTTPException(status_code=400, detail="Invalid season number")
    if any(number < 1 for number in payload.episode_numbers):
        raise HTTPException(status_code=400, detail="Invalid episode number")
    episode_crud.rewatch_episode_season(
        user_id, media_id, payload.season_number, payload.episode_numbers
    )


@router.delete(
    "/episode-progress/{media_id}/{season_number}/{episode_number}", status_code=204
)
def remove_episode_progress(
    media_id: int,
    season_number: int,
    episode_number: int,
    user_id: int = Depends(get_current_user_id),
) -> None:
    episode_crud.delete_episode_progress(user_id, media_id, season_number, episode_number)
