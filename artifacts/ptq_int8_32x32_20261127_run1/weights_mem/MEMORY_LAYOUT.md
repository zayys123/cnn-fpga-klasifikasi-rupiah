# Weight memory layout

All files contain one hexadecimal word per line, with no address prefix.

- Convolution weights: signed INT8 two's-complement bytes, flattened C-order
  from PyTorch OIHW layout: `[out_channel][in_channel][kernel_y][kernel_x]`.
- Fully connected weights: signed INT8 two's-complement bytes, flattened
  C-order `[out_feature][in_feature]`.
- Biases: signed INT32 two's-complement words, one per output channel/feature.
- Requantization multipliers: unsigned 32-bit Q31 words, one per output channel.
- Requantization shifts: signed decimal integers, one per output channel.
- Input image golden vectors: RGB channel-first (CHW), then row-major within each channel.
- Expected logits: raw signed INT32 fully-connected accumulators. All seven logits
  share one positive scale because FC weights use per-tensor quantization.
