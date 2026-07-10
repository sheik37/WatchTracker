#!/bin/sh
set -eu

ROOT_DIR="/volume1/homes/sheik37.v/docker"
. "$ROOT_DIR/common/.secrets"
. "$ROOT_DIR/common/common.sh"

notify_discord "WatchTracker • Maintenance Mensuelle • WARN" "Verifier/faire: MAJ DSM + paquets Synology, dependances Python API, dependances Android, puis test fonctionnel."