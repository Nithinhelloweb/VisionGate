#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Linux Native Prerequisites Installer
# Target Environment: Ubuntu 24.04.4 LTS (Noble) / Intel Ultra 9 285K / RTX 5070
# Usage: sudo bash 01_prerequisites.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  VisionGate / Attenda - Native Linux System Prerequisites Installer         ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run with sudo or as root.${NC}"
    echo -e "Usage: sudo bash $0"
    exit 1
fi

# 1. System Identification
echo -e "\n${CYAN}[1/6] Verifying System Architecture & OS...${NC}"
OS_INFO=$(cat /etc/os-release | grep -E "^(NAME|VERSION)=" || true)
echo -e "${GREEN}Detected OS:${NC}\n$OS_INFO"

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo -e "${RED}[WARNING] Unexpected architecture: $ARCH (expected x86_64).${NC}"
else
    echo -e "${GREEN}[✓] Architecture verified: $ARCH${NC}"
fi

# 2. Update Apt Repositories
echo -e "\n${CYAN}[2/6] Updating APT package repositories...${NC}"
apt-get update -y

# 3. Install Core System Tools & Compilers
echo -e "\n${CYAN}[3/6] Installing build tools, Python 3.12 environment, and image libraries...${NC}"
apt-get install -y \
    software-properties-common \
    curl \
    wget \
    git \
    jq \
    ufw \
    build-essential \
    python3 \
    python3-venv \
    python3-dev \
    python3-pip \
    libpq-dev \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev

echo -e "${GREEN}[✓] Python and runtime build tools installed successfully.${NC}"

# 4. Install PostgreSQL 16 & pgvector
echo -e "\n${CYAN}[4/6] Installing PostgreSQL 16, contrib extensions, and pgvector...${NC}"
# Enable universe/multiverse if not enabled
add-apt-repository -y universe || true

# Try installing postgresql-16-pgvector directly from Ubuntu 24.04 repos
if apt-cache show postgresql-16-pgvector &>/dev/null; then
    apt-get install -y postgresql postgresql-contrib postgresql-16-pgvector
else
    # Configure official PostgreSQL PGDG repo if pgvector is not in default pool
    echo -e "${YELLOW}Adding official PostgreSQL apt repository for pgvector...${NC}"
    install -d /etc/apt/keyrings
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg --yes
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    apt-get update -y
    apt-get install -y postgresql-16 postgresql-contrib-16 postgresql-16-pgvector
fi

systemctl enable --now postgresql
echo -e "${GREEN}[✓] PostgreSQL 16 with pgvector installed and running.${NC}"

# 5. Install Nginx
echo -e "\n${CYAN}[5/6] Installing Nginx Reverse Proxy...${NC}"
apt-get install -y nginx
systemctl enable --now nginx
echo -e "${GREEN}[✓] Nginx installed and running.${NC}"

# 6. Install Cloudflare Tunnel CLI (cloudflared)
echo -e "\n${CYAN}[6/6] Installing Cloudflare Tunnel (cloudflared)...${NC}"
if command -v cloudflared &>/dev/null; then
    CF_VER=$(cloudflared --version || true)
    echo -e "${GREEN}[✓] cloudflared is already installed: $CF_VER${NC}"
else
    echo "Downloading official cloudflared package for x86_64 Linux..."
    wget -q -O /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared.deb || apt-get install -f -y
    rm -f /tmp/cloudflared.deb
    CF_VER=$(cloudflared --version || true)
    echo -e "${GREEN}[✓] Installed cloudflared: $CF_VER${NC}"
fi

# 7. Hardware & GPU Status Report
echo -e "\n${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  Hardware & Acceleration Summary                                            ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

if command -v nvidia-smi &>/dev/null; then
    echo -e "${GREEN}[✓] NVIDIA Driver detected!${NC}"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || nvidia-smi
else
    echo -e "${YELLOW}[!] nvidia-smi not detected in PATH. If using RTX 5070, verify driver installation.${NC}"
fi

echo -e "\n${GREEN}[SUCCESS] All prerequisites installed! Proceed to run: bash 02_setup_database.sh${NC}"
