#!/bin/bash

# ===========================================
# PiZoW - Project Management Script
# ===========================================
# Manage deployed projects on your Pi
#
# Usage:
#   ./manage.sh list              # List running apps
#   ./manage.sh stop <port>       # Stop app on port
#   ./manage.sh kill <port>       # Kill process on port
#   ./manage.sh remove <path>     # Remove deployed project
#   ./manage.sh logs <path>       # View logs
#   ./manage.sh restart <path>    # Restart app
# ===========================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load .env file if exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

PI_USER="${PI_USER:-YOUR_USERNAME}"
PI_HOST="${PI_HOST:-YOUR_PI_IP_ADDRESS}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check configuration
check_config() {
    if [ "$PI_USER" = "YOUR_USERNAME" ] || [ "$PI_HOST" = "YOUR_PI_IP_ADDRESS" ]; then
        echo -e "${RED}Error: Please configure .env file${NC}"
        exit 1
    fi
}

# Show usage
usage() {
    echo ""
    echo -e "${BLUE}PiZoW - Project Management${NC}"
    echo ""
    echo "Usage: ./manage.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                    List all running Node.js apps and ports"
    echo "  stop <port>             Stop app running on specified port"
    echo "  kill <port>             Force kill process on port"
    echo "  remove <project-path>   Remove deployed project from Pi"
    echo "  logs [path]             View logs (default: /tmp/pizow.log)"
    echo "  restart <project-path>  Restart app at specified path"
    echo "  services                List and manage systemd services"
    echo ""
    echo "Examples:"
    echo "  ./manage.sh list"
    echo "  ./manage.sh stop 4000"
    echo "  ./manage.sh kill 3000"
    echo "  ./manage.sh remove /home/mks/pizow-test"
    echo "  ./manage.sh logs"
    echo "  ./manage.sh restart /home/mks/pizow"
    echo ""
}

# List running apps
cmd_list() {
    check_config
    echo -e "${BLUE}Fetching running apps from Pi...${NC}"
    echo ""

    ssh "${PI_USER}@${PI_HOST}" << 'ENDSSH'
        echo -e "\033[1;33mNode.js Processes\033[0m"
        echo "─────────────────────────────────────────────────────────"
        ps aux | grep -E 'node|npm' | grep -v grep | while read -r line; do
            PID=$(echo "$line" | awk '{print $2}')
            MEM=$(echo "$line" | awk '{print $4}')
            CMD=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "; print ""}')
            printf "  PID %-6s | MEM %s%% | %s\n" "$PID" "$MEM" "$CMD"
        done || echo "  No Node.js processes running"
        echo ""

        echo -e "\033[1;33mListening Ports\033[0m"
        echo "─────────────────────────────────────────────────────────"
        ss -tlnp 2>/dev/null | grep -E 'LISTEN' | while read -r line; do
            PORT=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
            PROC=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+' 2>/dev/null || echo "unknown")
            PID=$(echo "$line" | grep -oP 'pid=\K[0-9]+' 2>/dev/null || echo "?")
            if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 3000 ] && [ "$PORT" -le 9999 ]; then
                printf "  :%s -> %s (PID: %s)\n" "$PORT" "$PROC" "$PID"
            fi
        done || echo "  No ports listening in range 3000-9999"
        echo ""

        echo -e "\033[1;33mSystemd Services\033[0m"
        echo "─────────────────────────────────────────────────────────"
        for svc in second-brain pizow node-api; do
            if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
                STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
                if [ "$STATUS" = "active" ]; then
                    echo -e "  $svc: \033[0;32m$STATUS\033[0m"
                else
                    echo -e "  $svc: \033[0;31m$STATUS\033[0m"
                fi
            fi
        done
        echo ""

        echo -e "\033[1;33mDeployed Projects\033[0m"
        echo "─────────────────────────────────────────────────────────"
        for dir in ~/pizow* ~/second-brain ~/node-api; do
            if [ -d "$dir" ]; then
                SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                echo "  $dir ($SIZE)"
            fi
        done || echo "  No projects found"
        echo ""
ENDSSH
}

# Stop app on port
cmd_stop() {
    check_config
    PORT="$1"

    if [ -z "$PORT" ]; then
        echo -e "${RED}Error: Please specify a port${NC}"
        echo "Usage: ./manage.sh stop <port>"
        exit 1
    fi

    echo -e "${YELLOW}Stopping app on port ${PORT}...${NC}"

    ssh "${PI_USER}@${PI_HOST}" << ENDSSH
        PID=\$(lsof -t -i:${PORT} 2>/dev/null || ss -tlnp | grep ":${PORT}" | grep -oP 'pid=\K[0-9]+')
        if [ -n "\$PID" ]; then
            kill \$PID 2>/dev/null && echo "Stopped process \$PID on port ${PORT}" || echo "Failed to stop"
        else
            echo "No process found on port ${PORT}"
        fi
ENDSSH
}

# Force kill on port
cmd_kill() {
    check_config
    PORT="$1"

    if [ -z "$PORT" ]; then
        echo -e "${RED}Error: Please specify a port${NC}"
        echo "Usage: ./manage.sh kill <port>"
        exit 1
    fi

    echo -e "${YELLOW}Force killing process on port ${PORT}...${NC}"

    ssh "${PI_USER}@${PI_HOST}" << ENDSSH
        # Try multiple methods to find and kill
        PID=\$(lsof -t -i:${PORT} 2>/dev/null)
        if [ -z "\$PID" ]; then
            PID=\$(ss -tlnp 2>/dev/null | grep ":${PORT}" | grep -oP 'pid=\K[0-9]+')
        fi
        if [ -z "\$PID" ]; then
            PID=\$(fuser ${PORT}/tcp 2>/dev/null)
        fi

        if [ -n "\$PID" ]; then
            kill -9 \$PID 2>/dev/null && echo "Killed process \$PID on port ${PORT}" || echo "Failed to kill"
        else
            echo "No process found on port ${PORT}"
        fi
ENDSSH
}

# Remove project
cmd_remove() {
    check_config
    PROJECT_PATH="$1"

    if [ -z "$PROJECT_PATH" ]; then
        echo -e "${RED}Error: Please specify project path${NC}"
        echo "Usage: ./manage.sh remove /home/mks/project-name"
        exit 1
    fi

    echo -e "${YELLOW}This will remove: ${PROJECT_PATH}${NC}"
    read -p "Are you sure? (y/N): " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Cancelled"
        exit 0
    fi

    echo -e "${YELLOW}Stopping any running processes...${NC}"
    ssh "${PI_USER}@${PI_HOST}" << ENDSSH
        # Kill any node process in this directory
        pkill -f "${PROJECT_PATH}" 2>/dev/null || true

        # Wait a moment
        sleep 1

        # Remove the directory
        if [ -d "${PROJECT_PATH}" ]; then
            rm -rf "${PROJECT_PATH}"
            echo "Removed ${PROJECT_PATH}"
        else
            echo "Directory not found: ${PROJECT_PATH}"
        fi
ENDSSH

    echo -e "${GREEN}Done!${NC}"
}

# View logs
cmd_logs() {
    check_config
    LOG_PATH="${1:-/tmp/pizow.log}"

    echo -e "${BLUE}Showing logs from ${LOG_PATH}...${NC}"
    echo -e "${YELLOW}(Press Ctrl+C to exit)${NC}"
    echo ""

    ssh "${PI_USER}@${PI_HOST}" "tail -f ${LOG_PATH} 2>/dev/null || echo 'Log file not found: ${LOG_PATH}'"
}

# Restart app
cmd_restart() {
    check_config
    PROJECT_PATH="$1"
    PORT="${2:-3000}"

    if [ -z "$PROJECT_PATH" ]; then
        echo -e "${RED}Error: Please specify project path${NC}"
        echo "Usage: ./manage.sh restart /home/mks/project-name [port]"
        exit 1
    fi

    echo -e "${YELLOW}Restarting app at ${PROJECT_PATH} on port ${PORT}...${NC}"

    ssh "${PI_USER}@${PI_HOST}" << ENDSSH
        # Kill existing
        pkill -f "${PROJECT_PATH}/server.js" 2>/dev/null || true
        sleep 1

        # Start
        cd "${PROJECT_PATH}" || exit 1
        PORT=${PORT} HOSTNAME=0.0.0.0 nohup node server.js > /tmp/pizow-\$(basename ${PROJECT_PATH}).log 2>&1 &

        sleep 2

        if pgrep -f "${PROJECT_PATH}/server.js" > /dev/null; then
            echo "App restarted successfully on port ${PORT}"
        else
            echo "Failed to start app"
            cat /tmp/pizow-\$(basename ${PROJECT_PATH}).log
        fi
ENDSSH
}

# Manage services
cmd_services() {
    check_config
    ACTION="${1:-status}"
    SERVICE="${2:-}"

    ssh "${PI_USER}@${PI_HOST}" << ENDSSH
        echo -e "\033[1;33mSystemd Services\033[0m"
        echo ""

        case "${ACTION}" in
            status)
                for svc in second-brain pizow node-api; do
                    if systemctl list-unit-files 2>/dev/null | grep -q "^$svc.service"; then
                        echo "=== \$svc ==="
                        systemctl status \$svc --no-pager 2>/dev/null | head -5
                        echo ""
                    fi
                done
                ;;
            stop)
                if [ -n "${SERVICE}" ]; then
                    sudo systemctl stop ${SERVICE} && echo "Stopped ${SERVICE}"
                else
                    echo "Usage: ./manage.sh services stop <service-name>"
                fi
                ;;
            start)
                if [ -n "${SERVICE}" ]; then
                    sudo systemctl start ${SERVICE} && echo "Started ${SERVICE}"
                else
                    echo "Usage: ./manage.sh services start <service-name>"
                fi
                ;;
            restart)
                if [ -n "${SERVICE}" ]; then
                    sudo systemctl restart ${SERVICE} && echo "Restarted ${SERVICE}"
                else
                    echo "Usage: ./manage.sh services restart <service-name>"
                fi
                ;;
            *)
                echo "Usage: ./manage.sh services [status|start|stop|restart] [service-name]"
                ;;
        esac
ENDSSH
}

# Main
case "${1:-}" in
    list)
        cmd_list
        ;;
    stop)
        cmd_stop "$2"
        ;;
    kill)
        cmd_kill "$2"
        ;;
    remove)
        cmd_remove "$2"
        ;;
    logs)
        cmd_logs "$2"
        ;;
    restart)
        cmd_restart "$2" "$3"
        ;;
    services)
        cmd_services "$2" "$3"
        ;;
    *)
        usage
        ;;
esac
