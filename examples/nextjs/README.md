# PiZoW Monitor

Real-time health monitoring dashboard for Raspberry Pi Zero W.

![Dashboard Preview](https://via.placeholder.com/800x400/09090b/ffffff?text=PiZoW+Monitor+Dashboard)

## Features

- **Real-time monitoring** - Auto-refreshes every 5 seconds
- **System metrics** - CPU, Memory, Disk, Temperature
- **Visual indicators** - Progress bars and status badges
- **Health status** - Green/Yellow/Red based on thresholds
- **Responsive** - Works on mobile and desktop
- **Dark theme** - Easy on the eyes

## Metrics Displayed

| Metric | Description |
|--------|-------------|
| Temperature | CPU temperature (°C) |
| Memory | RAM usage and swap |
| CPU | Load average and core count |
| Disk | Storage usage |
| Uptime | System uptime |
| Processes | Running Node.js processes |

## Local Development

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

> Note: Some metrics (temperature, etc.) only work on actual Pi hardware.

## Deploy to Pi

### Option 1: Standalone Deploy (Recommended)

From your Mac:

```bash
cd /path/to/pizow
./scripts/deploy-standalone.sh
```

### Option 2: Manual Deploy

On your Pi:

```bash
git clone https://github.com/YOUR_USERNAME/pizow.git
cd pizow/examples/nextjs
npm install
npm run build
PORT=4000 node .next/standalone/server.js
```

## API Endpoint

The dashboard uses `/api/health` endpoint which returns:

```json
{
  "timestamp": "2024-01-01T00:00:00.000Z",
  "system": {
    "hostname": "ubuntu",
    "ip": "192.168.1.100",
    "uptime": "5d 2h 30m",
    "platform": "linux",
    "arch": "arm64",
    "nodeVersion": "v22.0.0"
  },
  "temperature": 45.2,
  "memory": {
    "total": 409,
    "used": 250,
    "available": 159,
    "percent": 61,
    "swap": { "total": 1023, "used": 50, "percent": 5 }
  },
  "disk": {
    "total": "29G",
    "used": "5.2G",
    "available": "23G",
    "percent": 19
  },
  "cpu": {
    "cores": 4,
    "load": { "load1": 0.5, "load5": 0.3, "load15": 0.2 },
    "percent": 12
  },
  "processes": { "node": 2 }
}
```

## Health Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Temperature | > 70°C | > 80°C |
| Memory | > 80% | > 90% |
| Disk | > 80% | > 90% |

## Project Structure

```
examples/nextjs/
├── src/app/
│   ├── api/
│   │   └── health/
│   │       └── route.ts   # Health API endpoint
│   ├── layout.tsx         # Root layout
│   ├── page.tsx           # Dashboard page
│   └── globals.css        # Tailwind styles
├── public/
├── tailwind.config.js
├── postcss.config.js
├── next.config.js
├── package.json
└── tsconfig.json
```

## Tech Stack

- Next.js 15
- React 19
- Tailwind CSS
- TypeScript
