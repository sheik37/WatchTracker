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
: "${POSTGRES_DB:?POSTGRES_DB is required in BD/.env}"

BACKUP_DIR="${BACKUP_DIR:-$BASE_DIR/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-watchtracker_postgres}"

fail() {
  MESSAGE="$1"
  log_error "$MESSAGE"
  exit 1
}

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
TMP_SQL="$BACKUP_DIR/.watchtracker_${TIMESTAMP}.sql"
BACKUP_FILE="$BACKUP_DIR/watchtracker_${TIMESTAMP}.sql.gz"

if ! docker exec "$CONTAINER_NAME" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists > "$TMP_SQL"; then
  rm -f "$TMP_SQL"
  fail "PostgreSQL dump failed (container=$CONTAINER_NAME db=$POSTGRES_DB)."
fi

if ! gzip -c "$TMP_SQL" > "$BACKUP_FILE"; then
  rm -f "$TMP_SQL"
  fail "Gzip compression failed for backup file."
fi
rm -f "$TMP_SQL"

if ! find "$BACKUP_DIR" -type f -name "watchtracker_*.sql.gz" -mtime +"$RETENTION_DAYS" -delete; then
  log_error "Retention cleanup failed for $BACKUP_DIR."
fi

log_info "Backup created: $BACKUP_FILE"
