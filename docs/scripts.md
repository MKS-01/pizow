# Scripts Reference

## `setup-pi.sh`

Run once on a fresh Pi. Installs and configures everything:

- Node.js 22.x
- PM2 (process manager with autostart)
- Nginx (reverse proxy)
- 1 GB swap file

```bash
./scripts/setup-pi.sh          # auto-detects: skips if already set up
./scripts/setup-pi.sh --force  # re-run even if already set up
```

---

## `deploy.sh`

Main deploy script. Builds locally and rsyncs to Pi, or has the Pi pull and build itself.

```bash
./scripts/deploy.sh [--local] [--remote] [--restart]
```

| Flag | Description |
|------|-------------|
| `--local` | Build on your machine, rsync output to Pi (default) |
| `--remote` | Pi pulls from git and builds there |
| `--restart` | Skip build/sync, just restart PM2 |

For Next.js (`output: 'standalone'`), `--local` rsyncs `.next/standalone/` — no `node_modules` on the Pi.

---

## `deploy-standalone.sh`

Lightweight alternative to `deploy.sh` for Next.js standalone builds. No PM2 — starts the app directly with `node server.js` via nohup. Logs go to `/tmp/pizow.log` on the Pi.

```bash
./scripts/deploy-standalone.sh              # full build + deploy
./scripts/deploy-standalone.sh --skip-build # deploy existing build
```

Uses `BUILD_DIR` from `.env` (defaults to `examples/nextjs`).

> Use `deploy.sh` for general use (PM2 managed). Use `deploy-standalone.sh` for a quick, no-PM2 deploy.

---

## `nginx-setup.sh`

Configures Nginx as a reverse proxy — routes port 80 to your app port.

```bash
./scripts/nginx-setup.sh
```

---

## `manage.sh`

App lifecycle management on the Pi.

```bash
./scripts/manage.sh list                    # List running apps and ports
./scripts/manage.sh stop 3000               # Gracefully stop app on port
./scripts/manage.sh kill 3000               # Force kill
./scripts/manage.sh remove /home/user/myapp # Stop and delete project
./scripts/manage.sh logs                    # View logs
./scripts/manage.sh restart /path 3000      # Restart app
./scripts/manage.sh services status         # List systemd services
```

---

## `health-check.sh`

Prints CPU temp, memory, disk, and uptime. Useful for quick SSH checks.

```bash
./scripts/health-check.sh
```

---

## `setup-nas.sh` / `reset-nas.sh`

See [NAS Setup →](nas.md)

---

## Architecture

See the [deploy flowchart](../README.md#how-it-works) in the README for how these pieces connect.
