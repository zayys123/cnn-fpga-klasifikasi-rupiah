# RupiahVision CNN FPGA V1 — PTQ INT8 Report

**Baseline:** epoch 98, best validation-loss checkpoint.

## Quantization specification

- Input: RGB UINT8, CHW, scale=1/255, zero-point=0.
- Convolution weights: symmetric INT8 per output channel.
- FC weights: symmetric INT8 per tensor to retain a common output-logit scale.
- Activations: UINT8 after ReLU, zero-point=0.
- Bias and accumulators: INT32.
- Convolution requantization: Q31 multiplier + signed shift.
- GAP: integer sum over 8x8; scale is activation3_scale/64.
- Calibration uses train split only; validation is evaluation only; test is not accessed.

## Pre-quantization validation reproduction

- FP32 validation accuracy: 67.25146199%
- FP32 validation Macro-F1: 67.25920420%
- Stored validation metrics reproduced within 1e-6 tolerance.

## Calibration

- Images: 799
- ReLU1 maximum: 1.1071105; scale: 0.00434160981
- ReLU2 maximum: 7.12192106; scale: 0.0279291022
- ReLU3 maximum: 55.6755066; scale: 0.21833532

## Validation comparison

| Metric | FP32 | INT8 |
|---|---:|---:|
| Accuracy | 67.2515% | 67.8363% |
| Macro precision | 67.1631% | 67.7543% |
| Macro recall | 69.1263% | 69.7718% |
| Macro F1 | 67.2592% | 67.9236% |

- FP32/INT8 prediction agreement: 97.0760%
- Logit MAE after dequantization: 0.16263444
- Logit RMSE after dequantization: 0.17923934
- UINT8 saturation counts on validation: `{"conv1": 0, "conv2": 0, "conv3": 0}`

## Exported artifacts

- `quantized_parameters_int8.npz`: integer weights, biases, Q31 multipliers, shifts, scales.
- `weights_mem/`: `$readmemh`-compatible memory files and layout documentation.
- `golden_vectors/`: input and expected INT32 logits for ModelSim testbench.
- `quantization_manifest.json`: full numerical specification.
- `quantization_validation.json`: FP32 vs INT8 metrics.

## Acceptance note

Do not proceed to Verilog until the INT8 validation result is reviewed. A reasonable initial gate is prediction agreement >= 99% and Macro-F1 drop <= 1 percentage point, but the final acceptance threshold must be agreed and reported rather than assumed. If the gate fails, inspect activation saturation and quantization error before changing the CNN.

The known dataset limitation remains: multiple views of the same physical banknote appear across splits. These validation results are exploratory and do not establish generalization to unseen physical banknotes.