---
name: pi-setup
description: First-time Pi setup — installs Node 22, PM2, Nginx, and 1GB swap via SSH. Use when the user has a fresh Pi and wants to get it server-ready, or asks to set up / initialize the Pi.
---

Run the one-time Pi setup script over SSH.

## Step 1 — check .env

Source `.env` from the project root:

```bash
set -a; source .env; set +a
```

Verify `PI_USER` and `PI_HOST` are set and not placeholder values. If either is missing or still default, stop and tell the user:

> Set `PI_USER` and `PI_HOST` in `.env` first — copy `.env.example` if you haven't yet.

## Step 2 — check if already set up

SSH in and look for the marker file the script leaves behind:

```bash
ssh $PI_USER@$PI_HOST "[ -f ~/.pizow_setup_done ] && echo done || echo fresh"
```

- **`done`** — Pi is already configured. Show current versions and ask if they want to re-run with `--force`.
- **`fresh`** — proceed to Step 3.

## Step 3 — test SSH connectivity

```bash
ssh -q -o ConnectTimeout=5 $PI_USER@$PI_HOST exit
```

If this fails, stop and tell the user:
- Check the Pi is powered on and connected to WiFi
- Confirm the IP with `ping $PI_HOST` or check the router's DHCP list
- Make sure SSH key auth is set up: `ssh-copy-id $PI_USER@$PI_HOST`

## Step 4 — run setup

```bash
bash scripts/setup-pi.sh
```

The script auto-detects macOS and forwards itself to the Pi over SSH. Stream all output — do not suppress it. It runs 8 steps:

1. Locale configuration
2. System package update (`apt update && apt upgrade`)
3. Node.js 22.x install
4. PM2 install + PATH config
5. Nginx install + enable
6. Git + utilities (`htop`, `curl`, `wget`)
7. 1 GB swap file + swappiness tuning
8. PM2 startup on boot

This takes **5–15 minutes** on a Pi Zero 2 W — warn the user upfront so they don't think it's hung.

## Step 5 — verify

After the script exits, SSH in and confirm:

```bash
ssh $PI_USER@$PI_HOST "
  export PATH=\$PATH:\$(npm prefix -g)/bin
  echo 'Node:  '$(node --version)
  echo 'npm:   '$(npm --version)
  echo 'PM2:   '$(pm2 --version)
  echo 'Nginx: '$(nginx -v 2>&1 | cut -d/ -f2)
  echo 'Swap:  '$(free -h | awk '/^Swap:/{print \$2}')
"
```

## Step 6 — report + suggest next steps

Tell the user what was installed and suggest:

1. **Deploy the dashboard** — `bash scripts/deploy.sh --local` (or `/pi-deploy`)
2. **Set up Nginx** — `bash scripts/nginx-setup.sh` to proxy port 80 → your app
3. **Set up NAS** (optional) — `bash scripts/setup-nas.sh` if they have a USB drive

## Error handling

| Problem | Action |
|---|---|
| SSH key not set up | Guide: `ssh-copy-id $PI_USER@$PI_HOST`, then retry |
| `apt upgrade` hangs | Likely waiting on a lock — tell user to wait or run `sudo killall apt` on Pi |
| Node install fails | NodeSource CDN issue — suggest retry or manual install via `nvm` |
| Low disk during setup | `df -h /` on Pi — need at least 2 GB free |
| `--force` requested | Run `bash scripts/setup-pi.sh --force` — skips the already-done check |
