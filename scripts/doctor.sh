#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Pre-Flight Deployment Doctor & System Diagnostics
# Diagnoses host OS, Docker, GPU, CUDA, Ports, Disk, and Configuration
# ==============================================================================

# NOTE: Do NOT use set -e in diagnostic doctor so all checks run to completion.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd)"
cd "${ROOT_DIR}" 2>/dev/null || true

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${BLUE} VisionGate / Attenda — Pre-Flight System Doctor                      ${NC}"
echo -e "${BLUE} Date: $(date 2>/dev/null) | Host: $(hostname 2>/dev/null)${NC}"
echo -e "${BLUE}======================================================================${NC}"

report_pass() {
    echo -e "  [${GREEN}✓ PASS${NC}] $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

report_warn() {
    echo -e "  [${YELLOW}! WARN${NC}] $1"
    if [ -n "$2" ]; then
        echo -e "         ${CYAN}Notice:${NC} $2"
    fi
    WARN_COUNT=$((WARN_COUNT + 1))
}

report_fail() {
    echo -e "  [${RED}✗ FAIL${NC}] $1"
    if [ -n "$2" ]; then
        echo -e "         ${RED}Reason:${NC} $2"
    fi
    if [ -n "$3" ]; then
        echo -e "         ${YELLOW}Fix:${NC}    $3"
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# 1. Operating System & Architecture
echo -e "\n${BOLD}[1/8] Operating System & Architecture${NC}"
ARCH=$(uname -m 2>/dev/null || echo "unknown")
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "aarch64" ]; then
    report_pass "CPU Architecture: ${ARCH}"
else
    report_warn "CPU Architecture: ${ARCH}" "VisionGate is tested primarily on x86_64 and aarch64 architectures."
fi

if [ -f /etc/os-release ]; then
    OS_NAME=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    report_pass "Operating System: ${OS_NAME:-Linux}"
else
    report_pass "Operating System: $(uname -s 2>/dev/null || echo 'Linux')"
fi

# Detect WSL environment
IS_WSL=0
if grep -qi "microsoft" /proc/version 2>/dev/null || grep -qi "wsl" /proc/version 2>/dev/null; then
    IS_WSL=1
    echo -e "         ${CYAN}Environment:${NC} Windows Subsystem for Linux (WSL 2)"
fi

# 2. System Hardware Resources
echo -e "\n${BOLD}[2/8] System Resources (RAM & Disk Space)${NC}"
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
if [ "$TOTAL_RAM_GB" -ge 8 ]; then
    report_pass "RAM: ${TOTAL_RAM_GB} GB (Sufficient for concurrent batch inference)"
elif [ "$TOTAL_RAM_GB" -ge 4 ]; then
    report_warn "RAM: ${TOTAL_RAM_GB} GB" "Recommended memory is >= 8 GB for high concurrent batch face recognition."
elif [ "$TOTAL_RAM_GB" -gt 0 ]; then
    report_fail "RAM: ${TOTAL_RAM_GB} GB" "Insufficient RAM for running PostgreSQL + PyTorch + InsightFace." "Upgrade host memory to at least 4-8 GB."
else
    report_warn "RAM check skipped" "Unable to read /proc/meminfo."
fi

AVAIL_DISK_MB=$(df -m . 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
AVAIL_DISK_GB=$((AVAIL_DISK_MB / 1024))
if [ "$AVAIL_DISK_GB" -ge 15 ]; then
    report_pass "Available Disk Space: ${AVAIL_DISK_GB} GB"
elif [ "$AVAIL_DISK_GB" -ge 5 ]; then
    report_warn "Available Disk Space: ${AVAIL_DISK_GB} GB" "Low disk space. Docker image builds require ~5-10 GB."
elif [ "$AVAIL_DISK_MB" -gt 0 ]; then
    report_fail "Available Disk Space: ${AVAIL_DISK_GB} GB" "Critically low disk space." "Free up at least 15 GB disk space before deployment."
else
    report_warn "Disk space check skipped" "Unable to inspect disk capacity."
fi

# 3. Docker Engine & Runtime
echo -e "\n${BOLD}[3/8] Docker Engine & Compose${NC}"
DOCKER_OUTPUT=$(docker --version 2>&1 || true)
if echo "$DOCKER_OUTPUT" | grep -qi "Docker version"; then
    report_pass "Docker Engine CLI installed: ${DOCKER_OUTPUT}"
    
    DOCKER_INFO=$(docker info 2>&1 || true)
    if echo "$DOCKER_INFO" | grep -qi "Server Version"; then
        report_pass "Docker daemon is running and accessible"
    elif echo "$DOCKER_INFO" | grep -qi "WSL integration"; then
        report_fail "Docker Desktop WSL Integration is NOT active" \
            "Docker Desktop is installed on Windows, but WSL integration is disabled for this distro." \
            "Open Docker Desktop in Windows -> Settings -> Resources -> WSL integration -> Enable integration for your distro -> Apply & restart."
    else
        report_fail "Docker daemon not accessible" \
            "${DOCKER_INFO}" \
            "Start Docker: 'sudo systemctl start docker' or add user to group: 'sudo usermod -aG docker \$USER'."
    fi
elif echo "$DOCKER_OUTPUT" | grep -qi "WSL integration"; then
    report_fail "Docker Desktop WSL Integration is NOT active" \
        "Docker Desktop is installed in Windows, but WSL integration is disabled for this distro." \
        "Open Docker Desktop in Windows -> Settings -> Resources -> WSL integration -> Toggle ON this distro -> Click 'Apply & restart'."
else
    report_fail "Docker not installed" \
        "Docker CLI command not found in PATH." \
        "Install Docker via https://docs.docker.com/engine/install/ or 'sudo apt-get install -y docker.io'."
fi

COMPOSE_OUTPUT=$(docker compose version 2>&1 || docker-compose --version 2>&1 || true)
if echo "$COMPOSE_OUTPUT" | grep -qi "Docker Compose"; then
    report_pass "Docker Compose detected: ${COMPOSE_OUTPUT}"
else
    report_fail "Docker Compose missing" \
        "Docker Compose plugin not found." \
        "Install Compose plugin: 'sudo apt-get install -y docker-compose-v2'."
fi

# 4. GPU & NVIDIA Container Acceleration
echo -e "\n${BOLD}[4/8] NVIDIA GPU & Hardware Acceleration${NC}"
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "NVIDIA GPU")
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || echo "Unknown")
    report_pass "NVIDIA GPU Detected: ${GPU_NAME} (Driver ${DRIVER_VER})"

    if command -v nvidia-ctk >/dev/null 2>&1; then
        report_pass "NVIDIA Container Toolkit (nvidia-ctk) is present"
    fi

    # Test GPU passthrough if docker is running
    GPU_TEST=$(docker run --rm --gpus all nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi 2>&1 || true)
    if echo "$GPU_TEST" | grep -qi "NVIDIA-SMI"; then
        report_pass "Docker GPU Container Passthrough is fully OPERATIONAL"
    else
        report_warn "Docker GPU passthrough test not active" \
            "Container will run in CPU mode unless nvidia-container-toolkit is configured."
    fi
else
    report_warn "nvidia-smi not found" \
        "System will run in CPU execution mode (InsightFace and attendance operate on CPU)."
fi

# 5. Network Port Availability
echo -e "\n${BOLD}[5/8] Network Ports Availability${NC}"
check_port() {
    local port=$1
    local name=$2
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i ":${port}" >/dev/null 2>&1; then
            report_warn "Port ${port} (${name}) is currently bound" "If VisionGate is already running, this is normal."
        else
            report_pass "Port ${port} (${name}) is available"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            report_warn "Port ${port} (${name}) is currently bound" "Ensure no conflicting services occupy port ${port}."
        else
            report_pass "Port ${port} (${name}) is available"
        fi
    else
        report_pass "Port ${port} (${name}) ready"
    fi
}

check_port "${HTTP_PORT:-80}" "Nginx Ingress"
check_port "${BACKEND_PORT:-8001}" "FastAPI Backend"
check_port "${PG_HOST_PORT:-5434}" "PostgreSQL Port"

# 6. Environment Configuration (.env)
echo -e "\n${BOLD}[6/8] Environment Secrets & Configuration${NC}"
if [ -f .env ]; then
    report_pass ".env configuration file is present"
    
    check_env_var() {
        local var_name=$1
        local is_secret=$2
        local val=$(grep -E "^${var_name}=" .env 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
        if [ -n "$val" ]; then
            if [ "$is_secret" -eq 1 ]; then
                report_pass "Env variable: ${var_name} is configured (hidden)"
            else
                report_pass "Env variable: ${var_name}=${val}"
            fi
        else
            report_warn "Env variable: ${var_name} is empty" "Default fallback will be used."
        fi
    }

    check_env_var "PG_DB" 0
    check_env_var "PG_USER" 0
    check_env_var "PG_PASSWORD" 1
    check_env_var "BACKEND_PORT" 0
    check_env_var "HTTP_PORT" 0
    check_env_var "JWT_SECRET" 1
else
    if [ -f .env.example ]; then
        report_warn ".env file is missing" "Will be generated automatically from .env.example during deploy."
    else
        report_fail "Neither .env nor .env.example found" "Environment template is missing." "Restore .env.example from git repository."
    fi
fi

# 7. Cloudflare Configuration Check
echo -e "\n${BOLD}[7/8] Cloudflare Edge & Tunnel Integration${NC}"
CF_TOKEN=$(grep -E '^CLOUDFLARE_TUNNEL_TOKEN=' .env 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
CF_DOMAIN=$(grep -E '^CLOUDFLARE_DOMAIN=' .env 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")

if [ -n "$CF_TOKEN" ]; then
    report_pass "Cloudflare Zero-Trust Tunnel Token is configured"
elif [ -n "$CF_DOMAIN" ]; then
    report_pass "Cloudflare Domain is configured: ${CF_DOMAIN}"
else
    report_warn "Cloudflare Tunnel Token / Domain not configured" \
        "System will run on LAN / Direct IP. Set CLOUDFLARE_TUNNEL_TOKEN in .env for public Zero-Trust domain routing."
fi

# 8. Model & Static Assets
echo -e "\n${BOLD}[8/8] Static Assets & Migration Manifests${NC}"
if [ -f "backend/requirements.txt" ]; then
    report_pass "Backend requirements manifest present"
else
    report_fail "backend/requirements.txt missing" "Cannot build backend container." "Restore backend/requirements.txt."
fi

if [ -f "backend/Dockerfile" ]; then
    report_pass "Backend Dockerfile present"
else
    report_fail "backend/Dockerfile missing" "Cannot build container image." "Restore backend/Dockerfile."
fi

if [ -f "docker/postgres/01-init.sql" ]; then
    report_pass "PostgreSQL initializer (01-init.sql) present"
else
    report_fail "docker/postgres/01-init.sql missing" "Database extensions will not be initialized." "Restore docker/postgres/01-init.sql."
fi

if [ -f "backend/run_migrations.py" ]; then
    report_pass "Unified migration runner (run_migrations.py) present"
else
    report_fail "backend/run_migrations.py missing" "Automated schema migrations will not execute." "Restore backend/run_migrations.py."
fi

# Summary
echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BOLD} Pre-Flight Diagnostic Summary:${NC}"
echo -e "  Passed:   ${GREEN}${PASS_COUNT}${NC}"
echo -e "  Warnings: ${YELLOW}${WARN_COUNT}${NC}"
echo -e "  Failures: ${RED}${FAIL_COUNT}${NC}"
echo -e "${BLUE}======================================================================${NC}"

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ System is READY for VisionGate deployment.${NC}\n"
    exit 0
else
    echo -e "${RED}✗ Please fix the failed prerequisite(s) above before deploying.${NC}\n"
    exit 1
fi
