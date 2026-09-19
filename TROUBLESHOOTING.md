# VisionGate Troubleshooting & Diagnostic Guide

This guide provides targeted remediation procedures for common deployment, container, database, and hardware acceleration issues.

---

## 1. Problem Resolution Matrix

| Symptom | Probable Cause | Diagnostic Command | Remediation Step |
| :--- | :--- | :--- | :--- |
| **PostgreSQL container unhealthy** | Missing data permissions or failed initialization | `docker compose logs postgres` | Verify permissions on `attenda_postgres_data` volume. Ensure password in `.env` matches existing data volume. |
| **Backend healthcheck timeout** | Container slow to initialize or unready DB | `curl -i http://localhost:8001/health` | Run `docker compose logs backend` to inspect migration or startup log. |
| **CUDA passthrough failure** | NVIDIA Container Toolkit not registered with Docker | `bash scripts/verify_gpu.sh` | Run `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`. |
| **ONNX Runtime running on CPU** | Missing CUDAExecutionProvider or driver mismatch | `curl -s http://localhost:8001/health/dependencies` | Normal behavior on non-GPU hosts. On GPU hosts, verify CUDA 12.x/13.x compatibility in `verify_gpu.sh`. |
| **Cloudflare Tunnel not connecting** | Invalid or missing `CLOUDFLARE_TUNNEL_TOKEN` | `docker compose logs cloudflared` | Verify token string in `.env` without surrounding whitespace or quotes. |
| **Mobile app cannot connect** | Hardcoded development IP or mismatched domain | `curl -I https://attenda.yourdomain.com/health` | Update `customServerURL` in `siet_sync/lib/config/college_ip_config.dart` to match your public domain. |
| **Database migration deadlock** | Previous interrupted migration held advisory lock | `docker compose logs backend` | Run `docker exec -t attenda-postgres psql -U attenda -d attenda -c "SELECT pg_advisory_unlock_all();"`. |
| **Permission denied on volumes** | Host file ownership mismatch | `ls -la backend/debug_images` | Run `chmod -R 775 backend/debug_images backend/storage`. |

---

## 2. Step-by-Step Diagnostic Procedures

### 2.1 Full Pre-Flight Health Audit
Run the automated diagnostic doctor to test all subsystems:
```bash
bash scripts/doctor.sh
```

### 2.2 Deep Backend Log Inspection
```bash
# View last 100 log lines with live tailing
docker compose logs -f --tail=100 backend

# View database query and connection logs
docker compose logs -f --tail=100 postgres
```

### 2.3 Inspect Database Tables & Extensions Directly
```bash
docker exec -it attenda-postgres psql -U attenda -d attenda

# Inside PostgreSQL:
\dx                 # Check active extensions (vector, uuid-ossp, pg_trgm)
\dt                 # List all public tables
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM schema_migrations;
\q                  # Exit
```

### 2.4 Test API Routes Directly via Curl
```bash
# Test Root & Health
curl -s http://localhost:8001/health | jq

# Test Dependencies
curl -s http://localhost:8001/health/dependencies | jq

# Test Admin Authentication
curl -s -X POST http://localhost:8001/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}' | jq
```

---

## 3. Emergency Disaster Recovery (Clean Rebuild)

If the deployment has corrupted state and needs a clean re-initialization (preserving database backups):

```bash
# 1. Back up database first
bash scripts/backup_db.sh

# 2. Stop running containers
bash scripts/stop.sh

# 3. Clean untagged images and rebuild
docker compose build --no-cache backend

# 4. Start services fresh
bash scripts/deploy.sh

# 5. Verify system health
bash scripts/test.sh
```
