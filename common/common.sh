#!/bin/sh

json_escape() {
    printf '%s' "$1" | awk '
    BEGIN { ORS="" }
    {
        gsub(/\\/,"\\\\")
        gsub(/"/,"\\\"")
        gsub(/\r/,"")
        gsub(/\t/,"    ")
        if (NR > 1) printf "\\n"
        printf "%s", $0
    }'
}

discord_level() {
    TITLE_UPPER="$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')"
    case "$TITLE_UPPER" in
        *"• ERROR"*|*" ERROR"*) printf '%s' "ERROR" ; return 0 ;;
        *"• WARN"*|*" WARN"*)   printf '%s' "WARN" ; return 0 ;;
        *"• OK"*|*" OK"*)       printf '%s' "OK" ; return 0 ;;
    esac

    TEXT_UPPER="$(printf '%s %s' "${1:-}" "${2:-}" | tr '[:lower:]' '[:upper:]')"
    case "$TEXT_UPPER" in
        *ERROR*|*FAILED*|*FAIL*|*DOWN*|*KO*) printf '%s' "ERROR" ;;
        *WARN*|*ALERT*|*HIGH*)              printf '%s' "WARN" ;;
        *OK*|*SUCCESS*|*UP*)                printf '%s' "OK" ;;
        *)                                   printf '%s' "INFO" ;;
    esac
}

discord_color() {
    case "$1" in
        ERROR) printf '%s' "15158332" ;;
        WARN)  printf '%s' "16753920" ;;
        OK)    printf '%s' "5763719" ;;
        *)     printf '%s' "3447003" ;;
    esac
}

discord_icon() {
    case "$1" in
        ERROR) printf '%s' "❌" ;;
        WARN)  printf '%s' "⚠️" ;;
        OK)    printf '%s' "✅" ;;
        *)     printf '%s' "ℹ️" ;;
    esac
}

notify_discord() {
    [ -n "${DISCORD_WEBHOOK_URL:-}" ] || return 0
    TITLE="${1:-WatchTracker}"
    MESSAGE="${2:-}"
    LEVEL="$(discord_level "$TITLE" "$MESSAGE")"
    COLOR="$(discord_color "$LEVEL")"
    ICON="$(discord_icon "$LEVEL")"

    case "$TITLE" in
        *"✅"*|*"❌"*|*"⚠️"*|*"ℹ️"*|*"🐳"*|*"🗄️"*) FINAL_TITLE="$TITLE" ;;
        *) FINAL_TITLE="$ICON $TITLE" ;;
    esac

    TITLE_ESCAPED="$(json_escape "$FINAL_TITLE")"
    MESSAGE_ESCAPED="$(json_escape "$MESSAGE")"
    TIMESTAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PAYLOAD="{\"embeds\":[{\"title\":\"$TITLE_ESCAPED\",\"description\":\"$MESSAGE_ESCAPED\",\"color\":$COLOR,\"timestamp\":\"$TIMESTAMP_UTC\"}]}"

    curl -fsS -H "Content-Type: application/json" -d "$PAYLOAD" "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

log_alert() {
    LEVEL="$1"
    TITLE="$2"
    MESSAGE="$3"
    LOG_DIR="${WATCHTRACKER_LOG_DIR:-/volume1/homes/sheik37.v/docker/logs}"
    LOG_FILE="$LOG_DIR/alerts.log"
    mkdir -p "$LOG_DIR"
    printf "[%s] [%s] %s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$LEVEL" "$TITLE" "$MESSAGE" >> "$LOG_FILE"
}

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

die() {
    log_error "$1"
    exit 1
}