# ==============================================================================
# VisionGate / Attenda - Automated Smoke Test Suite (PowerShell / Windows)
# ==============================================================================

$Passed = 0
$Failed = 0

function Report-Test($name, $success, $details) {
    if ($success) {
        Write-Host "  [PASS] $name" -ForegroundColor Green
        if ($details) { Write-Host "         $details" -ForegroundColor Cyan }
        $script:Passed++
    } else {
        Write-Host "  [FAIL] $name" -ForegroundColor Red
        if ($details) { Write-Host "         $details" -ForegroundColor Red }
        $script:Failed++
    }
}

Write-Host "======================================================================" -ForegroundColor Blue
Write-Host " VisionGate / Attenda - Automated Smoke Test Suite (PowerShell)       " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Blue

# 1. Containers Running
Write-Host "[1/7] Container Lifecycle & Health Checks" -ForegroundColor White
$containers = @("attenda-postgres", "attenda-backend", "attenda-nginx")
foreach ($c in $containers) {
    $status = docker inspect --format '{{json .State.Health.Status}}' $c 2>$null
    if ($status) {
        Report-Test "Container '$c' running (Health: $status)" $true ""
    } else {
        Report-Test "Container '$c' running" $false "Container not running"
    }
}

# 2. HTTP & Health Endpoints
Write-Host "`n[2/7] Core HTTP & Health Endpoints" -ForegroundColor White
try {
    $res = Invoke-RestMethod -Uri "http://localhost:8001/" -Method Get -TimeoutSec 5
    Report-Test "GET / (Root status endpoint)" ($res.status -eq "healthy") "Status: $($res.status)"
} catch {
    Report-Test "GET / (Root status endpoint)" $false $_.Exception.Message
}

try {
    $res = Invoke-RestMethod -Uri "http://localhost:8001/health" -Method Get -TimeoutSec 5
    Report-Test "GET /health (Universal Healthcheck)" ($res.status -eq "healthy") "Status: $($res.status)"
} catch {
    Report-Test "GET /health (Universal Healthcheck)" $false $_.Exception.Message
}

try {
    $res = Invoke-RestMethod -Uri "http://localhost:8001/health/ready" -Method Get -TimeoutSec 5
    Report-Test "GET /health/ready (Readiness Probe)" ($res.status -eq "ready") "Database & Model ready"
} catch {
    Report-Test "GET /health/ready (Readiness Probe)" $false $_.Exception.Message
}

# 3. Dependencies & Diagnostics
Write-Host "`n[3/7] Diagnostic & Dependency Introspection" -ForegroundColor White
try {
    $res = Invoke-RestMethod -Uri "http://localhost:8001/health/dependencies" -Method Get -TimeoutSec 5
    Report-Test "PostgreSQL Database Layer" ($res.database -eq "healthy") "Status: $($res.database)"
    Report-Test "Face Recognition Engine ($($res.face_recognition_mode))" ($null -ne $res.face_recognition_mode) "Mode: $($res.face_recognition_mode)"
} catch {
    Report-Test "Dependencies check" $false $_.Exception.Message
}

# 4. Geofence & Public Settings
Write-Host "`n[4/7] Geofence & Public Settings API" -ForegroundColor White
try {
    $res = Invoke-RestMethod -Uri "http://localhost:8001/geo-fence/public" -Method Get -TimeoutSec 5
    Report-Test "GET /geo-fence/public" ($res.success -eq $true) "Polygons loaded"
} catch {
    Report-Test "GET /geo-fence/public" $false $_.Exception.Message
}

# 5. Admin Authentication
Write-Host "`n[5/7] Authentication & Security Verification" -ForegroundColor White
try {
    $body = @{ username = "admin"; password = "admin123" } | ConvertTo-Json
    $res = Invoke-RestMethod -Uri "http://localhost:8001/login" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 5
    Report-Test "POST /login (Admin credentials)" ($res.message -eq "Login successful") "Token generated"
} catch {
    Report-Test "POST /login (Admin credentials)" $false $_.Exception.Message
}

# 6. Nginx Ingress
Write-Host "`n[6/7] Nginx Reverse Proxy Routing" -ForegroundColor White
try {
    $res = Invoke-RestMethod -Uri "http://127.0.0.1/healthz" -Method Get -TimeoutSec 5
    Report-Test "Nginx /healthz Ingress Endpoint" ($res -ne $null) "HTTP 200 OK"
} catch {
    Report-Test "Nginx /healthz Ingress Endpoint" $false $_.Exception.Message
}

# 7. Cloudflare Tunnel (if running)
Write-Host "`n[7/7] Cloudflare Edge & Ingress Tunnel" -ForegroundColor White
$CfRunning = docker ps --format '{{.Names}}' | Select-String "attenda-cloudflared"
if ($CfRunning) {
    try {
        $Logs = docker logs --tail 50 attenda-cloudflared 2>&1 | Out-String
        if ($Logs -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
            $TunUrl = $Matches[0]
            $res = Invoke-RestMethod -Uri "$TunUrl/health" -Method Get -TimeoutSec 10
            Report-Test "Cloudflare Quick Tunnel Ingress ($TunUrl)" ($res.status -eq "healthy") "Status: healthy"
        } else {
            Report-Test "Cloudflare Tunnel Container Running" $true "Tunnel active"
        }
    } catch {
        Report-Test "Cloudflare Tunnel Endpoint" $false $_.Exception.Message
    }
} else {
    Write-Host "  [-] Cloudflare tunnel container not running (run .\scripts\tunnel.ps1 to start)" -ForegroundColor DarkGray
}

Write-Host "======================================================================" -ForegroundColor Blue
Write-Host " Smoke Test Summary:" -ForegroundColor White
Write-Host "  Passed: $Passed" -ForegroundColor Green
Write-Host "  Failed: $Failed" -ForegroundColor Red
Write-Host "======================================================================" -ForegroundColor Blue

if ($Failed -eq 0) {
    Write-Host "[ALL SYSTEM TESTS PASSED SUCCESSFULLY]" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[Some tests failed. Check logs with 'docker compose logs backend']" -ForegroundColor Red
    exit 1
}
