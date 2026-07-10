#!/bin/sh
set -eu
. /volume1/homes/sheik37.v/docker/common/.secrets
. /volume1/homes/sheik37.v/docker/common/common.sh

LOG_DIR="${WATCHTRACKER_LOG_DIR:-/volume1/homes/sheik37.v/docker/logs}"
AUTH_IP_LOG="$LOG_DIR/task-alert-auth-ip.log"
mkdir -p "$LOG_DIR"

AUTH_WINDOW_LOGS="$(docker logs watchtracker_api-api-1 --since 15m 2>&1 || true)"

printf "%s\n" "$AUTH_WINDOW_LOGS" | grep "event=auth_login_failed" | sed -n "s/.*ip=\([^ ]*\).*/\1/p" | while IFS= read -r ip; do
  [ -n "$ip" ] || continue
  printf "[%s] ip=%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$ip" >> "$AUTH_IP_LOG"
done

if printf "%s\n" "$AUTH_WINDOW_LOGS" | grep -q "event=AUTH_ALERT"; then
  TITLE="WatchTracker • Security • AUTH_ALERT"
  MSG="AUTH_ALERT detecte sur les 15 dernieres minutes."
  log_alert "WARN" "$TITLE" "$MSG"
  notify_discord "$TITLE" "$MSG"
fi