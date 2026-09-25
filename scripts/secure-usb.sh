#!/usr/bin/env bash
# Encrypted (LUKS) USB storage, unlocked by passphrase after each boot.
#
#   sudo secure-usb setup /dev/sdX   one-time: ERASE the drive and encrypt it
#   sudo secure-usb unlock           ask passphrase, mount, start apps that need it
#   sudo secure-usb lock             stop those apps, unmount, lock
#   sudo secure-usb status
#
# Apps that live on the drive have an apps/<app>/requires-mount file;
# deploy.sh skips them while the drive is locked.
set -euo pipefail

CONF="/etc/secure-usb.conf"
MAPPER="secure"
MOUNT="/mnt/secure"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run with sudo"

is_open() { [[ -e "/dev/mapper/$MAPPER" ]]; }

setup() {
  local dev="${1:-}"
  [[ -b "$dev" && "$(lsblk -dno TYPE "$dev")" == disk ]] || die "usage: secure-usb setup /dev/sdX (a whole disk)"
  [[ "$dev" != /dev/mmcblk* ]] || die "refusing to touch the SD card"
  [[ ! -f "$CONF" ]] || die "$CONF exists; already set up"

  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL "$dev"
  echo
  read -rp "ALL DATA on $dev will be destroyed. Type ERASE to continue: " answer
  [[ "$answer" == ERASE ]] || die "aborted"

  command -v cryptsetup >/dev/null || { apt-get update -qq && apt-get install -y -qq cryptsetup; }

  # Unmount anything the desktop auto-mounted from this drive.
  lsblk -lnpo MOUNTPOINTS "$dev" | { grep . || true; } | while read -r mp; do umount "$mp"; done

  wipefs -aq "$dev"
  echo 'type=linux' | sfdisk -q --label gpt "$dev"
  udevadm settle
  local part
  part="$(lsblk -lnpo NAME,TYPE "$dev" | awk '$2 == "part" {print $1; exit}')"
  [[ -n "$part" ]] || die "partition not found on $dev"

  echo
  echo "Choose a strong passphrase. If you forget it, the data is gone for good."
  cryptsetup luksFormat --type luks2 --label secure "$part"
  cryptsetup open "$part" "$MAPPER"
  mkfs.ext4 -q -L securedata "/dev/mapper/$MAPPER"

  echo "LUKS_UUID=$(blkid -s UUID -o value "$part")" > "$CONF"

  # While locked, the empty mountpoint is immutable: nothing (e.g. a container
  # starting at boot) can write unencrypted data onto the SD card by mistake.
  mkdir -p "$MOUNT"
  chattr +i "$MOUNT"
  mount "/dev/mapper/$MAPPER" "$MOUNT"

  cat > /usr/local/bin/secure-usb <<EOF
#!/bin/sh
exec /bin/bash $REPO_DIR/scripts/secure-usb.sh "\$@"
EOF
  chmod +x /usr/local/bin/secure-usb

  echo
  echo "Done. $dev is encrypted and mounted at $MOUNT."
  echo "After each reboot run: sudo secure-usb unlock"
  start_apps
}

start_apps() {
  echo "Starting apps that use $MOUNT..."
  /bin/bash "$REPO_DIR/scripts/deploy.sh" --force
}

unlock() {
  [[ -f "$CONF" ]] || die "not set up; run: sudo secure-usb setup /dev/sdX"
  source "$CONF"
  if mountpoint -q "$MOUNT"; then
    echo "already unlocked and mounted at $MOUNT"
  else
    is_open || cryptsetup open "/dev/disk/by-uuid/$LUKS_UUID" "$MAPPER"
    mount "/dev/mapper/$MAPPER" "$MOUNT"
    echo "unlocked, mounted at $MOUNT"
  fi
  start_apps
}

lock() {
  # Stop every container with a bind mount on the drive.
  local ids
  ids="$(docker ps -q | xargs -r docker inspect \
          --format '{{.Id}}{{range .Mounts}} {{.Source}}{{end}}' \
        | awk -v m="$MOUNT/" '{for (i = 2; i <= NF; i++) if (index($i, m) == 1) {print $1; break}}')"
  if [[ -n "$ids" ]]; then
    echo "stopping containers using $MOUNT"
    docker stop $ids >/dev/null
  fi
  mountpoint -q "$MOUNT" && umount "$MOUNT"
  is_open && cryptsetup close "$MAPPER"
  echo "locked; safe to unplug"
}

status() {
  if mountpoint -q "$MOUNT"; then
    echo "UNLOCKED, mounted at $MOUNT"
    df -h "$MOUNT" | tail -1
  elif is_open; then
    echo "unlocked but not mounted (run: sudo secure-usb unlock)"
  else
    echo "LOCKED (run: sudo secure-usb unlock)"
  fi
}

case "${1:-}" in
  setup)  setup "${2:-}" ;;
  unlock) unlock ;;
  lock)   lock ;;
  status) status ;;
  *) echo "usage: secure-usb {setup /dev/sdX|unlock|lock|status}"; exit 1 ;;
esac
