#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Zero-Data-Loss System Update Script
# Pre-backups database, pulls git updates, rebuilds containers, runs migrations
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
echo -e "${BOLD}${BLUE} VisionGate / Attenda — Production System Update Engine               ${NC}"
echo -e "${BLUE} Date: $(date)${NC}"
echo -e "${BLUE}======================================================================${NC}"

# Detect Compose Command
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

# Step 1: Pre-Update Backup
echo -e "\n${BOLD}${YELLOW}[1/5] Creating Pre-Update PostgreSQL Safety Backup...${NC}"
if [ -f "scripts/backup_db.sh" ]; then
    bash scripts/backup_db.sh || {
        echo -e "${YELLOW}Warning: Pre-update backup could not be completed (database container may be stopped). Continuing...${NC}"
    }
fi

# Step 2: Git Pull Updates
echo -e "\n${BOLD}${YELLOW}[2/5] Pulling Latest Repository Updates from Git...${NC}"
if [ -d ".git" ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    echo -e "  -> Pulling updates on branch: ${CYAN}${CURRENT_BRANCH}${NC}"
    git pull origin "${CURRENT_BRANCH}" || {
        echo -e "${RED}Git pull failed. Please check your network connection or local git changes.${NC}"
        exit 1
    }
else
    echo -e "  ${YELLOW}! Not a git repository. Skipping git pull.${NC}"
fi

# Step 3: Rebuild Backend Image
echo -e "\n${BOLD}${YELLOW}[3/5] Rebuilding Production Container Images...${NC}"
${COMPOSE_CMD} build backend

# Step 4: Restart Services
echo -e "\n${BOLD}${YELLOW}[4/5] Restarting Services & Running Migrations...${NC}"
set -a
source .env 2>/dev/null || true
set +a

if [ -n "${CLOUDFLARE_TUNNEL_TOKEN}" ]; then
    ${COMPOSE_CMD} --profile tunnel up -d
else
    ${COMPOSE_CMD} up -d
fi

# Step 5: Verification
echo -e "\n${BOLD}${YELLOW}[5/5] Verifying Updated System Health...${NC}"
sleep 5
if [ -f "scripts/test.sh" ]; then
    bash scripts/test.sh
else
    echo -e "Checking container status:"
    ${COMPOSE_CMD} ps
fi

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${BOLD}${GREEN}  [✓] VisionGate Update Process Completed Successfully!               ${NC}"
echo -e "${GREEN}======================================================================${NC}\n"
