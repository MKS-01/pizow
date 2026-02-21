#!/bin/bash

# ===========================================
# PiZoW - Raspberry Pi Zero W Setup Script
# ===========================================
# Prepares your Pi Zero W as a Node.js server
# Works with any Node.js project
#
# Usage:
#   ./setup-pi.sh          # auto-detects: skips if already set up
#   ./setup-pi.sh --force  # re-run even if already set up
#   ./setup-pi.sh --local  # force run locally (must be on the Pi)
# ===========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── If running on macOS, SSH into Pi and run this script there ────
if [[ "$(uname)" == "Darwin" ]] && [[ "$1" != "--local" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    # Load .env to get PI_USER / PI_HOST
    if [ -f "$PROJECT_ROOT/.env" ]; then
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    fi

    PI_USER="${PI_USER:-YOUR_USERNAME}"
    PI_HOST="${PI_HOST:-YOUR_PI_IP_ADDRESS}"
    PI_PASSWORD="${PI_PASSWORD:-}"
    FORCE=false
    for arg in "$@"; do [[ "$arg" == "--force" ]] && FORCE=true; done

    if [ "$PI_USER" = "YOUR_USERNAME" ] || [ "$PI_HOST" = "YOUR_PI_IP_ADDRESS" ]; then
        echo -e "${RED}Error: Set PI_USER and PI_HOST in .env first${NC}"
        exit 1
    fi

    # Check if already set up (marker file on Pi)
    if [ "$FORCE" = "false" ] && ssh "${PI_USER}@${PI_HOST}" "[ -f ~/.pizow_setup_done ]" 2>/dev/null; then
        echo -e "${GREEN}✓ Pi is already set up!${NC}"
        echo ""
        echo "  Node.js: $(ssh ${PI_USER}@${PI_HOST} 'node --version 2>/dev/null || echo n/a')"
        echo "  PM2:     $(ssh ${PI_USER}@${PI_HOST} 'pm2 --version 2>/dev/null || echo n/a')"
        echo "  Nginx:   $(ssh ${PI_USER}@${PI_HOST} 'nginx -v 2>&1 | cut -d/ -f2 || echo n/a')"
        echo ""
        echo -e "  Run ${YELLOW}./scripts/setup-pi.sh --force${NC} to re-run setup."
        exit 0
    fi

    echo -e "${BLUE}Detected macOS — forwarding setup to ${PI_USER}@${PI_HOST}...${NC}"
    echo ""

    # Resolve absolute path to this script
    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    REMOTE_FLAGS="--local"
    [ "$FORCE" = "true" ] && REMOTE_FLAGS="--local --force"

    # Copy script to Pi (try sshpass first, fall back to key auth)
    sshpass -p "$PI_PASSWORD" scp -q "$SELF" "${PI_USER}@${PI_HOST}:/tmp/setup-pi.sh" 2>/dev/null \
        || scp -q "$SELF" "${PI_USER}@${PI_HOST}:/tmp/setup-pi.sh"

    # Run it via SSH — use key auth (already works), pass password only for sudo via env var
    ssh "${PI_USER}@${PI_HOST}" \
        "SUDO_PASS='${PI_PASSWORD}' bash /tmp/setup-pi.sh ${REMOTE_FLAGS}; rm -f /tmp/setup-pi.sh"
    exit $?
fi

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  PiZoW - Pi Zero W Server Setup${NC}"
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

# Configuration
TOTAL_STEPS=8
NODE_VERSION="20"
SWAP_SIZE="1G"

print_header

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please run as regular user, not root"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    echo -e "Detected OS: ${GREEN}$OS${NC}"
else
    echo -e "OS: ${YELLOW}Unknown${NC}"
fi

echo ""

# Helper: run sudo, using SUDO_PASS env var if set (non-interactive SSH), else interactive
_sudo() {
    if [ -n "${SUDO_PASS:-}" ]; then
        echo "$SUDO_PASS" | sudo -S "$@" 2>/dev/null
    else
        sudo "$@"
    fi
}

# Step 1: Fix locale
print_step 1 "Configuring locale..."
_sudo apt install -y locales
_sudo locale-gen en_US.UTF-8
_sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
print_success "Locale configured"

# Step 2: Update system
print_step 2 "Updating system packages..."
_sudo apt update && _sudo apt upgrade -y
print_success "System updated"

# Step 3: Install Node.js
print_step 3 "Installing Node.js ${NODE_VERSION}.x..."
if command -v node &> /dev/null; then
    CURRENT_NODE=$(node --version)
    echo "  Node.js already installed: $CURRENT_NODE"
else
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x -o /tmp/nodesource_setup.sh
    _sudo bash /tmp/nodesource_setup.sh
    rm -f /tmp/nodesource_setup.sh
    _sudo apt install -y nodejs
fi
print_success "Node.js $(node --version) installed"
print_success "npm $(npm --version) installed"

# Step 4: Install PM2
print_step 4 "Installing PM2 process manager..."
if command -v pm2 &> /dev/null; then
    echo "  PM2 already installed"
else
    _sudo npm install -g pm2
fi
# Ensure PM2 (and npm globals) are in PATH for non-interactive SSH sessions
NPM_GLOBAL_BIN="$(npm bin -g 2>/dev/null || npm prefix -g)/bin"
for PROFILE in ~/.bashrc ~/.profile; do
    if ! grep -q 'npm bin -g\|npm prefix -g' "$PROFILE" 2>/dev/null; then
        echo "export PATH=\"\$PATH:${NPM_GLOBAL_BIN}\"" >> "$PROFILE"
    fi
done
export PATH="$PATH:${NPM_GLOBAL_BIN}"
print_success "PM2 installed and PATH configured"

# Step 5: Install Nginx
print_step 5 "Installing Nginx..."
if command -v nginx &> /dev/null; then
    echo "  Nginx already installed"
else
    _sudo apt install -y nginx
fi
_sudo systemctl enable nginx
print_success "Nginx installed and enabled"

# Step 6: Install Git and utilities
print_step 6 "Installing Git and utilities..."
_sudo apt install -y git htop curl wget
print_success "Utilities installed"

# Step 7: Configure swap
print_step 7 "Configuring swap (${SWAP_SIZE})..."
if [ -f /swapfile ]; then
    CURRENT_SWAP=$(free -h | awk '/^Swap:/ {print $2}')
    echo "  Swap already configured: $CURRENT_SWAP"
else
    _sudo fallocate -l ${SWAP_SIZE} /swapfile
    _sudo chmod 600 /swapfile
    _sudo mkswap /swapfile
    _sudo swapon /swapfile

    # Make permanent
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | _sudo tee -a /etc/fstab
    fi

    # Optimize swappiness
    if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
        echo 'vm.swappiness=10' | _sudo tee -a /etc/sysctl.conf
        _sudo sysctl -p
    fi
fi
print_success "Swap configured"

# Step 8: Configure PM2 startup
print_step 8 "Configuring PM2 startup..."
PM2_STARTUP=$(pm2 startup | grep "sudo" | tail -n 1)
if [ -n "$PM2_STARTUP" ]; then
    # Replace 'sudo' in the startup command with our _sudo wrapper
    PM2_STARTUP="${PM2_STARTUP/sudo/_sudo}"
    eval $PM2_STARTUP 2>/dev/null || true
fi
pm2 save 2>/dev/null || true
print_success "PM2 startup configured"

# Mark setup as complete
touch ~/.pizow_setup_done

# Summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Installed:"
echo "  • Node.js $(node --version)"
echo "  • npm $(npm --version)"
echo "  • PM2 $(pm2 --version)"
echo "  • Nginx $(nginx -v 2>&1 | cut -d'/' -f2)"
echo "  • Git $(git --version | cut -d' ' -f3)"
echo ""
echo "System:"
echo "  • Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "  • Swap: $(free -h | awk '/^Swap:/ {print $2}')"
echo "  • Disk: $(df -h / | awk 'NR==2 {print $4}') available"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Clone your project:"
echo "     git clone https://github.com/YOUR_USERNAME/YOUR_PROJECT.git"
echo ""
echo "  2. Install dependencies:"
echo "     cd YOUR_PROJECT && npm install"
echo ""
echo "  3. Build (if needed):"
echo "     npm run build"
echo ""
echo "  4. Start with PM2:"
echo "     pm2 start npm --name \"app\" -- start"
echo "     pm2 save"
echo ""
echo "  5. Configure Nginx (see nginx-setup.sh)"
echo ""
