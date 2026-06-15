# Troubleshooting & Commands

## Common Issues

### Can't SSH to Pi
- Double-check WiFi credentials set in Imager
- Confirm SSH is enabled
- Try `ping raspberrypi.local` or check your router's DHCP list

### Out of Memory / Build Fails

```bash
# Increase swap to 2 GB
sudo swapoff /swapfile
sudo fallocate -l 2G /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### App Won't Start

```bash
pm2 logs APP_NAME --lines 100
sudo lsof -i :3000          # Check if port is already in use
```

### PM2 Crash-Looping

Usually means PM2 is using a stale start command from a previous deploy.

```bash
pm2 delete APP_NAME

# Standalone Next.js (server.js, no node_modules)
PORT=3000 HOSTNAME=0.0.0.0 pm2 start server.js --name APP_NAME

# Regular Node.js app
pm2 start npm --name APP_NAME -- start

pm2 save
```

### Nginx 502 Bad Gateway

```bash
pm2 status                           # Is the app actually running?
sudo nginx -t                        # Config syntax OK?
sudo tail -f /var/log/nginx/error.log
```

### High CPU Temperature

```bash
vcgencmd measure_temp
# Over 80°C? Add a heatsink or reduce workload
```

### NAS Not Showing in Dashboard

The NAS card only appears when `/mnt/nas` is mounted.

```bash
mountpoint /mnt/nas    # is it mounted?
lsblk                  # is the drive detected?
sudo mount -a          # try mounting from fstab manually
```

### NAS Won't Auto-Remount After Plug

```bash
sudo blkid /dev/sda1                          # check LABEL= matches "pizow-nas"
ls /etc/udev/rules.d/99-pizow-nas.rules       # rule exists?
sudo udevadm control --reload-rules
```

### File Browser 403 / Can't Upload

```bash
sudo systemctl status filebrowser
sudo journalctl -u filebrowser -n 30
```

If config is wrong, reinitialize:

```bash
sudo systemctl stop filebrowser
filebrowser config set --database /opt/filebrowser/filebrowser.db --root /mnt/nas
sudo systemctl start filebrowser
```

---

## Useful Commands

### PM2

```bash
pm2 status                  # App status
pm2 logs APP_NAME           # Live logs
pm2 restart APP_NAME        # Restart
pm2 monit                   # Real-time resource monitor
```

### System

```bash
htop                        # Process viewer
free -h                     # Memory
df -h                       # Disk
vcgencmd measure_temp       # CPU temperature
uptime                      # Uptime
```

### Nginx

```bash
sudo systemctl status nginx
sudo nginx -t               # Test config
sudo tail -f /var/log/nginx/error.log
```
