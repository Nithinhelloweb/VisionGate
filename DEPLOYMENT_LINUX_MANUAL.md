# VisionGate / Attenda — Native Linux Deployment Manual (Zero Docker)

## 1. Executive Summary & Target Environment

This manual guides the complete bare-metal deployment of **VisionGate / Attenda** on your Linux server **without Docker**, tailored specifically to the server profile documented in `systemconfigdeploy.txt`:

| Specification | Target Server Configuration |
| :--- | :--- |
| **Operating System** | Ubuntu 24.04.4 LTS (Noble Numbat) |
| **Kernel** | Linux 7.0.0-28-generic (x86_64) |
| **Processor** | Intel Core Ultra 9 285K (24 physical cores / 24 threads) |
| **Graphics (GPU)** | NVIDIA GeForce RTX 5070 (12GB VRAM, Driver 595.84, CUDA 13.2) |
| **System Memory** | 32 GB RAM (31 GiB physical, NVMe swap) |
| **Storage** | 952 GB NVMe SSD (231 GB available) |
| **Default User** | `techpark-2` (with sudo privileges) |
| **Workspace Directory** | `/home/techpark-2/attenda` |
| **Public Domain** | `https://attenda.srishakthicgpa.in` |

---

## 2. Compatibility Audit: Changes Made in This System

Before pushing to GitHub, the following compatibility fixes were engineered across the codebase:

1. **Python Dependencies Audit ([`backend/requirements.txt`](file:///d:/CLG/AAS/APP/Attenda_V1%20-%20Staff%20-%20Copy/backend/requirements.txt))**:
   - Added missing runtime imports: `python-dotenv>=1.0.0`, `httpx>=0.27.0`, `psutil>=5.9.0`, and `structlog>=24.1.0`.
   - Without these, a fresh `pip install -r requirements.txt` on a clean Linux system would fail immediately with `ModuleNotFoundError: No module named 'dotenv'` or `'psutil'`.

2. **Environment Loading Hierarchy ([`backend/pg_adapter.py`](file:///d:/CLG/AAS/APP/Attenda_V1%20-%20Staff%20-%20Copy/backend/pg_adapter.py))**:
   - Added dual `.env` detection so configuration is loaded seamlessly from both `backend/.env` and root `.env`.

3. **Backend Host and Port Dynamic Binding ([`backend/main.py`](file:///d:/CLG/AAS/APP/Attenda_V1%20-%20Staff%20-%20Copy/backend/main.py))**:
   - Allowed dynamic host and port configuration via `HOST`, `PORT`, and `BACKEND_PORT` environment variables with default fallback to `0.0.0.0:8001`.

4. **Schema & Database Script Parity ([`01-init.sql`](file:///d:/CLG/AAS/APP/Attenda_V1%20-%20Staff%20-%20Copy/backend/01-init.sql))**:
   - Fully synchronized `backend/01-init.sql` and `docker/postgres/01-init.sql` with class-specific timetable columns (`batch`, `semester`, `section`) and composite index `idx_apc_class_lookup`.

5. **Cloudflare Tunnel Native Ingress ([`05_setup_cloudflared.sh`](file:///d:/CLG/AAS/APP/Attenda_V1%20-%20Staff%20-%20Copy/deploy/native_linux/05_setup_cloudflared.sh))**:
   - In Docker, ingress routed to `http://nginx:80` (a container hostname). On native Linux, this will fail DNS resolution.
   - The native installer points ingress to `http://127.0.0.1:80` (or `http://127.0.0.1:8001`), ensuring 100% connectivity.

---

## 3. Workflow: Push From Laptop to GitHub & Pull on Linux

### On Your Laptop (Current Workspace):
1. Review modified files and stage changes:
   ```powershell
   git status
   git add backend/ requirements.txt docker/postgres/01-init.sql deploy/ .env.example
   git commit -m "chore: prepare native linux deployment scripts and dependencies"
   git push origin master
   ```

### On the Linux Server (`techpark-2`):
1. SSH into the server or open the terminal:
   ```bash
   cd /home/techpark-2
   ```
2. Clone the repository (or pull latest updates):
   ```bash
   # If cloning for the first time:
   git clone https://github.com/nithin1112006/VisionGate.git attenda
   cd attenda

   # If updating an existing clone:
   cd /home/techpark-2/attenda
   git fetch origin master
   git reset --hard origin/master
   ```
3. Create your production `.env` file:
   ```bash
   cp .env.example .env
   ```
   Ensure the following values are in `/home/techpark-2/attenda/.env`:
   ```bash
   PG_DB=attenda
   PG_USER=attenda
   PG_PASSWORD=attenda_password
   PG_HOST=127.0.0.1
   PG_PORT=5432
   BACKEND_PORT=8001
   HTTP_PORT=80
   APP_ENV=production
   CLOUDFLARE_TUNNEL_TOKEN=eyJhIjogIjM2Mzc3MTE3NDNiZmI3MjJiYjhmZmQ3NjA4ZjhlODM4IiwgInQiOiAiMjdiOTBmZDYtZjExYi00ZjM1LWIxNjAtNDdiY2MyZTJlZDllIiwgInMiOiAiaUVjQk95Q3BEb2grRFFnMXp4MGI1d3Aya3pLRU81T1l3OUtqVEFFdGM5VT0ifQ==
   CLOUDFLARE_DOMAIN=attenda.srishakthicgpa.in
   ```

---

## 4. One-Click Automated Deployment (Zero Docker)

To set up everything in one pass:

```bash
cd /home/techpark-2/attenda/deploy/native_linux
sudo bash setup_all.sh
```

This single command executes:
1. **System packages**: Installs PostgreSQL 16, `postgresql-16-pgvector`, Python 3.12 venv/dev packages, OpenCV dependencies (`libgl1`, `libglib2.0-0`), Nginx, and `cloudflared`.
2. **Database setup**: Creates `attenda` role, creates `attenda` database, enables `vector`/`uuid-ossp`/`pg_trgm`, applies `01-init.sql`, runs migrations, and seeds admin & departments.
3. **Backend setup**: Creates Python 3.12 virtualenv at `backend/venv`, installs PyTorch with CUDA 12.4 for the RTX 5070, and installs all Python requirements.
4. **Backend systemd service**: Installs `/etc/systemd/system/attenda-backend.service` and enables auto-start on boot.
5. **Nginx setup**: Configures reverse proxy on port 80 with Cloudflare real IP restoration and WebSocket support.
6. **Cloudflare Tunnel**: Installs `cloudflared` as a native systemd service pointing `attenda.srishakthicgpa.in` to `http://127.0.0.1:80`.
7. **Diagnostic check**: Runs `doctor_linux.sh` to verify all components.

---

## 5. Step-by-Step Manual Deployment (Command by Command)

If you prefer to run each step individually:

### Step 1: Install System Prerequisites
```bash
cd /home/techpark-2/attenda/deploy/native_linux
sudo bash 01_prerequisites.sh
```

### Step 2: Initialize Database & Seed Data
```bash
bash 02_setup_database.sh
```
*Verification:*
```bash
psql -h 127.0.0.1 -U attenda -d attenda -c "\dt"
```

### Step 3: Setup Python Virtual Environment & RTX 5070 Acceleration
```bash
bash 03_setup_backend.sh
```
*Verification:*
Checks that `torch.cuda.is_available()` returns `True` and detects `NVIDIA GeForce RTX 5070`.

### Step 4: Install and Start Backend Service
```bash
sudo bash setup_backend_service.sh
```
*Verification:*
```bash
sudo systemctl status attenda-backend
curl -s http://127.0.0.1:8001/health
```

### Step 5: Configure Nginx Reverse Proxy
```bash
sudo bash 04_setup_nginx.sh
```
*Verification:*
```bash
curl -s http://127.0.0.1/healthz
```

### Step 6: Configure Cloudflare Tunnel
```bash
sudo bash 05_setup_cloudflared.sh
```
*Verification:*
```bash
sudo systemctl status cloudflared
curl -I https://attenda.srishakthicgpa.in/health
```

---

## 6. Frontend Deployment

### Android Application (Mobile Phones & Tablets):
- The Flutter mobile client connects to `customServerURL = "https://attenda.srishakthicgpa.in"` defined in [`college_ip_config.dart`](file:///d:/CLG/AAS/APP/Attenda_V1%20-%20Staff%20-%20Copy/siet_sync/lib/config/college_ip_config.dart#L33).
- Build the APK on your laptop:
  ```powershell
  cd siet_sync
  flutter build apk --release
  ```
- Distribute `build/app/outputs/flutter-apk/app-release.apk` to staff and students.

### Web Application (Optional Desktop Browser Access):
- Build Flutter Web on your laptop:
  ```powershell
  cd siet_sync
  flutter build web --release
  ```
- Copy `siet_sync/build/web` to `/home/techpark-2/attenda/siet_sync/build/web` on the Linux server.
- Nginx will automatically serve the web app on `https://attenda.srishakthicgpa.in/` and proxy API calls to `:8001`!

---

## 7. Service Management & Operations

Use [`manage_services.sh`](file:///d:/CLG/AAS/APP/Attenda_V1%20-%20Staff%20-%20Copy/deploy/native_linux/manage_services.sh) for everyday administration:

```bash
cd /home/techpark-2/attenda/deploy/native_linux

# Check status of all components
bash manage_services.sh status

# Restart backend, nginx, and cloudflare tunnel
bash manage_services.sh restart

# Stream live backend logs
bash manage_services.sh logs attenda-backend

# Stream cloudflare tunnel logs
bash manage_services.sh logs cloudflared

# Run full health diagnostics
bash doctor_linux.sh
```

---

## 8. Credentials & Access Reference

- **Admin Portal**: `https://attenda.srishakthicgpa.in`
- **Initial Admin Username**: `admin`
- **Initial Admin Password**: `admin123`
- **Interactive API Documentation (Swagger)**: `https://attenda.srishakthicgpa.in/docs`
- **Local PostgreSQL Connection**:
  - Host: `127.0.0.1`
  - Port: `5432`
  - Database: `attenda`
  - User: `attenda`
  - Password: `attenda_password`
