#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Container Entrypoint Script
# ==============================================================================
set -e

echo "======================================================================"
echo " Starting VisionGate Backend Service"
echo " Date/Time: $(date)"
echo " Host: $(hostname)"
echo "======================================================================"

# Target PostgreSQL connection parameters
PG_HOST="${PG_HOST:-postgres}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-attenda}"
PG_DB="${PG_DB:-attenda}"
PORT="${PORT:-8001}"

echo "[1/4] Waiting for PostgreSQL database at ${PG_HOST}:${PG_PORT}..."
MAX_RETRIES=60
RETRY_COUNT=0

until nc -z -w3 "$PG_HOST" "$PG_PORT" >/dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        echo "ERROR: Timed out waiting for PostgreSQL at ${PG_HOST}:${PG_PORT} after ${MAX_RETRIES} attempts." >&2
        exit 1
    fi
    echo "  -> Waiting for database connection... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 1
done

echo "  -> Database network port is open and ready."

echo "[2/4] Executing Database Migrations & Initial Setup..."
python3 run_migrations.py

echo "[3/4] Verifying Hardware & GPU Runtime Acceleration..."
python3 -c "
import sys
import torch

print('  -> Python version:', sys.version.split()[0])
print('  -> PyTorch version:', torch.__version__)
cuda_ok = torch.cuda.is_available()
print('  -> PyTorch CUDA available:', cuda_ok)

if cuda_ok:
    print('  -> GPU Device Name:', torch.cuda.get_device_name(0))
    print('  -> CUDA Capability:', torch.cuda.get_device_capability(0))
    print('  -> Allocated VRAM:', round(torch.cuda.memory_allocated(0)/(1024**2), 2), 'MB')
else:
    print('  -> NOTE: PyTorch running in CPU mode (GPU passthrough not detected or disabled)')

try:
    import onnxruntime as ort
    providers = ort.get_available_providers()
    print('  -> ONNX Runtime Available Providers:', providers)
    if 'CUDAExecutionProvider' in providers:
        print('  -> ONNX CUDAExecutionProvider: READY (Hardware Accelerated Face Inference)')
    else:
        print('  -> ONNX CUDAExecutionProvider: Fallback to CPUExecutionProvider')
except Exception as e:
    print('  -> ONNX Runtime diagnostic warning:', e)
"

echo "[4/4] Launching Uvicorn Server on 0.0.0.0:${PORT}..."
exec uvicorn main:app \
    --host 0.0.0.0 \
    --port "${PORT}" \
    --loop asyncio \
    --limit-concurrency 100 \
    --timeout-keep-alive 30
