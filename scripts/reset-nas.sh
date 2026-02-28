#!/bin/bash

# ===========================================
# PiZoW - NAS Reset Script
# ===========================================
# Wipes all NAS components so setup-nas.sh
# can be run fresh from scratch.
#
# Usage (run from your Mac):
#   ./scripts/reset-nas.sh
#   ./scripts/reset-nas.sh --local   # run directly on Pi
# ===========================================

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── If running on macOS, SSH into Pi and run this script there ────
if [[ "$(uname)" == "Darwin" ]] && [[ "$1" != "--local" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    if [ -f "$PROJECT_ROOT/.env" ]; then
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    fi

    PI_USER="${PI_USER:-YOUR_USERNAME}"
    PI_HOST="${PI_HOST:-YOUR_PI_IP_ADDRESS}"
    PI_PASSWORD="${PI_PASSWORD:-}"

    if [ "$PI_USER" = "YOUR_USERNAME" ] || [ "$PI_HOST" = "YOUR_PI_IP_ADDRESS" ]; then
        echo -e "${RED}Error: Set PI_USER and PI_HOST in .env first${NC}"
        exit 1
    fi

    echo -e "${BLUE}Detected macOS — forwarding NAS reset to ${PI_USER}@${PI_HOST}...${NC}"
    echo ""

    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    sshpass -p "$PI_PASSWORD" scp -q "$SELF" "${PI_USER}@${PI_HOST}:/tmp/reset-nas.sh" 2>/dev/null \
        || scp -q "$SELF" "${PI_USER}@${PI_HOST}:/tmp/reset-nas.sh"

    ssh "${PI_USER}@${PI_HOST}" \
        "SUDO_PASS='${PI_PASSWORD}' bash /tmp/reset-nas.sh --local; rm -f /tmp/reset-nas.sh"
    exit $?
fi

# ── Helpers ────────────────────────────────────────────────────────
_sudo() {
    if [ -n "${SUDO_PASS:-}" ]; then
        echo "$SUDO_PASS" | sudo -S "$@" 2>/dev/null
    else
        sudo "$@"
    fi
}

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  PiZoW - NAS Reset${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}This will remove all NAS services, configs, and mount points.${NC}"
echo -e "${YELLOW}The USB drive data itself will NOT be deleted.${NC}"
echo ""
echo -n "  Continue? [y/N] "
read -r CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Stop and disable services
echo -e "${YELLOW}Stopping services...${NC}"
_sudo systemctl stop filebrowser 2>/dev/null && echo "  ✓ filebrowser stopped" || true
_sudo systemctl stop pizow-nas-api 2>/dev/null && echo "  ✓ pizow-nas-api stopped" || true
_sudo systemctl stop nas-api 2>/dev/null || true
_sudo systemctl disable filebrowser 2>/dev/null || true
_sudo systemctl disable pizow-nas-api 2>/dev/null || true
_sudo systemctl disable nas-api 2>/dev/null || true

# Remove service files
echo -e "${YELLOW}Removing service files...${NC}"
_sudo rm -f /etc/systemd/system/filebrowser.service
_sudo rm -f /etc/systemd/system/pizow-nas-api.service
_sudo rm -f /etc/systemd/system/nas-api.service
_sudo systemctl daemon-reload
echo "  ✓ Service files removed"

# Remove File Browser binary and data
echo -e "${YELLOW}Removing File Browser...${NC}"
_sudo rm -f /usr/local/bin/filebrowser
_sudo rm -rf /opt/filebrowser
rm -rf "$HOME/.filebrowser"
echo "  ✓ File Browser removed"

# Remove NFS exports
echo -e "${YELLOW}Removing NFS exports...${NC}"
_sudo sed -i '/\/mnt\/nas/d' /etc/exports
_sudo exportfs -ra 2>/dev/null || true
echo "  ✓ NFS exports cleared"

# Unmount drive
echo -e "${YELLOW}Unmounting /mnt/nas...${NC}"
_sudo umount /mnt/nas 2>/dev/null && echo "  ✓ Unmounted" || echo "  (not mounted)"

# Remove fstab entry
_sudo sed -i '/\/mnt\/nas/d' /etc/fstab
echo "  ✓ fstab entry removed"

# Remove mount point
_sudo rm -rf /mnt/nas
echo "  ✓ Mount point removed"

# Remove udev rule
echo -e "${YELLOW}Removing udev auto-remount rule...${NC}"
_sudo rm -f /etc/udev/rules.d/99-pizow-nas.rules
_sudo udevadm control --reload-rules
echo "  ✓ udev rule removed"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  NAS reset complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Now run: ./scripts/setup-nas.sh"
echo ""
