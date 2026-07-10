import os
from contextlib import contextmanager
from typing import Optional
from pathlib import Path

import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool

_pool: Optional[SimpleConnectionPool] = None


def build_dsn() -> str:
    host = os.getenv("PGHOST")
    if host:
        port = os.getenv("PGPORT", "5432")
        dbname = os.getenv("PGDATABASE", "WatchTracker")
        user = os.getenv("PGUSER", "postgres")
        password = os.getenv("PGPASSWORD", "")

        parts = [f"host={host}", f"port={port}", f"dbname={dbname}", f"user={user}"]
        if password:
            parts.append(f"password={password}")
        return " ".join(parts)

    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return database_url

    return "host=localhost port=5432 dbname=WatchTracker user=postgres"


def get_pool() -> SimpleConnectionPool:
    global _pool
    if _pool is None:
        _pool = SimpleConnectionPool(1, 10, dsn=build_dsn())
    return _pool


@contextmanager
def connection():
    pool = get_pool()
    conn = pool.getconn()
    conn.autocommit = False
    conn.rollback()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


@contextmanager
def cursor():
    with connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            yield cur


def initialize_schema(schema_filename: str = "sql/watchtracker_schema.sql") -> None:
    schema_path = Path(__file__).resolve().parent / schema_filename
    schema_sql = schema_path.read_text(encoding="utf-8")
    pool = get_pool()
    conn = pool.getconn()
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(schema_sql)
            cur.execute(
                """
                DO $$
                DECLARE legacy_user_id BIGINT;
                BEGIN
                    INSERT INTO users (username, password_hash)
                    VALUES ('legacy', 'disabled')
                    ON CONFLICT (username) DO NOTHING;

                    SELECT id INTO legacy_user_id FROM users WHERE username = 'legacy' LIMIT 1;

                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'watchlist' AND column_name = 'user_id'
                    ) THEN
                        ALTER TABLE watchlist ADD COLUMN user_id BIGINT;
                        UPDATE watchlist SET user_id = legacy_user_id WHERE user_id IS NULL;
                        ALTER TABLE watchlist ALTER COLUMN user_id SET NOT NULL;
                    END IF;

                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'episode_progress' AND column_name = 'user_id'
                    ) THEN
                        ALTER TABLE episode_progress ADD COLUMN user_id BIGINT;
                        UPDATE episode_progress SET user_id = legacy_user_id WHERE user_id IS NULL;
                        ALTER TABLE episode_progress ALTER COLUMN user_id SET NOT NULL;
                    END IF;

                    ALTER TABLE watchlist DROP CONSTRAINT IF EXISTS watchlist_pkey;
                    ALTER TABLE episode_progress DROP CONSTRAINT IF EXISTS episode_progress_pkey;

                    ALTER TABLE watchlist
                        ADD CONSTRAINT watchlist_pkey PRIMARY KEY (user_id, id, media_type);
                    ALTER TABLE episode_progress
                        ADD CONSTRAINT episode_progress_pkey PRIMARY KEY (user_id, media_id, season_number, episode_number);

                    IF NOT EXISTS (
                        SELECT 1 FROM pg_constraint WHERE conname = 'watchlist_user_id_fkey'
                    ) THEN
                        ALTER TABLE watchlist
                            ADD CONSTRAINT watchlist_user_id_fkey
                            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
                    END IF;

                    IF NOT EXISTS (
                        SELECT 1 FROM pg_constraint WHERE conname = 'episode_progress_user_id_fkey'
                    ) THEN
                        ALTER TABLE episode_progress
                            ADD CONSTRAINT episode_progress_user_id_fkey
                            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
                    END IF;

                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'auth_tokens' AND column_name = 'expires_at'
                    ) THEN
                        ALTER TABLE auth_tokens
                            ADD COLUMN expires_at TIMESTAMPTZ;
                        UPDATE auth_tokens
                            SET expires_at = created_at + interval '30 days'
                            WHERE expires_at IS NULL;
                        ALTER TABLE auth_tokens
                            ALTER COLUMN expires_at SET NOT NULL;
                    END IF;

                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'auth_tokens' AND column_name = 'revoked_at'
                    ) THEN
                        ALTER TABLE auth_tokens
                            ADD COLUMN revoked_at TIMESTAMPTZ;
                    END IF;

                    CREATE INDEX IF NOT EXISTS idx_auth_tokens_expires_at
                        ON auth_tokens (expires_at);

                    ALTER TABLE watchlist
                        ALTER COLUMN added_at TYPE DATE USING added_at::date;
                    ALTER TABLE episode_progress
                        ALTER COLUMN updated_at TYPE DATE USING updated_at::date;
                    ALTER TABLE anime_structures
                        ALTER COLUMN updated_at TYPE DATE USING updated_at::date;
                END $$;
                """
            )
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.autocommit = False
        pool.putconn(conn)
