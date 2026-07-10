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
  log_alert() { :; }
fi

ROOT_DIR="$(dirname "$BASE_DIR")"
SCRIPTS_DIR="$BASE_DIR/scripts"
LOG_DIR="${WATCHTRACKER_LOG_DIR:-$ROOT_DIR/logs}"
ARCHIVE_DIR="$LOG_DIR/archives"
BACKUP_LOG="$LOG_DIR/backup.log"
RESTORE_LOG="$LOG_DIR/restore-test.log"
SYNCHRO_LOG="$LOG_DIR/synchro.log"
DAILY_OPS_LOG="$LOG_DIR/daily-ops.log"

API_CONTAINER_NAME="${API_CONTAINER_NAME:-watchtracker_api-api-1}"
POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-watchtracker_postgres}"
RUN_RESTORE_TEST_ON_WEEKDAY="${RUN_RESTORE_TEST_ON_WEEKDAY:-7}" # 1=Mon ... 7=Sun
RUN_WEEKLY_AUDIT_ON_WEEKDAY="${RUN_WEEKLY_AUDIT_ON_WEEKDAY:-7}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
HYPERBACKUP_TASK_ID="${HYPERBACKUP_TASK_ID:-}"

mkdir -p "$LOG_DIR" "$ARCHIVE_DIR"

REPORT_FILE="$LOG_DIR/.daily_ops_report.$$"
WEEKLY_REPORT_FILE="$LOG_DIR/.weekly_ops_report.$$"
: > "$REPORT_FILE"
: > "$WEEKLY_REPORT_FILE"

HAS_ERROR=0
HAS_WARN=0
WEEKLY_HAS_WARN=0

append_report() {
  printf "%s\n" "$1" >> "$REPORT_FILE"
}

append_weekly_report() {
  printf "%s\n" "$1" >> "$WEEKLY_REPORT_FILE"
}

mark_error() {
  HAS_ERROR=1
}

mark_warn() {
  if [ "$HAS_ERROR" -eq 0 ]; then
    HAS_WARN=1
  fi
}

mark_weekly_warn() {
  WEEKLY_HAS_WARN=1
}

run_backup() {
  if "$SCRIPTS_DIR/backup_postgres.sh" >> "$BACKUP_LOG" 2>&1; then
    append_report "✅ Backup DB: OK"
  else
    append_report "❌ Backup DB: ECHEC (voir $BACKUP_LOG)"
    mark_error
  fi
}

count_auth_alert_today_from_logs() {
  find "$LOG_DIR" -maxdepth 1 -type f -name "alerts.log" ! -name "$(basename "$DAILY_OPS_LOG")" -print 2>/dev/null | while IFS= read -r f; do
    grep -Eci "AUTH_ALERT" "$f" || true
  done | awk '{s+=$1} END {print s+0}'
}

count_pattern_last7_archives() {
  FILE_NAME="$1"
  PATTERN="$2"
  find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" 2>/dev/null | sort -r | head -n 7 | while IFS= read -r day_dir; do
    find "$ARCHIVE_DIR/$day_dir" -type f -name "$FILE_NAME" -print 2>/dev/null | while IFS= read -r f; do
      grep -Eci "$PATTERN" "$f" || true
    done
  done | awk '{s+=$1} END {print s+0}'
}

collect_top_ips_last7_logs() {
  {
    if [ -f "$LOG_DIR/task-alert-auth-ip.log" ]; then
      cat "$LOG_DIR/task-alert-auth-ip.log"
    fi
    find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" 2>/dev/null | sort -r | head -n 7 | while IFS= read -r day_dir; do
      if [ -f "$ARCHIVE_DIR/$day_dir/task-alert-auth-ip.log" ]; then
        cat "$ARCHIVE_DIR/$day_dir/task-alert-auth-ip.log"
      fi
    done
  } | sed -n "s/.*ip=\([^ ]*\).*/\1/p" | awk 'NF > 0 {print $0}' | sort | uniq -c | sort -nr | head -n 5 | awk '{printf "• IP: %s — %d tentative(s)\n", $2, $1}'
}

run_restore_test_if_scheduled() {
  DOW="$(date +%u)"
  if [ "$DOW" = "$RUN_RESTORE_TEST_ON_WEEKDAY" ]; then
    if "$SCRIPTS_DIR/restore_test_postgres.sh" >> "$RESTORE_LOG" 2>&1; then
      append_report "✅ Restore test: OK (jour planifie)"
    else
      append_report "❌ Restore test: ECHEC (voir $RESTORE_LOG)"
      mark_error
    fi
  else
    append_report "ℹ️ Restore test: non planifie aujourd'hui"
  fi
}

rotate_logs() {
  local archive_day
  archive_day="$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"

  local day_archive_dir="$ARCHIVE_DIR/$archive_day"
  mkdir -p "$day_archive_dir" || return 1

  find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" ! -name "$(basename "$DAILY_OPS_LOG")" | while IFS= read -r f; do
    base="$(basename "$f")"

    mv "$f" "$day_archive_dir/$base" || return 1
    : > "$f" || return 1
  done

  find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$LOG_RETENTION_DAYS" -exec rm -rf {} + || return 1
}

run_log_rotation() {
  if rotate_logs; then
    append_report "✅ Rotation logs: OK"
  else
    append_report "⚠️ Rotation logs: erreur partielle"
    mark_warn
  fi
}

run_hyperbackup_sync_if_configured() {
  if [ -n "$HYPERBACKUP_TASK_ID" ]; then
    if /var/packages/HyperBackup/target/bin/dsmbackup --backup "$HYPERBACKUP_TASK_ID" >> "$SYNCHRO_LOG" 2>&1; then
      append_report "✅ Hyper Backup run: OK"
    else
      append_report "❌ Hyper Backup run: ECHEC"
      mark_error
    fi
  else
    append_report "ℹ️ Hyper Backup run: non configure (HYPERBACKUP_TASK_ID vide)"
  fi
}

run_auth_alert_health_check() {
  ALERT_COUNT="$(count_auth_alert_today_from_logs)"
  if [ "$ALERT_COUNT" -gt 0 ]; then
    append_report "❌ AUTH_ALERT (1d): $ALERT_COUNT"
    mark_error
  else
    append_report "✅ AUTH_ALERT (1d): OK"
  fi
}

run_container_alert_health_check() {
   for c in $API_CONTAINER_NAME $POSTGRES_CONTAINER_NAME; do
     if ! docker inspect -f "{{.State.Running}}" "$c" 2>/dev/null | grep -q true; then
       sleep 20
       if ! docker inspect -f "{{.State.Running}}" "$c" 2>/dev/null | grep -q true; then
         append_report "❌ Container $c is not running"
         mark_error
       else
         append_report "⚠️ Container $c is restarting"
         mark_warn
       fi
     else
       append_report "✅ Container $c is running"
     fi
   done
}

run_disk_alert_health_check() {
  USED=$(df -P /volume1 | awk 'NR==2 {gsub("%","",$5); print $5}')
  if [ "$USED" -ge 85 ]; then
    append_report "❌ Disk usage: $USED% (>= 85%)"
    mark_error
  else
    append_report "✅ Disk usage: $USED% (< 85%)"
  fi
}

run_weekly_audit_if_scheduled() {
  DOW="$(date +%u)"
  if [ "$DOW" != "$RUN_WEEKLY_AUDIT_ON_WEEKDAY" ]; then
    return 0
  fi

  AUTH_ALERT_COUNT="$(count_pattern_last7_archives "alerts.log" "AUTH_ALERT")"
  TOP_IPS="$(collect_top_ips_last7_logs)"
  CONTAINER_DROPS_7D="$(count_pattern_last7_archives "alerts.log" "CONTAINER_DOWN")"
  BACKUP_ERRORS="$(grep -Ei "ERROR|failed|Backup file not found" "$BACKUP_LOG" "$RESTORE_LOG" 2>/dev/null | tail -n 10 || true)"

  append_weekly_report "📊 Weekly audit (7j):"
  append_weekly_report "   🔐 AUTH_ALERT count: $AUTH_ALERT_COUNT"
  if [ "$AUTH_ALERT_COUNT" -gt 0 ]; then
    mark_weekly_warn
  fi
  if [ -n "$TOP_IPS" ]; then
    append_weekly_report "   🌍 Top IP auth echecs:"
    printf "%s\n" "$TOP_IPS" | sed 's/^/     /' >> "$WEEKLY_REPORT_FILE"
  else
    append_weekly_report "   🌍 Top IP auth echecs: aucun"
  fi
  append_weekly_report "   🐳 Chutes conteneur (7j): $CONTAINER_DROPS_7D"
  if [ "$CONTAINER_DROPS_7D" -gt 0 ]; then
    mark_weekly_warn
  fi
  if [ -n "$BACKUP_ERRORS" ]; then
    append_weekly_report "  🗄️ Incidents backup/restore recents:"
    printf "%s\n" "$BACKUP_ERRORS" | sed 's/^/   - /' >> "$WEEKLY_REPORT_FILE"
    mark_weekly_warn
  else
    append_weekly_report "   🗄️ Incidents backup/restore recents: aucun"
  fi

  send_weekly_summary
}

send_summary() {
  TITLE="WatchTracker • Ops Daily • OK"
  LEVEL="INFO"
  if [ "$HAS_ERROR" -eq 1 ]; then
    TITLE="WatchTracker • Ops Daily • ERROR"
    LEVEL="ERROR"
  elif [ "$HAS_WARN" -eq 1 ]; then
    TITLE="WatchTracker • Ops Daily • WARN"cd
    LEVEL="WARN"
  fi

  SUMMARY="$(cat "$REPORT_FILE")"
  log_alert "$LEVEL" "$TITLE" "Execution quotidienne terminee"
  notify_discord "$TITLE" "$(printf '```text\n%s\n```' "$SUMMARY")"
}

send_weekly_summary() {
  WEEKLY_TITLE="WatchTracker • Ops Weekly • OK"
  WEEKLY_LEVEL="INFO"
  if [ "$WEEKLY_HAS_WARN" -eq 1 ]; then
    WEEKLY_TITLE="WatchTracker • Ops Weekly • WARN"
    WEEKLY_LEVEL="WARN"
  fi

  WEEKLY_SUMMARY="$(cat "$WEEKLY_REPORT_FILE")"
  if [ -n "$WEEKLY_SUMMARY" ]; then
    log_alert "$WEEKLY_LEVEL" "$WEEKLY_TITLE" "Weekly audit termine"
    notify_discord "$WEEKLY_TITLE" "$(printf '```text\n%s\n```' "$WEEKLY_SUMMARY")"
  fi
}

cleanup() {
  rm -f "$REPORT_FILE"
  rm -f "$WEEKLY_REPORT_FILE"
}
trap cleanup EXIT

run_backup
run_restore_test_if_scheduled
run_auth_alert_health_check
run_container_alert_health_check
run_disk_alert_health_check
run_log_rotation
run_hyperbackup_sync_if_configured
send_summary
run_weekly_audit_if_scheduled
