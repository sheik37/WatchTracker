import os
from contextlib import contextmanager
from pathlib import Path
from typing import Optional

import psycopg2  # noqa: F401 - requis pour la compatibilité psycopg2.extras/pool
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool

from security import hash_password as _hash_password
from security import verify_password as _verify_password

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
            # Le bloc DO $$ ci-dessous ne contient plus que de vraies migrations
            # incrémentales pour les bases existantes créées avant l'ajout de
            # certaines tables/colonnes/index à watchtracker_schema.sql
            # (ALTER TABLE, changements de PK/FK, backfills de données,
            # suppression de table obsolète). Les tables et index déjà définis
            # dans watchtracker_schema.sql (exécuté juste au-dessus, avec
            # CREATE TABLE/INDEX IF NOT EXISTS) ne sont plus recréés ici pour
            # éviter la duplication du schéma entre les deux fichiers.
            cur.execute("""
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

                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'episode_progress' AND column_name = 'sync_updated_at'
                    ) THEN
                        ALTER TABLE episode_progress
                            ADD COLUMN sync_updated_at TIMESTAMPTZ;
                        UPDATE episode_progress
                            SET sync_updated_at = updated_at
                            WHERE sync_updated_at IS NULL;
                        ALTER TABLE episode_progress
                            ALTER COLUMN sync_updated_at SET NOT NULL;
                    END IF;

                    -- watchlist_tombstones, episode_progress_tombstones,
                    -- episode_watch_events et movie_watch_events sont déjà
                    -- créées par watchtracker_schema.sql ci-dessus ; plus
                    -- besoin de les recréer ici.

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

                    -- email_verification_tokens, password_reset_tokens,
                    -- password_history, email_delivery_events,
                    -- auth_refresh_tokens, auth_rate_limit_states et tous
                    -- leurs index sont déjà créés par
                    -- watchtracker_schema.sql ci-dessus ; plus besoin de les
                    -- recréer ici.

                    INSERT INTO episode_watch_events (
                        user_id,
                        media_id,
                        season_number,
                        episode_number,
                        watched_at,
                        created_at
                    )
                    SELECT
                        ep.user_id,
                        ep.media_id,
                        ep.season_number,
                        ep.episode_number,
                        ep.updated_at,
                        ep.updated_at
                    FROM episode_progress ep
                    WHERE ep.is_watched = true
                      AND NOT EXISTS (
                          SELECT 1
                          FROM episode_watch_events ev
                          WHERE ev.user_id = ep.user_id
                            AND ev.media_id = ep.media_id
                            AND ev.season_number = ep.season_number
                            AND ev.episode_number = ep.episode_number
                      );

                    INSERT INTO movie_watch_events (
                        user_id,
                        media_id,
                        watched_at,
                        created_at
                    )
                    SELECT
                        w.user_id,
                        w.id,
                        w.updated_at,
                        w.updated_at
                    FROM watchlist w
                    WHERE w.media_type = 'movie'
                      AND w.content_status = 'watched'
                      AND NOT EXISTS (
                          SELECT 1
                          FROM movie_watch_events mv
                          WHERE mv.user_id = w.user_id
                            AND mv.media_id = w.id
                      );

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
                    -- episode_progress_tombstones est déjà créée par
                    -- watchtracker_schema.sql ci-dessus (et avait déjà été
                    -- recréée plus haut dans ce même bloc de migration).
                    DROP TABLE IF EXISTS anime_structures;
                END $$;
                """)

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
                    if not _verify_password(
                        admin_password, existing_admin["password_hash"]
                    ):
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
