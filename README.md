# comfyui-rinsei

**ComfyUI for AMD RDNA2 on Windows — gfx1031 (RX 6700 XT) confirmed working.**

A custom fork of ComfyUI built for AMD GPUs that the official portable build doesn't support. Strips cloud bloat, fixes the kernel dispatch problem, and runs local-first.

---

## Status

| Component | Status |
|---|---|
| GPU inference (gfx1031) | ✅ Working |
| SD1.5 / SDXL generation | ✅ Working |
| LoRA support | ✅ Working |
| Video (Wan 2.2 I2V) | 🔧 In progress |
| Custom UI | 🔧 In progress |

---

## The Problem This Solves

The official Comfy-Org portable build ships `comfy_kitchen` — a closed-source kernel acceleration package with pre-compiled HIP kernels for gfx1030 only. On gfx1031 (RX 6700 XT), every GPU dispatch fails with `hipErrorInvalidImage`. `HSA_OVERRIDE_GFX_VERSION=10.3.0` fixes device detection but not kernel execution.

Additionally, the `gfx103X-dgpu` nightly index was replaced by `gfx103X-all` on 2026.04.22. The old index wheels have broken kernels for gfx1031. The new index works.

---

## Working Stack

Tested on:
- GPU: AMD Radeon RX 6700 XT (gfx1031, RDNA2, 12GB GDDR6)
- OS: Windows 10 Pro 22H2
- Driver: Adrenalin 26.6.1
- Python: 3.12.10 (embedded)

| Package | Version |
|---|---|
| torch | 2.10.0+rocm7.14.0a20260603 |
| torchvision | 0.25.0+rocm7.14.0a20260603 |
| torchaudio | 2.11.0+rocm7.14.0a20260603 |
| rocm | 7.14.0a20260603 |
| rocm-sdk-core | 7.14.0a20260603 |
| rocm-sdk-devel | 7.14.0a20260603 |
| rocm-sdk-libraries-gfx103X-all | 7.14.0a20260603 |
| comfy-aimdo | 0.4.8 |
| comfy-kitchen | ❌ uninstalled |

**Index:** `https://rocm.nightlies.amd.com/v2-staging/gfx103X-all/`

---

## Install

### Step 1 — Download the official ComfyUI AMD portable

**[ComfyUI_windows_portable_amd.7z](https://github.com/Comfy-Org/ComfyUI/releases/latest/download/ComfyUI_windows_portable_amd.7z)**

Extract with [7-Zip](https://7-zip.org) to your desired location, e.g. `C:\comfyui-rinsei`.

### Step 2 — Clone this repo

Copy `comfyui_rinsei.bat` and `extra_model_paths.yaml.example` into your extracted ComfyUI directory.

### Step 3 — Install ROCm packages

Open a command prompt in your ComfyUI directory. Use `--no-deps` on every call — without it, pip backtracks through hundreds of nightly wheels and downloads gigabytes.

```bat
python_embeded\python.exe -m pip install --force-reinstall ^
  "torch==2.10.0+rocm7.14.0a20260603" ^
  "torchaudio==2.11.0+rocm7.14.0a20260603" ^
  --index-url https://rocm.nightlies.amd.com/v2-staging/gfx103X-all/ --no-deps

python_embeded\python.exe -m pip install --force-reinstall ^
  "torchvision==0.25.0+rocm7.14.0a20260603" ^
  --index-url https://rocm.nightlies.amd.com/v2-staging/gfx103X-all/ --no-deps

python_embeded\python.exe -m pip install --force-reinstall ^
  "rocm==7.14.0a20260603" ^
  "rocm-sdk-core==7.14.0a20260603" ^
  "rocm-sdk-devel==7.14.0a20260603" ^
  "rocm-sdk-libraries-gfx103X-all==7.14.0a20260603" ^
  --index-url https://rocm.nightlies.amd.com/v2-staging/gfx103X-all/ --no-deps
```

### Step 4 — Fix comfy_kitchen

`comfy_kitchen` must be uninstalled. `comfy-aimdo` must stay — it is a hard import in `main.py`.

```bat
python_embeded\python.exe -m pip uninstall comfy_kitchen -y
python_embeded\python.exe -m pip install comfy-aimdo
```

### Step 5 — Configure model paths

Copy `extra_model_paths.yaml.example` to `extra_model_paths.yaml` and edit the paths to point at your model directories.

### Step 6 — Launch

Edit `comfyui_rinsei.bat` and set `COMFYUI_DIR` to your install path. Then run it.

---

## Launch Configuration

`comfyui_rinsei.bat` is included in this repo. Edit `COMFYUI_DIR` at the top to match your install path.

```bat
@echo off
setlocal enabledelayedexpansion

set COMFYUI_DIR=C:\comfyui-rinsei

set HSA_OVERRIDE_GFX_VERSION=10.3.0
set AMDGPU_TARGETS=gfx1031
set HIP_VISIBLE_DEVICES=0
set ROCR_VISIBLE_DEVICES=0
set TORCH_BACKENDS_CUDA_FLASH_SDP_ENABLED=0
set TORCH_BACKENDS_CUDA_MEM_EFF_SDP_ENABLED=0
set TORCH_BACKENDS_CUDA_MATH_SDP_ENABLED=1
set MIOPEN_FIND_ENFORCE=1
set MIOPEN_FIND_MODE=2
set MIOPEN_SEARCH_CUTOFF=1
set MIOPEN_ENABLE_LOGGING=0

cd /d %COMFYUI_DIR%
python_embeded\python.exe main.py --disable-smart-memory --disable-pinned-memory --use-quad-cross-attention --cache-none %*
```

---

## Known Issues / Gotchas

**torchvision version matters.** `torchvision 0.27.0` with `torch 2.10.0` causes a DLL load failure (`operator torchvision::nms does not exist`). Must use `0.25.0`.

**Do not use `--force-reinstall` without `--no-deps` on the index URL.** Pip will backtrack through every nightly build from the last 6 months and download gigabytes before giving up or selecting something wrong.

**The mediafire wheels from patientx/ComfyUI-Zluda #435 are corrupt.** `rocm-sdk-core-7.12.0.dev0` fails with `zipfile.BadZipFile: Bad CRC-32`. Do not attempt to use them.

**The `rocm.devreleases.amd.com` dev0 wheels all 404.** The index lists them but the files don't exist.

**`gfx103X-dgpu` is the old index.** It was replaced by `gfx103X-all` on 2026.04.22. Wheels from the old index have broken gfx1031 kernels.

**`comfy-aimdo` cannot be uninstalled.** ComfyUI 0.23.0 has a hard `import comfy_aimdo.control` in `main.py`. Uninstalling it crashes on startup.

---

## Performance

SD1.5 512×768, 28 steps, DPM++ 2M ancestral, exponential scheduler:
- **1.70 it/s**
- **22.54s per image**

---

## Roadmap

- [ ] Wan 2.2 I2V workflow support
- [ ] Custom UI — strip Firebase/cloud/login/templates
- [ ] Local model browser with CivitAI sidecar support
- [ ] Missing node pack installer
- [ ] CivitAI download integration

---

## Credits

- [patientx-cfz/comfyui-rocm](https://github.com/patientx-cfz/comfyui-rocm) — ROCm Windows path
- [patientx/ComfyUI-Zluda #435](https://github.com/patientx/ComfyUI-Zluda/issues/435) — gfx103X community research
- [Comfy-Org/ComfyUI](https://github.com/Comfy-Org/ComfyUI) — upstream
