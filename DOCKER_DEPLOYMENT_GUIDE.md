# Production Docker Deployment Guide for Attenda / VisionGate

This guide details the deployment of the VisionGate / Attenda facial attendance and staff management system on Ubuntu 24.04.4 LTS (Noble) with NVIDIA GeForce RTX 5070 (Blackwell architecture), CUDA 13.x, and **Cloudflare Static IP / Cloudflare Tunnel integration**.

---

## 1. System Specifications & Topology

- **Host Machine**: Alienware Aurora ACT1250 / x86_64
- **Host Operating System**: Ubuntu 24.04.4 LTS (Linux 7.0 Kernel)
- **CPU**: Intel Core Ultra 9 285K (24 cores)
- **Host Memory**: 32 GB RAM
- **GPU**: NVIDIA GeForce RTX 5070 (12 GB VRAM, Blackwell `sm_120`, Driver 595.84, CUDA 13.2)
- **Database Engine**: PostgreSQL 16 (`pgvector/pgvector:pg16`)
- **DNS / Edge CDN**: Cloudflare (Static IP / Cloudflare Proxy & Tunnels)

---

## 2. Cloudflare Configuration Options

Depending on your network topology, you can use either **Cloudflare DNS Proxy (Static IP)** or **Cloudflare Tunnel (Zero Trust)**.

### Option A: Cloudflare DNS Proxy with Static IP (Recommended if you have a public static IP)

1. **Cloudflare DNS Records**:
   - In your Cloudflare Dashboard -> **DNS** -> **Records**:
     - Type: `A`
     - Name: `attenda` (or `@` for apex domain)
     - IPv4 address: `YOUR_STATIC_IP`
     - Proxy status: **Proxied (Orange Cloud ON)**
2. **Cloudflare SSL/TLS Settings**:
   - In Cloudflare Dashboard -> **SSL/TLS**:
     - Set encryption mode to **Full** (or **Flexible** if forwarding plain HTTP on port 80).
     - Under **Edge Certificates**, enable **Always Use HTTPS** and **Automatic HTTPS Rewrites**.
3. **Router / Firewall Port Forwarding**:
   - Forward external port **80** (and **443**) to internal host IP **`192.168.76.12`** port **80** (or backend port **8001**).
4. **Nginx Real IP Handling**:
   - Nginx is already configured in `docker/nginx/nginx.conf` with `set_real_ip_from` for all Cloudflare IP ranges. This ensures all user IP logs, rate limiters, and geolocation tracking in FastAPI receive the real client IP via `CF-Connecting-IP`.

---

### Option B: Cloudflare Zero-Trust Tunnel (Recommended if you don't want to open router ports)

Cloudflare Tunnel creates an encrypted outbound-only connection from your server to Cloudflare Edge:
1. In Cloudflare Zero Trust Dashboard -> **Networks** -> **Tunnels** -> **Create a Tunnel**.
2. Select **Docker** and copy the Tunnel Token (`eyJh...`).
3. Add the token to `.env`:
   ```bash
   CLOUDFLARE_TUNNEL_TOKEN="eyJh..."
   ```
4. In the Cloudflare Tunnel public hostname configuration:
   - Service: `HTTP`
   - URL: `attenda-nginx:80` (or `attenda-backend:8001`)
5. Start the stack with the tunnel profile:
   ```bash
   docker compose --profile tunnel up -d
   ```

---

## 3. Client Application Configuration (Flutter / Mobile / Kiosk)

In `siet_sync/lib/config/college_ip_config.dart`, update the server URL to point to your Cloudflare domain:

```dart
// Cloudflare Domain URL (HTTPS is automatically managed by Cloudflare)
const String customServerURL = "https://attenda.yourdomain.com";
```

All WebSocket requests (`wss://attenda.yourdomain.com/ws/...`) and REST endpoints will be routed seamlessly through Cloudflare Edge.

---

## 4. Quickstart Deployment on Ubuntu 24.04

```bash
# 1. Ensure scripts have execute permissions
chmod +x scripts/*.sh backend/entrypoint.sh

# 2. Deploy PostgreSQL, Backend, and Nginx
bash scripts/deploy.sh

# 3. (If using Cloudflare Tunnel) Launch the tunnel service
docker compose --profile tunnel up -d

# 4. Verify GPU passthrough and CUDA acceleration
bash scripts/verify_gpu.sh
```

---

## 5. Daily Management & Operational Commands

| Action | Command |
| :--- | :--- |
| **Start Standard Stack** | `docker compose up -d` |
| **Start with Cloudflare Tunnel** | `docker compose --profile tunnel up -d` |
| **Stop All Containers** | `docker compose down` |
| **Rebuild After Code Changes** | `docker compose up -d --build` |
| **View Live Backend Logs** | `docker compose logs -f backend` |
| **Backup PostgreSQL DB** | `bash scripts/backup_db.sh` |
| **Restore PostgreSQL DB** | `bash scripts/restore_db.sh <backup_file.sql.gz>` |
