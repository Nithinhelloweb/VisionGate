# VisionGate Database Backup & Disaster Recovery Guide

## 1. Backup Architecture

VisionGate includes an automated, gzip-compressed backup system for the PostgreSQL database (`pgvector/pgvector:pg16`). Backups contain all schema structures, table records, and vector embeddings.

---

## 2. Creating Manual Backups

To trigger an on-demand timestamped database dump:

```bash
bash scripts/backup_db.sh
```

- **Output Location**: `./backups/attenda_db_backup_YYYYMMDD_HHMMSS.sql.gz`
- **Integrity Check**: The script automatically runs `gzip -t` to verify archive integrity.
- **Retention**: Automatically purges backups older than 14 days (configurable via `BACKUP_RETENTION_DAYS` in `.env`).

---

## 3. Restoring from a Backup

To restore a database backup into a running `attenda-postgres` container:

```bash
bash scripts/restore_db.sh ./backups/attenda_db_backup_20260901_120000.sql.gz
```

The restore script:
1. Validates the archive integrity.
2. Prompts for explicit interactive confirmation (`RESTORE`).
3. Streams the decompressed SQL dump directly into `psql` inside the container.
4. Restores all table definitions, triggers, indexes, and face vector records.

---

## 4. Setting Up Automated Daily Cron Backups

To automate backups on a production Linux server:

1. Open root crontab:
   ```bash
   sudo crontab -e
   ```
2. Add a daily scheduled job at 02:00 AM:
   ```cron
   0 2 * * * cd /path/to/VisionGate && bash scripts/backup_db.sh >> /var/log/visiongate_backup.log 2>&1
   ```
3. Verify cron schedule:
   ```bash
   sudo crontab -l
   ```

---

## 5. Cold Disaster Recovery Workflow (Server Migration)

To migrate VisionGate to a new physical or virtual server:

1. Create a backup on the source server:
   ```bash
   bash scripts/backup_db.sh
   ```
2. Copy the backup file to the target server via `scp` or `rsync`:
   ```bash
   scp backups/attenda_db_backup_*.sql.gz user@new-server:/home/user/VisionGate/backups/
   ```
3. On the new server, clone the repository and run initial deployment:
   ```bash
   git clone https://github.com/nithin1112006/VisionGate.git
   cd VisionGate
   cp .env.example .env
   # configure .env secrets
   bash scripts/deploy.sh
   ```
4. Restore the database from the copied backup file:
   ```bash
   bash scripts/restore_db.sh backups/attenda_db_backup_*.sql.gz
   ```
5. Run the smoke test suite to verify data integrity:
   ```bash
   bash scripts/test.sh
   ```
