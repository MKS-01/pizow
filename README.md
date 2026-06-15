# PiZoW

> Turn your Raspberry Pi Zero W into a lightweight home server — with deployment scripts, process management, a real-time monitoring dashboard, and NAS storage via USB.

![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-C51A4A?style=for-the-badge&logo=Raspberry-Pi&logoColor=white)
![Node](https://img.shields.io/badge/Node-339933?style=for-the-badge&logo=nodedotjs&logoColor=white)
![Next.js](https://img.shields.io/badge/Next.js-000000?style=for-the-badge&logo=nextdotjs&logoColor=white)
![PM2](https://img.shields.io/badge/PM2-2B037A?style=for-the-badge&logo=pm2&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-009639?style=for-the-badge&logo=nginx&logoColor=white)
![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)

![PiZoW Dashboard](screenshot/web-dashboard.png)

---

## What is PiZoW?

PiZoW is a collection of shell scripts and a ready-to-use Next.js dashboard that makes it dead simple to:

- **Set up** a Raspberry Pi Zero W as a Node.js web server
- **Deploy** any Node.js app (Next.js, Express, Fastify, etc.) from your local machine
- **Monitor** your Pi in real time — CPU, memory, disk, temp, network, and all running services
- **Turn any USB drive into a NAS** — NFS share + File Browser web UI

> Also running on [Readback](https://github.com/MKS-01/readback) — a terminal read-later client built on the same Pi stack.

---

## Claude Code Skills

PiZoW ships with built-in [Claude Code](https://claude.ai/code) skills — invoke them directly from your terminal:

| Skill | Trigger | What it does |
|---|---|---|
| `pi-setup` | `/pi-setup` | First-time Pi setup — installs Node 22, PM2, Nginx, 1 GB swap over SSH |
| `pi-deploy` | `/pi-deploy` | Build + rsync + restart PM2. Accepts `--local`, `--remote`, `--restart` |
| `pi-status` | `/pi-status` | SSH health snapshot — PM2 processes, CPU temp, memory, disk |

Skills live in `.claude/skills/` and are picked up automatically when you open the project in Claude Code.

---

## Quick Start

### 1. Flash Your SD Card

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) — enable SSH, set username/password, configure WiFi. **Recommended OS: Ubuntu Server 24.04 LTS.**

### 2. SSH in & set up key auth

```bash
ssh YOUR_USERNAME@YOUR_PI_IP
ssh-copy-id YOUR_USERNAME@YOUR_PI_IP
```

### 3. Run setup

```bash
curl -sSL https://raw.githubusercontent.com/MKS-01/pizow/main/scripts/setup-pi.sh | bash
```

Installs Node.js 22, PM2, Nginx, and 1 GB swap (essential for Pi Zero).

### 4. Configure `.env`

```bash
cp .env.example .env
```

Set `PI_USER`, `PI_HOST`, `PROJECT_NAME`, `PM2_APP_NAME`, and `PORT` at minimum.

### 5. Deploy

```bash
./scripts/deploy.sh           # build locally, rsync to Pi (default)
./scripts/deploy.sh --remote  # Pi pulls from git and builds itself
./scripts/deploy.sh --restart # restart PM2 only
```

Then open `http://YOUR_PI_IP` in any browser on your network.

---

## Project Structure

```
pizow/
├── scripts/
│   ├── setup-pi.sh          # One-time Pi setup (Node, PM2, Nginx, swap)
│   ├── setup-nas.sh         # NAS setup (ext4, NFS, File Browser, udev auto-remount)
│   ├── reset-nas.sh         # Wipe all NAS components for a fresh setup
│   ├── deploy.sh            # Deploy via local rsync or git pull
│   ├── deploy-standalone.sh # Build locally + rsync prebuilt output
│   ├── nginx-setup.sh       # Configure Nginx reverse proxy
│   ├── health-check.sh      # Pi health check (CPU, mem, disk, temp)
│   └── manage.sh            # List, stop, kill, remove deployed apps
├── examples/
│   ├── nextjs/              # Monitoring dashboard (Next.js 15 + Tailwind)
│   └── node-api/            # Minimal Express API
├── docs/
│   ├── scripts.md           # Full scripts reference + architecture
│   ├── nas.md               # NAS setup deep dive
│   └── troubleshooting.md   # Troubleshooting + useful commands
├── .claude/skills/          # Claude Code skills
├── .env.example
└── README.md
```

---

## Requirements

- Any Raspberry Pi — Zero W, Zero 2 W, 3, 4, 5 (built and tested on Pi Zero 2 W)
- Any Debian-based OS (tested on [Ubuntu 24.04.4 LTS](https://ubuntu.com/download/raspberry-pi))
- macOS or Linux on your dev machine
- Node.js 22+ locally (for building)
- SSH access to your Pi

---

## Docs

- [Scripts Reference](docs/scripts.md)
- [NAS Setup](docs/nas.md)
- [Troubleshooting & Commands](docs/troubleshooting.md)

---

## License

MIT — see [LICENSE](LICENSE)
