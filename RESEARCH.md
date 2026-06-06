# Research Log — Pathways, Dead Ends, and Open Questions

This document covers the investigative work behind comfyui-rinsei: what was tried, what failed, why it failed, and what remains open. The goal is to prevent the community from re-discovering dead ends independently and to provide a clear map of where research is still needed.

---

## Context: Why This Work Matters Now

Consumer access to new AI-capable hardware is deteriorating rapidly due to converging supply chain pressures, most of which are structural rather than temporary.

**Memory and storage:**
Micron announced the complete shutdown of its Crucial consumer memory and SSD product line in December 2025, with shipments ending by February 2026. All Micron DRAM production is now allocated to HBM for AI accelerators. This removed the brand that historically set the retail price floor, leaving a duopoly of Samsung and SK Hynix — both of whom are similarly redirecting capacity toward AI infrastructure. HBM is consuming approximately 23% of global DRAM wafer capacity as of Q1 2026, with projections toward 70% of high-end capacity by end of year. Consumer DDR4 and DDR5 prices have increased dramatically as a result. Samsung has also scaled back SATA SSD production, reallocating NAND flash toward higher-margin datacenter products. Consumer storage and memory are becoming structurally more expensive.

**Semiconductor supply:**
The Iran conflict has disrupted helium supply from Qatar's Ras Laffan facility, which accounts for approximately 35% of global helium production. Semiconductor fabrication is the world's largest consumer of helium — it is non-substitutable in photolithography and thermal management processes. The disruption is estimated to reduce global helium availability by 30% or more. Major manufacturers in Taiwan and South Korea source over 60% of their helium from Qatar. This adds upward cost pressure to new chip production at every node.

**The practical consequence:**
People who already own AMD RDNA2, RDNA1, or Vega hardware are increasingly unable to upgrade affordably. The installed base of cards in the Vega 56/64 through RX 6600/6600 XT range represents millions of machines that are capable of meaningful AI workloads if the software stack can be made to work. AMD has historically provided insufficient ROCm support for consumer cards on Windows. This project documents how to close that gap on existing hardware rather than waiting for hardware prices to normalize.

---

## What Was Tried and Ruled Out

### A1111 + DirectML on Vega 56

**Status:** Partial — works for SD 1.5 inference, does not extend to video generation.

**What works:** AMD's DirectML backend for ONNX Runtime provides GPU-accelerated inference for Stable Diffusion 1.5 and SDXL image generation on Vega hardware via A1111. This was the initial approach and confirmed that GPU acceleration was achievable.

**What doesn't work:** DirectML has no viable path to Wan 2.2 video generation. The video generation stack requires PyTorch with GPU compute, not ONNX Runtime. There is no DirectML backend for PyTorch on Windows. Attempting to bridge between them was explored and ruled out — the two stacks are not compatible at the compute layer.

**Conclusion:** A1111 + DirectML is a working solution for SD1.5 image generation on Vega. It is a dead end for video generation. The investigation confirmed that a completely different approach was needed.

### ZLUDA on RX 6700 XT (gfx1031)

**Status:** Dead end for current workflows.

**What was tried:** ZLUDA provides a CUDA translation layer that maps CUDA calls to HIP/ROCm, allowing CUDA-compiled software to run on AMD hardware. This was investigated as a path to running CUDA-dependent workflows on gfx1031.

**What failed:** ZLUDA on gfx1031 hits a CUTLASS Flash Attention kernel incompatibility. The Flash Attention kernels are compiled for SM80 (NVIDIA Ampere architecture) and cannot execute on AMD hardware through translation. Attempts to run ComfyUI workflows through ZLUDA resulted in hard freezes during the attention computation phase. The freeze is silent — no error, no crash, just a hung process.

**Current status of ZLUDA community efforts:** The patientx/ComfyUI-Zluda repository (#435) documents ongoing community attempts. Prebuilt wheel packages from third-party hosting (mediafire links) are corrupt (BadZipFile CRC errors). The `rocm.devreleases.amd.com` dev0 wheels listed in the index 404. The `gfx103X-dgpu` index was replaced by `gfx103X-all` on 2026.04.22, and wheels from the old index have broken gfx1031 kernels. These were all individually confirmed dead ends before the working path was found.

**Conclusion:** ZLUDA is not a viable path for ComfyUI video generation on gfx1031 at this time.

### ZLUDA on Vega 56 (gfx900) — LoRA Training

**Status:** Partially progressed, hard freeze on kernel compilation.

LoRA training via ZLUDA on gfx900 was attempted with the following stack: HIP SDK 5.7.1, lshqqytiger ZLUDA fork (windows-rocm5-amd64), advanced-lvl-up gfx900 Tensile fix, PyTorch 2.3.1+cu118, kohya_ss v25.2.1. GPU detection confirmed working via PyTorch (`torch.cuda.is_available()` = True, device name = Radeon RX Vega [ZLUDA]).

**Failure 1 — VAE encoding:** Training crashes on first batch with `CUBLAS_STATUS_NOT_SUPPORTED` calling `cublasSgemm`. Single-precision float32 GEMM is not implemented for gfx900 in the current Tensile library. Workaround: pre-encode all training images to `.npz` on CPU, bypass VAE with `cache_latents_to_disk=true`.

**Failure 2 — U-Net silent hang:** With CPU-cached latents, training proceeds further but hangs at step 0 with no error, no GPU activity. Root cause per lshqqytiger: kohya_ss does not preload ZLUDA DLLs (unlike SD.Next/A1111-amdgpu which do so silently). Fix: replace PyTorch's `cublas64_11.dll` in `site-packages/torch/lib/` with the `cublas.dll` shipped in the ZLUDA distribution. Setting `ZLUDA_COMGR_LOG_LEVEL=1` confirms the hang is actually kernel compilation in progress — ZLUDA compiles GPU kernels JIT and this can take 10-20 minutes.

**Failure 3 — Hard freeze during kernel compilation:** With the DLL replaced, kernel compilation begins and is confirmed active via log output. During compilation, a fatal error appears: `FATAL: kernel fmha_cutlassF_f32_aligned_64x64_rf_sm80 is for sm80-sm100, but was built for sm37`. This is the same CUTLASS Flash Attention kernel mismatch documented on gfx1031 — kernels compiled for sm80 (NVIDIA Ampere) cannot run on gfx900 (equivalent sm37 compute level). The system hard locked requiring a power cycle.

**Conclusion:** ZLUDA LoRA training on gfx900 reaches further than gfx1031 (gets past GPU detection and into kernel compilation) but ultimately hits the same CUTLASS wall. The DLL replacement fix is required and documented. The sm80/sm37 mismatch is the hard blocker.

**Issue filed:** github.com/lshqqytiger/ZLUDA/issues/138

### ROCm on Vega 56 (gfx900) — Status Update (June 2026)

**Status:** Officially supported on Linux (PyTorch 2.9 / ROCm 6.3-6.4). Windows unconfirmed.

gfx900 is now listed as an officially supported architecture in AMD's PyTorch 2.9 variant wheel system for ROCm 6.3 and 6.4. The full supported GPU list per AMD's documentation: gfx1030, gfx1100, gfx1101, gfx1102, gfx1200, gfx1201, gfx900, gfx906, gfx908, gfx90a, gfx942.

This is a significant change from the previous status. gfx900 was dropped from ROCm 6.x official support but has been re-added to the PyTorch wheel ecosystem via TheRock.

**Linux path:** Install PyTorch 2.9 via the variant wheel system with ROCm 6.3 or 6.4 installed. The AMD provider plugin detects gfx900 automatically. For ROCm 7.0+, use the nightly index at `download.pytorch.org/whl/nightly/rocm7.0` — gfx900 nightly wheels exist but show instability (TensileLibrary.dat crash reported April 2026, PyTorch issue #179865).

**Windows path:** Unconfirmed. The nightly wheels at `rocm.nightlies.amd.com` may include gfx900 kernels but no clean Windows stack has been verified. `HSA_OVERRIDE_GFX_VERSION=9.0.0` is the expected override (gfx900 presents as itself, no spoofing needed). This is an active research target.

**TheRock build system:** gfx900 is functional in TheRock but noted as needing fixes (TheRock issue #2588). The advanced-lvl-up gfx800/gfx900 Tensile fix repo has been updated to include ComfyUI GGUF support and 10-step workflow examples for gfx900.

**Wan 2.2 video LoRA training on legacy AMD hardware:** The advanced-lvl-up contributor demonstrated Wan 2.2 5B LoRA training running on an RX470 (gfx803 — older than gfx900) with peak 6GB VRAM using a custom training loop: PEFT + diffusers, a custom Rose optimizer, manual DataLoader preparation, AMP GradScaler, gradient accumulation with optimizer and attention activation offloading. 50 video samples at 640×480 49 frames, 500 steps, output at 1280×704 121 frames. This bypasses kohya_ss entirely and avoids the Tensile dependency. The training framework code is approximately 3000 lines including helper functions and is not yet publicly released, but the contributor has offered to complete it on request.

### kohya_ss LoRA Training on Vega 56

**Status:** CPU-only confirmed working. GPU not utilized.

LoRA training via kohya_ss was tested on Vega 56 as a means of training image generation LoRAs without requiring RDNA2 hardware.

- `float32` training on CPU: confirmed working, slow but functional
- `fp16` training: silent hang with no error output — GPU never utilized
- ZLUDA path for GPU training: CUTLASS Flash Attention hard freeze (as above)

The result is that LoRA training on Vega 56 with the current toolchain is CPU-only float32. For small LoRAs (rank 4-8) on a Ryzen 9 5950X, this is feasible overnight but not practical for larger training runs.

**Open question:** Whether ROCm 5.7 pinned wheels enable fp16 training on gfx900. Training has different VRAM and compute profiles than inference — it may be achievable at lower ranks even if inference is not. This remains unexplored.

---

## The Vulkan Thread

Vulkan compute is the architecture-agnostic path that connects several different parts of this problem space.

Unlike ROCm, which requires HIP kernels compiled specifically per GPU architecture, Vulkan compute shaders compile to SPIR-V — an intermediate representation that runs on any GPU with Vulkan 1.3 support. This includes Vega (gfx900), RDNA1 (gfx101X), RDNA2 (gfx103X), and RDNA3 (gfx110X). It also includes Intel and NVIDIA GPUs.

**Where Vulkan already works on AMD:**

[whisper-windows-mcp](https://github.com/eviscerations/whisper-windows-mcp) provides whisper.cpp based speech transcription as a Model Context Protocol server for Windows. The underlying whisper.cpp library has a Vulkan compute backend (`-DGGML_VULKAN=ON`) that enables GPU-accelerated transcription on any Vulkan 1.3 capable GPU — including Vega hardware where ROCm is not viable.

**Ollama + Vulkan for local LLM inference:**

Ollama uses llama.cpp internally. llama.cpp has a mature Vulkan compute backend. Setting `OLLAMA_GPU_DRIVER=vulkan` before launching Ollama enables Vulkan-based LLM inference on Vega and other AMD hardware without any ROCm dependency. Quantized models (GGUF Q4, Q3, Q2) run within the 8GB HBM2 budget of Vega 56/64. This is a confirmed viable path to local LLM inference on Vega hardware.

**ComfyUI and Vulkan:**

ComfyUI uses PyTorch for GPU compute. PyTorch does not have a Vulkan compute backend for inference — it has a limited Vulkan backend for mobile/embedded targets that does not cover the operations used in diffusion model inference. This means Vulkan cannot directly accelerate ComfyUI on Vega. The ROCm path remains blocked on gfx900. DirectML works for SD1.5 but not video.

**The coherence of the Vulkan thread:**

For audio processing (whisper.cpp), local LLM inference (Ollama/llama.cpp), and other inference workloads that use GGML-based backends, Vulkan provides GPU acceleration on the entire AMD hardware range. For ComfyUI specifically, Vulkan remains a gap. Research into whether a Vulkan-backed PyTorch alternative (such as WebGPU/wgpu or Burn with Vulkan backend) could handle diffusion inference is an open area.

---

## LoRA Training on RDNA2 — Unexplored Potential

Training LoRAs for video models (Wan 2.2) via musubi-tuner (kohya-ss) on RDNA2 hardware is a research target that has not yet been characterized on gfx1031.

The key insight is that training has different VRAM requirements than inference:

- Inference at Q3KM: ~6.7GB diffusion model + compute overhead
- LoRA training at rank 8: activations, gradients, optimizer states — scaling with rank, not full model size

For low-rank training (rank 4-16), the peak VRAM requirement may be substantially lower than inference at higher quantizations. It is plausible that gfx1031 with 12GB can run rank-8 or rank-16 Wan 2.2 video LoRA training in float32 or bf16. This is unconfirmed and requires testing.

If it works, it enables a closed-loop pipeline entirely on RDNA2 hardware: generate reference content in ComfyUI, curate a training dataset, train a video LoRA with musubi-tuner on the same machine, use the LoRA in subsequent ComfyUI generations.

For Vega 56/64 specifically, the same question applies with more constraint: rank 4-8 training in float32 may be achievable via ROCm 5.7 pinned builds or possibly through a Vulkan-backed training framework. This is entirely unexplored and would represent a meaningful capability unlock for the Vega installed base.

---

## Open Research Questions

In rough priority order:

**1. Q2_K_M on gfx1031 (RX 6650 XT target)**
Does Q2_K_M of Wan 2.2 14B I2V produce acceptable quality for motion generation? At ~4.6GB per model, two Q2KM models fit within 8GB alongside the GGUF text encoder. The quantization script using the `gguf` Python library is feasible. Quality validation is the open question.

**2. RX 6600 / 6600 XT (gfx1032)**
Does the same `HSA_OVERRIDE_GFX_VERSION=10.3.0` trick work for gfx1032, or does it require a different value? gfx1032 is RDNA2 but a different die from gfx1031. The override approach should be similar but is unconfirmed.

**3. RDNA1 (gfx1010) on Windows ROCm**
Does `HSA_OVERRIDE_GFX_VERSION=10.3.0` produce working inference on RX 5700 XT (gfx1010)? Community reports on Linux suggest partial success. Windows is entirely undocumented.

**4. Vega 56/64 ROCm 5.7 pinned build for training**
Can fp16 LoRA training be achieved on gfx900 with pinned ROCm 5.7 builds? The float32 CPU training path is confirmed. GPU training with older ROCm is unexplored.

**5. Vulkan-backed diffusion inference**
Is there a viable path to running diffusion model inference on Vega via a Vulkan compute backend? WebGPU, wgpu-based frameworks, or direct Vulkan compute with SPIR-V shader compilation could theoretically handle the tensor operations. No concrete attempt has been made.

**6. Radeon VII (gfx906, 16GB HBM2)**
16GB of HBM2 with its associated memory bandwidth represents significant compute potential if the software stack can be made to work. gfx906 has full Vulkan 1.3 support. ROCm 5.7 had full gfx906 support. Whether either path enables modern ComfyUI inference is unknown.

---

## Summary of Confirmed States

| Approach | Hardware | Status |
|---|---|---|
| ComfyUI + ROCm 7.x nightlies | gfx1031 (RX 6700 XT) | ✅ Confirmed working |
| Wan 2.2 I2V inference at Q3KM | gfx1031 | ✅ Confirmed working |
| Wan 2.2 SVI long-video generation | gfx1031 | ✅ Confirmed working |
| A1111 + DirectML SD1.5 inference | gfx900 (Vega 56) | ✅ Works — image only |
| CPU float32 LoRA training | gfx900 via Ryzen 9 5950X | ✅ Works — slow |
| Ollama + Vulkan LLM inference | gfx900 | ✅ Works (not yet characterized here) |
| whisper.cpp Vulkan transcription | gfx900 | ✅ Works via Vulkan backend |
| ZLUDA ComfyUI inference | gfx1031 | ❌ CUTLASS Flash Attn freeze |
| ZLUDA LoRA training (kohya_ss) | gfx900 | ❌ sm80 CUTLASS kernel + hard freeze |
| ROCm 7.x nightly ComfyUI (Windows) | gfx900 | ❓ Unconfirmed — active research |
| PyTorch 2.9 + ROCm 6.3/6.4 (Linux) | gfx900 | ✅ Officially supported |
| fp16 GPU LoRA training (kohya_ss) | gfx900 | ❌ Silent hang without DLL fix |
| Wan 2.2 5B LoRA training (custom loop) | gfx803 (RX470) | ✅ Confirmed — 6GB VRAM peak |
| fp8 text encoders | gfx1031 | ❌ comfy_kitchen dependency crash |
| SageAttention | gfx1031 | ❌ CUDA/Triton only |
| ComfyUI inference via DirectML | any | ❌ Not applicable to PyTorch compute path |
