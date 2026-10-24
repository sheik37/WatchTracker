#!/bin/sh
set -eu
. /volume1/homes/sheik37.v/docker/common/.secrets
. /volume1/homes/sheik37.v/docker/common/common.sh

API_CONTAINER_NAME="${API_CONTAINER_NAME:-watchtracker_api-api-1}"
POSTGRES_CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-watchtracker_postgres}"

for c in $API_CONTAINER_NAME $POSTGRES_CONTAINER_NAME; do
  if container_is_running "$c" 20; then
    wt_alert_clear "container_down_$c"
  else
    if wt_alert_should_fire "container_down_$c"; then
      TITLE="WatchTracker • Infra • CONTAINER_DOWN"
      MSG="$c est arrete."
      log_alert "ERROR" "$TITLE" "$MSG"
      notify_discord "$TITLE" "$MSG"
    fi
  fi
done