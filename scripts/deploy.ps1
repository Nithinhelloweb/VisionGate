# ==============================================================================
# VisionGate / Attenda - Automated Deployment Script (PowerShell / Windows)
# ==============================================================================

Write-Host "======================================================================" -ForegroundColor Blue
Write-Host " VisionGate / Attenda — Production Stack Deployment Engine (PowerShell)" -ForegroundColor Cyan
Write-Host " Date: $(Get-Date) | Host: $env:COMPUTERNAME" -ForegroundColor Blue
Write-Host "======================================================================" -ForegroundColor Blue

# 1. Run Pre-flight Doctor
Write-Host "`n[Step 1/6] Running Pre-Flight System Diagnostics..." -ForegroundColor Yellow
if (Test-Path "scripts\doctor.ps1") {
    & .\scripts\doctor.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Doctor checks failed. Resolve issues before deploying." -ForegroundColor Red
        exit 1
    }
}

# 2. Environment Setup
Write-Host "`n[Step 2/6] Configuring Environment Secrets..." -ForegroundColor Yellow
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Host "  [✓] Created .env from .env.example" -ForegroundColor Green
    } else {
        Write-Host "Error: .env and .env.example not found." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [✓] Existing .env configuration loaded." -ForegroundColor Green
}

# Hardware Acceleration Mode Detection
$composeFiles = @("-f", "docker-compose.yml")
Write-Host "`n[*] Detecting Hardware Acceleration Mode..." -ForegroundColor Yellow
$gpuTest = docker run --rm --gpus all nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi 2>$null
if ($gpuTest -match "NVIDIA-SMI") {
    Write-Host "  [✓] NVIDIA GPU Container Passthrough is OPERATIONAL." -ForegroundColor Green
    if (Test-Path "docker-compose.gpu.yml") {
        $composeFiles += @("-f", "docker-compose.gpu.yml")
    }
} else {
    Write-Host "  [! GPU detected on host but container passthrough unavailable or driver constraint.]" -ForegroundColor Yellow
    Write-Host "  -> Deploying in CPU Execution mode (InsightFace operates fully on CPU)." -ForegroundColor Cyan
}

# 3. Build Backend Image
Write-Host "`n[Step 3/6] Building Production Container Images..." -ForegroundColor Yellow
Write-Host "  -> Pre-fetching base image (with retries for slow connections)..."

$pullSuccess = $false
for ($i = 1; $i -le 3; $i++) {
    Write-Host "     [Attempt $i/3] Pulling nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04..."
    docker pull nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04
    if ($LASTEXITCODE -eq 0) {
        $pullSuccess = $true
        Write-Host "     [✓] Base image cached successfully." -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 3
}

Write-Host "  -> Building VisionGate backend container with ONNX & InsightFace..."
$buildSuccess = $false
for ($j = 1; $j -le 3; $j++) {
    docker compose @composeFiles build backend
    if ($LASTEXITCODE -eq 0) {
        $buildSuccess = $true
        break
    }
    Write-Host "  [! Build attempt $j failed. Retrying in 5 seconds...]" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

if (-not $buildSuccess) {
    Write-Host "ERROR: Container build failed after 3 attempts." -ForegroundColor Red
    exit 1
}

# 4. Start Postgres
Write-Host "`n[Step 4/6] Initializing Database & Core Services..." -ForegroundColor Yellow
docker compose @composeFiles up -d postgres

Write-Host "Waiting for PostgreSQL database container to become healthy..."
$maxWait = 60
$waited = 0
$pgHealthy = $false

while ($waited -lt $maxWait) {
    $status = docker inspect --format '{{json .State.Health.Status}}' attenda-postgres 2>$null
    if ($status -eq '"healthy"') {
        $pgHealthy = $true
        Write-Host "  [✓] PostgreSQL container is HEALTHY and accepting connections." -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 2
    $waited += 2
}

if (-not $pgHealthy) {
    Write-Host "PostgreSQL failed to become healthy within ${maxWait}s." -ForegroundColor Red
    docker compose logs postgres
    exit 1
}

# 5. Start Backend, Nginx, and Cloudflare Tunnel
Write-Host "`n[Step 5/6] Starting VisionGate Application Services..." -ForegroundColor Yellow
$envContent = Get-Content ".env" -Raw -ErrorAction SilentlyContinue
if ($envContent -match "CLOUDFLARE_TUNNEL_TOKEN=([^\r\n]+)" -and $matches[1].Trim().Length -gt 5) {
    Write-Host "  -> Cloudflare Tunnel Token detected. Launching stack with tunnel profile..." -ForegroundColor Cyan
    docker compose @composeFiles --profile tunnel up -d
} else {
    Write-Host "  -> Launching standard stack (PostgreSQL, Backend, Nginx)..."
    docker compose @composeFiles up -d
}

# 6. Service Health Verification
Write-Host "`n[Step 6/6] Verifying Service Health & Readiness..." -ForegroundColor Yellow
$maxWait = 90
$waited = 0
$backendOk = $false

while ($waited -lt $maxWait) {
    $bStatus = docker inspect --format '{{json .State.Health.Status}}' attenda-backend 2>$null
    $nStatus = docker inspect --format '{{json .State.Health.Status}}' attenda-nginx 2>$null

    if ($bStatus -eq '"healthy"' -and $nStatus -eq '"healthy"') {
        $backendOk = $true
        break
    }
    Write-Host "  -> Waiting for services: Backend ($bStatus), Nginx ($nStatus) [${waited}s/${maxWait}s]"
    Start-Sleep -Seconds 3
    $waited += 3
}

if ($backendOk) {
    Write-Host "`n======================================================================" -ForegroundColor Green
    Write-Host "  VISIONGATE SYSTEM DEPLOYED SUCCESSFULLY!                            " -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  Public Nginx Entrypoint: http://localhost:80" -ForegroundColor Cyan
    Write-Host "  Direct Backend API:      http://localhost:8001" -ForegroundColor Cyan
    Write-Host "  API Documentation:       http://localhost:8001/docs" -ForegroundColor Cyan
    Write-Host "  Health Check:            http://localhost:8001/health" -ForegroundColor Cyan
    Write-Host "  Dependency Status:       http://localhost:8001/health/dependencies" -ForegroundColor Cyan
    Write-Host "  PostgreSQL Database:     localhost:5434 (DB: attenda)" -ForegroundColor Cyan
    Write-Host "======================================================================`n" -ForegroundColor Green
} else {
    Write-Host "Deployment timed out waiting for backend services to become healthy." -ForegroundColor Red
    docker compose logs backend
    exit 1
}
