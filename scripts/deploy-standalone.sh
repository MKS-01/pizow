#!/bin/bash

# ===========================================
# PiZoW - Standalone Deployment Script
# ===========================================
# Build locally, rsync to Pi (for Pi Zero with limited RAM)
# Based on second-brain deployment approach
#
# Usage:
#   ./deploy-standalone.sh              # full build + deploy
#   ./deploy-standalone.sh --skip-build # deploy existing build
# ===========================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load .env file if exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

# ============================================
# CONFIGURATION (can be overridden by .env)
# ============================================
PI_USER="${PI_USER:-YOUR_USERNAME}"
PI_HOST="${PI_HOST:-YOUR_PI_IP_ADDRESS}"
PI_PATH="${PROJECT_PATH:-/home/${PI_USER}/${PROJECT_NAME:-app}}"
PORT="${PORT:-3000}"
BUILD_DIR="${BUILD_DIR:-examples/nextjs}"  # Which example to deploy
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[deploy]${NC} $1"; }
ok()   { echo -e "${GREEN}[  ok  ]${NC} $1"; }
warn() { echo -e "${YELLOW}[ warn ]${NC} $1"; }
err()  { echo -e "${RED}[error ]${NC} $1"; exit 1; }

# Pre-flight checks
command -v rsync >/dev/null 2>&1 || err "rsync is not installed"
command -v ssh   >/dev/null 2>&1 || err "ssh is not installed"
command -v npm   >/dev/null 2>&1 || err "npm is not installed"

# Check configuration
if [ "$PI_USER" = "YOUR_USERNAME" ] || [ "$PI_HOST" = "YOUR_PI_IP_ADDRESS" ]; then
    err "Please configure .env file (cp .env.example .env)"
fi

# Parse args
SKIP_BUILD=false
for arg in "$@"; do
    case $arg in
        --skip-build) SKIP_BUILD=true ;;
    esac
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  PiZoW - Standalone Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Source: ${GREEN}${BUILD_DIR}${NC}"
echo -e "Target: ${GREEN}${PI_USER}@${PI_HOST}:${PI_PATH}${NC}"
echo -e "Port:   ${GREEN}${PORT}${NC}"
echo ""

# Change to build directory
cd "$PROJECT_ROOT/$BUILD_DIR" || err "Build directory not found: $BUILD_DIR"

# Step 1: Build
if [ "$SKIP_BUILD" = false ]; then
    log "Building Next.js (standalone)..."
    npm run build
    ok "Build complete"
else
    if [ ! -d ".next/standalone" ]; then
        err "No build found at .next/standalone — run without --skip-build first"
    fi
    warn "Skipping build, using existing .next/standalone"
fi

# Step 2: Check Pi is reachable
log "Checking Pi connectivity..."
ssh -o ConnectTimeout=5 -o BatchMode=yes "${PI_USER}@${PI_HOST}" "echo ok" >/dev/null 2>&1 \
    || err "Cannot reach Pi at ${PI_USER}@${PI_HOST}"
ok "Pi is reachable"

# Step 3: Create remote directory
log "Preparing remote directory..."
ssh "${PI_USER}@${PI_HOST}" "mkdir -p ${PI_PATH}"

# Step 4: Sync standalone build
log "Syncing standalone build to Pi..."
rsync -az --delete \
    .next/standalone/ \
    "${PI_USER}@${PI_HOST}:${PI_PATH}/"
ok "Standalone server synced"

# Step 5: Sync static assets
log "Syncing static assets..."
rsync -az --delete \
    .next/static/ \
    "${PI_USER}@${PI_HOST}:${PI_PATH}/.next/static/"
ok "Static assets synced"

# Step 6: Sync public folder
if [ -d "public" ]; then
    log "Syncing public folder..."
    rsync -az --delete \
        public/ \
        "${PI_USER}@${PI_HOST}:${PI_PATH}/public/"
    ok "Public folder synced"
fi

# Step 7: Start/restart server
log "Starting server on Pi..."
ssh "${PI_USER}@${PI_HOST}" << ENDSSH
    # Kill existing process if running
    pkill -f "${PI_PATH}/server.js" 2>/dev/null || true

    # Start server
    cd ${PI_PATH}
    PORT=${PORT} HOSTNAME=0.0.0.0 nohup node server.js > /tmp/pizow.log 2>&1 &

    sleep 2

    # Check if running
    if pgrep -f "${PI_PATH}/server.js" > /dev/null; then
        echo "Server started successfully"
    else
        echo "Failed to start server. Check /tmp/pizow.log"
        cat /tmp/pizow.log
        exit 1
    fi
ENDSSH

ok "Deploy complete!"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Your app is running at: ${YELLOW}http://${PI_HOST}:${PORT}${NC}"
echo ""
echo "Logs: ssh ${PI_USER}@${PI_HOST} 'tail -f /tmp/pizow.log'"
echo ""
