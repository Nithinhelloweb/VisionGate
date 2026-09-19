#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Master Native Linux Deployment Orchestrator
# Executes full bare-metal setup for PostgreSQL 16, Python 3.12 Backend with GPU,
# Nginx Reverse Proxy, and Cloudflare Tunnel with zero Docker containers.
# Usage: sudo bash setup_all.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run setup_all.sh with sudo or as root.${NC}"
    echo -e "Usage: sudo bash $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  VisionGate / Attenda - Full Native Linux Server Setup (No Docker)           ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

# Step 1: System Prerequisites
echo -e "\n${CYAN}>>> STEP 1: Installing System Prerequisites (Postgres 16, Python 3.12, Nginx, Cloudflared)...${NC}"
bash 01_prerequisites.sh

# Step 2: Database Initialization
echo -e "\n${CYAN}>>> STEP 2: Configuring Database & Schema...${NC}"
bash 02_setup_database.sh

# Step 3: Backend Python Environment & Dependencies
echo -e "\n${CYAN}>>> STEP 3: Setting Up Backend Environment & GPU Acceleration...${NC}"
# Run step 3 as the non-root invoking user so virtualenv belongs to them
ACTUAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "techpark-2")}"
sudo -u "${ACTUAL_USER}" bash 03_setup_backend.sh

# Step 4: Backend Systemd Service
echo -e "\n${CYAN}>>> STEP 4: Configuring and Starting Backend Systemd Service...${NC}"
bash setup_backend_service.sh

# Step 5: Nginx Reverse Proxy
echo -e "\n${CYAN}>>> STEP 5: Setting Up Nginx Reverse Proxy (:80 -> :8001)...${NC}"
bash 04_setup_nginx.sh

# Step 6: Cloudflare Tunnel
echo -e "\n${CYAN}>>> STEP 6: Setting Up Cloudflare Tunnel...${NC}"
bash 05_setup_cloudflared.sh

# Step 7: System Diagnostics
echo -e "\n${CYAN}>>> STEP 7: Running System Diagnostic Verification...${NC}"
sleep 3
bash doctor_linux.sh

echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${GREEN}  DEPLOYMENT COMPLETED SUCCESSFULLY WITH 100% ACCURACY!                       ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Your application is now running live natively on the Linux server:"
echo -e "  - Backend API:       http://127.0.0.1:8001/docs"
echo -e "  - Nginx Proxy:       http://127.0.0.1:80"
echo -e "  - Public Tunnel:     https://attenda.srishakthicgpa.in"
echo -e "  - Systemd Service:   sudo systemctl status attenda-backend"
echo -e "  - Tunnel Service:    sudo systemctl status cloudflared"
