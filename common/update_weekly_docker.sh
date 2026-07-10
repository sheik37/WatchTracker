#!/bin/sh
set -eu

ROOT_DIR="/volume1/homes/sheik37.v/docker"
DB_DIR="$ROOT_DIR/watchtracker_db"
API_DIR="$ROOT_DIR/watchtracker_api"
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"

. "$ROOT_DIR/common/.secrets"
. "$ROOT_DIR/common/common.sh"

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/update-weekly-$STAMP.log"

UPDATE_POSTGRES="${UPDATE_POSTGRES:-false}"

exec >>"$LOG_FILE" 2>&1

log_info "Start weekly docker update"

# 0) Sauvegarde des version docker avant update
SNAP_DIR="/volume1/homes/sheik37.v/docker/logs/image-snapshots"
mkdir -p "$SNAP_DIR"
SNAP_FILE="$SNAP_DIR/images_before_update_$(date +%Y%m%d_%H%M%S).txt"
docker image prune -f
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" > "$SNAP_FILE"

# 1) backup before update
cd "$DB_DIR"
./scripts/backup_postgres.sh

# 2) pull/update DB stack (pgadmin always, postgres optional)
docker compose pull pgadmin
docker compose up -d pgadmin

if [ "$UPDATE_POSTGRES" = "true" ]; then
  docker compose pull postgres
  docker compose up -d postgres
fi

# 3) pull/update API stack
cd "$API_DIR"
docker compose pull
docker compose up -d

# 4) health check
if curl -fsS https://watchtracker-api.duckdns.org/health >/dev/null; then
  notify_discord "WatchTracker • Update Weekly • OK" "MAJ Docker terminee. Log: $LOG_FILE"
else
  notify_discord "WatchTracker • Update Weekly • ERROR" "Healthcheck KO apres MAJ. Log: $LOG_FILE"
  exit 1
fi