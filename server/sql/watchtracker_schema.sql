BEGIN;

CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    email_verified_at TIMESTAMPTZ,
    created_at DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE IF NOT EXISTS auth_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 days'),
    revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS auth_refresh_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    replaced_by_token_hash TEXT
);

CREATE TABLE IF NOT EXISTS email_verification_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS password_history (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS email_delivery_events (
    id BIGSERIAL PRIMARY KEY,
    email_type TEXT NOT NULL CHECK (email_type IN ('verification', 'password_reset')),
    quota_day DATE NOT NULL DEFAULT CURRENT_DATE,
    status TEXT NOT NULL CHECK (status IN ('reserved', 'sent', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth_rate_limit_states (
    endpoint TEXT NOT NULL,
    scope_key TEXT NOT NULL,
    failure_count INTEGER NOT NULL DEFAULT 0,
    first_failure_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_failure_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    blocked_until TIMESTAMPTZ,
    PRIMARY KEY (endpoint, scope_key)
);

CREATE TABLE IF NOT EXISTS watchlist (
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id INTEGER NOT NULL,
    title TEXT NOT NULL,
    poster_path TEXT,
    media_type TEXT NOT NULL CHECK (media_type IN ('movie', 'tv')),
    content_category TEXT NOT NULL CHECK (content_category IN ('films', 'series', 'anime')),
    content_status TEXT NOT NULL,
    total_episodes INTEGER NOT NULL DEFAULT 0,
    added_at DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (user_id, id, media_type)
);

CREATE TABLE IF NOT EXISTS episode_progress (
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    media_id INTEGER NOT NULL,
    season_number INTEGER NOT NULL,
    episode_number INTEGER NOT NULL,
    is_watched BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (user_id, media_id, season_number, episode_number)
);

CREATE TABLE IF NOT EXISTS anime_structures (
    normalized_title TEXT PRIMARY KEY,
    season TEXT CHECK (season IN ('WINTER', 'SPRING', 'SUMMER', 'FALL')),
    season_year INTEGER,
    payload_json JSONB NOT NULL,
    updated_at DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE INDEX IF NOT EXISTS idx_watchlist_category
    ON watchlist (user_id, content_category);

CREATE INDEX IF NOT EXISTS idx_episode_progress_media
    ON episode_progress (user_id, media_id);

CREATE INDEX IF NOT EXISTS idx_auth_tokens_user_id
    ON auth_tokens (user_id);

CREATE INDEX IF NOT EXISTS idx_auth_tokens_expires_at
    ON auth_tokens (expires_at);

CREATE INDEX IF NOT EXISTS idx_auth_refresh_tokens_user_id
    ON auth_refresh_tokens (user_id);

CREATE INDEX IF NOT EXISTS idx_auth_refresh_tokens_expires_at
    ON auth_refresh_tokens (expires_at);

CREATE INDEX IF NOT EXISTS idx_email_verification_tokens_user_id
    ON email_verification_tokens (user_id);

CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_user_id
    ON password_reset_tokens (user_id);

CREATE INDEX IF NOT EXISTS idx_password_history_user_id_created_at
    ON password_history (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_delivery_events_quota_day_status
    ON email_delivery_events (quota_day, status);

CREATE INDEX IF NOT EXISTS idx_auth_rate_limit_states_last_failure_at
    ON auth_rate_limit_states (last_failure_at);

CREATE INDEX IF NOT EXISTS idx_anime_structures_season_year
    ON anime_structures (season_year);

COMMIT;
