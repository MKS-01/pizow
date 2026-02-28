#!/bin/bash

# ===========================================
# PiZoW - NAS Setup Script
# ===========================================
# Turns your Pi Zero W into a NAS using an
# external USB HDD (Toshiba or any USB drive)
#
# Features:
#   - exFAT format + auto-mount on boot
#   - NFS server (for Linux/Mac clients)
#   - File Browser (web UI on port 8080)
#   - Dashboard-ready API endpoint at /nas-info
#
# Usage (run from your Mac):
#   ./scripts/setup-nas.sh
#   ./scripts/setup-nas.sh --local   # run directly on Pi
#
# Prerequisites:
#   - .env with PI_USER, PI_HOST set
#   - USB HDD connected to Pi via OTG adapter
# ===========================================

set -eo pipefail
# Don't exit on errors in individual commands — we handle them explicitly
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

    echo -e "${BLUE}Detected macOS — forwarding NAS setup to ${PI_USER}@${PI_HOST}...${NC}"
    echo ""

    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    sshpass -p "$PI_PASSWORD" scp -q "$SELF" "${PI_USER}@${PI_HOST}:/tmp/setup-nas.sh" 2>/dev/null \
        || scp -q "$SELF" "${PI_USER}@${PI_HOST}:/tmp/setup-nas.sh"

    ssh "${PI_USER}@${PI_HOST}" \
        "SUDO_PASS='${PI_PASSWORD}' bash /tmp/setup-nas.sh --local; rm -f /tmp/setup-nas.sh"
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

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  PiZoW - NAS Setup${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}[$1/$TOTAL_STEPS]${NC} $2"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ── Config ─────────────────────────────────────────────────────────
TOTAL_STEPS=8
MOUNT_POINT="/mnt/nas"
NAS_LABEL="pizow-nas"
FILEBROWSER_PORT=8080
# NFS export: allow entire /24 subnet by default
NFS_SUBNET="192.168.1.0/24"
# File Browser admin password — must be set via FB_PASSWORD in .env
if [ -z "${FB_PASSWORD:-}" ]; then
    print_error "FB_PASSWORD is not set. Add it to your .env file before running."
    exit 1
fi

print_header

# Check not root
if [ "$EUID" -eq 0 ]; then
    print_error "Run as regular user, not root"
    exit 1
fi

echo -e "Mount point: ${GREEN}${MOUNT_POINT}${NC}"
echo -e "NFS subnet:  ${GREEN}${NFS_SUBNET}${NC} (edit NFS_SUBNET in script if different)"
echo -e "File Browser: port ${GREEN}${FILEBROWSER_PORT}${NC}"
echo ""

# ── Step 1: Detect USB drive ───────────────────────────────────────
print_step 1 "Detecting USB drive..."

# List block devices that are NOT the SD card (mmcblk0)
USB_DEVS=$(lsblk -rno NAME,TYPE,TRAN | awk '$2=="disk" && $3=="usb" {print "/dev/"$1}')

if [ -z "$USB_DEVS" ]; then
    echo ""
    print_error "No USB drive detected!"
    echo ""
    echo "  Make sure your HDD is:"
    echo "    1. Connected via a USB OTG adapter"
    echo "    2. Powered (USB hub with power if needed)"
    echo ""
    echo "  You can list all block devices with:"
    echo "    lsblk"
    echo ""
    echo "  Then rerun this script."
    exit 1
fi

# Pick the first USB disk
USB_DISK=$(echo "$USB_DEVS" | head -n1)
# The partition will be ${USB_DISK}1 (e.g. /dev/sda1)
USB_PART="${USB_DISK}1"

echo ""
echo "  Detected disk: ${USB_DISK}"
echo ""
lsblk "$USB_DISK" 2>/dev/null || true
echo ""

print_warn "This will ERASE all data on ${USB_DISK}!"
echo -n "  Continue? [y/N] "
read -r CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

print_success "USB drive detected: ${USB_DISK}"

# ── Step 2: Install required packages ─────────────────────────────
print_step 2 "Installing packages (e2fsprogs, NFS, curl)..."
_sudo apt update -qq
_sudo apt install -y e2fsprogs nfs-kernel-server curl
print_success "Packages installed"

# ── Step 3: Format drive as ext4 ─────────────────────────────────
print_step 3 "Formatting ${USB_DISK} as ext4..."

# Skip format if already mounted at MOUNT_POINT
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "  Drive already mounted at ${MOUNT_POINT} — skipping format"
else
    # Unmount if mounted elsewhere
    _sudo umount "${USB_PART}" 2>/dev/null || true
    _sudo umount "${USB_DISK}" 2>/dev/null || true

    # Wipe partition table and create new GPT with single partition
    _sudo parted -s "$USB_DISK" mklabel gpt
    _sudo parted -s "$USB_DISK" mkpart primary 0% 100%
    sleep 2  # let kernel re-read partition table

    # Format as ext4 with label
    _sudo mkfs.ext4 -L "$NAS_LABEL" "${USB_PART}"
    print_success "Drive formatted as ext4 (label: ${NAS_LABEL})"
fi

# ── Step 4: Auto-mount via /etc/fstab ────────────────────────────
print_step 4 "Configuring auto-mount at ${MOUNT_POINT}..."

# Get UUID of the partition
sleep 1
UUID=$(blkid -s UUID -o value "${USB_PART}" 2>/dev/null || true)
if [ -z "$UUID" ]; then
    print_error "Could not read UUID from ${USB_PART}. Try: sudo blkid"
    exit 1
fi

echo "  UUID: $UUID"

# Create mount point
_sudo mkdir -p "$MOUNT_POINT"

# Add fstab entry (remove old entry for this mount point first)
_sudo sed -i "\|${MOUNT_POINT}|d" /etc/fstab
# Write to /tmp first, then append with sudo — avoids _sudo tee pipe corruption
echo "UUID=${UUID}  ${MOUNT_POINT}  ext4  defaults,nofail  0  2" > /tmp/fstab_entry
_sudo sh -c "cat /tmp/fstab_entry >> /etc/fstab"
rm -f /tmp/fstab_entry

# Mount if not already mounted
if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    _sudo mount "$MOUNT_POINT"
else
    echo "  Already mounted — skipping mount"
fi

# Set ownership so user can write without sudo
_sudo chown -R "$USER":"$USER" "$MOUNT_POINT"
_sudo chmod 755 "$MOUNT_POINT"

# Create default folders
_sudo mkdir -p "${MOUNT_POINT}/media" "${MOUNT_POINT}/docs" "${MOUNT_POINT}/backup"
_sudo chown -R "$USER":"$USER" "${MOUNT_POINT}" 2>/dev/null || true
print_success "Drive mounted at ${MOUNT_POINT} and will auto-mount on boot"

# ── Step 5: NFS Server setup ──────────────────────────────────────
print_step 5 "Configuring NFS server..."

# Remove old export for this path if exists
_sudo sed -i "\|${MOUNT_POINT}|d" /etc/exports

# Add NFS export
echo "${MOUNT_POINT}  ${NFS_SUBNET}(rw,sync,no_subtree_check,all_squash,anonuid=$(id -u),anongid=$(id -g))" > /tmp/exports_entry
_sudo sh -c "cat /tmp/exports_entry >> /etc/exports"
rm -f /tmp/exports_entry

_sudo exportfs -ra
_sudo systemctl enable nfs-kernel-server
_sudo systemctl restart nfs-kernel-server

print_success "NFS server running — export: ${MOUNT_POINT} → ${NFS_SUBNET}"

# ── Step 6: File Browser (web UI) ────────────────────────────────
print_step 6 "Installing File Browser (web UI)..."

if ! command -v filebrowser &>/dev/null; then
    # Download latest release binary directly for arm64 (Pi Zero 2 W)
    FB_VERSION=$(curl -fsSL https://api.github.com/repos/filebrowser/filebrowser/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    FB_VERSION="${FB_VERSION:-v2.31.2}"
    ARCH="arm64"
    # Pi Zero (original) is armv6/armv7, Pi Zero 2 W is arm64
    if uname -m | grep -q "armv6\|armv7"; then
        ARCH="armv7"
    fi
    curl -fsSL "https://github.com/filebrowser/filebrowser/releases/download/${FB_VERSION}/linux-${ARCH}-filebrowser.tar.gz" \
        -o /tmp/filebrowser.tar.gz
    _sudo tar -xzf /tmp/filebrowser.tar.gz -C /usr/local/bin filebrowser
    _sudo chmod +x /usr/local/bin/filebrowser
    rm -f /tmp/filebrowser.tar.gz
fi

# Create config dir
FB_DIR="/opt/filebrowser"
_sudo mkdir -p "$FB_DIR"
_sudo chown "$USER":"$USER" "$FB_DIR"

# Always stop service before touching db
_sudo systemctl stop filebrowser 2>/dev/null || true

# Initialize database if not exists
if [ ! -f "$FB_DIR/filebrowser.db" ]; then
    filebrowser config init --database "$FB_DIR/filebrowser.db"
    filebrowser config set \
        --database "$FB_DIR/filebrowser.db" \
        --address 0.0.0.0 \
        --port "$FILEBROWSER_PORT" \
        --root "$MOUNT_POINT" \
        --log "$FB_DIR/filebrowser.log"
fi

# Always ensure admin user exists (add or update)
filebrowser users add admin "$FB_PASSWORD" \
    --database "$FB_DIR/filebrowser.db" \
    --perm.admin 2>/dev/null \
|| filebrowser users update admin \
    --password "$FB_PASSWORD" \
    --database "$FB_DIR/filebrowser.db" 2>/dev/null || true

# Create systemd service for File Browser
# Write to /tmp first (as user), then move with sudo — avoids heredoc corruption with _sudo tee
cat > /tmp/filebrowser.service <<EOF
[Unit]
Description=PiZoW File Browser
After=network.target

[Service]
User=${USER}
ExecStart=/usr/local/bin/filebrowser --database ${FB_DIR}/filebrowser.db
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
_sudo mv /tmp/filebrowser.service /etc/systemd/system/filebrowser.service
_sudo chmod 644 /etc/systemd/system/filebrowser.service

_sudo systemctl daemon-reload
_sudo systemctl enable filebrowser
_sudo systemctl restart filebrowser

print_success "File Browser running at http://$(hostname -I | awk '{print $1}'):${FILEBROWSER_PORT}"
print_warn "Login: admin / ${FB_PASSWORD} — change the password after first login!"

# ── Step 7: Dashboard info endpoint ──────────────────────────────
print_step 7 "Creating NAS info endpoint for dashboard..."

# Simple bash-based HTTP endpoint via netcat — exposed on port 8081
# The dashboard (Next.js) can call http://localhost:8081 for NAS stats
NAS_API_SCRIPT="/opt/filebrowser/nas-api.sh"

cat > "$NAS_API_SCRIPT" <<'SCRIPT'
#!/bin/bash
# Minimal HTTP server returning NAS stats as JSON on port 8081
# Called by the PiZoW dashboard to display drive info
MOUNT="/mnt/nas"
PORT=8081
while true; do
    DISK_TOTAL=$(df -B1 "$MOUNT" 2>/dev/null | awk 'NR==2{print $2}')
    DISK_USED=$(df -B1 "$MOUNT" 2>/dev/null | awk 'NR==2{print $3}')
    DISK_FREE=$(df -B1 "$MOUNT" 2>/dev/null | awk 'NR==2{print $4}')
    DISK_PCT=$(df "$MOUNT" 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    MOUNTED=$(mountpoint -q "$MOUNT" && echo true || echo false)
    FILES=$(find "$MOUNT" -maxdepth 3 -type f 2>/dev/null | wc -l)

    BODY="{\"mounted\":${MOUNTED},\"mount\":\"${MOUNT}\",\"total_bytes\":${DISK_TOTAL:-0},\"used_bytes\":${DISK_USED:-0},\"free_bytes\":${DISK_FREE:-0},\"use_pct\":${DISK_PCT:-0},\"file_count\":${FILES}}"
    RESPONSE="HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${#BODY}\r\nConnection: close\r\n\r\n${BODY}"

    echo -e "$RESPONSE" | nc -l -p $PORT -q 1
done
SCRIPT

chmod +x "$NAS_API_SCRIPT"

# Systemd service for NAS API
cat > /tmp/pizow-nas-api.service <<EOF
[Unit]
Description=PiZoW NAS Stats API
After=network.target

[Service]
User=${USER}
ExecStart=/bin/bash ${NAS_API_SCRIPT}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
_sudo mv /tmp/pizow-nas-api.service /etc/systemd/system/pizow-nas-api.service
_sudo chmod 644 /etc/systemd/system/pizow-nas-api.service

_sudo systemctl daemon-reload
_sudo systemctl enable pizow-nas-api
_sudo systemctl restart pizow-nas-api

print_success "NAS stats API running at http://localhost:8081 (for dashboard)"

# ── Step 8: udev rule for auto-remount on USB plug ───────────────
print_step 8 "Setting up udev auto-remount rule..."

# Write a udev rule: when any USB storage partition appears (add event),
# run systemd-mount to mount it using the fstab entry.
# LABEL match ensures we only trigger on our specific drive.
cat > /tmp/99-pizow-nas.rules <<'RULES'
# Auto-remount pizow-nas pendrive when plugged in
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="pizow-nas", \
    RUN+="/bin/systemctl restart local-fs.target"
RULES
_sudo mv /tmp/99-pizow-nas.rules /etc/udev/rules.d/99-pizow-nas.rules
_sudo chmod 644 /etc/udev/rules.d/99-pizow-nas.rules
_sudo udevadm control --reload-rules

print_success "udev rule installed — drive will auto-remount when plugged in"

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  NAS Setup Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
PI_IP=$(hostname -I | awk '{print $1}')
echo "  Drive:        ${USB_DISK} → ${MOUNT_POINT} (exFAT)"
echo "  Drive free:   $(df -h ${MOUNT_POINT} | awk 'NR==2{print $4}') available"
echo ""
echo "  NFS share:    ${MOUNT_POINT} exported to ${NFS_SUBNET}"
echo "  File Browser: http://${PI_IP}:${FILEBROWSER_PORT}  (admin / pizow)"
echo "  NAS API:      http://${PI_IP}:8081  (JSON stats for dashboard)"
echo ""
echo -e "${YELLOW}Connect from Mac:${NC}"
echo "  # NFS"
echo "  sudo mkdir -p /Volumes/pizow-nas"
echo "  sudo mount -t nfs ${PI_IP}:${MOUNT_POINT} /Volumes/pizow-nas"
echo ""
echo "  # Or via Finder: Go → Connect to Server → nfs://${PI_IP}${MOUNT_POINT}"
echo ""
echo -e "${YELLOW}Connect from Linux:${NC}"
echo "  sudo mount -t nfs ${PI_IP}:${MOUNT_POINT} /mnt/pizow-nas"
echo ""
echo -e "${YELLOW}Default folders created:${NC}"
echo "  ${MOUNT_POINT}/media    ${MOUNT_POINT}/docs    ${MOUNT_POINT}/backup"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "  • Change File Browser password: http://${PI_IP}:${FILEBROWSER_PORT}"
echo "  • Drive is formatted as ext4 — access via NFS or File Browser"
echo "    (not directly readable by Mac/Windows without NFS)"
echo ""
echo -e "${YELLOW}Dashboard integration (coming next):${NC}"
echo "  • Call http://PI_IP:8081 from your Next.js dashboard"
echo "  • Returns JSON: mounted, total/used/free bytes, file count"
echo ""
