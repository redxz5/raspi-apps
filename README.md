# raspi

GitOps-style config for my Raspberry Pi. Every app is a Docker Compose project under
`apps/`. The Pi checks this repo every 5 minutes and applies any changes.

```
apps/<name>/compose.yaml     app definition (required)
apps/<name>/pre-deploy.sh    optional hook, e.g. create data dirs
apps/<name>/disabled         optional: if present, app is stopped/removed
apps/<name>/requires-mount   optional: path that must be mounted (encrypted USB) before deploy
scripts/deploy.sh            git pull + reconcile (run by systemd timer)
scripts/bootstrap.sh         one-time Pi setup
scripts/secure-usb.sh        encrypted USB: setup / unlock / lock / status
systemd/                     timers: every 5 min + weekly image refresh
.env.example                 host-specific settings template (.env is gitignored)
```

## First-time setup on the Pi

```sh
sudo apt install -y git
sudo git clone https://github.com/redxz5/raspi-apps.git /opt/raspi
sudo bash /opt/raspi/scripts/bootstrap.sh
```

Then edit `/opt/raspi/.env` (set `MEDIA_ROOT` to your media drive) and run
`sudo raspi-deploy --force`.

If the repo is private, the Pi needs read access: add a
[deploy key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)
for root (`sudo ssh-keygen -t ed25519`, add `/root/.ssh/id_ed25519.pub` to the repo)
and clone with `git@github.com:redxz5/raspi-apps.git` instead.

## Day to day

- **Change something:** edit, commit, push. The Pi applies it within 5 minutes.
- **Deploy now:** `sudo raspi-deploy` (or `--force` to redeploy everything and re-pull images).
- **Upgrade an app:** bump its image tag in `compose.yaml` and push.
- **Add an app:** create `apps/<name>/compose.yaml` and push. Use `${DATA_ROOT}/<name>/...`
  for its state and `ensure_dir` in `pre-deploy.sh` to create those dirs. Add a tile for it
  in `apps/homepage/config/services.yaml`.
- **Remove an app:** delete its directory (or add a `disabled` file) and push.
  Its data under `DATA_ROOT` is kept.
- **Encrypted USB (if set up):** after a reboot run `sudo secure-usb unlock` (asks the passphrase)
  to mount it and start apps that need it. `sudo secure-usb lock` before unplugging.
- **Logs:** `journalctl -u raspi-deploy -f`, `docker logs -f jellyfin`.

## What's in git vs. on the Pi

Git holds *how* apps run (images, ports, mounts). App state (the Jellyfin library
database, users, settings you change in the web UI) lives in `DATA_ROOT` on the Pi.
Back up `DATA_ROOT` separately. Secrets go in `.env`, never in git.

## Apps

| App         | URL                          | Notes |
|-------------|------------------------------|-------|
| Homepage    | `http://<pi-host>`               | Dashboard linking to everything below |
| Jellyfin    | `http://<pi-host>:8096`          | Movies, shows, music from `MEDIA_ROOT` |
| Pi-hole     | `http://<pi-host>:8081/admin`    | DNS ad blocking on port 53. Admin password = `PIHOLE_PASSWORD` in `.env` |
| Calibre-Web | `http://<pi-host>:8083`          | Library in `MEDIA_ROOT/Calibre`. Copy books into `MEDIA_ROOT/BookDrop` to import them (files there are deleted after import). First login `admin` / `admin123` — change it. |
