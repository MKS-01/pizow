# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PiZoW is a Raspberry Pi Zero 2W home server toolkit. It provides:
- `examples/nextjs/` — live system monitoring dashboard (Next.js 15 + TypeScript + Tailwind)
- `examples/node-api/` — minimal Express API example
- `scripts/` — shell scripts for first-time Pi setup, deployment, NAS, and management

The two examples are **independent apps** — each has its own `package.json`. There is no monorepo workspace config.

## Deploy Workflow

All deploy config lives in `.env` at the project root (copy from `.env.example`). Required vars:

```
PI_USER        SSH username on the Pi
PI_HOST        Pi IP address
PROJECT_NAME   Subdirectory name under examples/ (e.g. nextjs)
PM2_APP_NAME   PM2 process name (e.g. pizow)
PORT           App port (default 3000)
```

Deploy commands (run from project root):

```bash
bash scripts/deploy.sh --local    # build locally, rsync .next/standalone to Pi, restart PM2
bash scripts/deploy.sh --remote   # git pull + build on Pi
bash scripts/deploy.sh --restart  # restart PM2 only (no build/sync)
```

The Next.js app uses `output: 'standalone'` — rsync the `.next/standalone/` directory, not the whole project. The Pi runs it with `node server.js` directly (not `npm start`).

## Pi-Specific Gotchas

- **Swap is required**: Pi Zero 2W has 512MB RAM — the setup script creates 1GB swap. Builds fail without it.
- **USB power limit**: The OTG port maxes at 500mA. Spinning hard drives won't work; use flash storage or a powered hub.
- **NAS mounts at `/mnt/nas`**: The `nofail` flag in fstab means boot succeeds even if the drive is absent. Check `mountpoint -q /mnt/nas` before assuming NAS data is available.
- **File Browser**: Runs on port 8080 (web UI) and 8081 (stats API). Set `FB_PASSWORD` in `.env` before running `setup-nas.sh`.
- **SSH key auth**: All scripts assume `ssh-copy-id` is already done. Run `ssh-copy-id $PI_USER@$PI_HOST` once before using any script.

## Scripts Reference

| Script | Purpose |
|---|---|
| `setup-pi.sh` | One-time: installs Node 22, PM2, Nginx, creates 1GB swap |
| `deploy.sh` | Main deploy — local (rsync) or remote (git pull) |
| `deploy-standalone.sh` | Lightweight deploy without PM2 |
| `nginx-setup.sh` | Configures Nginx reverse proxy on port 80 |
| `setup-nas.sh` | USB NAS: ext4 format, NFS, File Browser, udev auto-remount |
| `reset-nas.sh` | Removes NAS components (non-destructive to data) |
| `manage.sh` | App lifecycle: list, stop, restart, logs, status |
| `health-check.sh` | Quick diagnostics: temp, memory, disk, uptime |

## Code Style

- TypeScript strict mode is enabled in `examples/nextjs/`
- Path alias `@/*` maps to `./src/*`
- No Prettier config — no auto-formatting is enforced
- Run `npm run lint` inside `examples/nextjs/` to lint

## Git Workflow

Push directly to `main`. No PRs required. Commit messages follow conventional format (`feat:`, `fix:`, `docs:`, `chore:`).
