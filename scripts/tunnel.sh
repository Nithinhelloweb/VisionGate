#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda — Cloudflare Tunnel Launch & Domain Discovery Engine
# Starts Cloudflare Zero-Trust or Quick Ephemeral Tunnel and resolves public URL
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${BLUE} VisionGate / Attenda — Cloudflare Secure Ingress Tunnel Engine        ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# Check docker compose command
if docker compose version &>/dev/null; then
    COMPOSE_BASE="docker compose"
else
    COMPOSE_BASE="docker-compose"
fi

if docker run --rm --gpus all nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi &>/dev/null; then
    COMPOSE_CMD="${COMPOSE_BASE} -f docker-compose.yml -f docker-compose.gpu.yml"
else
    COMPOSE_CMD="${COMPOSE_BASE} -f docker-compose.yml"
fi

if [ -f "docker/cloudflared/config.yml" ]; then
    export CLOUDFLARE_COMMAND="tunnel --config /etc/cloudflared/config.yml run"
elif [ -n "${CLOUDFLARE_TUNNEL_TOKEN}" ]; then
    export CLOUDFLARE_COMMAND="tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}"
else
    export CLOUDFLARE_COMMAND="tunnel --url http://nginx:80 --no-autoupdate"
fi

echo -e "\n[*] Starting Cloudflare Tunnel Container..."
${COMPOSE_CMD} --profile tunnel up -d cloudflared

echo -e "[*] Waiting for tunnel connection and resolving public URL..."
MAX_WAIT=30
WAITED=0
TUNNEL_URL=""

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
    LOGS=$(docker logs --tail 50 attenda-cloudflared 2>&1 || echo "")
    
    # Check for trycloudflare quick tunnel URL
    if echo "$LOGS" | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | head -n 1 | grep -q 'trycloudflare\.com'; then
        TUNNEL_URL=$(echo "$LOGS" | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | head -n 1)
        break
    fi
    
    # Check for established named tunnel connection
    if echo "$LOGS" | grep -qi 'Registered tunnel connection'; then
        if [[ "${CLOUDFLARE_DOMAIN}" =~ ^http ]]; then
            TUNNEL_URL="${CLOUDFLARE_DOMAIN}"
        else
            TUNNEL_URL="https://${CLOUDFLARE_DOMAIN:-attenda.srishakthicgpa.in}"
        fi
        break
    fi
    
    sleep 2
    WAITED=$((WAITED + 2))
done

echo ""
if [ -n "$TUNNEL_URL" ]; then
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}  CLOUDFLARE TUNNEL ONLINE & OPERATIONAL!                             ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "  ${CYAN}Public Tunnel URL:${NC} ${BOLD}${TUNNEL_URL}${NC}"
    echo -e "  ${CYAN}Mobile App Target:${NC} ${TUNNEL_URL}/health"
    echo -e "${GREEN}======================================================================${NC}\n"
else
    echo -e "${YELLOW}Tunnel is running. View live logs with:${NC}"
    echo -e "  ${COMPOSE_CMD} logs -f cloudflared\n"
fi
