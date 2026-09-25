# Sourced by scripts/deploy.sh before `docker compose up`.
# Only runs when /mnt/secure is unlocked (see requires-mount).
# The containers set their own ownership (www-data / postgres) on first start.
mkdir -p /mnt/secure/nextcloud/html /mnt/secure/nextcloud/db

# Hostname Nextcloud accepts requests on; override with PI_HOST in .env.
export PI_HOST="${PI_HOST:-$(hostname)}"
