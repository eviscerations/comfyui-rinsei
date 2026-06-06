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

### ZLUDA on Vega 56 (gfx900)

**Status:** Dead end for training — CUTLASS incompatibility, hard freeze.

During LoRA training experiments on Vega 56, ZLUDA was tested as a path to GPU-accelerated training via the CUDA backend. The result was a hard freeze identical to the gfx1031 CUTLASS failure. ZLUDA does not provide a viable training path on gfx900.

### ROCm on Vega 56 (gfx900) for ComfyUI

**Status:** Not viable with current ROCm 6.x / 7.x wheels.

ROCm 5.7 was the last release with full GCN 5.1 (gfx906) support, and GCN 5 (gfx900) support has been progressively degraded. The ROCm 7.x nightly wheels used by this repository (required for PyTorch 2.10.x) do not support gfx900 for GPU compute in ComfyUI. The `HSA_OVERRIDE_GFX_VERSION=10.3.0` trick that enables gfx1031 to run as gfx1030 does not produce working results on gfx900 for inference workloads — the override works because gfx1031 and gfx1030 are the same RDNA2 ISA. gfx900 is GCN5 and the ISA difference is too large.

**What partially works on gfx900:** ROCm 5.3–5.7 pinned builds may enable some older model inference. This is unexplored territory and not documented here.

**Conclusion:** ComfyUI image and video generation on Vega via ROCm is not currently viable. Vulkan is the viable inference pathway for Vega.

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
| ZLUDA LoRA training | gfx900 | ❌ CUTLASS Flash Attn freeze |
| ROCm 7.x ComfyUI inference | gfx900 | ❌ ISA mismatch, not viable |
| fp16 GPU LoRA training | gfx900 | ❌ Silent hang |
| fp8 text encoders | gfx1031 | ❌ comfy_kitchen dependency crash |
| SageAttention | gfx1031 | ❌ CUDA/Triton only |
| ComfyUI inference via DirectML | any | ❌ Not applicable to PyTorch compute path |
