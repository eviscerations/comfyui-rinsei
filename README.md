# comfyui-rinsei

**ComfyUI for AMD RDNA2 on Windows — gfx1031 (RX 6700 XT) confirmed working.**

This repository documents the working configuration and install path for running ComfyUI on AMD RDNA2 GPUs under ROCm on Windows — specifically targeting video generation with Wan 2.2 I2V, including SVI long-video workflows. It serves as a reference for users on hardware that the official portable build does not support.

---

## Mission

The goal of this project is to unlock AMD RDNA2 GPUs for AI video generation — starting with the RX 6700 XT (gfx1031) and working toward broader hardware support.

The official ComfyUI portable build ships `comfy_kitchen`, a closed-source kernel acceleration package with pre-compiled HIP kernels for gfx1030 only. On gfx1031, every GPU dispatch fails at the kernel level. This repository documents how to work around that and get a fully functional video generation stack running.

Beyond gfx1031, there is a clear quantization pathway that may extend this further. GGUF quantization allows progressively smaller model files:

- **Q5/Q4 (~9-11GB):** Equivalent step time to Q3 — compute-bound, not memory-bound
- **Q3_K_M (~6.7GB for 14B):** Confirmed working on 12GB RDNA2. Enough free VRAM headroom for split attention at 480×832.
- **Q2_K (~4.6GB for 14B):** Theoretical target for 8GB cards. With a ~3.4GB GGUF text encoder, the full model stack fits within 8GB with room for compute.
- **Q1 and below:** Experimental. Quality degrades significantly but may be the path to 6GB cards.

This means cards like the RX 6600 (8GB) and potentially older RDNA1 hardware may be reachable with additional quantization work. The Vega 56 (gfx900) is also being explored via a Vulkan inference pathway that bypasses ROCm entirely.

---

## Status

| Component | Status |
|---|---|
| GPU inference (gfx1031) | ✅ Confirmed working |
| SD 1.5 / SDXL image generation | ✅ Confirmed working |
| LoRA support | ✅ Confirmed working |
| Wan 2.2 I2V video generation | ✅ Confirmed working |
| Wan 2.2 SVI multi-section long video | ✅ Confirmed working (~40s per 8-section run) |
| LTX Video | 🔧 Planned — targets 8GB+ cards |
| Hunyuan Video | 🔧 Planned |
| Q2KM re-quantization | 🔧 Planned |
| RDNA2-optimized workflow release | 🔧 In progress |
| Vega 56 / gfx900 Vulkan pathway | 🔧 Experimental |
| Custom UI | 🔧 In progress |

---

## Hardware

Tested on:
- GPU: AMD Radeon RX 6700 XT (gfx1031, RDNA2, 12GB GDDR6)
- OS: Windows 10 Pro 22H2
- Driver: Adrenalin 26.6.1 (32.0.21043.12001)
- Python: 3.12.10 (embedded)

---

## Working Package Stack

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
| comfy-kitchen | ❌ must be uninstalled |

**Index:** `https://rocm.nightlies.amd.com/v2-staging/gfx103X-all/`

---

## Install

### Step 1 — Download the official ComfyUI AMD portable

**[ComfyUI_windows_portable_amd.7z](https://github.com/Comfy-Org/ComfyUI/releases/latest/download/ComfyUI_windows_portable_amd.7z)**

Extract to your desired location.

### Step 2 — Clone this repo

Copy `comfyui_rinsei.bat` and `extra_model_paths.yaml.example` into your ComfyUI directory.

### Step 3 — Install ROCm packages

Open a command prompt in your ComfyUI directory. Use `--no-deps` on every pip call — without it, pip backtracks through months of nightly builds.

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

`comfy_kitchen` must be uninstalled. `comfy-aimdo` must remain — ComfyUI 0.23.0 has a hard import of it in `main.py`.

```bat
python_embeded\python.exe -m pip uninstall comfy_kitchen -y
python_embeded\python.exe -m pip install comfy-aimdo
```

### Step 5 — Configure model paths

Copy `extra_model_paths.yaml.example` to `extra_model_paths.yaml` and edit paths.

### Step 6 — Launch

Run `comfyui_rinsei.bat`.

---

## Launch Configuration

```bat
@echo off
setlocal enabledelayedexpansion

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

set GPU_MAX_HEAP_SIZE=100
set GPU_MAX_ALLOC_PERCENT=100
set PYTORCH_HIP_ALLOC_CONF=expandable_segments:True

cd /d %COMFYUI_DIR%
python_embeded\python.exe main.py --use-quad-cross-attention --front-end-root web %*
```

---

## Custom Node Packs

### Essential for video generation

These are required to run Wan 2.2 I2V and SVI workflows. Install via ComfyUI Manager or git clone into `custom_nodes/`.

| Pack | Purpose |
|---|---|
| [ComfyUI-GGUF](https://github.com/city96/ComfyUI-GGUF) | Loads all GGUF-format models. Required for both diffusion models and text encoders on ROCm. |
| [ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes) | `LazySwitchKJ`, `GetNode`, `SetNode` — used by nearly all SVI workflows for routing and state distribution. |
| [ComfyUI-VideoHelperSuite](https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite) | `VHS_VideoCombine` for video output. Standard for all video workflows. |
| [ComfyUI-Wan22FMLF](https://github.com/wallen0322/ComfyUI-Wan22FMLF) | Provides `WanImageToVideoSVIPro` — the core SVI temporal continuity node. Required for any SVI long-video workflow. |
| [ComfyUI-Frame-Interpolation](https://github.com/Fannovel16/ComfyUI-Frame-Interpolation) | RIFE and FILM frame interpolation for smoother output. |
| [rgthree-comfy](https://github.com/rgthree/rgthree-comfy) | `SetNode`/`GetNode`/`Power Lora Loader`/`Fast Groups Bypasser` — used heavily in SVI workflow architectures. |

### Recommended

| Pack | Purpose |
|---|---|
| [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) | Install and manage all other packs from within the UI. |
| [ComfyUI-Crystools](https://github.com/crystian/ComfyUI-Crystools) | Live GPU/VRAM/CPU stats in the header bar. Useful for monitoring ROCm utilization. |
| [ComfyUI-Custom-Scripts](https://github.com/pythongosssss/ComfyUI-Custom-Scripts) | `MathExpression\|pysssss` and other utilities used by many workflows. |
| [ComfyUI-Easy-Use](https://github.com/yolain/ComfyUI-Easy-Use) | Convenience nodes that simplify common patterns. |
| [comfyui_essentials](https://github.com/cubiq/comfyui_essentials) | `ImageFromBatch+`, batch manipulation, and other utility nodes. |
| [was-node-suite-comfyui](https://github.com/WASasquatch/was-node-suite-comfyui) | Large general-purpose pack (220+ nodes). |
| [comfy-mtb](https://github.com/melMass/comfy_mtb) | `Pick From Batch` and other frame/batch operations. |
| [comfyui_fill-nodes](https://github.com/filliptm/ComfyUI_Fill-Nodes) | `FL_RIFE` interpolation variant. |
| [ComfyUI-Lora-Manager](https://github.com/willmiao/ComfyUI-Lora-Manager) | LoRA browser with CivitAI metadata sidecar support and filtering. |
| [comfyui-find-perfect-resolution](https://github.com/ashtar1984/comfyui-find-perfect-resolution) | Automatically calculates optimal generation resolution from source image aspect ratio. |

---

## Confirmed Working Models

### Diffusion Models

GGUF format is required. fp8 and standard safetensors require `comfy_kitchen` and will crash on ROCm.

Load via `UnetLoaderGGUF` (from ComfyUI-GGUF). Wan 2.2 I2V requires two files — High Noise and Low Noise — both loaded and run sequentially per generation pass.

**Quantization guide for 12GB cards:**

| Quantization | Approx. size | Free compute VRAM | Split attn at 480×832 |
|---|---|---|---|
| Q5_K_M | ~10.8GB | ~1.2GB | ✗ |
| Q4_K_S | ~8.75GB | ~3.25GB | ✗ |
| Q3_K_M | ~6.7GB | **~5.3GB** | ✅ |

Q3_K_M is the recommended quantization for 12GB cards. Higher quantizations offer no speed improvement and leave insufficient compute VRAM headroom.

Example of confirmed working Q3KM I2V GGUF pair: `https://civitai.com/models/2472759`

### Text Encoders

Wan 2.2 uses a umt5-xxl text encoder. Load via `CLIPLoaderGGUF`.

| Format | Status | Notes |
|---|---|---|
| GGUF Q4/Q5 (~3.4-4.1GB) | ✅ Works | Recommended. Load with `CLIPLoaderGGUF`. |
| fp16 safetensors (~11.4GB) | ⚠️ Works but costly | Loads correctly via `CLIPLoader`, but causes high system RAM usage (~27GB+) during multi-section SVI runs. |
| fp8 safetensors | ❌ Crashes | Requires `comfy_kitchen`. Fails with `AttributeError: 'NoneType' object has no attribute 'Params'`. |

### VAE

- `Wan2_1_VAE_fp32.safetensors` — confirmed working for all 14B I2V workflows. Available from standard Wan 2.1/2.2 model repositories.

### Clip Vision

- `clip_vision_h.safetensors` — standard clip vision model used for image conditioning in I2V workflows.

### LoRAs for SVI

SVI temporal continuity requires specific LoRAs trained for it. Without them, motion across section boundaries degrades significantly. Both High Noise and Low Noise variants are required.

Available from Kijai's model repository: `https://huggingface.co/Kijai/WanVideo_comfy/tree/main/LoRAs/Stable-Video-Infinity/v2.0`

---

## Wan 2.2 I2V Video Generation

### Attention Mode

`--use-quad-cross-attention` in the bat file is required for stable multi-frame generation at higher resolutions. Split attention (`--use-split-cross-attention`) OOMs beyond certain frame count / resolution combinations on 12GB.

Confirmed working with split attention and Q3KM:
- 17 frames at 480×832: ~28s/step
- 33 frames at 352×608: ~25s/step

For longer clips and higher resolutions, use quad attention (~240–480s/step depending on resolution, no OOM risk).

### SVI Architecture

SVI (Stable-Video-Infinity) maintains temporal coherence across multiple sequential generation sections. Rather than extracting the last frame of each clip and encoding it back through the VAE as the start of the next (which causes quality degradation), SVI passes the raw latent tensor from the end of each section into the next section's denoising process.

This preserves motion direction, lighting structure, and spatial continuity at the latent level — information that would otherwise be destroyed by a full VAE decode/encode round trip.

The `WanImageToVideoSVIPro` node (ComfyUI-Wan22FMLF) handles this. Each section receives `prev_samples` from the previous section and outputs both decoded frames and a new latent for the following section.

Each section generates 81 frames at 16fps (~5 seconds). An 8-section workflow produces approximately 40 seconds of raw output in a single run.

**Multi-prompt workflows** allow per-section text conditioning, enabling narrative control across the full clip. Each section's prompt describes what is happening in that ~5-second window. Search for SVI + I2V + Wan 2.2 workflows that support per-section prompting.

### RDNA2-Specific Workflow Fix

Many SVI workflows embed a `CLIPLoader` inside a ComfyUI subgraph definition, pointed at an fp8 safetensors text encoder. This fails on ROCm. The fix requires editing the workflow JSON directly:

In `definitions.subgraphs[0].nodes`, find the `CLIPLoader` node and change:
- `type`: `CLIPLoader` → `CLIPLoaderGGUF`
- `widgets_values`: `["umt5_xxl_fp8_e4m3fn_scaled.safetensors", "wan", "default"]` → `["your_gguf_encoder.gguf", "wan"]`

This change is not visible from the main ComfyUI canvas — it must be made in the JSON or by expanding the subgraph node via its expand icon.

An RDNA2-optimized workflow with this fix pre-applied is planned for release from this repository.

---

## Known Issues / Gotchas

**torchvision version matters.** `torchvision 0.27.0` with `torch 2.10.0` causes a DLL load failure. Use `0.25.0`.

**`--no-deps` is required** when installing from the nightly index. Without it, pip backtracks through months of builds.

**The mediafire wheels from patientx/ComfyUI-Zluda #435 are corrupt.** `BadZipFile: Bad CRC-32`.

**`rocm.devreleases.amd.com` dev0 wheels 404.** Listed in the index but files don't exist.

**`gfx103X-dgpu` is the old index**, replaced by `gfx103X-all` on 2026.04.22. Old index wheels have broken gfx1031 kernels.

**`comfy-aimdo` cannot be uninstalled.** ComfyUI 0.23.0 has a hard import of it in `main.py`.

**MIOpen CK grouped conv warning is harmless.** `MIOpen(HIP): Warning [OpenRuntimeLibraryForDevice] CK grouped conv library not found for device gfx1031` — appears on every run, no effect on generation.

**MIOpen kernel cache warmth.** The first generation in a cold session takes significantly longer (~1075s/step observed vs ~250s/step warm) while MIOpen tunes and caches kernels for the specific operation shapes being run. This is expected ROCm behavior and improves on subsequent runs.

**SageAttention is incompatible.** Requires CUDA/Triton. Any `PathchSageAttentionKJ` nodes in a workflow must be set to disabled.

---

## Performance

**Image generation — SD 1.5, 512×768, 28 steps:**
- 1.70 it/s / 22.54s per image

**Video — Wan 2.2 I2V, 480×832, 17 frames, Q3KM, split attention (warm):**
- ~28s/step

**Video — Wan 2.2 SVI, quad attention, warm MIOpen cache:**
- ~242–263s/step per KSampler pass
- 8 sections × 2 passes ≈ 3.5 hours → ~40 seconds output

---


## UI Customization

The default ComfyUI frontend includes Firebase authentication, a cloud template marketplace, an onboarding modal, and a login button — none of which are relevant to a fully local workflow. These have been removed by rebuilding the frontend from source.

**Removed from the frontend:**
- Login/account button (top menu bar)
- Templates button (left sidebar)
- Firebase dependency and authentication system (`firebase` 11.6.0)
- Cloud template marketplace (`comfyui-workflow-templates`)
- Onboarding modal

**Color palette:**

`ui/rinsei-dark-palette.json` is the dark purple/black color scheme. Import it via Settings → Color Palette → Import. Note: ComfyUI 0.23.0+ uses shadcn/ui for some panels (sidebar, node inspector) with its own CSS variable system (`--background`, `--card`, `--popover`, etc.) separate from the LiteGraph palette — these panels may show white until a frontend rebuild is applied.

**Rebuilding the frontend:**

```bat
cd C:\dev\comfyui-rinsei-frontend
pnpm run build
:: Copy dist/ to your ComfyUI web/ directory
:: Launch ComfyUI with --front-end-root web in the bat file
```

**Planned:**
- Custom model browser (reads `.civitai.info` sidecars, filters by base model type — equivalent to A1111's checkpoint/LoRA tabs)
- Local workflow template panel (replaces cloud templates with a local directory read)
- Missing node pack installer

## Credits

- [patientx-cfz/comfyui-rocm](https://github.com/patientx-cfz/comfyui-rocm) — ROCm Windows path research
- [patientx/ComfyUI-Zluda #435](https://github.com/patientx/ComfyUI-Zluda/issues/435) — gfx103X community research
- [Comfy-Org/ComfyUI](https://github.com/Comfy-Org/ComfyUI) — upstream
- [city96/ComfyUI-GGUF](https://github.com/city96/ComfyUI-GGUF) — GGUF model loading
- [kijai/ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes) — utility nodes
- [kijai/WanVideo_comfy](https://huggingface.co/Kijai/WanVideo_comfy) — SVI LoRAs and model resources
- [wallen0322/ComfyUI-Wan22FMLF](https://github.com/wallen0322/ComfyUI-Wan22FMLF) — WanImageToVideoSVIPro node
