import argparse
import json
from pathlib import Path

import numpy as np

INT32_MIN = -(2**31)
INT32_MAX = 2**31 - 1
INT64_MAX = 2**63 - 1


def conv2d_int32(input_u8, weight_i8, bias_i32):
    """Match RupiahVision_INT8_PTQ.py convolution reference."""

    in_channels, height, width = input_u8.shape
    out_channels, weight_in, kh, kw = weight_i8.shape

    if in_channels != weight_in or kh != 3 or kw != 3:
        raise ValueError("Unexpected convolution dimensions.")

    padded = np.pad(
        input_u8,
        ((0, 0), (1, 1), (1, 1)),
        mode="constant",
        constant_values=0
    )

    windows = np.lib.stride_tricks.sliding_window_view(
        padded, (3, 3), axis=(1, 2)
    )

    acc64 = np.einsum(
        "chwkl,ockl->ohw",
        windows.astype(np.int64),
        weight_i8.astype(np.int64),
        optimize=True,
        dtype=np.int64
    )

    acc64 += bias_i32.astype(np.int64)[:, None, None]

    if np.any(acc64 < INT32_MIN) or np.any(acc64 > INT32_MAX):
        raise OverflowError("Convolution accumulator exceeds INT32.")

    return acc64.astype(np.int32)


def requantize_relu(accumulator, multipliers, shifts):
    """Match Python Q31 rounding and UINT8 saturation."""

    acc = np.maximum(accumulator.astype(np.int64), 0)

    output = np.zeros(acc.shape, dtype=np.uint8)
    saturation_mask = np.zeros(acc.shape, dtype=bool)

    for channel in range(acc.shape[0]):

        q31 = int(multipliers[channel])
        shift = int(shifts[channel])

        if q31 == 0:
            continue

        if q31 > INT32_MAX or not -31 <= shift <= 30:
            raise ValueError("Invalid actual Q31 parameters.")

        if shift >= 0:
            factor = q31 * (1 << shift)
            denominator = 1 << 31
        else:
            factor = q31
            denominator = 1 << (31 - shift)

        channel_acc = acc[channel]

        max_acc = int(channel_acc.max()) if channel_acc.size else 0

        if max_acc and factor > INT64_MAX // max_acc:
            raise OverflowError("INT64 multiplication overflow risk.")

        numerator = channel_acc * np.int64(factor)

        rounded = (
            numerator + np.int64(denominator // 2)
        ) // np.int64(denominator)

        saturation_mask[channel] = rounded > 255

        output[channel] = np.clip(
            rounded, 0, 255
        ).astype(np.uint8)

    return output, saturation_mask


def maxpool2x2(x):
    channels, height, width = x.shape

    if height % 2 or width % 2:
        raise ValueError("Invalid MaxPool dimensions.")

    return x.reshape(
        channels, height // 2, 2, width // 2, 2
    ).max(axis=(2, 4))


def append_vectors(
    lines, accumulator, multipliers, shifts,
    expected, saturation, layer_id
):
    channels, height, width = accumulator.shape

    for c in range(channels):

        multiplier = int(multipliers[c])
        shift = int(shifts[c])

        for y in range(height):
            for x in range(width):

                acc = int(accumulator[c, y, x])
                exp = int(expected[c, y, x])
                sat = int(saturation[c, y, x])

                # 96-bit packed vector:
                # [95:64] accumulator INT32
                # [63:32] multiplier Q31
                # [31:24] signed shift INT8
                # [23:16] expected UINT8
                # [15]    saturation
                # [14]    invalid_config
                # [13:12] layer ID
                # [11:0]  reserved

                word = (
                    ((acc & 0xFFFFFFFF) << 64)
                    | ((multiplier & 0xFFFFFFFF) << 32)
                    | ((shift & 0xFF) << 24)
                    | ((exp & 0xFF) << 16)
                    | (sat << 15)
                    | (0 << 14)
                    | ((layer_id & 3) << 12)
                )

                lines.append(f"{word:024X}")


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("--parameters", required=True)
    parser.add_argument("--golden", required=True)
    parser.add_argument("--output", required=True)

    args = parser.parse_args()

    with np.load(args.parameters, allow_pickle=False) as z:
        p = {k: z[k].copy() for k in z.files}

    with np.load(args.golden, allow_pickle=False) as z:
        golden = {k: z[k].copy() for k in z.files}

    inputs = golden["input_chw"]
    expected_logits = golden["expected_logits_int32"]

    if inputs.shape != (14, 3, 32, 32):
        raise ValueError(f"Unexpected input shape: {inputs.shape}")

    if expected_logits.shape != (14, 7):
        raise ValueError("Unexpected expected logits shape.")

    layers = [
        ("conv1", 0),
        ("conv2", 1),
        ("conv3", 2),
    ]

    lines = []

    counts = {}
    verified_images = 0

    for image_index, raw_chw in enumerate(inputs):

        # Conv1
        acc1 = conv2d_int32(
            raw_chw.astype(np.uint8),
            p["conv1_weight"],
            p["conv1_bias"]
        )

        q1, sat1 = requantize_relu(
            acc1,
            p["conv1_multiplier_q31"],
            p["conv1_shift"]
        )

        append_vectors(
            lines, acc1,
            p["conv1_multiplier_q31"],
            p["conv1_shift"],
            q1, sat1, 0
        )

        # Conv2
        p1 = maxpool2x2(q1)

        acc2 = conv2d_int32(
            p1,
            p["conv2_weight"],
            p["conv2_bias"]
        )

        q2, sat2 = requantize_relu(
            acc2,
            p["conv2_multiplier_q31"],
            p["conv2_shift"]
        )

        append_vectors(
            lines, acc2,
            p["conv2_multiplier_q31"],
            p["conv2_shift"],
            q2, sat2, 1
        )

        # Conv3
        p2 = maxpool2x2(q2)

        acc3 = conv2d_int32(
            p2,
            p["conv3_weight"],
            p["conv3_bias"]
        )

        q3, sat3 = requantize_relu(
            acc3,
            p["conv3_multiplier_q31"],
            p["conv3_shift"]
        )

        append_vectors(
            lines, acc3,
            p["conv3_multiplier_q31"],
            p["conv3_shift"],
            q3, sat3, 2
        )

        # Global Average Pooling
        gap_sum = q3.astype(np.int64).sum(axis=(1, 2))

        # Fully Connected
        fc_acc64 = np.sum(
            gap_sum[None, :] * p["fc_weight"].astype(np.int64),
            axis=1
        )

        fc_acc64 += p["fc_bias"].astype(np.int64)

        if np.any(fc_acc64 < INT32_MIN) or np.any(fc_acc64 > INT32_MAX):
            raise OverflowError("FC accumulator exceeds INT32.")

        fc_logits = fc_acc64.astype(np.int32)

        # Critical: verify final output against original golden vectors.
        if not np.array_equal(fc_logits, expected_logits[image_index]):
            raise RuntimeError(
                f"Golden logits mismatch at image {image_index}."
            )

        if int(np.argmax(fc_logits)) != int(
            np.argmax(expected_logits[image_index])
        ):
            raise RuntimeError(
                f"Predicted class mismatch at image {image_index}."
            )

        verified_images += 1

    counts = {
        "conv1": 14 * 8 * 32 * 32,
        "conv2": 14 * 16 * 16 * 16,
        "conv3": 14 * 24 * 8 * 8,
    }

    expected_total = sum(counts.values())

    if len(lines) != expected_total:
        raise RuntimeError("Generated vector count mismatch.")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    output.write_text(
        "\n".join(lines) + "\n",
        encoding="ascii"
    )

    manifest = {
        "images_verified": verified_images,
        "final_logits_exact_match": True,
        "vectors_per_layer": counts,
        "total_vectors": len(lines),
        "record_width_bits": 96,
        "record_width_hex": 24,
        "layer_ids": {
            "0": "conv1",
            "1": "conv2",
            "2": "conv3"
        },
        "output_file": str(output)
    }

    manifest_path = output.with_suffix(".json")

    manifest_path.write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8"
    )

    print("--------------------------------------")
    print("REQuANTIZATION VECTOR GENERATION PASS")
    print("--------------------------------------")
    print("Golden images verified:", verified_images)
    print("Final logits: EXACT MATCH")
    print("Conv1 vectors:", counts["conv1"])
    print("Conv2 vectors:", counts["conv2"])
    print("Conv3 vectors:", counts["conv3"])
    print("Total vectors:", len(lines))
    print("Output:", output)
    print("Manifest:", manifest_path)


if __name__ == "__main__":
    main()
