#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Automated PostgreSQL Database Backup Script
# Creates timestamped, gzip-compressed database dumps with retention management
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

BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/backups}"
mkdir -p "${BACKUP_DIR}"

RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/attenda_db_backup_${TIMESTAMP}.sql.gz"

# Load database name/user from .env
set -a
source .env 2>/dev/null || true
set +a

PG_USER_NAME="${PG_USER:-attenda}"
PG_DB_NAME="${PG_DB:-attenda}"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${BLUE} VisionGate Database Backup Engine                                    ${NC}"
echo -e "${BLUE} Database: ${PG_DB_NAME} | User: ${PG_USER_NAME}${NC}"
echo -e "${BLUE}======================================================================${NC}"

if ! docker ps --format '{{.Names}}' | grep -q "^attenda-postgres$"; then
    echo -e "${RED}ERROR: 'attenda-postgres' container is not running.${NC}"
    exit 1
fi

echo -e "[*] Generating compressed SQL dump from 'attenda-postgres'..."
docker exec -t attenda-postgres pg_dump -U "${PG_USER_NAME}" -d "${PG_DB_NAME}" --clean --if-exists | gzip -9 > "${BACKUP_FILE}"

# Verify backup integrity
if [ -s "${BACKUP_FILE}" ] && gzip -t "${BACKUP_FILE}" 2>/dev/null; then
    BACKUP_SIZE=$(ls -lh "${BACKUP_FILE}" | awk '{print $5}')
    echo -e "  ${GREEN}✓${NC} Backup successfully created and verified:"
    echo -e "      File: ${CYAN}${BACKUP_FILE}${NC}"
    echo -e "      Size: ${CYAN}${BACKUP_SIZE}${NC}"
else
    echo -e "${RED}ERROR: Generated backup file is empty or corrupted.${NC}"
    rm -f "${BACKUP_FILE}"
    exit 1
fi

# Clean up older backups based on retention policy
echo -e "\n[*] Applying retention policy (retaining last ${RETENTION_DAYS} days of backups)..."
find "${BACKUP_DIR}" -name "attenda_db_backup_*.sql.gz" -type f -mtime "+${RETENTION_DAYS}" -exec rm -v {} \; 2>/dev/null || true

TOTAL_BACKUPS=$(ls -1 "${BACKUP_DIR}"/attenda_db_backup_*.sql.gz 2>/dev/null | wc -l || echo "0")
echo -e "  ${GREEN}✓${NC} Total backups retained: ${TOTAL_BACKUPS}"
echo -e "${BLUE}======================================================================${NC}\n"
