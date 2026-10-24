-- Mot de passe du role applicatif : NE JAMAIS committer de vraie valeur ici.
-- Ce script attend une variable psql "app_password" definie AVANT execution,
-- par exemple :
--   psql -v app_password='<mot_de_passe_reel>' -f watchtracker_app.sql
-- (valeur brute, sans guillemets supplementaires : psql les ajoute lui-meme)
-- La vraie valeur doit provenir d'un secret/variable d'environnement injecte
-- au moment du deploiement (ex: fichier .env/.secrets reel sur le NAS), et ne
-- doit jamais etre ecrite en clair dans ce depot. Si "app_password" n'est pas
-- definie, psql echouera avec une erreur explicite plutot que d'utiliser un
-- mot de passe par defaut faible.
\set ON_ERROR_STOP on
\if :{?app_password}
\else
    \warn 'Variable psql "app_password" non definie. Relancez avec : psql -v app_password=''<mot_de_passe_reel>'' -f watchtracker_app.sql'
    \quit
\endif

-- :'app_password' n'est pas substitue dans un bloc DO $$...$$ : on genere donc
-- la commande avec SELECT puis on l'execute avec \gexec.
SELECT format('CREATE ROLE watchtracker_app LOGIN PASSWORD %L', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'watchtracker_app')
\gexec

GRANT CONNECT ON DATABASE watchtracker TO watchtracker_app;
GRANT USAGE ON SCHEMA public TO watchtracker_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO watchtracker_app;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO watchtracker_app;

ALTER DEFAULT PRIVILEGES FOR ROLE watchtracker_admin IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO watchtracker_app;

ALTER DEFAULT PRIVILEGES FOR ROLE watchtracker_admin IN SCHEMA public
GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO watchtracker_app;