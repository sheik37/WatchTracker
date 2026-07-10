#!/bin/sh
set -eu
. /volume1/homes/sheik37.v/docker/common/.secrets
. /volume1/homes/sheik37.v/docker/common/common.sh

USED=$(df -P /volume1 | awk 'NR==2 {gsub("%","",$5); print $5}')
if [ "$USED" -ge 85 ]; then
  TITLE="WatchTracker • Infra • DISK_HIGH"
  MSG="/volume1 a ${USED}% d utilisation."
  log_alert "WARN" "$TITLE" "$MSG"
  notify_discord "$TITLE" "$MSG"
fi