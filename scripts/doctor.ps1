# ==============================================================================
# VisionGate / Attenda - Pre-Flight Diagnostic Doctor (PowerShell / Windows)
# ==============================================================================

$PassCount = 0
$WarnCount = 0
$FailCount = 0

function Report-Pass($msg) {
    Write-Host "  [✓ PASS] $msg" -ForegroundColor Green
    $script:PassCount++
}

function Report-Warn($msg, $notice) {
    Write-Host "  [! WARN] $msg" -ForegroundColor Yellow
    if ($notice) { Write-Host "         Notice: $notice" -ForegroundColor Cyan }
    $script:WarnCount++
}

function Report-Fail($msg, $reason, $fix) {
    Write-Host "  [✗ FAIL] $msg" -ForegroundColor Red
    if ($reason) { Write-Host "         Reason: $reason" -ForegroundColor Red }
    if ($fix) { Write-Host "         Fix:    $fix" -ForegroundColor Yellow }
    $script:FailCount++
}

Write-Host "======================================================================" -ForegroundColor Blue
Write-Host " VisionGate / Attenda — Pre-Flight System Doctor (PowerShell)         " -ForegroundColor Cyan
Write-Host " Date: $(Get-Date) | Host: $env:COMPUTERNAME" -ForegroundColor Blue
Write-Host "======================================================================" -ForegroundColor Blue

# 1. OS & Architecture
Write-Host "`n[1/8] Operating System & Architecture" -ForegroundColor White
$arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
Report-Pass "Operating System: Windows ($arch)"

# 2. System Hardware Resources
Write-Host "`n[2/8] System Resources (RAM & Disk Space)" -ForegroundColor White
$totalRamGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
if ($totalRamGb -ge 8) {
    Report-Pass "RAM: $totalRamGb GB (Sufficient for high-load attendance inference)"
} elseif ($totalRamGb -ge 4) {
    Report-Warn "RAM: $totalRamGb GB" "Recommended memory is >= 8 GB for high concurrent batch face recognition."
} else {
    Report-Fail "RAM: $totalRamGb GB" "Insufficient RAM for running PostgreSQL + PyTorch + InsightFace." "Upgrade host memory."
}

$drive = Get-PSDrive C -ErrorAction SilentlyContinue
$freeDiskGb = [math]::Round($drive.Free / 1GB, 1)
if ($freeDiskGb -ge 15) {
    Report-Pass "Available Disk Space: $freeDiskGb GB"
} else {
    Report-Warn "Available Disk Space: $freeDiskGb GB" "Recommended free disk is at least 15 GB."
}

# 3. Docker Engine & Compose
Write-Host "`n[3/8] Docker Engine & Compose" -ForegroundColor White
try {
    $dockerVer = docker --version 2>$null
    if ($dockerVer -match "Docker version") {
        Report-Pass "Docker Engine installed: $dockerVer"
        $dockerInfo = docker info --format '{{.ServerVersion}}' 2>$null
        if ($dockerInfo) {
            Report-Pass "Docker daemon is running and accessible (Server: $dockerInfo)"
        } else {
            Report-Fail "Docker daemon not running" "Docker Desktop is installed but not started." "Start Docker Desktop application."
        }
    } else {
        Report-Fail "Docker not found" "Docker CLI is not in PATH." "Install Docker Desktop for Windows."
    }
} catch {
    Report-Fail "Docker check failed" $_.Exception.Message "Ensure Docker Desktop is running."
}

try {
    $composeVer = docker compose version 2>$null
    if ($composeVer -match "Docker Compose") {
        Report-Pass "Docker Compose v2 detected: $composeVer"
    } else {
        Report-Fail "Docker Compose not detected" "Docker Compose plugin missing." "Update Docker Desktop."
    }
} catch {
    Report-Fail "Docker Compose check failed" $_.Exception.Message ""
}

# 4. NVIDIA GPU & Hardware Acceleration
Write-Host "`n[4/8] NVIDIA GPU & Hardware Acceleration" -ForegroundColor White
try {
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" } | Select-Object -First 1
    if ($gpu) {
        Report-Pass "NVIDIA GPU Detected: $($gpu.Name)"
    } else {
        Report-Warn "NVIDIA GPU not detected" "System will run in CPU execution mode (InsightFace operates on CPU)."
    }
} catch {
    Report-Warn "GPU check skipped" $_.Exception.Message
}

# 5. Network Ports
Write-Host "`n[5/8] Network Ports Availability" -ForegroundColor White
$ports = @(
    @{ Port = 80; Name = "Nginx Ingress" },
    @{ Port = 8001; Name = "FastAPI Backend" },
    @{ Port = 5434; Name = "PostgreSQL Port" }
)
foreach ($p in $ports) {
    $inUse = Get-NetTCPConnection -LocalPort $p.Port -State Listen -ErrorAction SilentlyContinue
    if ($inUse) {
        Report-Warn "Port $($p.Port) ($($p.Name)) is currently bound" "If VisionGate is already running, this is expected."
    } else {
        Report-Pass "Port $($p.Port) ($($p.Name)) is available"
    }
}

# 6. Environment Configuration
Write-Host "`n[6/8] Environment Secrets & Configuration" -ForegroundColor White
if (Test-Path ".env") {
    Report-Pass ".env configuration file is present"
} elseif (Test-Path ".env.example") {
    Report-Warn ".env file is missing" "Will be created automatically from .env.example during deployment."
} else {
    Report-Fail "Neither .env nor .env.example found" "Environment template missing." "Restore .env.example from git."
}

# 7. Cloudflare Check
Write-Host "`n[7/8] Cloudflare Edge & Tunnel Integration" -ForegroundColor White
if (Test-Path ".env") {
    $envContent = Get-Content ".env" -Raw
    if ($envContent -match "CLOUDFLARE_TUNNEL_TOKEN=([^\r\n]+)" -and $matches[1].Trim().Length -gt 5) {
        Report-Pass "Cloudflare Zero-Trust Tunnel Token is configured"
    } else {
        Report-Warn "Cloudflare Tunnel Token not configured" "System will run on LAN / Direct IP."
    }
} else {
    Report-Warn "Cloudflare check skipped" ".env not yet configured."
}

# 8. Assets & Manifests
Write-Host "`n[8/8] Static Assets & Migration Manifests" -ForegroundColor White
if (Test-Path "backend\requirements.txt") { Report-Pass "backend/requirements.txt present" } else { Report-Fail "backend/requirements.txt missing" "" "" }
if (Test-Path "backend\Dockerfile") { Report-Pass "backend/Dockerfile present" } else { Report-Fail "backend/Dockerfile missing" "" "" }
if (Test-Path "backend\run_migrations.py") { Report-Pass "backend/run_migrations.py present" } else { Report-Fail "backend/run_migrations.py missing" "" "" }
if (Test-Path "docker\postgres\01-init.sql") { Report-Pass "docker/postgres/01-init.sql present" } else { Report-Fail "docker/postgres/01-init.sql missing" "" "" }

Write-Host "`n======================================================================" -ForegroundColor Blue
Write-Host " Pre-Flight Diagnostic Summary:" -ForegroundColor White
Write-Host "  Passed:   $PassCount" -ForegroundColor Green
Write-Host "  Warnings: $WarnCount" -ForegroundColor Yellow
Write-Host "  Failures: $FailCount" -ForegroundColor Red
Write-Host "======================================================================" -ForegroundColor Blue

if ($FailCount -eq 0) {
    Write-Host "✓ System is READY for VisionGate deployment.`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Please fix the failed prerequisite(s) above before deploying.`n" -ForegroundColor Red
    exit 1
}
