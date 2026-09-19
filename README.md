# VisionGate

VisionGate is an automated facial recognition attendance, timetable scheduling, and leave management system built for educational institutions and enterprise environments.

---

## Quickstart Deployment

Deploying VisionGate on a fresh Linux server requires Docker, Docker Compose, and Git.

```bash
# 1. Clone repository
git clone https://github.com/nithin1112006/VisionGate.git
cd VisionGate

# 2. Configure secrets and ports
cp .env.example .env
nano .env

# 3. Run one-command deployment
bash scripts/deploy.sh
```

Once deployment completes, access the application:
- **Public Entrypoint (Nginx)**: `http://<server-ip>:80`
- **Direct API & Swagger Docs**: `http://<server-ip>:8001/docs`
- **Health Check**: `http://<server-ip>:8001/health`

---

## System Architecture

VisionGate runs as a multi-container Docker stack:

```text
┌─────────────────────────────────────────────────────────────┐
│                 Client (Flutter Mobile / Web)               │
└──────────────────────────────┬──────────────────────────────┘
                               │ HTTPS / WSS
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 Nginx Reverse Proxy (:80)                   │
│   - Real IP Restoration via CF-Connecting-IP               │
│   - Gzip Compression & Rate Limiting                        │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 FastAPI Backend API (:8001)                 │
│   - Authentication & Role-Based Access Control              │
│   - InsightFace (buffalo_s) & ONNX Runtime (GPU / CPU)      │
│   - Attendance Rules Engine & Geofencing                    │
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
                ▼                             ▼
┌──────────────────────────────┐  ┌───────────────────────────┐
│     PostgreSQL 16 Engine     │  │    Persistent Volumes     │
│   - pgvector 512-dim vectors │  │  - Database storage       │
│   - Automated Migrations     │  │  - Model cache            │
└──────────────────────────────┘  └───────────────────────────┘
```

---

## Operational Commands

| Action | Command |
| :--- | :--- |
| **Run Pre-flight Diagnostics** | `bash scripts/doctor.sh` |
| **Deploy Entire Stack** | `bash scripts/deploy.sh` |
| **Run System Smoke Tests** | `bash scripts/test.sh` |
| **Verify GPU Acceleration** | `bash scripts/verify_gpu.sh` |
| **View Live Backend Logs** | `docker compose logs -f backend` |
| **Create Database Backup** | `bash scripts/backup_db.sh` |
| **Restore Database** | `bash scripts/restore_db.sh <backup_file.sql.gz>` |
| **Pull Updates & Rebuild** | `bash scripts/update.sh` |
| **Stop All Containers** | `bash scripts/stop.sh` |

---

## Host Prerequisites

- **Operating System**: Linux (Ubuntu 22.04 LTS / 24.04 LTS recommended, x86_64 or aarch64)
- **Container Engine**: Docker Engine 24+ and Docker Compose v2
- **Memory**: Minimum 4 GB RAM (8 GB+ recommended for concurrent inference)
- **Disk Space**: Minimum 15 GB free disk
- **Optional GPU**: NVIDIA GPU with Linux driver $\ge$ 535 and `nvidia-container-toolkit`

---

## Documentation Links

- [DEPLOYMENT.md](DEPLOYMENT.md) — Comprehensive deployment guide and Cloudflare setup.
- [ARCHITECTURE.md](ARCHITECTURE.md) — Component architecture, data flows, and security model.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Problem diagnosis matrix and recovery steps.
- [BACKUP.md](BACKUP.md) — Database backup retention, automation, and disaster recovery.
