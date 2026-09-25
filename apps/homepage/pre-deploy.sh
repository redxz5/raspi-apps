# Sourced by scripts/deploy.sh before `docker compose up`.
# Copy dashboard config from git; Homepage picks up changes without a restart.
ensure_dir "$DATA_ROOT/homepage/config"
cp "$REPO_DIR"/apps/homepage/config/*.yaml "$DATA_ROOT/homepage/config/"
chown -R "${PUID}:${PGID}" "$DATA_ROOT/homepage/config"

# Hostname used in dashboard links; override with PI_HOST in .env.
export PI_HOST="${PI_HOST:-$(hostname)}"
