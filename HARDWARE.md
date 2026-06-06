# Hardware Compatibility — AMD GPU Roadmap

This document covers which AMD GPUs are confirmed working, which are likely to work, and which require additional research or different approaches. The goal is to extend AI video generation support to as much AMD hardware as possible.

The core problem is that the official ComfyUI portable build ships `comfy_kitchen`, a closed-source kernel package compiled only for gfx1030. This repository documents how to work around that using ROCm nightly wheels and GGUF quantized models. How far down the VRAM ladder that approach extends is the open research question.

---

## Confirmed Working

| Card | Architecture | gfx | VRAM | Notes |
|---|---|---|---|---|
| RX 6700 XT | RDNA2 | gfx1031 | 12GB | Fully confirmed. All workflows documented in this repo. |

---

## RDNA2 — Highest Priority Target Tier

All gfx1031 cards share the same ISA as the confirmed RX 6700 XT. Everything in this repository applies to them directly — same HSA override, same env vars, same ROCm wheels, same GGUF model stack. Only the VRAM budget differs.

| Card | gfx | VRAM | Expected status |
|---|---|---|---|
| RX 6750 XT | gfx1031 | 12GB | Should work identically to 6700 XT |
| RX 6700 | gfx1031 | 10GB | Should work, moderate headroom |
| **RX 6650 XT** | **gfx1031** | **8GB** | **Primary Q2KM target — same architecture** |
| RX 6600 XT | gfx1032 | 8GB | Adjacent architecture, likely similar |
| RX 6600 | gfx1032 | 8GB | Adjacent architecture, likely similar |
| RX 6500 XT | gfx1034 | 4GB | Too little VRAM for 14B models at any quantization |
| RX 6400 | gfx1034 | 4GB | Too little VRAM |

The RX 6650 XT is the most important near-term research target. It is gfx1031 — the identical ISA to the confirmed working RX 6700 XT — and is available cheaply on the used market. If Q2_K_M quantization works within its 8GB budget, the documentation requires no changes at all.

The RX 6600 / 6600 XT (gfx1032) are a slightly different die but the same RDNA2 generation. The approach should be similar. The key unknown is whether the same `HSA_OVERRIDE_GFX_VERSION=10.3.0` trick works or whether gfx1032 needs its own override value.

---

## Quantization Targets by VRAM

GGUF quantization is the mechanism that makes this possible. For Wan 2.2 14B I2V, the model stack consists of:

- Diffusion model (High Noise): variable by quantization
- Diffusion model (Low Noise): variable by quantization
- Text encoder (umt5-xxl GGUF): ~3.4GB at Q4/Q5
- VAE: ~242MB (loads and offloads during decode)

The two diffusion models are not loaded simultaneously in the GGUF stack — they load and offload alternately during generation. So the effective peak VRAM requirement is one diffusion model + text encoder (during encoding) or one diffusion model + VAE (during decode).

| Quantization | 14B model size | Encoder + VAE | Peak VRAM | Target card |
|---|---|---|---|---|
| Q5_K_M | ~10.8GB | ~3.6GB | ~12GB | RX 6700 XT (confirmed) |
| Q4_K_M | ~8.75GB | ~3.6GB | ~12GB | RX 6700 XT (tight) |
| Q3_K_M | ~6.7GB | ~3.6GB | ~8-10GB | RX 6700 XT (comfortable), RX 6700 |
| **Q2_K** | **~4.6GB** | **~3.6GB** | **~8GB** | **RX 6650 XT, RX 6600 XT** |
| Q1 | ~2.5GB | ~3.6GB | ~6GB | Speculative — significant quality loss |

Note: Q3_K_M is the confirmed inflection point on 12GB — it provides enough free compute VRAM for split attention at 480×832 resolution. Q2_K is unconfirmed but mathematically fits within 8GB. Quality degradation at Q2 is noticeable for image generation but may be acceptable for motion generation where temporal coherence matters more than fine detail.

---

## Vega / GCN 5 — Vulkan Pathway

Vega architecture (gfx900, gfx906) is a different research track from RDNA2. ROCm 5.7 was the last series with full GCN 5.1 support, and the ROCm 6.x nightly wheels used by this repository dropped Vega. The `HSA_OVERRIDE_GFX_VERSION=10.3.0` trick may partially work but is not confirmed for ComfyUI inference on these cards.

However, Vega has strong Vulkan 1.3 support. This opens an alternative pathway.

| Card | Architecture | gfx | VRAM | Pathway |
|---|---|---|---|---|
| Vega 56 | GCN 5 | gfx900 | 8GB HBM2 | Vulkan inference (llama.cpp, Ollama) |
| Vega 64 | GCN 5 | gfx900 | 8GB HBM2 | Vulkan inference |
| Radeon VII | GCN 5.1 | gfx906 | 16GB HBM2 | Vulkan inference — 16GB HBM2 bandwidth is significant |

**What Vulkan enables on Vega:**

LLM inference via llama.cpp's Vulkan backend (`-DGGML_VULKAN=ON`) runs on any GPU with Vulkan 1.3 support, including Vega. Ollama uses llama.cpp internally and can be configured to use the Vulkan backend with `OLLAMA_GPU_DRIVER=vulkan`. This is a clean path to local LLM inference on Vega hardware without any ROCm dependency.

ComfyUI image and video generation is harder — it uses PyTorch which requires ROCm (or CUDA) for GPU compute. There is no Vulkan backend for PyTorch. Options being researched:

1. **ROCm 5.7 with older wheel builds** — limited to older models, increasing incompatibility with current workflows
2. **DirectML via onnxruntime** — experimental, significant workflow changes required
3. **HSA_OVERRIDE trick with ROCm 7.x nightlies** — unconfirmed on gfx900, may work partially

The Radeon VII (16GB HBM2) is an interesting outlier. If any Vega card can be made to work with modern ROCm via the override trick, 16GB of HBM2 bandwidth would be a significant compute asset. It warrants dedicated testing.

---

## RDNA 1 — Middle Ground

RDNA1 (RX 5000 series) has no official ROCm support. Community reports suggest the `HSA_OVERRIDE_GFX_VERSION=10.3.0` trick sometimes works — the same override used for gfx1031. This is entirely undocumented territory on Windows.

| Card | gfx | VRAM | Notes |
|---|---|---|---|
| RX 5700 XT | gfx1010 | 8GB | Unconfirmed. Override may work. |
| RX 5700 | gfx1010 | 8GB | Unconfirmed. |
| RX 5500 XT 8GB | gfx1012 | 8GB | Unconfirmed. 4GB variant is too small. |
| RX 5600 XT | gfx1011 | 6GB | Below Q3KM threshold. |

If RDNA1 works with the override, it opens a very large installed base — the RX 5700 XT was a popular card in its generation and many are still in daily use.

---

## RDNA 3 — Higher Tier

RDNA3 has official ROCm support on Linux. Windows ROCm support is in active development from AMD. These cards should work with the same approach as gfx1031, possibly with less friction as official Windows support matures.

| Card | gfx | VRAM | Notes |
|---|---|---|---|
| RX 7900 XTX | gfx1100 | 24GB | More than enough for any current model |
| RX 7900 XT | gfx1100 | 20GB | Comfortable for all workflows |
| RX 7800 XT | gfx1101 | 16GB | Strong position |
| RX 7700 XT | gfx1101 | 12GB | Same VRAM as 6700 XT |
| RX 7600 XT | gfx1102 | 16GB | Strong position for the price |
| RX 7600 | gfx1102 | 8GB | Q2KM target like 6650 XT |

RDNA3 is not the focus of this repository — those cards are increasingly well-supported upstream. The contribution of comfyui-rinsei is in the cards that nobody else is documenting.

---

## Nvidia Equivalent Reference

For users coming from the Nvidia world trying to find the AMD equivalent of what they have:

| Nvidia card | AMD equivalent | VRAM tier |
|---|---|---|
| GTX 1060 6GB | RX 580 6GB / RX 5600 XT | 6GB |
| GTX 1070 / 1070 Ti | Vega 56 / Vega 64 | 8GB |
| GTX 1080 | Vega 64 / RX 5700 XT | 8GB |
| GTX 1080 Ti | Radeon VII | 16GB HBM2 |
| RTX 2060 | RX 5700 / RX 6600 XT | 8GB |
| RTX 2060 Super | RX 5700 XT / RX 6650 XT | 8GB |
| RTX 2070 | RX 6700 / RX 6650 XT | 8-10GB |
| RTX 2070 Super | RX 6700 XT | 12GB |
| RTX 2080 | RX 6700 XT / RX 6800 | 12-16GB |
| RTX 2080 Ti | RX 6800 XT | 16GB |
| RTX 3060 12GB | RX 6700 XT | 12GB |

The practical comparison for AI inference is VRAM first, compute second. HBM2 bandwidth on Vega is significantly higher than GDDR6 on equivalent RDNA2 cards at the same capacity, which may matter for bandwidth-bound operations.

---

## Research Priorities

In order of expected impact:

1. **RX 6650 XT (gfx1031, 8GB)** — Same ISA, same stack, only needs Q2KM model confirmation
2. **RX 6600 / 6600 XT (gfx1032, 8GB)** — Adjacent RDNA2 die, likely similar with possible gfx override differences
3. **RX 5700 XT (gfx1010, 8GB)** — Large installed base, RDNA1 completely undocumented on Windows ROCm
4. **Vega 56/64 (gfx900, 8GB) Vulkan path** — Different approach entirely, enables LLM inference at minimum
5. **Radeon VII (gfx906, 16GB HBM2)** — Long shot but high value if achievable
6. **Q2_K_M quantization** — Unlocks the 8GB tier across all confirmed RDNA2 hardware

Community reports on any of these cards are welcome. Open an issue with your hardware, OS, driver version, and what worked or didn't.
