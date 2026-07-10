DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'watchtracker_app') THEN
        CREATE ROLE watchtracker_app LOGIN PASSWORD 'CHANGE_ME_STRONG';
    END IF;
END $$;

GRANT CONNECT ON DATABASE watchtracker TO watchtracker_app;
GRANT USAGE ON SCHEMA public TO watchtracker_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO watchtracker_app;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO watchtracker_app;

ALTER DEFAULT PRIVILEGES FOR ROLE watchtracker_admin IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO watchtracker_app;

ALTER DEFAULT PRIVILEGES FOR ROLE watchtracker_admin IN SCHEMA public
GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO watchtracker_app;