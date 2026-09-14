# Full Quantization Comparison Table (Theoretical 100B Model)

This comparison is for a theoretical 100B model. The goal is to illustrate the tradeoff between memory efficiency and quality retention.

## Assumptions

- 100B model weights are used as the baseline.
- Weight-only memory estimates are approximate and theoretical.
- VRAM demand will be higher in real workloads because of KV cache, activations, and runtime overhead.
- Values below are intended for rough planning rather than perfect engineering measurements.

## Quick interpretation

- FP32 / FP16 / BF16 are highest quality, but highest memory.
- Q8 and Q6 are usually near-original quality while saving a lot of VRAM.
- Q4_K_M is the community sweet spot for many local model deployments.
- IQ variants are often a better low-bit compromise than older Q3/Q2 families.
- UD and very aggressive 2-bit / 1-bit quantizations are useful only when memory is the top priority.

## Full Quantization Comparison Table

| Quantization Type | Effective bpw | Model Weight Size (GB) | Est. VRAM for Weights (GiB) | Quality Retention / Impact |
| --- | ---: | ---: | ---: | --- |
| FP32 (Full) | 32.0 | 400.0 GB | ~372.5 GiB | 100% (Exact baseline, uncompressed) |
| FP16 / BF16 | 16.0 | 200.0 GB | ~186.3 GiB | 100% (Standard training precision baseline) |
| Q8_0 / Q8_K | ~8.5 | ~106.3 GB | ~99.0 GiB | ~99.9% (Imperceptible loss from FP16) |
| Q6_K | ~6.56 | ~82.0 GB | ~76.4 GiB | ~99.5% (Virtually identical to original) |
| Q5_K_M | ~5.5 | ~68.8 GB | ~64.0 GiB | ~98.5% (High-fidelity sweet spot) |
| Q5_K_S | ~5.3 | ~66.3 GB | ~61.7 GiB | ~98.0% (Very minor drop vs. Q5_K_M) |
| Q4_K_M | ~4.8 | ~60.0 GB | ~55.9 GiB | ~97.0% (Community gold standard; best balance) |
| Q4_K_S | ~4.5 | ~56.3 GB | ~52.4 GiB | ~96.0% (Slight loss on fine reasoning/math) |
| IQ4_NL / IQ4_XS | ~4.25 – 4.45 | ~54.0 GB | ~50.3 GiB | ~96.5% (Non-linear quant; beats standard Q4 at lower size) |
| Q3_K_L / M | ~3.8 | ~47.5 GB | ~44.2 GiB | ~92.0% (Decent for general chat; minor code/math degradation) |
| Q3_K_S | ~3.4 | ~42.5 GB | ~39.6 GiB | ~88.0% (Noticeable perplexity increase) |
| IQ3_M / IQ3_S | ~3.5 – 3.7 | ~45.0 GB | ~41.9 GiB | ~93.0% (Importance-matrix quant preserves reasoning better than Q3_K) |
| IQ3_XXS / XS | ~3.0 – 3.3 | ~39.0 GB | ~36.3 GiB | ~88.0% (Fits on 40GB–48GB VRAM cards) |
| UD-Q2_K_XL | ~2.9 – 3.1 | ~37.5 GB | ~34.9 GiB | ~84.0% (Dynamic layers preserve coherence and syntax) |
| Q2_K / Q2_K_M | ~2.6 – 2.7 | ~33.5 GB | ~31.2 GiB | ~70.0% (Severe degradation; looping, hallucination, broken markdown) |
| IQ2_M / IQ2_S | ~2.5 – 2.7 | ~32.5 GB | ~30.3 GiB | ~78.0% (Tolerable output on 100B due to parameter density) |
| IQ2_XXS / XS | ~2.1 – 2.4 | ~28.0 GB | ~26.1 GiB | ~65.0% (High perplexity, basic QA only) |
| IQ1_S / IQ1_M | ~1.7 – 1.8 | ~22.0 GB | ~20.5 GiB | ~45.0% (Severe damage; fragmented syntax, barely intelligible) |

## What the labels mean

### Full floating-point formats

- FP32: exact 32-bit weights, no compression; worst memory efficiency.
- FP16 / BF16: standard high-quality inference precision; widely used for modern GPUs.
- Training and inference quality is maximized, but VRAM cost is extremely high for 100B models.

### Q family

- Q8 / Q6 / Q5 / Q4: integer quantizations in the GGUF / llama.cpp ecosystem.
- Lower bit-depth means smaller weights and lower VRAM, but more quality loss.
- Q4_K_M is usually the best all-around default for local inference when aiming for a balance of quality and memory.

### IQ family

- IQ stands for importance-aware or non-linear quantization schemes.
- These are designed to keep more important weights accurate while compressing less critical weights more aggressively.
- IQ variants often outperform older Q3/Q2 schemes at similar memory cost.

### UD family

- UD-style variants are custom or experimental low-bit schemes that are often optimized for very low memory footprint.
- They can preserve coherence better than naive low-bit files in some cases, but they are not universally standardized.
- Their behavior varies more by runtime and model architecture.

## Relative VRAM savings vs. FP16

For a theoretical 100B model:

- FP16 / BF16: baseline
- Q8_0 / Q8_K: about 2x smaller than FP16
- Q6_K: about 2.5x smaller than FP16
- Q5_K_M: about 3x smaller than FP16
- Q4_K_M: about 3.3x smaller than FP16
- Q3_K_M: about 4x to 5x smaller than FP16
- Q2 / IQ2 / UD low-bit: about 6x to 8x smaller than FP16
- IQ1: roughly 9x smaller than FP16

Real memory use in practice will also include KV cache and activations, so total system VRAM should be treated as a higher number than the raw weight-only estimate.

## Practical recommendations

### Best quality, high-VRAM setup

- FP16 / BF16
- Q8_0 / Q8_K
- Q6_K

These are good if you want near-original behavior and have enough VRAM.

### Best balance for real local use

- Q5_K_M
- Q4_K_M
- IQ4_NL / IQ4_XS

This is the sweet spot for many practical 100B deployments.

### Memory-constrained setups

- Q3_K_M
- IQ3_M / IQ3_S
- UD-Q2_K_XL
- Q2_K / IQ2

These are useful only when VRAM is the primary limit and some quality loss is acceptable.

### Extreme memory reduction

- IQ2_XXS / XS
- IQ1_S / IQ1_M

These should be treated as last-resort quantizations when the goal is running a model at all, not necessarily preserving high-quality output.

## Bottom line

For a 100B model, the most useful practical range is usually:

- Q8 to Q5 for near-original output
- Q4 to IQ4 for the best quality-to-memory ratio
- Q3 to Q2 for aggressive memory savings and visible quality degradation
- IQ1 / extremely tiny variants only for the most memory-constrained situations

If you want a simple rule:

- Q6 to Q8 = almost full quality
- Q5 to Q4 = best real-world balance
- Q3 to Q2 = low-memory fallback
- IQ1 / tiny UD = extreme compression, major quality tradeoff
