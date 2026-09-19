# VisionGate System Architecture Specification

## 1. Architectural Overview

VisionGate is architected as an asynchronous, containerized multi-tier service optimized for real-time facial recognition attendance, staff and student lifecycle tracking, and academic scheduling.

```
                           +-------------------------------------------------------+
                           |             Client Presentation Tier                  |
                           |   Flutter Mobile App (siet_sync)  / Admin Dashboard   |
                           +---------------------------+---------------------------+
                                                       |
                                           HTTPS / WSS / TLS 1.3
                                                       |
                                                       v
                           +-------------------------------------------------------+
                           |             Edge / Security Gateway                   |
                           |    Cloudflare Edge Proxy / Zero-Trust Named Tunnel    |
                           +---------------------------+---------------------------+
                                                       |
                                            Docker Bridge Network
                                                       |
                                                       v
                           +-------------------------------------------------------+
                           |              Reverse Proxy Tier (Nginx)               |
                           |  - Real IP Extraction (CF-Connecting-IP)             |
                           |  - Static Asset Buffering & Gzip Acceleration         |
                           |  - Ingress Rate Limiting                              |
                           +---------------------------+---------------------------+
                                                       |
                                             HTTP / FastCGI (Port 8001)
                                                       |
                                                       v
                           +-------------------------------------------------------+
                           |            Application API Tier (FastAPI)             |
                           |  - Multi-Worker Async Concurrency (Uvicorn)           |
                           |  - JWT & Base64 Auth Middleware                       |
                           |  - Geofence Polygon Engine                            |
                           |  - Alternate Faculty Substitution Matrix              |
                           +---------------------------+---------------------------+
                                                       |
                                       +---------------+---------------+
                                       |                               |
                                       v                               v
            +--------------------------------------+   +-------------------------------+
            |        AI / Inference Engine         |   |    Data & Persistence Tier    |
            |  - InsightFace buffalo_s Model       |   |  - PostgreSQL 16 + pgvector   |
            |  - ONNX Runtime GPU (CUDA sm_120)    |   |  - Schema Migrations Engine   |
            |  - Fallback CPUExecutionProvider     |   |  - Persistent Named Volumes   |
            +--------------------------------------+   +-------------------------------+
```

---

## 2. Component Specifications

### 2.1 Reverse Proxy (`attenda-nginx`)
- **Image**: `nginx:1.27-alpine`
- **Port**: Host port 80 (and 443 if SSL terminated locally).
- **Responsibilities**:
  - Restores authentic client IP addresses across all Cloudflare IPv4/IPv6 ranges using `set_real_ip_from` and `real_ip_header CF-Connecting-IP`.
  - Enables WebSocket streaming for live location telemetry (`/ws/`).
  - Gzip compression for payloads $\ge$ 500 bytes.
  - Passes traffic upstream to `backend:8001`.

### 2.2 Application Backend (`attenda-backend`)
- **Runtime**: Python 3.12 within `nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04`.
- **Framework**: FastAPI with asynchronous concurrency pool.
- **Inference Engine**: InsightFace 0.7.3 (`buffalo_s` pre-cached embedding model) with ONNX Runtime GPU.
- **Health Introspection**: Implements `/health`, `/health/live`, `/health/ready`, and `/health/dependencies`.

### 2.3 Database Engine (`attenda-postgres`)
- **Image**: `pgvector/pgvector:pg16`
- **Extensions**: `vector` (512-dimensional face vectors), `uuid-ossp`, `pg_trgm`.
- **Storage**: Persistent Docker volume `attenda_postgres_data` mounted at `/var/lib/postgresql/data`.
- **Connection Adapter**: `pg_adapter.py` maintaining thread-safe pooled connections and advisory lock synchronization.

### 2.4 Cloudflare Tunnel (`attenda-cloudflared`)
- **Image**: `cloudflare/cloudflared:latest`
- **Execution Mode**: Docker compose profile (`tunnel`).
- **Security Boundary**: Outbound-only TLS tunnel; no external ingress ports require opening on the host router/firewall.

---

## 3. Data Persistence & Volume Layout

| Volume Name | Container Path | Purpose |
| :--- | :--- | :--- |
| `attenda_postgres_data` | `/var/lib/postgresql/data` | PostgreSQL tables, indexes, and vector embeddings |
| `attenda_storage` | `/app/storage` | Uploaded document proofs, medical certificates, reports |
| `attenda_insightface_models` | `/root/.insightface` | Pre-cached InsightFace model weights |
| Host Mount (`./backend/debug_images`) | `/app/debug_images` | Diagnostic capture frames (git-ignored) |

---

## 4. Security & Access Control Model

1. **Database Isolation**: In production, PostgreSQL port 5432 is bound strictly to `127.0.0.1` or remains internal to the Docker network.
2. **Advisory Locking**: DDL migrations utilize PostgreSQL advisory locks (`pg_try_advisory_lock(123456789)`) to prevent race conditions during multi-worker restarts.
3. **Password Security**: All user and staff passwords are encrypted using `bcrypt` salted hashes.
4. **Network Verification**: Dynamic VPN detection evaluates client IP address ranges, while geofencing validates coordinate inclusion against configurable campus polygons.
