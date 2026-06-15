---
name: pi-deploy
description: Deploy the Next.js dashboard (or any configured app) to the Pi. Accepts --local (default), --remote, or --restart. Use when the user asks to deploy, push, or update the Pi.
---

Deploy the app to the Pi using `scripts/deploy.sh`.

## Step 1 — parse the user's intent

From the user's message determine the deploy mode:
- **`--local`** (default) — build on this machine, rsync `.next/standalone` to Pi
- **`--remote`** — Pi pulls from git and builds itself
- **`--restart`** — skip build/sync, just restart PM2

If the user didn't specify, use `--local`.

## Step 2 — load config

Source `.env` from the project root to get `PI_USER`, `PI_HOST`, `PORT`, `PM2_APP_NAME`. If `.env` is missing or `PI_HOST` is still the placeholder, stop and tell the user to configure it.

```bash
set -a; source .env; set +a
```

## Step 3 — run the deploy

Run from the project root:

```bash
bash scripts/deploy.sh --local    # or --remote / --restart
```

Stream the output as it runs — do not suppress it. The script handles SSH connection checks, build, rsync, and PM2 restart internally.

## Step 4 — post-deploy health check

After the script exits successfully, SSH in and show a brief status:

```bash
ssh $PI_USER@$PI_HOST "
  export PATH=\$PATH:\$(npm prefix -g)/bin
  echo '=== PM2 ==='
  pm2 list
  echo ''
  echo -n 'Temp:   '; cat /sys/class/thermal/thermal_zone0/temp | awk '{printf \"%.1f°C\n\", \$1/1000}'
  echo -n 'Mem:    '; free -h | awk '/Mem:/{print \$3 \" / \" \$2}'
"
```

## Step 5 — report

Tell the user:
- Which mode was used and what was deployed
- The URL: `http://$PI_HOST` (port 80 via Nginx) or `http://$PI_HOST:$PORT` if Nginx isn't set up
- Flag anything concerning from the health check (PM2 process not `online`, temp > 70°C)

## Error handling

| Problem | Action |
|---|---|
| SSH connection refused | Tell user to check Pi is on and reachable: `ping $PI_HOST` |
| Build fails | Show the npm error output, suggest checking RAM/swap on Pi for `--remote` mode |
| PM2 crash-loop | Suggest `bash scripts/manage.sh logs` and check the error |
| `.env` not configured | Stop immediately — do not guess values |
