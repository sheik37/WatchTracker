#!/bin/sh
set -eu

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMMON_DIR="${COMMON_DIR:-$(dirname "$BASE_DIR")/common}"
ENV_FILE="$BASE_DIR/.env"
COMMON_SH_FILE="$COMMON_DIR/common.sh"
COMMON_SECRETS_FILE="${COMMON_SECRETS_FILE:-$COMMON_DIR/.secrets}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
. "$ENV_FILE"
if [ -f "$COMMON_SECRETS_FILE" ]; then
  # shellcheck disable=SC1090
  . "$COMMON_SECRETS_FILE"
fi

if [ -f "$COMMON_SH_FILE" ]; then
  # shellcheck disable=SC1090
  . "$COMMON_SH_FILE"
else
  log_info() { echo "[INFO] $1"; }
  log_error() { echo "[ERROR] $1" >&2; }
  notify_discord() { :; }
fi

: "${POSTGRES_USER:?POSTGRES_USER is required in BD/.env}"
: "${POSTGRES_DB:?POSTGRES_DB is required in BD/.env}"

CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-watchtracker_postgres}"
API_CONTAINER_NAME="${API_CONTAINER_NAME:-watchtracker_api-api-1}"
STOP_API_DURING_RESTORE="${STOP_API_DURING_RESTORE:-true}"
BACKUP_BEFORE_RESTORE="${BACKUP_BEFORE_RESTORE:-true}"
RESTORE_NOTIFY_ON_SUCCESS="${RESTORE_NOTIFY_ON_SUCCESS:-true}"
HOSTNAME_VALUE="$(hostname 2>/dev/null || echo unknown)"
API_STOPPED_FOR_RESTORE="false"

usage() {
  echo "Usage: $0 <backup_file.sql.gz> --yes"
  echo "Example: $0 $BASE_DIR/backups/watchtracker_20260707_030000.sql.gz --yes"
  exit 1
}

notify_restore() {
  LEVEL="$1"
  MESSAGE="$2"
  notify_discord "WatchTracker • RestoreProd • $LEVEL" "$MESSAGE (host=$HOSTNAME_VALUE)"
}

restart_api_if_needed() {
  if [ "$API_STOPPED_FOR_RESTORE" = "true" ]; then
    if docker start "$API_CONTAINER_NAME" >/dev/null; then
      log_info "API container restarted: $API_CONTAINER_NAME"
    else
      log_error "Failed to restart API container: $API_CONTAINER_NAME"
    fi
    API_STOPPED_FOR_RESTORE="false"
  fi
}

fail() {
  MESSAGE="$1"
  log_error "$MESSAGE"
  restart_api_if_needed
  notify_restore "ERROR" "$MESSAGE"
  exit 1
}

[ "${1:-}" != "" ] || usage
BACKUP_FILE="$1"
[ "${2:-}" = "--yes" ] || fail "Confirmation required. Re-run with --yes."

if [ ! -f "$BACKUP_FILE" ]; then
  fail "Backup file not found: $BACKUP_FILE"
fi

if [ "$BACKUP_BEFORE_RESTORE" = "true" ]; then
  if [ -x "$BASE_DIR/scripts/backup_postgres.sh" ]; then
    log_info "Creating pre-restore safety backup..."
    if ! "$BASE_DIR/scripts/backup_postgres.sh"; then
      fail "Pre-restore safety backup failed. Restore aborted."
    fi
  else
    fail "backup_postgres.sh not found or not executable."
  fi
fi

if [ "$STOP_API_DURING_RESTORE" = "true" ]; then
  if docker inspect -f "{{.State.Running}}" "$API_CONTAINER_NAME" 2>/dev/null | grep -q true; then
    log_info "Stopping API container: $API_CONTAINER_NAME"
    if ! docker stop "$API_CONTAINER_NAME" >/dev/null; then
      fail "Cannot stop API container: $API_CONTAINER_NAME"
    fi
    API_STOPPED_FOR_RESTORE="true"
  else
    log_info "API container already stopped: $API_CONTAINER_NAME"
  fi
fi

log_info "Starting production restore into database: $POSTGRES_DB"
if ! gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null; then
  fail "Production restore failed from backup: $BACKUP_FILE"
fi

TABLE_COUNT="$(docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")"
log_info "Production restore completed (public tables: $TABLE_COUNT)"

restart_api_if_needed

if [ "$RESTORE_NOTIFY_ON_SUCCESS" = "true" ]; then
  notify_restore "OK" "Production restore completed for $POSTGRES_DB from $BACKUP_FILE (public tables: $TABLE_COUNT)"
fi

