BEGIN;

CREATE TABLE IF NOT EXISTS watchlist (
    id INTEGER NOT NULL,
    title TEXT NOT NULL,
    poster_path TEXT,
    media_type TEXT NOT NULL CHECK (media_type IN ('movie', 'tv')),
    content_category TEXT NOT NULL CHECK (content_category IN ('films', 'series', 'anime')),
    content_status TEXT NOT NULL,
    total_episodes INTEGER NOT NULL DEFAULT 0,
    added_at DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (id, media_type)
);

CREATE TABLE IF NOT EXISTS episode_progress (
    media_id INTEGER NOT NULL,
    season_number INTEGER NOT NULL,
    episode_number INTEGER NOT NULL,
    is_watched BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (media_id, season_number, episode_number)
);

CREATE TABLE IF NOT EXISTS anime_structures (
    normalized_title TEXT PRIMARY KEY,
    season TEXT CHECK (season IN ('WINTER', 'SPRING', 'SUMMER', 'FALL')),
    season_year INTEGER,
    payload_json JSONB NOT NULL,
    updated_at DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE INDEX IF NOT EXISTS idx_watchlist_category
    ON watchlist (content_category);

CREATE INDEX IF NOT EXISTS idx_episode_progress_media
    ON episode_progress (media_id);

CREATE INDEX IF NOT EXISTS idx_anime_structures_season_year
    ON anime_structures (season_year);

COMMIT;
