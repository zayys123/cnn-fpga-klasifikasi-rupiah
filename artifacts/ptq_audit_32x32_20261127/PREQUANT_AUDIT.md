# RupiahVision CNN FPGA V1 — Pre-quantization Audit

**Status: PASS**

- Selected baseline: epoch 98, minimum validation loss.
- Checkpoint and FP32 NPZ: exact tensor-by-tensor match.
- Model: RupiahTinyCNN, input `[3,32,32]`, seven classes.
- Parameters: 5,047.
- MACs per image: 737,448.
- Input: RGB uint8 `[0,255]`, training normalization `x / 255.0`.
- BatchNorm: absent; Dropout: absent.
- Original files are read-only; output is isolated in a new directory.

## Epoch-98 metrics

- Validation loss: 0.77972469
- Validation accuracy: 67.251462%
- Validation Macro-F1: 67.259204%

## SHA-256

- Checkpoint: `8d0a3bae06a6a7fae0f916832f4bf83f7d6d776f09460b2dc6b745d020af6a66`
- FP32 NPZ: `8fb2a2038f29fb167835b2586440036154d7e4d7378ed0ca9bf2f2a5f194a132`
- Architecture: `ada27fc7e905c06e8876e5f6e2003dadd7586f2de0b11eb0c081423ce9bac141`

## Limitation

This audit verifies artifact consistency, not generalization. The known dataset contains multiple image views of the same physical banknote across splits; validation metrics must therefore be interpreted as exploratory image-view results.