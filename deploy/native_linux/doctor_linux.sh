#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Native Linux System Diagnostic & Doctor
# Verifies Database, Backend, GPU (RTX 5070), Nginx, and Cloudflare Tunnel.
# Usage: bash doctor_linux.sh
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  VisionGate / Attenda - Native Linux Diagnostic Health Check               ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

TOTAL_CHECKS=0
PASSED_CHECKS=0

report_pass() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    echo -e "  [${GREEN}PASS${NC}] $1"
}

report_fail() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -e "  [${RED}FAIL${NC}] $1"
    if [ -n "${2:-}" ]; then
        echo -e "         ${YELLOW}Reason: $2${NC}"
    fi
}

report_warn() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -e "  [${YELLOW}WARN${NC}] $1"
    if [ -n "${2:-}" ]; then
        echo -e "         ${YELLOW}Note: $2${NC}"
    fi
}

# 1. System Resources
echo -e "\n${CYAN}1. System Hardware & Resources${NC}"
OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d '=' -f2 | tr -d '"')
report_pass "Operating System: ${OS_NAME}"

FREE_MEM_MB=$(free -m | awk '/^Mem:/{print $7}')
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [ "${FREE_MEM_MB}" -gt 1024 ]; then
    report_pass "Available RAM: ${FREE_MEM_MB} MB / ${TOTAL_MEM_MB} MB"
else
    report_warn "Available RAM is low: ${FREE_MEM_MB} MB / ${TOTAL_MEM_MB} MB"
fi

DISK_AVAIL_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
if [ "${DISK_AVAIL_GB}" -gt 10 ]; then
    report_pass "Root Disk Space Available: ${DISK_AVAIL_GB} GB"
else
    report_warn "Low root disk space: ${DISK_AVAIL_GB} GB"
fi

# 2. NVIDIA GPU & Hardware Acceleration
echo -e "\n${CYAN}2. NVIDIA GPU & Hardware Acceleration (RTX 5070)${NC}"
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
    DRV_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
    report_pass "NVIDIA GPU Detected: ${GPU_NAME} (Driver: ${DRV_VER})"
else
    report_warn "nvidia-smi not in PATH. System will run in high-performance CPU mode."
fi

# 3. PostgreSQL Database
echo -e "\n${CYAN}3. Native PostgreSQL 16 Service & Database${NC}"
if systemctl is-active --quiet postgresql; then
    report_pass "PostgreSQL system service is running"
else
    report_fail "PostgreSQL service is not running" "Run: sudo systemctl start postgresql"
fi

DB_USER="attenda"
DB_PASS="attenda_password"
DB_NAME="attenda"

if PGPASSWORD="${DB_PASS}" psql -h 127.0.0.1 -p 5432 -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" &>/dev/null; then
    report_pass "Database connection to '${DB_NAME}' as user '${DB_USER}' succeeded"
    
    TABLE_COUNT=$(PGPASSWORD="${DB_PASS}" psql -h 127.0.0.1 -p 5432 -U "${DB_USER}" -d "${DB_NAME}" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")
    report_pass "Database tables verified: ${TABLE_COUNT} tables active"

    # Check pgvector
    HAS_VECTOR=$(PGPASSWORD="${DB_PASS}" psql -h 127.0.0.1 -p 5432 -U "${DB_USER}" -d "${DB_NAME}" -tAc "SELECT 1 FROM pg_extension WHERE extname='vector';" || true)
    if [ "${HAS_VECTOR}" = "1" ]; then
        report_pass "pgvector extension is installed and active"
    else
        report_warn "pgvector extension not detected. Face embeddings will use fallback storage."
    fi
else
    report_fail "Database connection failed" "Check PostgreSQL user credentials and pg_hba.conf"
fi

# 4. FastAPI Backend
echo -e "\n${CYAN}4. Backend Application Server (:8001)${NC}"
BACKEND_HEALTH=$(curl -sf -m 5 http://127.0.0.1:8001/health 2>/dev/null || true)
if [ -n "${BACKEND_HEALTH}" ]; then
    report_pass "Backend /health responded: ${BACKEND_HEALTH}"
else
    if systemctl is-active --quiet attenda-backend; then
        report_warn "attenda-backend service is active but port 8001 not responding yet (may still be warming face models)"
    else
        report_fail "Backend is not responding on http://127.0.0.1:8001" "Check: sudo systemctl status attenda-backend"
    fi
fi

# 5. Nginx Reverse Proxy
echo -e "\n${CYAN}5. Nginx Reverse Proxy (:80)${NC}"
if systemctl is-active --quiet nginx; then
    report_pass "Nginx service is running"
else
    report_fail "Nginx service is not running" "Run: sudo systemctl start nginx"
fi

NGINX_RESP=$(curl -sf -m 5 http://127.0.0.1/healthz 2>/dev/null || true)
if [ "${NGINX_RESP}" = "healthy" ]; then
    report_pass "Nginx reverse proxy health check passed (:80 -> healthy)"
else
    report_warn "Nginx port 80 check did not return healthy"
fi

# 6. Cloudflare Tunnel
echo -e "\n${CYAN}6. Cloudflare Tunnel (:cloudflared)${NC}"
if systemctl is-active --quiet cloudflared; then
    report_pass "cloudflared systemd service is active and running"
else
    report_warn "cloudflared service is not currently active" "Check: sudo systemctl status cloudflared"
fi

# Test public domain resolution
if command -v host &>/dev/null || command -v nslookup &>/dev/null; then
    DOMAIN_IP=$(getent hosts attenda.srishakthicgpa.in | awk '{print $1}' | head -n 1 || true)
    if [ -n "${DOMAIN_IP}" ]; then
        report_pass "Domain attenda.srishakthicgpa.in resolves to: ${DOMAIN_IP}"
    else
        report_warn "Could not resolve attenda.srishakthicgpa.in via DNS"
    fi
fi

echo -e "\n${BLUE}==============================================================================${NC}"
echo -e "  Health Check Summary: ${GREEN}${PASSED_CHECKS}${NC} / ${TOTAL_CHECKS} Checks Passed"
echo -e "${BLUE}==============================================================================${NC}"
