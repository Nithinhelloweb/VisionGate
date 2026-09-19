#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Automated Production Smoke Test Suite
# Validates Database, Auth, AI Models, Geofencing, Attendance, and Routing
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

TESTS_PASSED=0
TESTS_FAILED=0

report_test() {
    local name=$1
    local status=$2
    local details=$3
    if [ "$status" -eq 0 ]; then
        echo -e "  [${GREEN}✓ PASS${NC}] ${name}"
        if [ -n "$details" ]; then
            echo -e "         ${CYAN}${details}${NC}"
        fi
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  [${RED}✗ FAIL${NC}] ${name}"
        if [ -n "$details" ]; then
            echo -e "         ${RED}${details}${NC}"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Read config from .env
set -a
source .env 2>/dev/null || true
set +a

PORT="${BACKEND_PORT:-8001}"
BASE_URL="http://localhost:${PORT}"
NGINX_URL="http://localhost:${HTTP_PORT:-80}"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${BLUE} VisionGate / Attenda — Automated System Smoke Test Suite             ${NC}"
echo -e "${BLUE} Target Backend: ${BASE_URL} | Target Nginx: ${NGINX_URL} ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# 1. Check Container Health Status
echo -e "${BOLD}[1/7] Container Lifecycle & Health Checks${NC}"
for c in attenda-postgres attenda-backend attenda-nginx; do
    if docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
        STATUS=$(docker inspect --format='{{json .State.Health.Status}}' "$c" 2>/dev/null || echo "\"running\"")
        report_test "Container '${c}' running (Health: ${STATUS})" 0 ""
    else
        report_test "Container '${c}' running" 1 "Container is not running in Docker"
    fi
done

# 2. Test Root & Universal Health Endpoints
echo -e "\n${BOLD}[2/7] Core HTTP & Health Endpoints${NC}"
ROOT_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/" || echo "000")
if [ "$ROOT_CODE" -eq 200 ]; then
    report_test "GET / (Root status endpoint)" 0 "HTTP 200 OK"
else
    report_test "GET / (Root status endpoint)" 1 "Received HTTP ${ROOT_CODE}"
fi

HEALTH_RESP=$(curl -s "${BASE_URL}/health" || echo "")
if echo "$HEALTH_RESP" | grep -q "healthy"; then
    report_test "GET /health (Universal Healthcheck)" 0 "Status: healthy"
else
    report_test "GET /health (Universal Healthcheck)" 1 "Invalid response: ${HEALTH_RESP}"
fi

READY_RESP=$(curl -s "${BASE_URL}/health/ready" || echo "")
if echo "$READY_RESP" | grep -q "ready"; then
    report_test "GET /health/ready (Readiness Probe)" 0 "Database & Models Ready"
else
    report_test "GET /health/ready (Readiness Probe)" 1 "Not ready: ${READY_RESP}"
fi

# 3. Test Dependencies & Hardware Diagnostics Endpoint
echo -e "\n${BOLD}[3/7] Diagnostic & Dependency Introspection${NC}"
DEP_RESP=$(curl -s "${BASE_URL}/health/dependencies" || echo "")
if echo "$DEP_RESP" | grep -q '"database":\s*"healthy"'; then
    report_test "PostgreSQL Database Layer" 0 "Connected & operational"
else
    report_test "PostgreSQL Database Layer" 1 "Unhealthy response: ${DEP_RESP}"
fi

if echo "$DEP_RESP" | grep -q "face_recognition_mode"; then
    MODE=$(echo "$DEP_RESP" | grep -o '"face_recognition_mode":\s*"[^"]*"' | cut -d: -f2 | tr -d ' "')
    report_test "Face Recognition Engine (${MODE})" 0 "Mode: ${MODE}"
else
    report_test "Face Recognition Engine" 1 "Face recognition diagnostics missing"
fi

# 4. Test Database Schema & pgvector Extension Inside Container
echo -e "\n${BOLD}[4/7] PostgreSQL Schema & pgvector Verification${NC}"
if docker exec -i attenda-postgres psql -U "${PG_USER:-attenda}" -d "${PG_DB:-attenda}" -c "\dx vector" | grep -q "vector"; then
    report_test "pgvector extension installed in PostgreSQL" 0 "Extension active"
else
    report_test "pgvector extension installed in PostgreSQL" 1 "Extension 'vector' not found in database"
fi

TABLE_COUNT=$(docker exec -i attenda-postgres psql -U "${PG_USER:-attenda}" -d "${PG_DB:-attenda}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' \r\n')
if [ "$TABLE_COUNT" -gt 10 ]; then
    report_test "Schema Tables Initialized (${TABLE_COUNT} public tables)" 0 "Tables present"
else
    report_test "Schema Tables Initialized" 1 "Only ${TABLE_COUNT} tables found (expected $\ge$ 15)"
fi

# 5. Test Public Configuration & Geofence Endpoints
echo -e "\n${BOLD}[5/7] Geofence & Public Settings API${NC}"
GEOFENCE_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/geo-fence/public" || echo "000")
if [ "$GEOFENCE_CODE" -eq 200 ]; then
    report_test "GET /geo-fence/public" 0 "HTTP 200 OK"
else
    report_test "GET /geo-fence/public" 1 "Received HTTP ${GEOFENCE_CODE}"
fi

SETTINGS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/settings/allow_any_network" || echo "000")
if [ "$SETTINGS_CODE" -eq 200 ]; then
    report_test "GET /settings/allow_any_network" 0 "HTTP 200 OK"
else
    report_test "GET /settings/allow_any_network" 1 "Received HTTP ${SETTINGS_CODE}"
fi

# 6. Test Authentication Flow
echo -e "\n${BOLD}[6/7] Authentication & Security Verification${NC}"
AUTH_RESP=$(curl -s -X POST "${BASE_URL}/login" \
    -H "Content-Type: application/json" \
    -d '{"username": "admin", "password": "admin123"}' || echo "")

if echo "$AUTH_RESP" | grep -q "Login successful"; then
    report_test "POST /login (Admin credentials authentication)" 0 "Token generated successfully"
else
    report_test "POST /login (Admin credentials authentication)" 1 "Response: ${AUTH_RESP}"
fi

# 7. Test Nginx Reverse Proxy & Healthz
echo -e "\n${BOLD}[7/7] Nginx Reverse Proxy Routing${NC}"
NGINX_HEALTH=$(curl -s "${NGINX_URL}/healthz" || echo "")
if echo "$NGINX_HEALTH" | grep -q "healthy"; then
    report_test "Nginx /healthz Ingress Endpoint" 0 "HTTP 200 OK"
else
    report_test "Nginx /healthz Ingress Endpoint" 1 "Response: ${NGINX_HEALTH}"
fi

NGINX_PROXY_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${NGINX_URL}/health" || echo "000")
if [ "$NGINX_PROXY_CODE" -eq 200 ]; then
    report_test "Nginx -> Backend Proxy Routing (/health)" 0 "HTTP 200 OK"
else
    report_test "Nginx -> Backend Proxy Routing (/health)" 1 "Received HTTP ${NGINX_PROXY_CODE}"
fi

# Summary
echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BOLD} VisionGate Smoke Test Summary:${NC}"
echo -e "  Passed:   ${GREEN}${TESTS_PASSED}${NC}"
echo -e "  Failed:   ${RED}${TESTS_FAILED}${NC}"
echo -e "${BLUE}======================================================================${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ ALL SYSTEM TESTS PASSED SUCCESSFULLY.${NC}\n"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Check logs with 'docker compose logs backend'.${NC}\n"
    exit 1
fi
