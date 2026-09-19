#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda — Universal Docker Stack Startup Engine (Bash)
# Launches PostgreSQL, Backend with AI models, Nginx & Cloudflare Named Tunnel
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${CYAN} VisionGate / Attenda — Production Stack Startup Engine               ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# Check .env
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo -e "  ${GREEN}[OK] Created .env from .env.example${NC}"
    else
        echo -e "  ${RED}[ERROR] .env file not found.${NC}"
        exit 1
    fi
fi

# Detect compose command
if docker compose version &>/dev/null; then
    COMPOSE_BASE="docker compose"
else
    COMPOSE_BASE="docker-compose"
fi

# Hardware acceleration probe
COMPOSE_ARGS="-f docker-compose.yml"
echo -e "\n[*] Detecting Hardware Acceleration Mode..."
if docker run --rm --gpus all nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi &>/dev/null; then
    echo -e "  ${GREEN}[OK] NVIDIA GPU Container Acceleration is ACTIVE.${NC}"
    if [ -f "docker-compose.gpu.yml" ]; then
        COMPOSE_ARGS="-f docker-compose.yml -f docker-compose.gpu.yml"
    fi
else
    echo -e "  ${CYAN}[i] Running in CPU Execution Mode (InsightFace on CPU).${NC}"
fi

# Spin up stack
echo -e "\n[*] Launching Docker Stack Services (Postgres, Backend, Nginx, Cloudflare)..."
${COMPOSE_BASE} ${COMPOSE_ARGS} --profile tunnel up -d

# Wait for health
echo -e "\n[*] Waiting for services to become healthy..."
MAX_WAIT=120
WAITED=0
ALL_HEALTHY=false

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
    PG_H=$(docker inspect --format '{{json .State.Health.Status}}' attenda-postgres 2>/dev/null || echo "")
    BK_H=$(docker inspect --format '{{json .State.Health.Status}}' attenda-backend 2>/dev/null || echo "")
    NX_H=$(docker inspect --format '{{json .State.Health.Status}}' attenda-nginx 2>/dev/null || echo "")

    if [ "$PG_H" == '"healthy"' ] && [ "$BK_H" == '"healthy"' ] && [ "$NX_H" == '"healthy"' ]; then
        ALL_HEALTHY=true
        break
    fi

    echo "  -> Waiting: Postgres ($PG_H), Backend ($BK_H), Nginx ($NX_H) [${WAITED}s/${MAX_WAIT}s]"
    sleep 3
    WAITED=$((WAITED + 3))
done

echo ""
if [ "$ALL_HEALTHY" = true ]; then
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}  VISIONGATE ATTENDA IS FULLY ONLINE & OPERATIONAL!                   ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "  ${CYAN}Public Production URL:${NC}  ${BOLD}https://attenda.srishakthicgpa.in${NC}"
    echo -e "  ${CYAN}Local Nginx Ingress:${NC}    http://localhost:80"
    echo -e "  ${CYAN}Direct Backend API:${NC}     http://localhost:8001"
    echo -e "  ${CYAN}Swagger Docs:${NC}           http://localhost:8001/docs"
    echo -e "  ${CYAN}Health Endpoint:${NC}        https://attenda.srishakthicgpa.in/health"
    echo -e "  ${CYAN}PostgreSQL Port:${NC}        localhost:5434 (DB: attenda)"
    echo -e "${GREEN}======================================================================${NC}\n"
else
    echo -e "${RED}======================================================================${NC}"
    echo -e "${BOLD}${RED}  WARNING: Services took longer than expected to report healthy.      ${NC}"
    echo -e "  Check logs with: ./logs.sh"
    echo -e "${RED}======================================================================${NC}\n"
fi

echo -e "Tip: View live logs anytime using: ${BOLD}./logs.sh${NC}\n"
