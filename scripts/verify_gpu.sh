#!/usr/bin/env bash
# ==============================================================================
# VisionGate / Attenda - GPU Diagnostic & Passthrough Verification Script
# Target: Any NVIDIA GPU Architecture (Blackwell, Ada Lovelace, Ampere, Turing)
# ==============================================================================
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BOLD}${BLUE} VisionGate GPU & Hardware Acceleration Verification Tool            ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# Step 1: Check host NVIDIA driver
echo -e "\n${BOLD}${YELLOW}[1/4] Checking Host NVIDIA Driver...${NC}"
if command -v nvidia-smi &> /dev/null; then
    NVIDIA_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    CUDA_VER=$(nvidia-smi | grep -o "CUDA Version: [0-9.]*" | head -n1 || echo "CUDA Version: Unknown")
    echo -e "  ${GREEN}✓${NC} Detected GPU:     ${GREEN}${GPU_NAME}${NC}"
    echo -e "  ${GREEN}✓${NC} Driver Version:   ${GREEN}${NVIDIA_DRIVER}${NC}"
    echo -e "  ${GREEN}✓${NC} Driver Capability: ${GREEN}${CUDA_VER}${NC}"
else
    echo -e "  ${YELLOW}! nvidia-smi not found on host.${NC}"
    echo -e "    System will run in CPU execution mode (InsightFace and attendance will operate on CPU)."
fi

# Step 2: Check Docker and NVIDIA Container Toolkit
echo -e "\n${BOLD}${YELLOW}[2/4] Checking Docker Runtime & NVIDIA Container Toolkit...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "  ${RED}✗ Docker is not installed.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Docker Version: $(docker --version)"

# Step 3: Test NVIDIA GPU Passthrough with Docker
echo -e "\n${BOLD}${YELLOW}[3/4] Testing GPU passthrough in temporary test container...${NC}"
if docker run --rm --gpus all nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi &> /dev/null; then
    echo -e "  ${GREEN}✓ Standard Docker '--gpus all' passthrough is OPERATIONAL.${NC}"
elif docker run --rm --runtime=nvidia nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04 nvidia-smi &> /dev/null; then
    echo -e "  ${GREEN}✓ Docker NVIDIA runtime passthrough is OPERATIONAL.${NC}"
else
    echo -e "  ${YELLOW}! GPU container passthrough test did not succeed.${NC}"
    echo -e "    To enable GPU acceleration on Ubuntu Linux:"
    echo -e "      1. sudo apt-get install -y nvidia-container-toolkit"
    echo -e "      2. sudo nvidia-ctk runtime configure --runtime=docker"
    echo -e "      3. sudo systemctl restart docker"
fi

# Step 4: Test PyTorch & ONNX Runtime CUDA Acceleration in Attenda container
echo -e "\n${BOLD}${YELLOW}[4/4] Verifying PyTorch and ONNX Runtime in VisionGate Backend...${NC}"
if docker ps --format '{{.Names}}' | grep -q "^attenda-backend$"; then
    docker exec -t attenda-backend python3 -c "
import sys
import torch

print('  PyTorch Version:', torch.__version__)
print('  PyTorch CUDA available:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('  GPU Device Name:', torch.cuda.get_device_name(0))
    print('  Compute Capability:', torch.cuda.get_device_capability(0))
    print('  Allocated VRAM:', round(torch.cuda.memory_allocated(0)/(1024**2), 2), 'MB')

try:
    import onnxruntime as ort
    providers = ort.get_available_providers()
    print('  ONNX Available Providers:', providers)
    if 'CUDAExecutionProvider' in providers:
        print('  ONNX CUDA Acceleration: OPERATIONAL (Hardware Acceleration Active)')
    else:
        print('  ONNX Execution Provider: CPUExecutionProvider (CPU Fallback Active)')
except Exception as e:
    print('  ONNX Runtime status:', e)
"
    echo -e "\n${GREEN}======================================================================${NC}"
    echo -e "${BOLD}${GREEN}  [✓] Hardware acceleration diagnostic completed successfully!        ${NC}"
    echo -e "${GREEN}======================================================================${NC}\n"
else
    echo -e "  ${YELLOW}Notice: 'attenda-backend' container is not running.${NC}"
    echo -e "  Start the stack with 'bash scripts/deploy.sh' before running container diagnostics."
fi
