---
name: deploy
description: Build the Next.js dashboard locally and deploy it to the Pi via rsync + PM2 restart. Use when the user asks to deploy, ship, push to Pi, or update the live dashboard.
disable-model-invocation: true
---

Deploy the pizow Next.js dashboard to the Pi.

Steps:
1. Check that `.env` exists at the project root. If missing, tell the user to copy `.env.example` to `.env` and fill in `PI_USER`, `PI_HOST`, `PROJECT_NAME`, and `PM2_APP_NAME`.
2. Run `bash scripts/deploy.sh --local` from the project root.
3. Report the outcome. If PM2 shows the app online, print the URL: `http://<PI_HOST>:3000`.
4. If rsync times out (common on Pi Zero — slow Wi-Fi), retry once with a longer timeout by running the rsync commands manually with `--timeout=120`.

If $ARGUMENTS contains `--restart`, run `bash scripts/deploy.sh --restart` instead (skips build and sync).
If $ARGUMENTS contains `--remote`, run `bash scripts/deploy.sh --remote` instead (Pi builds itself).
