#!/usr/bin/env bash
# Pull this repo and reconcile running apps with apps/*/compose.yaml.
#
#   deploy.sh           fetch; deploy only if origin has new commits
#   deploy.sh --force   fetch and deploy regardless (also re-pulls images)
#
# Runs as root from raspi-deploy.service.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${BRANCH:-main}"
STATE_FILE="/var/lib/raspi-deploy/deployed-apps"
APPLIED_FILE="/var/lib/raspi-deploy/applied-rev"
LOCK_FILE="/run/lock/raspi-deploy.lock"

log() { echo "[deploy] $*"; }

cd "$REPO_DIR"

# --- Phase 1: sync git, then re-exec so we run the *new* version of this script.
if [[ "${1:-}" != "--apply" ]]; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { log "another deploy is running, skipping"; exit 0; }

  git fetch --quiet origin "$BRANCH"
  applied_rev="$(cat "$APPLIED_FILE" 2>/dev/null || echo none)"
  remote_rev="$(git rev-parse "origin/$BRANCH")"

  # Compare against the last *successful* deploy, so failures get retried.
  if [[ "$applied_rev" == "$remote_rev" && "${1:-}" != "--force" ]]; then
    exit 0
  fi

  log "updating ${applied_rev:0:7} -> ${remote_rev:0:7}"
  git reset --quiet --hard "origin/$BRANCH"
  exec "$BASH" "$REPO_DIR/scripts/deploy.sh" --apply
fi

# --- Phase 2: apply.
[[ -f "$REPO_DIR/.env" ]] || { log "missing $REPO_DIR/.env (copy .env.example)"; exit 1; }
set -a; source "$REPO_DIR/.env"; set +a

# Helper available to apps/<app>/pre-deploy.sh hooks.
ensure_dir() {
  mkdir -p "$1"
  chown "${PUID}:${PGID}" "$1"
}

compose() {
  local app="$1"; shift
  docker compose \
    --project-name "$app" \
    --project-directory "$REPO_DIR/apps/$app" \
    --env-file "$REPO_DIR/.env" \
    -f "$REPO_DIR/apps/$app/compose.yaml" \
    "$@"
}

mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

# Keep installed systemd units in sync with the repo.
units_changed=0
for unit in "$REPO_DIR"/systemd/*.service "$REPO_DIR"/systemd/*.timer; do
  target="/etc/systemd/system/$(basename "$unit")"
  if ! cmp -s "$unit" "$target"; then
    cp "$unit" "$target"
    units_changed=1
  fi
done
if (( units_changed )); then
  log "systemd units changed, reloading"
  systemctl daemon-reload
fi

desired=()
for dir in "$REPO_DIR"/apps/*/; do
  app="$(basename "$dir")"
  [[ -f "$dir/compose.yaml" ]] || continue
  [[ -f "$dir/disabled" ]] && continue
  desired+=("$app")
done

# Stop apps that were removed or disabled since the last deploy.
while read -r app; do
  [[ -z "$app" ]] && continue
  if [[ ! " ${desired[*]} " =~ " $app " ]]; then
    log "removing $app"
    docker compose --project-name "$app" down --remove-orphans || true
  fi
done < "$STATE_FILE"

pre_hook() {
  local hook="$REPO_DIR/apps/$1/pre-deploy.sh"
  [[ ! -f "$hook" ]] || source "$hook"
}

failed=()
for app in "${desired[@]}"; do
  log "deploying $app"
  if ! { pre_hook "$app" &&
         compose "$app" pull --quiet &&
         compose "$app" up -d --remove-orphans; }; then
    log "FAILED: $app"
    failed+=("$app")
  fi
done

printf '%s\n' "${desired[@]}" > "$STATE_FILE"
docker image prune -f >/dev/null

if (( ${#failed[@]} )); then
  log "done with failures: ${failed[*]} (will retry next run)"
  exit 1
fi
git rev-parse HEAD > "$APPLIED_FILE"
log "done ($(git rev-parse --short HEAD))"
