# Sourced by scripts/deploy.sh before `docker compose up`.
# Pi-hole's container runs as root and manages its own file ownership.
mkdir -p "$DATA_ROOT/pihole/etc-pihole"

# The Pi must not resolve DNS through its own Pi-hole (via Tailscale DNS):
# if the container is down it couldn't pull the image to bring it back.
if command -v tailscale >/dev/null; then
  tailscale set --accept-dns=false
fi
