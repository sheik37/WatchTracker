#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COMPOSE_PATH="$SCRIPT_DIR/docker-compose.yml"
SERVICE_NAME="api"
IMAGE_NAME="watchtracker_api"

VERSION=""
SKIP_VERSION_BUMP="false"
NO_DOWN="false"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage: ./release-api.sh [options]

Options:
  --version <xx.xx.xx>  Force une version precise
  --skip-version-bump   Ne change pas la version
  --no-down             N'execute pas docker compose down
  --dry-run             Affiche les actions sans les executer
  --help                Affiche cette aide
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      if [ "$#" -lt 2 ]; then
        echo "Option --version invalide (valeur manquante)." >&2
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --skip-version-bump)
      SKIP_VERSION_BUMP="true"
      shift
      ;;
    --no-down)
      NO_DOWN="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Option inconnue: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$COMPOSE_PATH" ]; then
  echo "Compose file introuvable: $COMPOSE_PATH" >&2
  exit 1
fi

image_line=$(grep -E "^[[:space:]]*image:[[:space:]]*$IMAGE_NAME:[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$" "$COMPOSE_PATH" | head -n 1 || true)
if [ -z "$image_line" ]; then
  echo "Impossible de trouver la ligne image pour '$IMAGE_NAME' dans $COMPOSE_PATH" >&2
  exit 1
fi

current_version=$(printf '%s\n' "$image_line" | sed -E "s/.*$IMAGE_NAME:([0-9]+\.[0-9]+\.[0-9]+).*/\1/")

if [ -n "$VERSION" ]; then
  target_version="$VERSION"
elif [ "$SKIP_VERSION_BUMP" = "true" ]; then
  target_version="$current_version"
else
  target_version=$(printf '%s\n' "$current_version" | awk -F. '
    NF != 3 { exit 1 }
    {
      patch_width = length($3)
      patch = $3 + 1
      printf "%02d.%02d.%0*d", $1, $2, patch_width, patch
    }')
fi

if ! printf '%s\n' "$target_version" | grep -Eq '^[0-9]{2}\.[0-9]{2}\.[0-9]{2,}$'; then
  echo "Version invalide: '$target_version'. Format attendu: xx.xx.xx" >&2
  exit 1
fi

if [ "$target_version" != "$current_version" ]; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY-RUN] Mise a jour version: $current_version -> $target_version"
  else
    tmp_file=$(mktemp)
    awk -v image_name="$IMAGE_NAME" -v version="$target_version" '
      BEGIN { updated = 0 }
      {
        if (updated == 0 && $0 ~ "^[[:space:]]*image:[[:space:]]*" image_name ":[0-9]+\\.[0-9]+\\.[0-9]+[[:space:]]*$") {
          sub(image_name ":[0-9]+\\.[0-9]+\\.[0-9]+", image_name ":" version)
          updated = 1
        }
        print
      }
      END {
        if (updated == 0) {
          exit 2
        }
      }' "$COMPOSE_PATH" > "$tmp_file" || {
        rm -f "$tmp_file"
        echo "Echec lors de la mise a jour de version dans $COMPOSE_PATH" >&2
        exit 1
      }
    mv "$tmp_file" "$COMPOSE_PATH"
    echo "Version mise a jour: $current_version -> $target_version"
  fi
else
  echo "Version conservee: $current_version"
fi

run_compose() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY-RUN] docker compose $*"
    return 0
  fi
  docker compose "$@"
}

cd "$(dirname "$COMPOSE_PATH")"

if [ "$NO_DOWN" != "true" ]; then
  run_compose down
fi

if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY-RUN] docker build --network=host -t $IMAGE_NAME:$target_version ."
else
    docker build --network=host -t "$IMAGE_NAME:$target_version" .
fi

run_compose up -d "$SERVICE_NAME"

echo "Deployment termine pour '$SERVICE_NAME' en version '$target_version'."
