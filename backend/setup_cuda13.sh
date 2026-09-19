#!/bin/bash
# Script to install CUDA 13.x compatible PyTorch and ONNX Runtime GPU
# for Blackwell GPUs (RTX 5070 / sm_120) on Linux.

echo "=== Uninstalling existing PyTorch and ONNX Runtime packages ==="
pip uninstall -y torch torchvision torchaudio onnxruntime onnxruntime-gpu

echo "=== Installing PyTorch for CUDA 13.0 ==="
# Installs PyTorch built against CUDA 13.0
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130

echo "=== Installing ONNX Runtime GPU (CUDA 13 Nightly) ==="
# Installs ONNX Runtime GPU built against CUDA 13
pip install coloredlogs flatbuffers numpy packaging protobuf sympy
pip install --pre --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/ort-cuda-13-nightly/pypi/simple/ onnxruntime-gpu

echo "=== Verifying CUDA & GPU support ==="
python3 -c "
import torch
print('PyTorch version:', torch.__version__)
print('CUDA available in PyTorch:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('Device Name:', torch.cuda.get_device_name(0))
    print('Device Capability:', torch.cuda.get_device_capability(0))

try:
    import onnxruntime as ort
    print('ONNX Runtime providers:', ort.get_available_providers())
    if 'CUDAExecutionProvider' in ort.get_available_providers():
        print('ONNX Runtime CUDA provider is available!')
    else:
        print('WARNING: ONNX Runtime CUDA provider is NOT available.')
except Exception as e:
    print('ONNX Runtime check failed:', e)
"
