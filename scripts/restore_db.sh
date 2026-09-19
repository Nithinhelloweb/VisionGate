#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - PostgreSQL Database Restoration Script
# Usage: ./scripts/restore_db.sh <path_to_backup_file.sql.gz>
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

if [ -z "$1" ]; then
    echo -e "${RED}Usage: $0 <path_to_backup.sql.gz>${NC}"
    echo -e "Example: $0 ./backups/attenda_db_backup_20260901_120000.sql.gz"
    echo -e "\nAvailable backups in ./backups/:"
    ls -lh ./backups/*.sql.gz 2>/dev/null || echo "  (no backups found in ./backups/)"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "${BACKUP_FILE}" ]; then
    echo -e "${RED}Error: Backup file not found: ${BACKUP_FILE}${NC}"
    exit 1
fi

# Test archive integrity before restoring
if ! gzip -t "${BACKUP_FILE}" 2>/dev/null; then
    echo -e "${RED}Error: Backup archive '${BACKUP_FILE}' is corrupted or not a valid gzip file.${NC}"
    exit 1
fi

# Load database config from .env
set -a
source .env 2>/dev/null || true
set +a

PG_USER_NAME="${PG_USER:-attenda}"
PG_DB_NAME="${PG_DB:-attenda}"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${RED} ATTENTION: DATABASE RESTORATION                                     ${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo -e "Target Database:  ${CYAN}${PG_DB_NAME}${NC}"
echo -e "Target Container: ${CYAN}attenda-postgres${NC}"
echo -e "Source Backup:    ${CYAN}${BACKUP_FILE}${NC}"
echo -e "${YELLOW}WARNING: This operation will overwrite all existing tables and data.${NC}"
echo -e "${BLUE}======================================================================${NC}"

read -p "Type 'RESTORE' to confirm and proceed: " CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
    echo -e "${YELLOW}Restore operation aborted by user.${NC}"
    exit 0
fi

if ! docker ps --format '{{.Names}}' | grep -q "^attenda-postgres$"; then
    echo -e "${RED}ERROR: 'attenda-postgres' container is not running. Start it first with 'docker compose up -d postgres'.${NC}"
    exit 1
fi

echo -e "\n[*] Restoring database schema and records from compressed archive..."
gunzip -c "${BACKUP_FILE}" | docker exec -i attenda-postgres psql -U "${PG_USER_NAME}" -d "${PG_DB_NAME}"

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${BOLD}${GREEN}  [✓] Database restored successfully from ${BACKUP_FILE}!             ${NC}"
echo -e "${GREEN}======================================================================${NC}\n"
