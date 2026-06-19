# CLI Cheatsheet

Quick reference for SSH, Nmap, and Linux day-to-day commands.

---

## Table of Contents

- [SSH](#ssh)
- [Nmap](#nmap)
- [File & Directory](#file--directory)
- [Process & System](#process--system)
- [Network](#network)
- [Disk & Storage](#disk--storage)
- [Package Management](#package-management)
- [PM2](#pm2)
- [Permissions](#permissions)
- [Logs](#logs)
- [Ubuntu / Linux Admin](#ubuntu--linux-admin)
- [Miscellaneous](#miscellaneous)

---

## SSH

```bash
# Connect
ssh user@host
ssh user@192.168.1.100
ssh -p 2222 user@host                        # custom port

# Key setup
ssh-keygen -t ed25519 -C "label"             # generate key
ssh-copy-id user@host                        # copy public key to remote
ssh-keyscan host >> ~/.ssh/known_hosts       # add host key without interactive prompt

# Tunnels & forwarding
ssh -L 8080:localhost:3000 user@host         # local forward  → localhost:8080 → remote:3000
ssh -R 9090:localhost:3000 user@host         # reverse tunnel → remote:9090 → local:3000
ssh -D 1080 user@host                        # SOCKS5 proxy on localhost:1080

# Copy files
scp file.txt user@host:/path/to/dest/
scp -r ./folder user@host:/path/
rsync -az --progress ./src/ user@host:/dst/  # sync folder (resume-able)
rsync -az --delete ./src/ user@host:/dst/    # mirror (deletes removed files)

# Run remote command
ssh user@host "command"
ssh user@host "df -h && free -h"

# Config shortcut (~/.ssh/config)
# Host pi
#   HostName YOUR_PI_IP
#   User mks
#   IdentityFile ~/.ssh/id_ed25519
# Then just: ssh pi
```

---

## Nmap

```bash
# Discovery
nmap -sn 192.168.1.0/24                      # ping scan — find live hosts
nmap -sn 192.168.1.0/24 | grep -i rasp       # find Raspberry Pi devices

# Port scanning
nmap 192.168.1.100                            # default scan (top 1000 ports)
nmap -p 22,80,443,3000 192.168.1.100         # specific ports
nmap -p- 192.168.1.100                        # all 65535 ports
nmap -p 1-9999 192.168.1.100                 # port range

# Service & OS detection
nmap -sV 192.168.1.100                        # detect service versions
nmap -O 192.168.1.100                         # OS detection (needs root)
nmap -A 192.168.1.100                         # aggressive: OS + version + scripts

# Speed
nmap -T4 192.168.1.0/24                       # faster scan (T0=paranoid … T5=insane)

# Output
nmap -oN output.txt 192.168.1.100            # save normal output
nmap -oG output.gnmap 192.168.1.0/24         # greppable output

# UDP
nmap -sU -p 53,67,161 192.168.1.100          # UDP scan (slow, needs root)
```

---

## File & Directory

```bash
# Navigate
ls -lah                                       # list with hidden + human sizes
ls -lt                                        # sort by modified time
cd -                                          # jump to previous directory
pwd                                           # print working directory

# Create / delete
mkdir -p a/b/c                                # create nested dirs
rm -rf folder/                               # delete folder recursively
cp -r src/ dst/                              # copy folder
mv old new                                   # rename / move

# Find
find . -name "*.log"                          # find by name
find . -type f -mtime -1                      # modified in last 24h
find . -size +100M                            # files over 100MB
find . -name "*.js" | xargs grep "TODO"      # grep across found files

# View
cat file.txt
less file.txt                                 # scrollable viewer (q to quit)
head -n 20 file.txt
tail -n 50 file.txt
tail -f /var/log/syslog                       # follow live log

# Search in files
grep -r "pattern" ./src                       # recursive search
grep -rn "pattern" ./src                      # with line numbers
grep -ri "pattern" ./src                      # case-insensitive

# Archives
tar -czf archive.tar.gz folder/              # compress
tar -xzf archive.tar.gz                      # extract
tar -tzf archive.tar.gz                      # list contents
zip -r archive.zip folder/
unzip archive.zip
```

---

## Process & System

```bash
# Processes
ps aux                                        # all processes
ps aux | grep node                            # filter by name
top                                           # live process viewer
htop                                          # better top (if installed)
kill 1234                                     # send SIGTERM
kill -9 1234                                  # force kill (SIGKILL)
pkill node                                    # kill by name
pgrep -fl node                                # find PIDs by name

# System info
uname -a                                      # kernel + arch
hostname -I                                   # IP address(es)
uptime                                        # uptime + load avg
cat /proc/cpuinfo                             # CPU details
cat /proc/meminfo                             # memory details
cat /proc/loadavg                             # load averages
cat /sys/class/thermal/thermal_zone0/temp     # CPU temp (in millidegrees)
vcgencmd measure_temp                         # Pi temperature (vcgencmd)

# Services (systemd)
systemctl status nginx
systemctl start / stop / restart nginx
systemctl enable nginx                        # start on boot
systemctl disable nginx
journalctl -u nginx -f                        # follow service logs
systemctl list-units --type=service --state=running

# Background jobs
command &                                     # run in background
jobs                                          # list background jobs
fg %1                                         # bring job 1 to foreground
nohup command &                               # persist after logout
screen -S session_name                        # start named screen session
screen -r session_name                        # reattach
tmux new -s main                             # start tmux session
tmux attach -t main                          # reattach
```

---

## Network

```bash
# Interfaces
ip a                                          # all interfaces + IPs
ip r                                          # routing table
ifconfig                                      # (legacy)

# Connectivity
ping -c 4 8.8.8.8
curl -I https://example.com                   # HTTP headers only
curl -o /dev/null -w "%{http_code}" url       # just status code
wget -q -O- url | head                        # fetch + preview

# Open ports (local)
ss -tlnp                                      # TCP listening ports + process
ss -tn                                        # established TCP connections
netstat -tlnp                                 # (legacy alternative)

# DNS
nslookup example.com
dig example.com
dig +short example.com

# Transfer speed test
curl -o /dev/null http://host/bigfile         # download speed test

# Firewall (ufw)
sudo ufw status
sudo ufw allow 3000
sudo ufw deny 22
sudo ufw enable / disable
```

---

## Disk & Storage

```bash
df -h                                         # disk usage per mount
df -h /                                       # root partition only
du -sh folder/                               # folder size
du -sh * | sort -h                           # sizes sorted
lsblk                                         # list block devices
mount | grep sda                             # check mounts
mountpoint -q /mnt/nas && echo mounted        # check if path is mounted

# SD card / USB
lsblk -f                                      # filesystems
fdisk -l                                      # partition table (needs root)
```

---

## Package Management

```bash
# apt (Debian / Ubuntu / Raspberry Pi OS)
sudo apt update                               # refresh package list
sudo apt upgrade -y                           # upgrade all packages
sudo apt install package
sudo apt remove package
sudo apt autoremove -y                        # clean unused deps
apt list --upgradable                         # see what can be upgraded
apt search keyword
apt show package                              # package info

# npm
npm install
npm ci                                        # clean install from lockfile
npm run build
npm audit fix
npm list -g --depth=0                         # global packages
```

---

## PM2

```bash
# Process management
pm2 start server.js --name myapp
pm2 start npm --name myapp -- start
pm2 stop myapp
pm2 restart myapp
pm2 delete myapp
pm2 list                                      # all processes
pm2 show myapp                                # detailed info

# Logs
pm2 logs                                      # all logs
pm2 logs myapp                               # specific app
pm2 logs myapp --lines 100
pm2 flush                                     # clear logs

# Startup
pm2 save                                      # save current process list
pm2 startup                                   # generate startup script
pm2 unstartup                                 # remove startup script

# Env / config
PORT=4000 pm2 start server.js --name myapp
pm2 restart myapp --update-env
pm2 env 0                                     # show env for process id 0
```

---

## Permissions

```bash
chmod +x script.sh                            # make executable
chmod 755 file                                # rwx r-x r-x
chmod 644 file                                # rw- r-- r--
chmod -R 755 folder/                         # recursive
chown user:group file
chown -R mks:mks /home/mks/app               # recursive ownership

# Common patterns
ls -la                                        # see permissions
stat file                                     # detailed file info
sudo !!                                       # rerun last command as sudo
```

---

## Logs

```bash
# System logs
journalctl -f                                 # follow all logs
journalctl -u service -f                      # follow service logs
journalctl --since "1 hour ago"
journalctl -p err                             # errors only
cat /var/log/syslog | tail -100
dmesg | tail -50                              # kernel messages

# Nginx
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

---

## Ubuntu / Linux Admin

```bash
# System info
lsb_release -a                                # distro details
cat /etc/os-release                           # OS info
uname -r                                      # kernel version
hostnamectl                                   # hostname + OS + kernel
arch                                          # architecture (aarch64, x86_64)

# Users & groups
whoami
id                                            # uid, gid, groups
sudo adduser username
sudo usermod -aG sudo username                # grant sudo
sudo deluser username
passwd                                        # change own password
last                                          # login history
w                                             # who's logged in + what they're doing

# Cron
crontab -l                                    # list cron jobs
crontab -e                                    # edit cron jobs
# m h dom mon dow command
# 0 3 * * * /home/mks/backup.sh              # daily at 3am
sudo ls /etc/cron.d/                          # system cron jobs
systemctl status cron                         # cron service status

# Swap
free -h                                       # memory + swap usage
swapon --show                                 # active swap devices
sudo fallocate -l 1G /swapfile                # create 1GB swapfile
sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile

# Kernel & modules
lsmod                                         # loaded kernel modules
modinfo module_name                           # module details
dmesg | tail -30                              # recent kernel messages
dmesg -T                                      # with human-readable timestamps

# Hardware
lscpu                                         # CPU info
lsmem                                         # memory layout
lsusb                                         # USB devices
lspci                                         # PCI devices
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL   # detailed block devices
sensors                                       # temps/voltages (lm-sensors)

# Networking (Ubuntu)
ip link set eth0 up / down                    # enable/disable interface
nmcli dev status                              # NetworkManager devices
nmcli con show                                # connections
ss -s                                         # socket summary
resolvectl status                             # DNS resolver info

# Systemd timers (modern cron alternative)
systemctl list-timers --all                   # all scheduled timers
systemctl status myapp.timer

# Snap (Ubuntu)
snap list                                     # installed snaps
sudo snap install package
sudo snap remove package
sudo snap refresh                             # update all snaps

# Unattended upgrades
sudo apt install unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades     # enable auto security updates
cat /var/log/unattended-upgrades/unattended-upgrades.log

# Boot & startup
systemd-analyze                               # boot time
systemd-analyze blame                         # slow services at boot
systemctl list-unit-files --state=enabled     # what starts on boot
```

---

## Miscellaneous

```bash
# History
history | grep ssh
ctrl+r                                        # reverse search history
!!                                            # repeat last command
!$                                            # last argument of previous command

# Aliases (add to ~/.bashrc or ~/.zshrc)
alias ll='ls -lah'
alias gs='git status'
alias pi='ssh YOUR_USER@YOUR_PI_IP'

# Environment
echo $PATH
export VAR=value
env | grep NODE
source ~/.bashrc                              # reload shell config

# Time & date
date
timedatectl                                   # timezone info
timedatectl set-timezone Asia/Kolkata

# One-liners
watch -n 2 'df -h'                            # run command every 2s
yes | command                                 # auto-confirm prompts
command | tee output.txt                      # stdout + save to file
diff file1 file2
wc -l file.txt                               # line count
sort file.txt | uniq -c | sort -rn           # frequency count
```

---

> Configure your Pi details in `.env` — see `.env.example` for required vars.
