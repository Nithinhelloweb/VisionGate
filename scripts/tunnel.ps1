# ==============================================================================
# VisionGate / Attenda - Cloudflare Tunnel Launch & Discovery (PowerShell)
# ==============================================================================

$ErrorActionPreference = "Continue"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

Write-Host "======================================================================" -ForegroundColor Blue
Write-Host " VisionGate / Attenda - Cloudflare Secure Ingress Tunnel Engine" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Blue

# Load .env if present
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
        }
    }
}

if (Test-Path "docker/cloudflared/config.yml") {
    $env:CLOUDFLARE_COMMAND = "tunnel --config /etc/cloudflared/config.yml run"
} elseif ($env:CLOUDFLARE_TUNNEL_TOKEN) {
    $env:CLOUDFLARE_COMMAND = "tunnel --no-autoupdate run --token $($env:CLOUDFLARE_TUNNEL_TOKEN)"
} else {
    $env:CLOUDFLARE_COMMAND = "tunnel --url http://nginx:80 --no-autoupdate"
}

# Determine GPU overlay
$GpuTest = docker run --rm --gpus all nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi 2>&1
if ($LASTEXITCODE -eq 0) {
    $ComposeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.gpu.yml", "--profile", "tunnel")
} else {
    $ComposeArgs = @("-f", "docker-compose.yml", "--profile", "tunnel")
}

Write-Host "`n[*] Starting Cloudflare Tunnel Container..." -ForegroundColor Yellow
& docker compose @ComposeArgs up -d cloudflared

Write-Host "[*] Waiting for tunnel connection and resolving public URL..." -ForegroundColor Yellow
$MaxWait = 30
$Waited = 0
$TunnelUrl = ""

while ($Waited -lt $MaxWait) {
    $Logs = docker logs --tail 50 attenda-cloudflared 2>&1 | Out-String
    if ($Logs -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
        $TunnelUrl = $Matches[0]
        break
    }
    if ($Logs -match 'Registered tunnel connection') {
        $TunnelUrl = if ($env:CLOUDFLARE_DOMAIN) {
            if ($env:CLOUDFLARE_DOMAIN.StartsWith("http")) { $env:CLOUDFLARE_DOMAIN } else { "https://$($env:CLOUDFLARE_DOMAIN)" }
        } else { "https://attenda.srishakthicgpa.in" }
        break
    }
    Start-Sleep -Seconds 2
    $Waited += 2
}

Write-Host ""
if ($TunnelUrl) {
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  CLOUDFLARE TUNNEL ONLINE & OPERATIONAL!" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  Public Tunnel URL: $TunnelUrl" -ForegroundColor Cyan
    Write-Host "  Mobile App Target: $TunnelUrl/health" -ForegroundColor Cyan
    Write-Host "======================================================================`n" -ForegroundColor Green
} else {
    Write-Host "Tunnel is running. View live logs with:" -ForegroundColor Yellow
    Write-Host "  docker compose logs -f cloudflared`n" -ForegroundColor White
}
