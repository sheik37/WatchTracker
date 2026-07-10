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
fi

: "${POSTGRES_USER:?POSTGRES_USER is required in BD/.env}"

BACKUP_DIR="${BACKUP_DIR:-$BASE_DIR/backups}"
CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-watchtracker_postgres}"
RESTORE_TEST_DB="${RESTORE_TEST_DB:-watchtracker_restore_test}"
DROP_AFTER_TEST="${RESTORE_DROP_AFTER_TEST:-true}"

fail() {
  MESSAGE="$1"
  log_error "$MESSAGE"
  exit 1
}

if [ "${1:-}" != "" ]; then
  BACKUP_FILE="$1"
else
  BACKUP_FILE="$(ls -1t "$BACKUP_DIR"/watchtracker_*.sql.gz "$BACKUP_DIR"/.watchtracker_*.sql.gz 2>/dev/null | head -n 1 || true)"
fi

if [ ! -f "$BACKUP_FILE" ]; then
  fail "Backup file not found: $BACKUP_FILE"
fi

if ! docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$RESTORE_TEST_DB\";"; then
  fail "Cannot drop restore test database: $RESTORE_TEST_DB."
fi
if ! docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$RESTORE_TEST_DB\";"; then
  fail "Cannot create restore test database: $RESTORE_TEST_DB."
fi
if ! gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$RESTORE_TEST_DB" >/dev/null; then
  fail "Restore import failed from backup: $BACKUP_FILE."
fi

TABLE_COUNT="$(docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$RESTORE_TEST_DB" -Atc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")"
log_info "Restore test OK on $RESTORE_TEST_DB from $BACKUP_FILE (public tables: $TABLE_COUNT)"

if [ "$DROP_AFTER_TEST" = "true" ]; then
  if ! docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$RESTORE_TEST_DB\";"; then
    fail "Restore test succeeded but cleanup drop failed: $RESTORE_TEST_DB."
  fi
  log_info "Restore test database dropped: $RESTORE_TEST_DB"
fi
