# GPU Setup Guide (CUDA 13.x & NVIDIA Blackwell RTX 50-Series)

This guide helps configure the backend environment to run GPU-accelerated face recognition (InsightFace) on systems equipped with NVIDIA Blackwell GPUs (e.g., RTX 5070 / compute capability `sm_120`) running CUDA 13.x on Linux.

## Root Cause of Incompatibilities
1. **PyTorch:** Default PyTorch binaries from standard PyPI builds target CUDA 12.1 or 12.4, which lack compatibility with the new Blackwell `sm_120` architecture.
2. **ONNX Runtime (GPU):** Standard PyPI `onnxruntime-gpu` releases target CUDA 12.x and fail to find the CUDA 13.x libraries (e.g., expecting `libcudart.so.12` instead of `libcudart.so.13`).

---

## Prerequisites
- **OS:** Linux
- **Driver Version:** `>= 580.x` (supporting CUDA 13.x)
- **CUDA Toolkit:** `13.x`
- **cuDNN:** `9.x` (matching the installed CUDA toolkit version)

---

## Installation & Setup

We have provided an automated script `setup_cuda13.sh` to install all compatible binaries.

### Step 1: Execute the Setup Script
Make the script executable and run it:
```bash
chmod +x setup_cuda13.sh
./setup_cuda13.sh
```

### Step 2: Manual Installation (Alternative)
If you prefer running commands manually, run:
```bash
# 1. Uninstall older/incompatible packages
pip uninstall -y torch torchvision torchaudio onnxruntime onnxruntime-gpu

# 2. Install PyTorch with CUDA 13.0 support
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130

# 3. Install ONNX Runtime GPU (CUDA 13 Nightly Build)
pip install coloredlogs flatbuffers numpy packaging protobuf sympy
pip install --pre --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/ort-cuda-13-nightly/pypi/simple/ onnxruntime-gpu
```

---

## Verification
You can verify that PyTorch and ONNX Runtime are successfully utilizing the GPU by running:
```bash
python3 -c "
import torch
print('PyTorch version:', torch.__version__)
print('CUDA available in PyTorch:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('Device Name:', torch.cuda.get_device_name(0))
    print('Device Capability:', torch.cuda.get_device_capability(0))

import onnxruntime as ort
print('ONNX Runtime providers:', ort.get_available_providers())
"
```

**Expected output:**
- `CUDA available in PyTorch: True`
- `Device Capability: (12, 0)` (or similar corresponding to `sm_120`)
- `ONNX Runtime providers:` must include `'CUDAExecutionProvider'`
