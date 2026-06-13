---
name: pi-status
description: SSH into the Pi and show a quick health snapshot — PM2 processes, CPU temp, memory, disk usage, and uptime. Use when the user asks about Pi status, what's running, or system health.
---

SSH into the Pi and show a concise health snapshot.

Run this single command (load PI_USER and PI_HOST from .env first):

```bash
ssh $PI_USER@$PI_HOST "
  export PATH=\$PATH:\$(npm prefix -g)/bin
  echo '=== PM2 ==='
  pm2 list
  echo ''
  echo '=== System ==='
  echo -n 'Temp:   '; vcgencmd measure_temp 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp | awk '{printf \"%.1f°C\n\", \$1/1000}'
  echo -n 'Uptime: '; uptime -p
  echo ''
  echo '=== Memory ==='
  free -h
  echo ''
  echo '=== Disk ==='
  df -h / /mnt/nas 2>/dev/null || df -h /
"
```

Present the output cleanly. Flag anything concerning:
- Temperature > 70°C → warning
- Memory used > 80% → warning  
- Disk used > 85% → warning
- Any PM2 process not `online` → flag with the error status
