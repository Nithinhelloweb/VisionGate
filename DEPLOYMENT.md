# VisionGate Production Deployment Manual

This document details the production deployment process for the VisionGate system on a clean Linux host, including GPU container configuration, Cloudflare routing, database initialization, and mobile integration.

---

## 1. Fresh Server Setup

### 1.1 Update Base Packages

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl wget git net-tools ca-certificates gnupg lsb-release
```

### 1.2 Install Docker & Docker Compose Plugin

```bash
# Add Docker official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Set up repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow current user to run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker
```

---

## 2. NVIDIA GPU & CUDA Configuration (Optional for Hardware Acceleration)

VisionGate supports both GPU hardware acceleration and automatic CPU execution. If an NVIDIA GPU is installed on the host, configure the container toolkit:

```bash
# 1. Install NVIDIA Linux Driver
sudo apt-get install -y nvidia-driver-535
# (Reboot server if driver was newly installed)

# 2. Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# 3. Configure Docker Daemon Runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 4. Verify GPU Passthrough
docker run --rm --gpus all nvidia/cuda:12.8.0-runtime-ubuntu24.04 nvidia-smi
```

---

## 3. Clone Repository & Environment Setup

```bash
git clone https://github.com/nithin1112006/VisionGate.git
cd VisionGate

cp .env.example .env
nano .env
```

### Environment Configuration Reference

| Parameter | Default | Purpose |
| :--- | :--- | :--- |
| `PG_DB` | `attenda` | PostgreSQL database name |
| `PG_USER` | `attenda` | Database master user |
| `PG_PASSWORD` | *(Required)* | Strong database password |
| `PG_HOST` | `postgres` | Internal Docker DNS hostname |
| `PG_PORT` | `5432` | Internal database port |
| `PG_HOST_PORT` | `5432` | Host mapped port (restricted to 127.0.0.1 in prod) |
| `BACKEND_PORT` | `8001` | FastAPI application port |
| `HTTP_PORT` | `80` | Nginx reverse proxy HTTP port |
| `JWT_SECRET` | *(Required)* | 64-character random string for signing JWT tokens |
| `CLOUDFLARE_TUNNEL_TOKEN` | *(Optional)* | Cloudflare Zero-Trust tunnel token |
| `CLOUDFLARE_DOMAIN` | *(Optional)* | Public domain name |

---

## 4. Run Pre-Flight Diagnostic Doctor

Execute the doctor diagnostic before starting the deployment:

```bash
bash scripts/doctor.sh
```

The script validates CPU, RAM, disk space, Docker socket permissions, GPU passthrough, and `.env` presence.

---

## 5. Launch One-Command Deployment

```bash
bash scripts/deploy.sh
```

The deployment engine will:
1. Validate system prerequisites.
2. Initialize `.env`.
3. Build the container images deterministically with pre-cached InsightFace models.
4. Launch PostgreSQL and wait for database health readiness.
5. Sequentially run schema migrations and default table seeding.
6. Launch Backend, Nginx, and Cloudflare Tunnel (if token configured).
7. Perform automated health verification and display accessible URLs.

---

## 6. Cloudflare Configuration Options

### Option A: Cloudflare Zero-Trust Tunnel (Outbound Encrypted Connection)

No open firewall ports are required.
1. Create a tunnel in the Cloudflare Zero Trust Dashboard $\rightarrow$ **Networks** $\rightarrow$ **Tunnels**.
2. Copy the tunnel token into `.env`:
   ```env
   CLOUDFLARE_TUNNEL_TOKEN=eyJh...
   ```
3. Set public hostname target in Cloudflare:
   - Service: `HTTP`
   - URL: `attenda-nginx:80` (or `attenda-backend:8001`)
4. Re-run deploy or start with tunnel profile:
   ```bash
   docker compose --profile tunnel up -d
   ```

### Option B: Cloudflare DNS Proxy with Public IP

1. In Cloudflare Dashboard $\rightarrow$ **DNS** $\rightarrow$ **Records**:
   - Type: `A`
   - Name: `attenda` (or `@`)
   - IPv4 Address: `<your-server-public-ip>`
   - Proxy status: **Proxied (Orange Cloud ON)**
2. In Cloudflare Dashboard $\rightarrow$ **SSL/TLS**:
   - Set encryption mode to **Full**.
   - Enable **Always Use HTTPS**.
3. Forward port 80/443 on your router/firewall to host port 80.
4. Nginx automatically restores real client IP addresses from `CF-Connecting-IP`.

---

## 7. Mobile Client Configuration (Flutter)

In `siet_sync/lib/config/college_ip_config.dart`, configure the public domain:

```dart
static const String customServerURL = "https://attenda.yourdomain.com";
```

All mobile attendance requests, live location streams, and background sync services will securely route through Cloudflare Edge.
