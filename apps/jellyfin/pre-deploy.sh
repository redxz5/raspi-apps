# Sourced by scripts/deploy.sh before `docker compose up`.
# Create bind-mount dirs ourselves so Docker doesn't create them as root.
ensure_dir "$DATA_ROOT/jellyfin/config"
ensure_dir "$DATA_ROOT/jellyfin/cache"
