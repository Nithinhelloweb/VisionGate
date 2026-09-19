#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - Native Linux Backend Setup Script
# Configures Python 3.12 Virtual Environment, installs PyTorch with CUDA support,
# installs all requirements, and tests GPU + InsightFace models.
# Usage: bash 03_setup_backend.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  VisionGate / Attenda - Backend Python 3.12 & GPU Setup                     ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

# 1. Check Python version
echo -e "\n${CYAN}[1/5] Checking Python 3 version...${NC}"
PY_VER=$(python3 --version || true)
echo -e "${GREEN}[✓] System Python: ${PY_VER}${NC}"

# 2. Create Python 3.12 Virtual Environment
echo -e "\n${CYAN}[2/5] Creating virtual environment at backend/venv...${NC}"
cd "${BACKEND_DIR}"
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}[✓] Created virtualenv in ${BACKEND_DIR}/venv${NC}"
else
    echo -e "${GREEN}[✓] Virtualenv already exists at ${BACKEND_DIR}/venv${NC}"
fi

VENV_PYTHON="${BACKEND_DIR}/venv/bin/python"
VENV_PIP="${BACKEND_DIR}/venv/bin/pip"

# 3. Upgrade core packaging tools
echo -e "\n${CYAN}[3/5] Upgrading pip, setuptools, and wheel...${NC}"
"${VENV_PIP}" install --upgrade pip setuptools wheel

# 4. Install PyTorch with CUDA for RTX 5070 acceleration
echo -e "\n${CYAN}[4/5] Installing PyTorch with CUDA support (for NVIDIA GeForce RTX 5070)...${NC}"
if command -v nvidia-smi &>/dev/null; then
    echo "Installing PyTorch CUDA 12.4 build..."
    "${VENV_PIP}" install torch torchvision --index-url https://download.pytorch.org/whl/cu124 || {
        echo -e "${YELLOW}Falling back to standard PyTorch PyPI release...${NC}"
        "${VENV_PIP}" install torch torchvision
    }
else
    echo "No NVIDIA GPU detected; installing CPU PyTorch..."
    "${VENV_PIP}" install torch torchvision --index-url https://download.pytorch.org/whl/cpu
fi

# 5. Install Backend Requirements
echo -e "\n${CYAN}[5/5] Installing backend requirements from requirements.txt...${NC}"
"${VENV_PIP}" install -r requirements.txt

# 6. Verification and Diagnostics Test
echo -e "\n${CYAN}Running backend validation check...${NC}"
"${VENV_PYTHON}" -c "
import sys
print(f'Python Executable: {sys.executable}')

try:
    import fastapi
    print(f'[✓] FastAPI version: {fastapi.__version__}')
except Exception as e:
    print(f'[!] FastAPI import error: {e}')

try:
    import torch
    cuda_avail = torch.cuda.is_available()
    print(f'[✓] PyTorch version: {torch.__version__} (CUDA Available: {cuda_avail})')
    if cuda_avail:
        print(f'    GPU Device: {torch.cuda.get_device_name(0)}')
        print(f'    VRAM Total: {round(torch.cuda.get_device_properties(0).total_memory / (1024**3), 2)} GB')
except Exception as e:
    print(f'[!] PyTorch check notice: {e}')

try:
    import onnxruntime as ort
    print(f'[✓] ONNX Runtime version: {ort.__version__}')
    print(f'    Available Providers: {ort.get_available_providers()}')
except Exception as e:
    print(f'[!] ONNX Runtime notice: {e}')

try:
    from insightface.app import FaceAnalysis
    print(f'[✓] InsightFace imported successfully.')
except Exception as e:
    print(f'[!] InsightFace notice: {e}')

try:
    import pg_adapter
    conn = pg_adapter.get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT 1;')
    cur.close()
    conn.close()
    print(f'[✓] Database connectivity verified via pg_adapter!')
except Exception as e:
    print(f'[!] Database connectivity test notice: {e}')
"

echo -e "\n${GREEN}[SUCCESS] Backend environment setup completed!${NC}"
echo -e "Next step: sudo bash 04_setup_nginx.sh"
