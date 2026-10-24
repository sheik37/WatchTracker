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

# Charge un fichier d'environnement obligatoire ($1) puis un fichier de
# secrets optionnel ($2). Factorise le bootstrap duplique en haut des
# scripts BD/scripts/*.sh (backup/restore/daily_ops).
wt_load_env() {
    ENV_FILE_TO_LOAD="$1"
    SECRETS_FILE_TO_LOAD="${2:-}"

    if [ ! -f "$ENV_FILE_TO_LOAD" ]; then
        echo "Missing $ENV_FILE_TO_LOAD" >&2
        exit 1
    fi

    # shellcheck disable=SC1090
    . "$ENV_FILE_TO_LOAD"

    if [ -n "$SECRETS_FILE_TO_LOAD" ] && [ -f "$SECRETS_FILE_TO_LOAD" ]; then
        # shellcheck disable=SC1090
        . "$SECRETS_FILE_TO_LOAD"
    fi
}

# Indique si un conteneur docker est en cours d'execution, avec une
# nouvelle tentative apres un delai (utile pour ignorer un redemarrage
# bref). Renvoie 0 si en cours d'execution immediatement, 2 si en cours
# d'execution seulement apres le delai (ex: en cours de redemarrage),
# 1 s'il reste arrete.
container_is_running() {
    CONTAINER_NAME_TO_CHECK="$1"
    RETRY_DELAY_SECONDS="${2:-0}"

    if docker inspect -f "{{.State.Running}}" "$CONTAINER_NAME_TO_CHECK" 2>/dev/null | grep -q true; then
        return 0
    fi

    if [ "$RETRY_DELAY_SECONDS" -le 0 ] 2>/dev/null; then
        return 1
    fi

    sleep "$RETRY_DELAY_SECONDS"

    if docker inspect -f "{{.State.Running}}" "$CONTAINER_NAME_TO_CHECK" 2>/dev/null | grep -q true; then
        return 2
    fi

    return 1
}

# Mecanisme simple d'anti-repetition d'alerte base sur un fichier d'etat.
# wt_alert_should_fire <id> renvoie 0 (vrai) la premiere fois qu'un incident
# identifie par <id> est detecte (et marque l'etat comme actif), puis 1
# tant que l'incident persiste, pour eviter de spammer Discord a chaque
# execution cron. wt_alert_clear <id> doit etre appelee quand l'incident
# est resolu pour reactiver l'alerte au prochain incident.
wt_alert_should_fire() {
    ALERT_ID="$1"
    ALERT_STATE_DIR="${WATCHTRACKER_ALERT_STATE_DIR:-${TMPDIR:-/tmp}}"
    ALERT_STATE_FILE="$ALERT_STATE_DIR/watchtracker_alert_$ALERT_ID"

    mkdir -p "$ALERT_STATE_DIR" 2>/dev/null || true

    if [ -f "$ALERT_STATE_FILE" ]; then
        return 1
    fi

    : > "$ALERT_STATE_FILE" 2>/dev/null || true
    return 0
}

wt_alert_clear() {
    ALERT_ID="$1"
    ALERT_STATE_DIR="${WATCHTRACKER_ALERT_STATE_DIR:-${TMPDIR:-/tmp}}"
    rm -f "$ALERT_STATE_DIR/watchtracker_alert_$ALERT_ID" 2>/dev/null || true
}