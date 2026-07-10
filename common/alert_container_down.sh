#!/bin/sh
set -eu
. /volume1/homes/sheik37.v/docker/common/.secrets
. /volume1/homes/sheik37.v/docker/common/common.sh

for c in watchtracker_api-api-1 watchtracker_postgres; do
  if ! docker inspect -f "{{.State.Running}}" "$c" 2>/dev/null | grep -q true; then
    sleep 20
    if ! docker inspect -f "{{.State.Running}}" "$c" 2>/dev/null | grep -q true; then
      TITLE="WatchTracker • Infra • CONTAINER_DOWN"
      MSG="$c est arrete."
      log_alert "ERROR" "$TITLE" "$MSG"
      notify_discord "$TITLE" "$MSG"
    fi
  fi
done