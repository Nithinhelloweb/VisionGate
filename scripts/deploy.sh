#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Automated One-Command Production Deployer
# Target: Any Compatible Linux Server (x86_64 / aarch64) with NVIDIA GPU / CPU
# ==============================================================================
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${BLUE} VisionGate / Attenda — Production Stack Deployment Engine            ${NC}"
echo -e "${BLUE} Date: $(date) | Host: $(hostname)${NC}"
echo -e "${BLUE}======================================================================${NC}"

# 1. Run Pre-flight System Doctor
echo -e "\n${BOLD}${YELLOW}[Step 1/6] Running Pre-Flight System Diagnostics...${NC}"
if [ -f "scripts/doctor.sh" ]; then
    bash scripts/doctor.sh || {
        echo -e "${RED}Doctor checks failed. Resolve the prerequisite issues above before deploying.${NC}"
        exit 1
    }
fi

# Detect Compose Command
if docker compose version &> /dev/null; then
    COMPOSE_BASE="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_BASE="docker-compose"
else
    echo -e "${RED}Docker Compose is not available.${NC}"
    exit 1
fi

# 2. Environment Configuration
echo -e "\n${BOLD}${YELLOW}[Step 2/6] Configuring Environment Secrets...${NC}"
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo -e "  ${GREEN}✓${NC} Created .env from .env.example"
    else
        echo -e "  ${RED}Error: .env and .env.example not found.${NC}"
        exit 1
    fi
else
    echo -e "  ${GREEN}✓${NC} Existing .env configuration loaded."
fi

# Read environment variables
set -a
source .env 2>/dev/null || true
set +a

# Detect GPU capability
USE_GPU=0
echo -e "\n${BOLD}[*] Detecting Hardware Acceleration Mode...${NC}"
if command -v nvidia-smi &> /dev/null; then
    if docker run --rm --gpus all nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi &> /dev/null; then
        USE_GPU=1
        echo -e "  ${GREEN}✓ NVIDIA GPU Container Passthrough is OPERATIONAL.${NC}"
    else
        echo -e "  ${YELLOW}! GPU detected on host but container passthrough unavailable or driver too old for full passthrough.${NC}"
        echo -e "  ${CYAN}-> Deploying in robust CPU Execution mode (InsightFace operates fully on CPU).${NC}"
    fi
else
    echo -e "  ${CYAN}-> Deploying in CPU Execution mode (CPU fallback active).${NC}"
fi

if [ "$USE_GPU" -eq 1 ] && [ -f "docker-compose.gpu.yml" ]; then
    COMPOSE_CMD="${COMPOSE_BASE} -f docker-compose.yml -f docker-compose.gpu.yml"
else
    COMPOSE_CMD="${COMPOSE_BASE} -f docker-compose.yml"
fi

# 3. Build Production Container Images
echo -e "\n${BOLD}${YELLOW}[Step 3/6] Building Production Container Images...${NC}"
echo -e "  -> Pre-fetching base image (with automatic retries for slow connections)..."

PULL_SUCCESS=0
for attempt in 1 2 3; do
    echo -e "     [Attempt $attempt/3] Pulling nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04..."
    if docker pull nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04; then
        PULL_SUCCESS=1
        echo -e "     ${GREEN}✓${NC} Base image successfully cached."
        break
    else
        echo -e "     ${YELLOW}! Network timeout during layer download. Retrying in 3 seconds...${NC}"
        sleep 3
    fi
done

echo -e "  -> Building VisionGate backend container with ONNX & InsightFace..."
BUILD_SUCCESS=0
for b_attempt in 1 2 3; do
    if ${COMPOSE_CMD} build backend; then
        BUILD_SUCCESS=1
        break
    else
        echo -e "  ${YELLOW}! Build attempt $b_attempt failed. Retrying in 5 seconds...${NC}"
        sleep 5
    fi
done

if [ "$BUILD_SUCCESS" -ne 1 ]; then
    echo -e "${RED}ERROR: Container build failed after 3 attempts.${NC}"
    echo -e "${YELLOW}Tip: If your internet connection has packet loss, check your network or try again.${NC}"
    exit 1
fi

# 4. Start Database & Infrastructure
echo -e "\n${BOLD}${YELLOW}[Step 4/6] Initializing Database & Core Services...${NC}"
${COMPOSE_CMD} up -d postgres

echo "Waiting for PostgreSQL database container to become healthy..."
MAX_PG_WAIT=60
WAITED=0
PG_HEALTHY=0

while [ "$WAITED" -lt "$MAX_PG_WAIT" ]; do
    STATUS=$(docker inspect --format='{{json .State.Health.Status}}' attenda-postgres 2>/dev/null || echo "\"starting\"")
    if [ "$STATUS" == "\"healthy\"" ]; then
        PG_HEALTHY=1
        echo -e "  ${GREEN}✓${NC} PostgreSQL container is HEALTHY and accepting connections."
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ "$PG_HEALTHY" -ne 1 ]; then
    echo -e "${RED}PostgreSQL failed to become healthy within ${MAX_PG_WAIT}s.${NC}"
    ${COMPOSE_CMD} logs postgres
    exit 1
fi

# 5. Start Backend, Nginx, and Optional Cloudflare Tunnel
echo -e "\n${BOLD}${YELLOW}[Step 5/6] Starting VisionGate Application Services...${NC}"
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN}" ]; then
    echo -e "  ${CYAN}-> Cloudflare Tunnel Token detected. Launching full stack with Cloudflare tunnel...${NC}"
    ${COMPOSE_CMD} --profile tunnel up -d
else
    echo -e "  -> Launching standard stack (PostgreSQL, Backend, Nginx)..."
    ${COMPOSE_CMD} up -d
fi

# 6. Service Health Verification & Operational Readiness
echo -e "\n${BOLD}${YELLOW}[Step 6/6] Verifying Service Health & Readiness...${NC}"
echo "Waiting for VisionGate backend API to report READY..."

MAX_WAIT=90
WAITED=0
BACKEND_OK=0

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
    BACKEND_STATUS=$(docker inspect --format='{{json .State.Health.Status}}' attenda-backend 2>/dev/null || echo "\"starting\"")
    NGINX_STATUS=$(docker inspect --format='{{json .State.Health.Status}}' attenda-nginx 2>/dev/null || echo "\"starting\"")

    if [ "$BACKEND_STATUS" == "\"healthy\"" ] && [ "$NGINX_STATUS" == "\"healthy\"" ]; then
        BACKEND_OK=1
        break
    fi

    echo -e "  -> Waiting for services: Backend (${BACKEND_STATUS}), Nginx (${NGINX_STATUS}) [${WAITED}s/${MAX_WAIT}s]"
    sleep 3
    WAITED=$((WAITED + 3))
done

echo ""
if [ "$BACKEND_OK" -eq 1 ]; then
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    BACKEND_PORT_VAL="${BACKEND_PORT:-8001}"
    HTTP_PORT_VAL="${HTTP_PORT:-80}"
    
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}  VISIONGATE SYSTEM DEPLOYED SUCCESSFULLY!                            ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "  ${CYAN}Public Nginx Entrypoint:${NC} http://${HOST_IP}:${HTTP_PORT_VAL}"
    echo -e "  ${CYAN}Direct Backend API:${NC}      http://${HOST_IP}:${BACKEND_PORT_VAL}"
    echo -e "  ${CYAN}API Documentation:${NC}       http://${HOST_IP}:${BACKEND_PORT_VAL}/docs"
    echo -e "  ${CYAN}Health Check:${NC}            http://${HOST_IP}:${BACKEND_PORT_VAL}/health"
    echo -e "  ${CYAN}Dependency Status:${NC}       http://${HOST_IP}:${BACKEND_PORT_VAL}/health/dependencies"
    echo -e "  ${CYAN}PostgreSQL Database:${NC}     ${HOST_IP}:${PG_HOST_PORT:-5434} (DB: ${PG_DB:-attenda})"
    
    if [ -n "${CLOUDFLARE_TUNNEL_TOKEN}" ]; then
        echo -e "  ${CYAN}Cloudflare Zero-Trust:${NC}   Enabled & Active via tunnel profile"
    fi
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "Operational Commands:"
    echo -e "  Run Smoke Tests:         ${YELLOW}bash scripts/test.sh${NC}"
    echo -e "  Verify GPU Acceleration: ${YELLOW}bash scripts/verify_gpu.sh${NC}"
    echo -e "  View Live Backend Logs:  ${YELLOW}${COMPOSE_CMD} logs -f backend${NC}"
    echo -e "  Backup Database:         ${YELLOW}bash scripts/backup_db.sh${NC}"
    echo -e "  Stop Stack Safely:       ${YELLOW}bash scripts/stop.sh${NC}"
    echo -e "${GREEN}======================================================================${NC}\n"
else
    echo -e "${RED}Deployment timed out waiting for backend services to become healthy.${NC}"
    echo -e "Inspect container logs for diagnosis:"
    echo -e "  ${YELLOW}${COMPOSE_CMD} logs backend${NC}"
    echo -e "  ${YELLOW}${COMPOSE_CMD} logs postgres${NC}"
    echo -e "  ${YELLOW}${COMPOSE_CMD} logs nginx${NC}"
    exit 1
fi
