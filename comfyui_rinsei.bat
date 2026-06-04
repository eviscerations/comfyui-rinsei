@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: comfyui-rinsei launch script — AMD RDNA2 gfx1031 (RX 6700 XT)
:: Edit COMFYUI_DIR below to match your install path
:: ============================================================

set COMFYUI_DIR=C:\comfyui-rinsei

:: gfx1031 RDNA2 core overrides
set HSA_OVERRIDE_GFX_VERSION=10.3.0
set AMDGPU_TARGETS=gfx1031
set HIP_VISIBLE_DEVICES=0
set ROCR_VISIBLE_DEVICES=0

:: Disable incompatible SDP backends for RDNA2
set TORCH_BACKENDS_CUDA_FLASH_SDP_ENABLED=0
set TORCH_BACKENDS_CUDA_MEM_EFF_SDP_ENABLED=0
set TORCH_BACKENDS_CUDA_MATH_SDP_ENABLED=1

:: MIOpen tuning
set MIOPEN_FIND_ENFORCE=1
set MIOPEN_FIND_MODE=2
set MIOPEN_SEARCH_CUTOFF=1
set MIOPEN_ENABLE_LOGGING=0

cd /d %COMFYUI_DIR%
python_embeded\python.exe main.py --disable-smart-memory --disable-pinned-memory --use-quad-cross-attention --cache-none %*
