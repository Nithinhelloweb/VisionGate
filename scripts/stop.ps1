# ==============================================================================
# VisionGate / Attenda - Safe Container Shutdown (PowerShell / Windows)
# ==============================================================================

Write-Host "======================================================================" -ForegroundColor Blue
Write-Host " VisionGate / Attenda — Safe Graceful Shutdown (PowerShell)          " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Blue

Write-Host "Stopping all VisionGate containers (preserving database and model storage)..." -ForegroundColor Yellow
docker compose --profile tunnel stop

Write-Host "Removing stopped containers..." -ForegroundColor Yellow
docker compose --profile tunnel down --remove-orphans

Write-Host "`n======================================================================" -ForegroundColor Green
Write-Host "  [✓] All VisionGate services have stopped safely.                    " -ForegroundColor Green
Write-Host "  Persistent volumes (Postgres DB, InsightFace Models) are intact.    " -ForegroundColor Green
Write-Host "======================================================================`n" -ForegroundColor Green
