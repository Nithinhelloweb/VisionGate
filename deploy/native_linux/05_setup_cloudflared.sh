#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Native Linux Cloudflare Tunnel Setup Script
# Installs and configures cloudflared as a native systemd service with zero Docker.
# Usage: sudo bash 05_setup_cloudflared.sh
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

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  VisionGate / Attenda - Native Cloudflare Tunnel Configuration              ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

# 1. Load Token from .env
TUNNEL_TOKEN=""
if [ -f "${ROOT_DIR}/.env" ]; then
    TUNNEL_TOKEN=$(grep -E "^CLOUDFLARE_TUNNEL_TOKEN=" "${ROOT_DIR}/.env" | cut -d '=' -f2- | tr -d '"' | tr -d "'" || true)
fi

if [ -z "${TUNNEL_TOKEN}" ] && [ -f "${ROOT_DIR}/backend/.env" ]; then
    TUNNEL_TOKEN=$(grep -E "^CLOUDFLARE_TUNNEL_TOKEN=" "${ROOT_DIR}/backend/.env" | cut -d '=' -f2- | tr -d '"' | tr -d "'" || true)
fi

# 2. Check cloudflared installation
if ! command -v cloudflared &>/dev/null; then
    echo -e "${YELLOW}cloudflared not found. Installing latest official package...${NC}"
    wget -q -O /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared.deb || apt-get install -f -y
    rm -f /tmp/cloudflared.deb
fi

# 3. Setup via Token (Preferred & Cleanest Method)
if [ -n "${TUNNEL_TOKEN}" ]; then
    echo -e "\n${CYAN}[1/2] Installing cloudflared system service with Tunnel Token...${NC}"
    
    # Uninstall existing service if any
    systemctl stop cloudflared 2>/dev/null || true
    cloudflared service uninstall 2>/dev/null || true

    # Install as official systemd service
    cloudflared service install "${TUNNEL_TOKEN}"
    systemctl daemon-reload
    systemctl enable --now cloudflared
    echo -e "${GREEN}[✓] cloudflared system service installed and started!${NC}"
else
    echo -e "\n${CYAN}[1/2] Token not found in .env; configuring via credentials.json...${NC}"
    mkdir -p /etc/cloudflared
    
    CRED_FILE="${ROOT_DIR}/docker/cloudflared/credentials.json"
    if [ -f "${CRED_FILE}" ]; then
        cp "${CRED_FILE}" /etc/cloudflared/credentials.json
        chmod 600 /etc/cloudflared/credentials.json
    fi

    # Native Ingress pointing to 127.0.0.1:80 instead of Docker hostname
    cat << 'EOF' > /etc/cloudflared/config.yml
tunnel: 27b90fd6-f11b-4f35-b160-47bcc2e2ed9e
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: attenda.srishakthicgpa.in
    service: http://127.0.0.1:80
  - service: http_status:404
EOF

    # Install systemd service
    cat << 'EOF' > /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflare Tunnel Agent (Native)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/cloudflared --config /etc/cloudflared/config.yml tunnel run
Restart=always
RestartSec=5s
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now cloudflared
    echo -e "${GREEN}[✓] cloudflared systemd service configured and started!${NC}"
fi

# 4. Verify Service Status
echo -e "\n${CYAN}[2/2] Checking cloudflared service status...${NC}"
sleep 2
if systemctl is-active --quiet cloudflared; then
    echo -e "${GREEN}[✓] cloudflared service is ACTIVE and RUNNING!${NC}"
else
    echo -e "${RED}[!] cloudflared service failed to start. Inspecting journalctl...${NC}"
    journalctl -u cloudflared -n 20 --no-pager
fi

echo -e "\n${GREEN}[SUCCESS] Cloudflare tunnel configured!${NC}"
echo -e "Public domain: https://attenda.srishakthicgpa.in"
