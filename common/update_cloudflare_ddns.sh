#!/bin/sh
set -eu

ROOT_DIR="${ROOT_DIR:-/volume1/homes/sheik37.v/docker}"
SECRETS_FILE="${SECRETS_FILE:-$ROOT_DIR/common/.secrets}"
COMMON_FILE="${COMMON_FILE:-$ROOT_DIR/common/common.sh}"

if [ -f "$SECRETS_FILE" ]; then
  # shellcheck disable=SC1090
  . "$SECRETS_FILE"
fi

if [ -f "$COMMON_FILE" ]; then
  # shellcheck disable=SC1090
  . "$COMMON_FILE"
else
  log_info() { echo "[INFO] $1"; }
  log_error() { echo "[ERROR] $1" >&2; }
fi

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"
: "${CLOUDFLARE_ZONE_ID:?CLOUDFLARE_ZONE_ID is required}"
: "${CLOUDFLARE_DNS_RECORD_NAME:?CLOUDFLARE_DNS_RECORD_NAME is required (example: api.watchtracker.net)}"

CLOUDFLARE_DNS_TTL="${CLOUDFLARE_DNS_TTL:-1}"
CLOUDFLARE_DNS_PROXIED="${CLOUDFLARE_DNS_PROXIED:-true}"
PUBLIC_IP_PROVIDER="${PUBLIC_IP_PROVIDER:-https://api.ipify.org}"

api_call() {
  METHOD="$1"
  URL="$2"
  BODY="${3:-}"
  if [ -n "$BODY" ]; then
    curl -fsS -X "$METHOD" "$URL" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$BODY"
  else
    curl -fsS -X "$METHOD" "$URL" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json"
  fi
}

PUBLIC_IP="$(curl -fsS "$PUBLIC_IP_PROVIDER" | tr -d '\r\n')"
if [ -z "$PUBLIC_IP" ]; then
  log_error "Unable to detect public IPv4 address."
  exit 1
fi

log_info "Current public IP: $PUBLIC_IP"

LOOKUP_URL="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=A&name=$CLOUDFLARE_DNS_RECORD_NAME"
LOOKUP_JSON="$(api_call GET "$LOOKUP_URL")"

if ! printf '%s' "$LOOKUP_JSON" | grep -q '"success":true'; then
  log_error "Cloudflare API lookup failed."
  exit 1
fi

RECORD_ID="$(printf '%s' "$LOOKUP_JSON" | sed -n 's/.*"result":\[{"id":"\([^"]*\)".*/\1/p')"
CURRENT_CONTENT="$(printf '%s' "$LOOKUP_JSON" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p')"

if [ -z "$RECORD_ID" ]; then
  CREATE_URL="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records"
  CREATE_BODY="$(printf '{"type":"A","name":"%s","content":"%s","ttl":%s,"proxied":%s}' \
    "$CLOUDFLARE_DNS_RECORD_NAME" "$PUBLIC_IP" "$CLOUDFLARE_DNS_TTL" "$CLOUDFLARE_DNS_PROXIED")"
  CREATE_JSON="$(api_call POST "$CREATE_URL" "$CREATE_BODY")"
  if printf '%s' "$CREATE_JSON" | grep -q '"success":true'; then
    log_info "Created A record: $CLOUDFLARE_DNS_RECORD_NAME -> $PUBLIC_IP"
    exit 0
  fi
  log_error "Failed to create DNS record."
  exit 1
fi

if [ "$CURRENT_CONTENT" = "$PUBLIC_IP" ]; then
  log_info "No change needed: $CLOUDFLARE_DNS_RECORD_NAME already points to $PUBLIC_IP"
  exit 0
fi

UPDATE_URL="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$RECORD_ID"
UPDATE_BODY="$(printf '{"type":"A","name":"%s","content":"%s","ttl":%s,"proxied":%s}' \
  "$CLOUDFLARE_DNS_RECORD_NAME" "$PUBLIC_IP" "$CLOUDFLARE_DNS_TTL" "$CLOUDFLARE_DNS_PROXIED")"
UPDATE_JSON="$(api_call PUT "$UPDATE_URL" "$UPDATE_BODY")"

if printf '%s' "$UPDATE_JSON" | grep -q '"success":true'; then
  log_info "Updated A record: $CLOUDFLARE_DNS_RECORD_NAME -> $PUBLIC_IP"
  exit 0
fi

log_error "Failed to update DNS record."
exit 1

