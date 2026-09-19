#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Backend Systemd Service Installer
# Installs and enables attenda-backend.service for automatic boot and restart.
# Usage: sudo bash setup_backend_service.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run with sudo or as root.${NC}"
    echo -e "Usage: sudo bash $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"
VENV_PYTHON="${BACKEND_DIR}/venv/bin/python"

# Detect non-root username who invoked sudo
RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "techpark-2")}"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  VisionGate / Attenda - Backend Systemd Service Installation               ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

if [ ! -f "${VENV_PYTHON}" ]; then
    echo -e "${RED}[ERROR] Virtualenv python not found at: ${VENV_PYTHON}${NC}"
    echo -e "Please run bash 03_setup_backend.sh first."
    exit 1
fi

SERVICE_FILE="/etc/systemd/system/attenda-backend.service"
echo -e "${CYAN}Generating systemd service file: ${SERVICE_FILE}...${NC}"
echo -e "  Service User:      ${GREEN}${RUN_USER}${NC}"
echo -e "  Working Directory: ${GREEN}${BACKEND_DIR}${NC}"
echo -e "  Python Binary:     ${GREEN}${VENV_PYTHON}${NC}"

cat << EOF > "${SERVICE_FILE}"
[Unit]
Description=VisionGate / Attenda FastAPI Backend Server
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${BACKEND_DIR}
EnvironmentFile=-${ROOT_DIR}/.env
EnvironmentFile=-${BACKEND_DIR}/.env
ExecStart=${VENV_PYTHON} main.py
Restart=always
RestartSec=5s
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload and enable
systemctl daemon-reload
systemctl enable --now attenda-backend.service

sleep 2
if systemctl is-active --quiet attenda-backend.service; then
    echo -e "${GREEN}[✓] attenda-backend.service is ACTIVE and RUNNING!${NC}"
    echo -e "To view logs: journalctl -u attenda-backend -f"
else
    echo -e "${RED}[!] attenda-backend.service failed to start. Inspecting journalctl...${NC}"
    journalctl -u attenda-backend -n 25 --no-pager
fi
