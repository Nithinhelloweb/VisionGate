# ==============================================================================
# VisionGate / Attenda — Universal Docker Stack Startup Engine (PowerShell)
# Launches PostgreSQL, Backend with AI models, Nginx & Cloudflare Named Tunnel
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$Logs,
    [switch]$Build,
    [string]$Service = ""
)

$ErrorActionPreference = "Stop"

Write-Host "======================================================================" -ForegroundColor Blue
Write-Host " VisionGate / Attenda - Production Stack Startup Engine" -ForegroundColor Cyan
Write-Host " Host: $env:COMPUTERNAME | Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Blue
Write-Host "======================================================================" -ForegroundColor Blue

# 1. Environment configuration check
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Host "  [OK] Created .env configuration from .env.example" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] .env file not found." -ForegroundColor Red
        exit 1
    }
}

# 2. Hardware acceleration detection (GPU vs CPU)
$composeArgs = @("-f", "docker-compose.yml")
Write-Host "`n[*] Detecting Hardware Acceleration Mode..." -ForegroundColor Yellow
$gpuProbe = docker run --rm --gpus all nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi 2>$null
if ($gpuProbe -match "NVIDIA-SMI") {
    Write-Host "  [OK] NVIDIA GPU Container Acceleration is ACTIVE." -ForegroundColor Green
    if (Test-Path "docker-compose.gpu.yml") {
        $composeArgs += @("-f", "docker-compose.gpu.yml")
    }
} else {
    Write-Host "  [i] Running in CPU Execution Mode (InsightFace initialized with CPU provider)." -ForegroundColor Cyan
}

# 3. Optional rebuild flag
if ($Build) {
    Write-Host "`n[*] Building VisionGate Container Images..." -ForegroundColor Yellow
    docker compose @composeArgs build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] Image build failed." -ForegroundColor Red
        exit 1
    }
}

# 4. Spin up the stack with Cloudflare Tunnel profile
Write-Host "`n[*] Launching Docker Stack Services (Postgres, Backend, Nginx, Cloudflare)..." -ForegroundColor Yellow
docker compose @composeArgs --profile tunnel up -d

# 5. Active health monitoring
Write-Host "`n[*] Waiting for services to become healthy..." -ForegroundColor Yellow
$maxWait = 120
$waited = 0
$allHealthy = $false

while ($waited -lt $maxWait) {
    $pgHealth = docker inspect --format '{{json .State.Health.Status}}' attenda-postgres 2>$null
    $bHealth = docker inspect --format '{{json .State.Health.Status}}' attenda-backend 2>$null
    $nHealth = docker inspect --format '{{json .State.Health.Status}}' attenda-nginx 2>$null

    if ($pgHealth -eq '"healthy"' -and $bHealth -eq '"healthy"' -and $nHealth -eq '"healthy"') {
        $allHealthy = $true
        break
    }

    Write-Host "  -> Waiting: Postgres ($pgHealth), Backend ($bHealth), Nginx ($nHealth) [${waited}s/${maxWait}s]"
    Start-Sleep -Seconds 3
    $waited += 3
}

Write-Host ""
if ($allHealthy) {
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  VISIONGATE ATTENDA IS FULLY ONLINE & OPERATIONAL!" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  Public Production URL:  https://attenda.srishakthicgpa.in" -ForegroundColor Cyan
    Write-Host "  Local Nginx Ingress:    http://localhost:80" -ForegroundColor Cyan
    Write-Host "  Direct Backend API:     http://localhost:8001" -ForegroundColor Cyan
    Write-Host "  Swagger Documentation:  http://localhost:8001/docs" -ForegroundColor Cyan
    Write-Host "  Health Endpoint:        https://attenda.srishakthicgpa.in/health" -ForegroundColor Cyan
    Write-Host "  PostgreSQL Port:        localhost:5434 (Database: attenda)" -ForegroundColor Cyan
    Write-Host "======================================================================`n" -ForegroundColor Green
} else {
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host "  WARNING: Services took longer than expected to report healthy." -ForegroundColor Red
    Write-Host "  Check container logs with: .\logs.ps1" -ForegroundColor Yellow
    Write-Host "======================================================================`n" -ForegroundColor Red
}

# 6. Stream logs if requested
if ($Logs) {
    if ($Service) {
        Write-Host "[*] Streaming live logs for service: $Service (Press Ctrl+C to exit)...`n" -ForegroundColor Cyan
        docker compose @composeArgs logs -f $Service
    } else {
        Write-Host "[*] Streaming live logs for all services (Press Ctrl+C to exit)...`n" -ForegroundColor Cyan
        docker compose @composeArgs logs -f
    }
} else {
    Write-Host "Tip: To view real-time logs, run: .\logs.ps1" -ForegroundColor Gray
}
