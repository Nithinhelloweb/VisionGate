# ==============================================================================
# VisionGate / Attenda — Universal Log Viewer (PowerShell)
# Tails logs for all containers or specific service with real-time stream
# ==============================================================================

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("all", "backend", "cloudflared", "postgres", "nginx", "tunnel", "db", "app", "")]
    [string]$Service = "all",

    [Parameter(Position = 1)]
    [int]$Lines = 100,

    [switch]$NoFollow
)

# Normalize service alias
$target = switch ($Service.ToLower()) {
    "backend"     { "backend" }
    "app"         { "backend" }
    "cloudflared" { "cloudflared" }
    "tunnel"      { "cloudflared" }
    "postgres"    { "postgres" }
    "db"          { "postgres" }
    "nginx"       { "nginx" }
    default       { "" }
}

Write-Host "======================================================================" -ForegroundColor Blue
Write-Host " VisionGate / Attenda - Container Log Inspector" -ForegroundColor Cyan
if ($target) {
    Write-Host " Target Service: $target | Lines: $Lines" -ForegroundColor Yellow
} else {
    Write-Host " Target: All Active Containers (Unified Stream) | Lines: $Lines" -ForegroundColor Yellow
}
Write-Host "======================================================================" -ForegroundColor Blue

$argsList = @("logs", "--tail", "$Lines")
if (-not $NoFollow) {
    $argsList += "-f"
    Write-Host "Streaming logs in real-time (Press Ctrl+C to stop)...`n" -ForegroundColor Gray
}

if ($target) {
    $argsList += $target
}

docker compose @argsList
