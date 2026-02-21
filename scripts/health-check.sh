#!/bin/bash

# ===========================================
# PiZoW - Health Check Script
# ===========================================
# Monitor Pi resources and app status
#
# Usage: ./health-check.sh        # Run from Mac (SSH to Pi)
#        ./health-check.sh --local # Run directly on Pi
# ===========================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if running locally on Pi or remotely from Mac
RUN_LOCAL=false
for arg in "$@"; do
    case $arg in
        --local) RUN_LOCAL=true ;;
    esac
done

# If not running locally, SSH to Pi and run there
if [ "$RUN_LOCAL" = false ]; then
    # Load .env file if exists
    if [ -f "$PROJECT_ROOT/.env" ]; then
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    fi

    PI_USER="${PI_USER:-YOUR_USERNAME}"
    PI_HOST="${PI_HOST:-YOUR_PI_IP_ADDRESS}"

    if [ "$PI_USER" = "YOUR_USERNAME" ] || [ "$PI_HOST" = "YOUR_PI_IP_ADDRESS" ]; then
        echo "Error: Please configure .env file with PI_USER and PI_HOST"
        exit 1
    fi

    # Copy script to Pi and run it
    ssh "${PI_USER}@${PI_HOST}" 'bash -s -- --local' < "$0"
    exit $?
fi

# ===========================================
# Everything below runs ON the Pi
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Thresholds
TEMP_WARN=70
TEMP_CRIT=80
MEM_WARN=80
DISK_WARN=80

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  PiZoW - Health Check${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# System Info
echo -e "${YELLOW}System${NC}"
echo "  Hostname: $(hostname)"
echo "  IP:       $(hostname -I 2>/dev/null | awk '{print $1}' || echo 'N/A')"
echo "  Uptime:   $(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
echo ""

# CPU Temperature
echo -e "${YELLOW}Temperature${NC}"
if command -v vcgencmd &> /dev/null; then
    TEMP=$(vcgencmd measure_temp | cut -d'=' -f2 | cut -d"'" -f1)
    TEMP_INT=${TEMP%.*}

    if [ "$TEMP_INT" -ge "$TEMP_CRIT" ]; then
        echo -e "  CPU: ${RED}${TEMP}°C (CRITICAL)${NC}"
    elif [ "$TEMP_INT" -ge "$TEMP_WARN" ]; then
        echo -e "  CPU: ${YELLOW}${TEMP}°C (Warning)${NC}"
    else
        echo -e "  CPU: ${GREEN}${TEMP}°C${NC}"
    fi
elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP=$((TEMP_RAW / 1000))
    if [ "$TEMP" -ge "$TEMP_CRIT" ]; then
        echo -e "  CPU: ${RED}${TEMP}°C (CRITICAL)${NC}"
    elif [ "$TEMP" -ge "$TEMP_WARN" ]; then
        echo -e "  CPU: ${YELLOW}${TEMP}°C (Warning)${NC}"
    else
        echo -e "  CPU: ${GREEN}${TEMP}°C${NC}"
    fi
else
    echo "  CPU: N/A"
fi
echo ""

# Memory
echo -e "${YELLOW}Memory${NC}"
MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/^Mem:/ {print $3}')
MEM_AVAIL=$(free -m | awk '/^Mem:/ {print $7}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

if [ "$MEM_PERCENT" -ge "$MEM_WARN" ]; then
    echo -e "  RAM:  ${RED}${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)${NC}"
else
    echo -e "  RAM:  ${GREEN}${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)${NC}"
fi
echo "  Available: ${MEM_AVAIL}MB"

SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
SWAP_USED=$(free -m | awk '/^Swap:/ {print $3}')
if [ "$SWAP_TOTAL" -gt 0 ]; then
    SWAP_PERCENT=$((SWAP_USED * 100 / SWAP_TOTAL))
    echo "  Swap: ${SWAP_USED}MB / ${SWAP_TOTAL}MB (${SWAP_PERCENT}%)"
fi
echo ""

# Disk
echo -e "${YELLOW}Disk${NC}"
DISK_PERCENT=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')

if [ "$DISK_PERCENT" -ge "$DISK_WARN" ]; then
    echo -e "  Usage:     ${RED}${DISK_PERCENT}%${NC} of ${DISK_TOTAL}"
else
    echo -e "  Usage:     ${GREEN}${DISK_PERCENT}%${NC} of ${DISK_TOTAL}"
fi
echo "  Available: ${DISK_AVAIL}"
echo ""

# Services
echo -e "${YELLOW}Services${NC}"

# Nginx
if command -v nginx &> /dev/null; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "  Nginx:  ${GREEN}Running${NC}"
    else
        echo -e "  Nginx:  ${RED}Stopped${NC}"
    fi
else
    echo -e "  Nginx:  ${YELLOW}Not installed${NC}"
fi

# PM2
if command -v pm2 &> /dev/null; then
    PM2_ONLINE=$(pm2 jlist 2>/dev/null | grep -c '"status":"online"' || echo 0)
    PM2_TOTAL=$(pm2 jlist 2>/dev/null | grep -c '"pm_id"' || echo 0)

    if [ "$PM2_TOTAL" -eq 0 ]; then
        echo -e "  PM2:    ${YELLOW}No apps${NC}"
    elif [ "$PM2_ONLINE" -eq "$PM2_TOTAL" ]; then
        echo -e "  PM2:    ${GREEN}${PM2_ONLINE}/${PM2_TOTAL} online${NC}"
    else
        echo -e "  PM2:    ${RED}${PM2_ONLINE}/${PM2_TOTAL} online${NC}"
    fi
else
    echo -e "  PM2:    ${YELLOW}Not installed${NC}"
fi
echo ""

# Systemd Services (common Node.js services)
echo -e "${YELLOW}Systemd Services${NC}"
SERVICES=("second-brain" "pizow" "node-api")
FOUND_SERVICE=false

for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
        FOUND_SERVICE=true
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${svc}: ${GREEN}Running${NC}"
        else
            echo -e "  ${svc}: ${RED}Stopped${NC}"
        fi
    fi
done

if [ "$FOUND_SERVICE" = false ]; then
    echo "  No PiZoW services found"
fi
echo ""

# Node.js Processes
echo -e "${YELLOW}Node.js Processes${NC}"
NODE_PROCS=$(pgrep -a node 2>/dev/null | grep -v grep || true)

if [ -n "$NODE_PROCS" ]; then
    echo "$NODE_PROCS" | while read -r line; do
        PID=$(echo "$line" | awk '{print $1}')
        CMD=$(echo "$line" | cut -d' ' -f2-)
        MEM=$(ps -p "$PID" -o rss= 2>/dev/null | awk '{printf "%.0f", $1/1024}')
        echo -e "  ${GREEN}PID $PID${NC} (${MEM}MB): $CMD"
    done
else
    echo "  No Node.js processes running"
fi
echo ""

# Listening Ports
echo -e "${YELLOW}Listening Ports${NC}"
ss -tlnp 2>/dev/null | grep -E ':3000|:4000|:5000|:8080' | while read -r line; do
    PORT=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
    PROC=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+' || echo "unknown")
    echo "  :${PORT} -> ${PROC}"
done || echo "  No common ports listening"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
