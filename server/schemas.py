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
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=10, max_length=128)


class AuthLoginIn(BaseModel):
    email: str
    password: str
    otp_code: Optional[str] = Field(default=None, min_length=6, max_length=12)


class AuthResendVerificationIn(BaseModel):
    email: str = Field(min_length=5, max_length=254)


class AuthForgotPasswordIn(BaseModel):
    email: str = Field(min_length=5, max_length=254)


class AuthResetPasswordIn(BaseModel):
    token: str = Field(min_length=20, max_length=512)
    password: str = Field(min_length=10, max_length=128)


class AuthRefreshIn(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=512)


class AuthLogoutIn(BaseModel):
    refresh_token: Optional[str] = Field(default=None, min_length=20, max_length=512)


class AuthTokenOut(BaseModel):
    token: str
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in_seconds: int


class AuthRegisterOut(BaseModel):
    message: str


class AuthMeOut(BaseModel):
    user_id: int
    email: str


class SyncSnapshotOut(BaseModel):
    watchlist: list[dict[str, Any]] = Field(default_factory=list)
    episode_progress: list[dict[str, Any]] = Field(default_factory=list)
