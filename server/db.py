import os
import hashlib
import hmac
import secrets
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
                        ADD CONSTRAINT watchlist_pkey PRIMARY KEY (user_id, id, media_type, content_category);
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
                        WHERE table_name = 'watchlist' AND column_name = 'updated_at'
                    ) THEN
                        ALTER TABLE watchlist
                            ADD COLUMN updated_at TIMESTAMPTZ;
                        UPDATE watchlist
                            SET updated_at = now()
                            WHERE updated_at IS NULL;
                        ALTER TABLE watchlist
                            ALTER COLUMN updated_at SET NOT NULL;
                    END IF;

                    CREATE TABLE IF NOT EXISTS watchlist_tombstones (
                        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        id INTEGER NOT NULL,
                        media_type TEXT NOT NULL CHECK (media_type IN ('movie', 'tv')),
                        content_category TEXT NOT NULL CHECK (content_category IN ('films', 'series', 'anime')),
                        deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                        PRIMARY KEY (user_id, id, media_type, content_category)
                    );

                    CREATE TABLE IF NOT EXISTS episode_progress_tombstones (
                        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        media_id INTEGER NOT NULL,
                        season_number INTEGER NOT NULL,
                        episode_number INTEGER NOT NULL,
                        deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                        PRIMARY KEY (user_id, media_id, season_number, episode_number)
                    );

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

                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'auth_tokens' AND column_name = 'token_hash'
                    ) THEN
                        TRUNCATE TABLE auth_tokens;
                        ALTER TABLE auth_tokens
                            DROP CONSTRAINT IF EXISTS auth_tokens_pkey;
                        ALTER TABLE auth_tokens
                            ADD COLUMN token_hash TEXT;
                        ALTER TABLE auth_tokens
                            ALTER COLUMN token_hash SET NOT NULL;
                        ALTER TABLE auth_tokens
                            ADD CONSTRAINT auth_tokens_pkey PRIMARY KEY (token_hash);
                    END IF;

                    IF EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'auth_tokens' AND column_name = 'token'
                    ) THEN
                        ALTER TABLE auth_tokens
                            DROP COLUMN token;
                    END IF;

                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'users' AND column_name = 'email_verified_at'
                    ) THEN
                        ALTER TABLE users
                            ADD COLUMN email_verified_at TIMESTAMPTZ;
                        UPDATE users
                            SET email_verified_at = now()
                            WHERE email_verified_at IS NULL;
                    END IF;

                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'users' AND column_name = 'display_name'
                    ) THEN
                        ALTER TABLE users
                            ADD COLUMN display_name TEXT;
                    END IF;

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

                    CREATE TABLE IF NOT EXISTS auth_refresh_tokens (
                        token_hash TEXT PRIMARY KEY,
                        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        family_id TEXT NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                        expires_at TIMESTAMPTZ NOT NULL,
                        revoked_at TIMESTAMPTZ,
                        replaced_by_token_hash TEXT
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
                    CREATE INDEX IF NOT EXISTS idx_watchlist_tombstones_user_deleted
                        ON watchlist_tombstones (user_id, deleted_at DESC);
                    CREATE INDEX IF NOT EXISTS idx_episode_progress_tombstones_user_deleted
                        ON episode_progress_tombstones (user_id, deleted_at DESC);

                    INSERT INTO password_history (user_id, password_hash, created_at)
                    SELECT u.id, u.password_hash, now()
                    FROM users u
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM password_history ph
                        WHERE ph.user_id = u.id
                    );

                    ALTER TABLE watchlist
                        ALTER COLUMN added_at TYPE DATE USING added_at::date;
                    ALTER TABLE watchlist
                        ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at::timestamptz;
                    ALTER TABLE episode_progress
                        ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at::timestamptz;
                    CREATE TABLE IF NOT EXISTS episode_progress_tombstones (
                        user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        media_id INTEGER NOT NULL,
                        season_number INTEGER NOT NULL,
                        episode_number INTEGER NOT NULL,
                        deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                        PRIMARY KEY (user_id, media_id, season_number, episode_number)
                    );
                    DROP TABLE IF EXISTS anime_structures;
                END $$;
                """
            )

            admin_email = os.getenv("ADMIN_BOOTSTRAP_EMAIL", "").strip().lower()
            admin_password = os.getenv("ADMIN_BOOTSTRAP_PASSWORD", "").strip()
            if admin_email and admin_password:
                cur.execute(
                    """
                    SELECT id, password_hash, email_verified_at
                    FROM users
                    WHERE username = %s
                    LIMIT 1
                    """,
                    (admin_email,),
                )
                existing_admin = cur.fetchone()
                if existing_admin is None:
                    password_hash = _hash_password(admin_password)
                    cur.execute(
                        """
                        INSERT INTO users (username, password_hash, email_verified_at)
                        VALUES (%s, %s, now())
                        RETURNING id
                        """,
                        (admin_email, password_hash),
                    )
                    admin_user_id = cur.fetchone()[0]
                    cur.execute(
                        """
                        INSERT INTO password_history (user_id, password_hash)
                        VALUES (%s, %s)
                        """,
                        (admin_user_id, password_hash),
                    )
                else:
                    if existing_admin["email_verified_at"] is None:
                        cur.execute(
                            """
                            UPDATE users
                            SET email_verified_at = now()
                            WHERE id = %s
                            """,
                            (existing_admin["id"],),
                        )
                    if not _verify_password(admin_password, existing_admin["password_hash"]):
                        password_hash = _hash_password(admin_password)
                        cur.execute(
                            """
                            UPDATE users
                            SET password_hash = %s
                            WHERE id = %s
                            """,
                            (password_hash, existing_admin["id"]),
                        )
                        cur.execute(
                            """
                            INSERT INTO password_history (user_id, password_hash)
                            VALUES (%s, %s)
                            """,
                            (existing_admin["id"], password_hash),
                        )
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.autocommit = False
        pool.putconn(conn)


def _hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    rounds = 150_000
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        rounds,
    ).hex()
    return f"pbkdf2_sha256${rounds}${salt}${digest}"


def _verify_password(password: str, encoded: str) -> bool:
    try:
        algo, rounds_text, salt, digest = encoded.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        rounds = int(rounds_text)
    except (TypeError, ValueError):
        return False
    check = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), rounds).hex()
    return hmac.compare_digest(check, digest)
