#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Safe Container Shutdown Script
# Gracefully stops all services while strictly PRESERVING persistent volumes
# ==============================================================================
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${BLUE} VisionGate / Attenda — Safe Graceful Shutdown                        ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# Detect Compose Command
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

echo -e "${YELLOW}Stopping all VisionGate containers (preserving database and model storage)...${NC}"
${COMPOSE_CMD} --profile tunnel stop

echo -e "${YELLOW}Removing stopped containers...${NC}"
${COMPOSE_CMD} --profile tunnel down --remove-orphans

echo -e "${GREEN}======================================================================${NC}"
echo -e "${BOLD}${GREEN}  [✓] All VisionGate services have stopped safely.                    ${NC}"
echo -e "${BOLD}${GREEN}  Persistent volumes (Postgres DB, InsightFace Models) are intact.    ${NC}"
echo -e "${GREEN}======================================================================${NC}\n"
