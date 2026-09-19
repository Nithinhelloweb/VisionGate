#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Native Linux Service Management Controller
# Controls: attenda-backend, postgresql, nginx, cloudflared
# Usage: bash manage_services.sh [start|stop|restart|status|logs]
# ==============================================================================

ACTION="${1:-status}"

SERVICES=("postgresql" "attenda-backend" "nginx" "cloudflared")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

case "${ACTION}" in
    start)
        echo -e "${CYAN}Starting all VisionGate services...${NC}"
        for s in "${SERVICES[@]}"; do
            echo -e "Starting $s..."
            sudo systemctl start "$s"
        done
        echo -e "${GREEN}[✓] All services started.${NC}"
        ;;
    stop)
        echo -e "${YELLOW}Stopping all VisionGate services...${NC}"
        sudo systemctl stop "cloudflared" || true
        sudo systemctl stop "nginx" || true
        sudo systemctl stop "attenda-backend" || true
        echo -e "${GREEN}[✓] Applications stopped (PostgreSQL left running for maintenance).${NC}"
        ;;
    restart)
        echo -e "${CYAN}Restarting VisionGate backend & tunnel...${NC}"
        sudo systemctl restart "attenda-backend"
        sudo systemctl restart "nginx"
        sudo systemctl restart "cloudflared"
        echo -e "${GREEN}[✓] Services restarted.${NC}"
        ;;
    status)
        echo -e "${CYAN}================ Service Status =================${NC}"
        for s in "${SERVICES[@]}"; do
            STATE=$(systemctl is-active "$s" 2>/dev/null || echo "inactive")
            if [ "$STATE" = "active" ]; then
                echo -e "  $s: ${GREEN}● ACTIVE${NC}"
            else
                echo -e "  $s: ${RED}○ $STATE${NC}"
            fi
        done
        echo -e "${CYAN}=================================================${NC}"
        ;;
    logs)
        TARGET="${2:-attenda-backend}"
        echo -e "${CYAN}Streaming logs for ${TARGET}... (Press Ctrl+C to exit)${NC}"
        sudo journalctl -u "${TARGET}" -f -n 50
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs [service_name]}"
        exit 1
        ;;
esac
