from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


class WatchlistItemIn(BaseModel):
    id: int
    title: str
    poster_path: Optional[str] = None
    media_type: Literal["movie", "tv"]
    content_category: Literal["films", "series", "anime"]
    content_status: str
    total_episodes: int = 0


class WatchlistStatusUpdate(BaseModel):
    content_status: str


class WatchlistTotalUpdate(BaseModel):
    total_episodes: int = Field(ge=0)


class EpisodeProgressItemIn(BaseModel):
    season_number: int = Field(ge=0)
    episode_number: int = Field(ge=1)
    is_watched: bool


class AnimeStructureSeasonIn(BaseModel):
    season_number: int = Field(ge=1)
    name: str
    start_episode: int = Field(ge=1)
    end_episode: int = Field(ge=1)


class AnimeStructureIn(BaseModel):
    title: str
    aliases: list[str] = Field(default_factory=list)
    season: Optional[Literal["WINTER", "SPRING", "SUMMER", "FALL"]] = None
    season_year: Optional[int] = None
    seasons: list[AnimeStructureSeasonIn] = Field(default_factory=list)


class AnimeStructureOut(AnimeStructureIn):
    normalized_title: str
    payload_json: dict[str, Any]
    updated_at: Optional[str] = None


class HealthResponse(BaseModel):
    status: str


class AuthRegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=8, max_length=128)


class AuthLoginIn(BaseModel):
    username: str
    password: str


class AuthTokenOut(BaseModel):
    token: str


class SyncSnapshotOut(BaseModel):
    watchlist: list[dict[str, Any]] = Field(default_factory=list)
    episode_progress: list[dict[str, Any]] = Field(default_factory=list)
