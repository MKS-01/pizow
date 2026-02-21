#!/bin/bash

# ===========================================
# PiZoW - Generic Deployment Script
# ===========================================
# Deploy any Node.js project to your Pi
#
# Usage: ./deploy.sh [options]
#
# Options:
#   --local    Build locally + rsync built output to Pi (default)
#   --remote   Pull latest from git remote on the Pi, build there
#   --restart  Only restart PM2 (skip build/sync/pull)
# ===========================================

set -e

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
APP_NAME="${PM2_APP_NAME:-${PROJECT_NAME:-app}}"
BRANCH="${BRANCH:-main}"
PORT="${PORT:-3000}"
REPO_URL="${REPO_URL:-}"
LOCAL_PATH="${LOCAL_PATH:-$PROJECT_ROOT/examples/${PROJECT_NAME}}"
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
RESTART_ONLY=false
DEPLOY_MODE="local"   # default: build locally, rsync output

for arg in "$@"; do
    case $arg in
        --local)   DEPLOY_MODE="local" ;;
        --remote)  DEPLOY_MODE="remote" ;;
        --restart) RESTART_ONLY=true ;;
    esac
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  PiZoW - Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check configuration
if [ "$PI_USER" = "YOUR_USERNAME" ] || [ "$PI_HOST" = "YOUR_PI_IP_ADDRESS" ]; then
    echo -e "${RED}Error: Please configure deployment settings${NC}"
    echo ""
    echo "  cp .env.example .env"
    echo "  # Edit .env with your values"
    echo ""
    exit 1
fi

echo -e "Mode:   ${GREEN}${DEPLOY_MODE}${NC}"
echo -e "Target: ${GREEN}${PI_USER}@${PI_HOST}:${PI_PATH}${NC}"
echo -e "App:    ${GREEN}${APP_NAME}${NC}"
echo -e "Port:   ${GREEN}${PORT}${NC}"
if [ "$DEPLOY_MODE" = "local" ]; then
    echo -e "Source: ${GREEN}${LOCAL_PATH}${NC}"
else
    echo -e "Branch: ${GREEN}${BRANCH}${NC}"
fi
echo ""

# Test SSH connection
echo -e "${YELLOW}Testing connection...${NC}"
if ! ssh -q -o ConnectTimeout=5 ${PI_USER}@${PI_HOST} exit; then
    echo -e "${RED}Cannot connect to ${PI_HOST}${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Connected"
echo ""

# ── LOCAL MODE: build on this machine, rsync output to Pi ────────
if [ "$DEPLOY_MODE" = "local" ] && [ "$RESTART_ONLY" = "false" ]; then

    if [ ! -d "$LOCAL_PATH" ]; then
        echo -e "${RED}Error: Local path not found: ${LOCAL_PATH}${NC}"
        echo "Set LOCAL_PATH in .env or pass the correct path."
        exit 1
    fi

    cd "$LOCAL_PATH"

    # Install deps locally if needed
    echo -e "${YELLOW}Installing local dependencies...${NC}"
    npm ci 2>/dev/null || npm install
    echo -e "${GREEN}✓${NC} Dependencies ready"
    echo ""

    # Build locally
    echo -e "${YELLOW}Building on local machine...${NC}"
    npm run build
    echo -e "${GREEN}✓${NC} Build complete"
    echo ""

    # Detect standalone Next.js output vs regular build
    if [ -d ".next/standalone" ]; then
        # Next.js standalone mode
        echo -e "${YELLOW}Syncing standalone build to Pi...${NC}"
        ssh "${PI_USER}@${PI_HOST}" "mkdir -p ${PI_PATH}"
        rsync -az --delete .next/standalone/ "${PI_USER}@${PI_HOST}:${PI_PATH}/"
        rsync -az --delete .next/static/     "${PI_USER}@${PI_HOST}:${PI_PATH}/.next/static/"
        [ -d "public" ] && rsync -az --delete public/ "${PI_USER}@${PI_HOST}:${PI_PATH}/public/"
        echo -e "${GREEN}✓${NC} Standalone build synced"
    else
        # Regular build — sync source + build output, skip heavy folders
        echo -e "${YELLOW}Syncing build to Pi...${NC}"
        rsync -az --delete \
            --exclude='.git' \
            --exclude='node_modules' \
            --exclude='.env' \
            "$LOCAL_PATH/" "${PI_USER}@${PI_HOST}:${PI_PATH}/"
        echo -e "${GREEN}✓${NC} Files synced"
        echo ""

        # Install production deps on Pi (no build needed)
        echo -e "${YELLOW}Installing production deps on Pi...${NC}"
        ssh "${PI_USER}@${PI_HOST}" "cd ${PI_PATH} && npm ci --omit=dev 2>/dev/null || npm install --omit=dev"
        echo -e "${GREEN}✓${NC} Production deps installed"
    fi
    echo ""

    cd "$PROJECT_ROOT"
fi

# ── REMOTE MODE: git clone / pull + build on Pi ──────────────────
if [ "$DEPLOY_MODE" = "remote" ] && [ "$RESTART_ONLY" = "false" ]; then
    ssh ${PI_USER}@${PI_HOST} << ENDSSH
    set -e
    export PATH="\$PATH:\$(npm prefix -g)/bin"
    if [ ! -d "${PI_PATH}" ]; then
        if [ -z "${REPO_URL}" ]; then
            echo "Project not found at ${PI_PATH} and REPO_URL is not set."
            exit 1
        fi
        echo "Cloning from ${REPO_URL}..."
        git clone ${REPO_URL} ${PI_PATH}
    fi
    cd ${PI_PATH}
    echo "Pulling latest from ${BRANCH}..."
    git fetch origin ${BRANCH}
    git reset --hard origin/${BRANCH}
    echo "Installing dependencies..."
    npm ci 2>/dev/null || npm install
    echo "Building..."
    npm run build
ENDSSH
fi

# ── Start / restart PM2 on Pi ────────────────────────────────────
echo -e "${YELLOW}Starting app on Pi...${NC}"

ssh ${PI_USER}@${PI_HOST} << ENDSSH
    set -e
    # Ensure npm global bin is in PATH (fixes pm2: command not found in non-interactive SSH)
    export PATH="\$PATH:\$(npm prefix -g)/bin"

    if [ ! -d "${PI_PATH}" ]; then
        echo "Directory not found: ${PI_PATH}"
        exit 1
    fi

    cd ${PI_PATH}

    # Standalone Next.js uses node server.js directly
    if [ -f "server.js" ]; then
        pm2 delete ${APP_NAME} 2>/dev/null || true
        PORT=${PORT} HOSTNAME=0.0.0.0 pm2 start server.js --name "${APP_NAME}"
    else
        if pm2 describe ${APP_NAME} > /dev/null 2>&1; then
            pm2 restart ${APP_NAME}
        else
            pm2 start npm --name "${APP_NAME}" -- start
        fi
    fi

    pm2 save

    echo ""
    echo "Status:"
    pm2 list
ENDSSH

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Your app is running at: ${YELLOW}http://${PI_HOST}:${PORT}${NC}"
echo ""
