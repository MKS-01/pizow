#!/bin/bash

# ===========================================
# PiZoW - Nginx Setup Script
# ===========================================
# Configure Nginx as reverse proxy
# Run this on your Pi after setup-pi.sh
#
# Usage: ./nginx-setup.sh [app-name] [port]
# Example: ./nginx-setup.sh myapp 3000
# ===========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APP_NAME="${1:-app}"
APP_PORT="${2:-3000}"
NGINX_CONF="/etc/nginx/sites-available/${APP_NAME}"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  PiZoW - Nginx Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "App Name: ${GREEN}${APP_NAME}${NC}"
echo -e "App Port: ${GREEN}${APP_PORT}${NC}"
echo ""

# Check if running on Pi
if [ ! -f /etc/nginx/nginx.conf ]; then
    echo -e "${RED}Nginx not found. Run setup-pi.sh first.${NC}"
    exit 1
fi

# Get hostname/IP for server_name
PI_IP=$(hostname -I | awk '{print $1}')
PI_HOSTNAME=$(hostname)

echo -e "${YELLOW}Creating Nginx configuration...${NC}"

# Create Nginx config
sudo tee ${NGINX_CONF} > /dev/null << EOF
server {
    listen 80;
    server_name ${PI_HOSTNAME} ${PI_HOSTNAME}.local ${PI_IP} _;

    # Logging
    access_log /var/log/nginx/${APP_NAME}.access.log;
    error_log /var/log/nginx/${APP_NAME}.error.log;

    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;

        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';

        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_cache_bypass \$http_upgrade;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Static files caching (optional)
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        proxy_pass http://127.0.0.1:${APP_PORT};
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

echo -e "${GREEN}✓${NC} Config created: ${NGINX_CONF}"

# Enable site
echo -e "${YELLOW}Enabling site...${NC}"
sudo ln -sf ${NGINX_CONF} /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Test configuration
echo -e "${YELLOW}Testing configuration...${NC}"
sudo nginx -t

# Restart Nginx
echo -e "${YELLOW}Restarting Nginx...${NC}"
sudo systemctl restart nginx

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Nginx Configured!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Your app is now accessible at:"
echo -e "  • ${YELLOW}http://${PI_IP}${NC}"
echo -e "  • ${YELLOW}http://${PI_HOSTNAME}.local${NC}"
echo ""
echo "Useful commands:"
echo "  • View logs:    sudo tail -f /var/log/nginx/${APP_NAME}.error.log"
echo "  • Test config:  sudo nginx -t"
echo "  • Restart:      sudo systemctl restart nginx"
echo ""
