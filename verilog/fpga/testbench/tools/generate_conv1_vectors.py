import argparse
import json
import hashlib
from pathlib import Path

import numpy as np

INT32_MIN = np.iinfo(np.int32).min
INT32_MAX = np.iinfo(np.int32).max
INT64_MAX = np.iinfo(np.int64).max


def conv2d_int32(input_u8, weight_i8, bias_i32):

    in_channels, height, width = input_u8.shape
    out_channels, weight_in, kh, kw = weight_i8.shape

    if in_channels != weight_in or kh != 3 or kw != 3:
        raise ValueError("Unexpected Conv1 dimensions.")

    padded = np.pad(
        input_u8,
        ((0, 0), (1, 1), (1, 1)),
        mode="constant"
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
        raise OverflowError("INT32 accumulator overflow.")

    return acc64.astype(np.int32)


def requantize_relu_uint8(accumulator, multipliers, shifts):

    acc = np.maximum(accumulator.astype(np.int64), 0)

    out = np.zeros(acc.shape, dtype=np.uint8)
    saturation_count = 0

    for channel in range(acc.shape[0]):

        q31 = int(multipliers[channel])
        shift = int(shifts[channel])

        if q31 == 0:
            continue

        if shift >= 0:
            factor = q31 * (1 << shift)
            denominator = 1 << 31
        else:
            factor = q31
            denominator = 1 << (31 - shift)

        channel_acc = acc[channel]
        max_acc = int(channel_acc.max()) if channel_acc.size else 0

        if max_acc and factor > INT64_MAX // max_acc:
            raise OverflowError("INT64 multiplication overflow.")

        numerator = channel_acc * np.int64(factor)

        rounded = (
            numerator + np.int64(denominator // 2)
        ) // np.int64(denominator)

        saturation_count += int(np.count_nonzero(rounded > 255))

        out[channel] = np.clip(
            rounded, 0, 255
        ).astype(np.uint8)

    return out, saturation_count


def maxpool2x2_u8(x):

    channels, height, width = x.shape

    return x.reshape(
        channels, height // 2, 2, width // 2, 2
    ).max(axis=(2, 4))


def integer_inference(raw, p, conv1_output):

    q1 = conv1_output
    p1 = maxpool2x2_u8(q1)

    acc2 = conv2d_int32(
        p1, p["conv2_weight"], p["conv2_bias"]
    )

    q2, _ = requantize_relu_uint8(
        acc2, p["conv2_multiplier_q31"], p["conv2_shift"]
    )

    p2 = maxpool2x2_u8(q2)

    acc3 = conv2d_int32(
        p2, p["conv3_weight"], p["conv3_bias"]
    )

    q3, _ = requantize_relu_uint8(
        acc3, p["conv3_multiplier_q31"], p["conv3_shift"]
    )

    gap_sum = q3.astype(np.int64).sum(axis=(1, 2))

    fc_acc64 = np.sum(
        gap_sum[None, :] * p["fc_weight"].astype(np.int64),
        axis=1
    )

    fc_acc64 += p["fc_bias"].astype(np.int64)

    if np.any(fc_acc64 < INT32_MIN) or np.any(fc_acc64 > INT32_MAX):
        raise OverflowError("FC INT32 overflow.")

    return fc_acc64.astype(np.int32)


def write_hex(path, values, width):

    values = np.asarray(values).reshape(-1)

    with open(path, "w", encoding="ascii", newline="\n") as f:
        for value in values:
            f.write(f"{int(value):0{width}X}\n")


def sha256(path):

    h = hashlib.sha256()

    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)

    return h.hexdigest()


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("--parameters", required=True)
    parser.add_argument("--golden", required=True)
    parser.add_argument("--output-dir", required=True)

    args = parser.parse_args()

    p = np.load(args.parameters, allow_pickle=False)
    g = np.load(args.golden, allow_pickle=False)

    images = g["input_chw"]
    expected_logits = g["expected_logits_int32"]

    if images.shape[1:] != (3, 32, 32):
        raise ValueError("Unexpected input image dimensions.")

    if expected_logits.shape != (len(images), 7):
        raise ValueError("Unexpected golden logits dimensions.")

    w1 = p["conv1_weight"]
    b1 = p["conv1_bias"]
    m1 = p["conv1_multiplier_q31"]
    s1 = p["conv1_shift"]

    if w1.shape != (8, 3, 3, 3):
        raise ValueError("Unexpected Conv1 weight shape.")

    outputs = np.zeros(
        (len(images), 8, 32, 32),
        dtype=np.uint8
    )

    saturation_total = 0

    print("--------------------------------------")
    print("GENERATING CONV1 GOLDEN VECTORS")
    print("--------------------------------------")

    for i, image in enumerate(images):

        acc = conv2d_int32(image, w1, b1)

        q1, sat = requantize_relu_uint8(
            acc, m1, s1
        )

        outputs[i] = q1
        saturation_total += sat

        logits = integer_inference(image, p, q1)

        if not np.array_equal(logits, expected_logits[i]):
            raise RuntimeError(
                f"Golden logits mismatch at image {i}."
            )

        print(
            f"Image {i+1}/{len(images)}: "
            f"Conv1={q1.size}, logits EXACT MATCH"
        )

    outdir = Path(args.output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    files = {
        "input": outdir / "conv1_input_images.mem",
        "weights": outdir / "conv1_weights_int8.mem",
        "bias": outdir / "conv1_bias_int32.mem",
        "multiplier": outdir / "conv1_multiplier_q31.mem",
        "shift": outdir / "conv1_shift_s8.mem",
        "expected": outdir / "conv1_expected_outputs.mem",
    }

    write_hex(files["input"], images, 2)

    write_hex(
        files["weights"],
        w1.view(np.uint8),
        2
    )

    write_hex(
        files["bias"],
        b1.view(np.uint32),
        8
    )

    write_hex(
        files["multiplier"],
        m1,
        8
    )

    write_hex(
        files["shift"],
        s1.view(np.uint8),
        2
    )

    write_hex(files["expected"], outputs, 2)

    manifest = {
        "module": "Conv1 INT8",
        "images": len(images),
        "input_shape": list(images.shape),
        "weight_shape": list(w1.shape),
        "output_shape": list(outputs.shape),
        "input_order": "NCHW, CHW per image",
        "weight_order": "OIHW, C-order",
        "output_order": "NCHW, C-order",
        "padding": 1,
        "stride": 1,
        "activation": "ReLU",
        "requantization": "Q31, nearest ties upward",
        "output_type": "UINT8",
        "saturation_count": saturation_total,
        "output_vectors": int(outputs.size),
        "golden_final_logits": "EXACT MATCH",
        "files": {}
    }

    for name, path in files.items():
        manifest["files"][name] = {
            "filename": path.name,
            "bytes": path.stat().st_size,
            "sha256": sha256(path)
        }

    manifest_path = outdir / "conv1_vectors_manifest.json"

    manifest_path.write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8"
    )

    print("--------------------------------------")
    print("CONV1 VECTOR GENERATION PASS")
    print("--------------------------------------")
    print("Golden images:", len(images))
    print("Input values:", images.size)
    print("Weight values:", w1.size)
    print("Output vectors:", outputs.size)
    print("Saturation:", saturation_total)
    print("Final logits: EXACT MATCH")
    print("Output:", outdir)
    print("Manifest:", manifest_path)


if __name__ == "__main__":
    main()
