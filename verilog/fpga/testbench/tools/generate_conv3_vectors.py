import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np


INT32_MIN = -(2**31)
INT32_MAX = 2**31 - 1


def load_reference(path):
    spec = importlib.util.spec_from_file_location(
        "rupiahvision_ptq_reference", path
    )

    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load PTQ reference.")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)

    required = (
        "conv2d_int32",
        "requantize_relu_uint8",
        "maxpool2x2_u8",
    )

    for name in required:
        if not hasattr(module, name):
            raise RuntimeError(
                f"Missing reference function: {name}"
            )

    return module


def write_hex(path, values, width):
    mask = (1 << (width * 4)) - 1

    with open(path, "w", encoding="ascii", newline="\n") as f:
        for value in np.asarray(values).reshape(-1):
            f.write(f"{int(value) & mask:0{width}X}\n")


def sha256(path):
    h = hashlib.sha256()

    with open(path, "rb") as f:
        for block in iter(
            lambda: f.read(1024 * 1024), b""
        ):
            h.update(block)

    return h.hexdigest()


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("--ptq-script", required=True)
    parser.add_argument("--parameters", required=True)
    parser.add_argument("--golden", required=True)
    parser.add_argument("--output", required=True)

    args = parser.parse_args()

    ptq = load_reference(args.ptq_script)

    with np.load(args.parameters, allow_pickle=False) as z:
        p = {k: z[k].copy() for k in z.files}

    with np.load(args.golden, allow_pickle=False) as z:
        inputs = z["input_chw"].copy()
        expected_logits = z["expected_logits_int32"].copy()

    if inputs.ndim != 4 or inputs.shape[1:] != (3, 32, 32):
        raise ValueError(
            f"Unexpected input shape: {inputs.shape}"
        )

    n = len(inputs)

    if expected_logits.shape != (n, 7):
        raise ValueError("Unexpected golden logits shape.")

    expected_shapes = {
        "conv1_weight": (8, 3, 3, 3),
        "conv2_weight": (16, 8, 3, 3),
        "conv3_weight": (24, 16, 3, 3),
        "conv1_bias": (8,),
        "conv2_bias": (16,),
        "conv3_bias": (24,),
        "conv1_multiplier_q31": (8,),
        "conv2_multiplier_q31": (16,),
        "conv3_multiplier_q31": (24,),
        "conv1_shift": (8,),
        "conv2_shift": (16,),
        "conv3_shift": (24,),
        "fc_weight": (7, 24),
        "fc_bias": (7,),
    }

    for key, shape in expected_shapes.items():
        if key not in p:
            raise KeyError(f"Missing parameter: {key}")

        if p[key].shape != shape:
            raise ValueError(
                f"{key}: expected {shape}, got {p[key].shape}"
            )

    input_features = []
    expected_outputs = []
    expected_accumulators = []

    saturation_counts = {
        "conv1": 0,
        "conv2": 0,
        "conv3": 0,
    }

    verified_images = 0

    print("--------------------------------------")
    print("GENERATING CONV3 GOLDEN VECTORS")
    print("--------------------------------------")

    for image_index, raw in enumerate(inputs):

        raw = raw.astype(np.uint8, copy=False)

        # =================================
        # CONV1
        # =================================

        acc1 = ptq.conv2d_int32(
            raw,
            p["conv1_weight"],
            p["conv1_bias"]
        )

        q1, sat1 = ptq.requantize_relu_uint8(
            acc1,
            p["conv1_multiplier_q31"],
            p["conv1_shift"]
        )

        saturation_counts["conv1"] += int(sat1)

        # =================================
        # MAXPOOL1
        # =================================

        p1 = ptq.maxpool2x2_u8(q1)

        if p1.shape != (8, 16, 16):
            raise RuntimeError(
                f"Invalid Pool1 shape: {p1.shape}"
            )

        # =================================
        # CONV2
        # =================================

        acc2 = ptq.conv2d_int32(
            p1,
            p["conv2_weight"],
            p["conv2_bias"]
        )

        q2, sat2 = ptq.requantize_relu_uint8(
            acc2,
            p["conv2_multiplier_q31"],
            p["conv2_shift"]
        )

        saturation_counts["conv2"] += int(sat2)

        if q2.shape != (16, 16, 16):
            raise RuntimeError(
                f"Invalid Conv2 output shape: {q2.shape}"
            )

        # =================================
        # MAXPOOL2
        # =================================

        p2 = ptq.maxpool2x2_u8(q2)

        if p2.shape != (16, 8, 8):
            raise RuntimeError(
                f"Invalid Pool2 shape: {p2.shape}"
            )

        # =================================
        # CONV3 INT32
        # =================================

        acc3 = ptq.conv2d_int32(
            p2,
            p["conv3_weight"],
            p["conv3_bias"]
        )

        if acc3.shape != (24, 8, 8):
            raise RuntimeError(
                f"Invalid Conv3 accumulator shape: {acc3.shape}"
            )

        # =================================
        # CONV3 REQUANTIZATION + RELU
        # =================================

        q3, sat3 = ptq.requantize_relu_uint8(
            acc3,
            p["conv3_multiplier_q31"],
            p["conv3_shift"]
        )

        saturation_counts["conv3"] += int(sat3)

        if q3.shape != (24, 8, 8):
            raise RuntimeError(
                f"Invalid Conv3 output shape: {q3.shape}"
            )

        # =================================
        # GAP + FULLY CONNECTED
        # =================================

        gap_sum = q3.astype(np.int64).sum(axis=(1, 2))

        fc_acc64 = np.sum(
            gap_sum[None, :] *
            p["fc_weight"].astype(np.int64),
            axis=1
        )

        fc_acc64 += p["fc_bias"].astype(np.int64)

        if np.any(fc_acc64 < INT32_MIN) or np.any(
            fc_acc64 > INT32_MAX
        ):
            raise OverflowError("FC INT32 overflow.")

        logits = fc_acc64.astype(np.int32)

        # =================================
        # VERIFY ORIGINAL GOLDEN LOGITS
        # =================================

        if not np.array_equal(
            logits,
            expected_logits[image_index]
        ):
            raise RuntimeError(
                f"Golden logits mismatch at image {image_index}."
            )

        # =================================
        # SAVE CONV3 GOLDEN DATA
        # =================================

        input_features.append(p2)
        expected_accumulators.append(acc3)
        expected_outputs.append(q3)

        verified_images += 1

        print(
            f"Image {image_index + 1}/{n}: "
            f"Input={p2.size}, "
            f"Accumulator={acc3.size}, "
            f"Output={q3.size}, "
            f"Logits EXACT MATCH"
        )

    # =================================
    # STACK DATA
    # =================================

    input_features = np.stack(input_features)
    expected_accumulators = np.stack(expected_accumulators)
    expected_outputs = np.stack(expected_outputs)

    # =================================
    # FINAL SHAPE VALIDATION
    # =================================

    if input_features.shape != (n, 16, 8, 8):
        raise RuntimeError("Invalid Conv3 input shape.")

    if expected_accumulators.shape != (n, 24, 8, 8):
        raise RuntimeError("Invalid Conv3 accumulator shape.")

    if expected_outputs.shape != (n, 24, 8, 8):
        raise RuntimeError("Invalid Conv3 output shape.")

    # =================================
    # OUTPUT DIRECTORY
    # =================================

    output_dir = Path(args.output)

    if output_dir.exists():
        if not output_dir.is_dir():
            raise RuntimeError("Output path is not a directory.")

        if any(output_dir.iterdir()):
            raise RuntimeError(
                "Output directory is not empty. "
                "Use a new directory."
            )

    output_dir.mkdir(parents=True, exist_ok=True)

    # =================================
    # WRITE MEMORY FILES
    # =================================

    input_file = (
        output_dir / "conv3_input_features_u8.mem"
    )

    accumulator_file = (
        output_dir / "conv3_expected_acc_int32.mem"
    )

    output_file = (
        output_dir / "conv3_expected_outputs_u8.mem"
    )

    write_hex(input_file, input_features, 2)
    write_hex(accumulator_file, expected_accumulators, 8)
    write_hex(output_file, expected_outputs, 2)

    # =================================
    # FILE MANIFEST
    # =================================

    files = {}

    for path in (
        input_file,
        accumulator_file,
        output_file
    ):
        with open(path, "r", encoding="ascii") as f:
            line_count = sum(1 for _ in f)

        files[path.name] = {
            "sha256": sha256(path),
            "lines": line_count
        }

    manifest = {
        "status": "PASS",
        "golden_images": verified_images,

        "conv3_input_shape": list(input_features.shape),
        "conv3_accumulator_shape": list(
            expected_accumulators.shape
        ),
        "conv3_output_shape": list(expected_outputs.shape),

        "input_layout": "[image][channel][y][x]",
        "accumulator_layout": "[image][channel][y][x]",
        "output_layout": "[image][channel][y][x]",

        "input_values": int(input_features.size),
        "accumulator_values": int(expected_accumulators.size),
        "output_values": int(expected_outputs.size),

        "input_channels": 16,
        "output_channels": 24,
        "kernel": [3, 3],
        "padding": "same_zero_padding",
        "stride": 1,
        "tap_per_pixel": 144,

        "saturation_counts": saturation_counts,

        "final_logits_verification": "EXACT MATCH",
        "test_split_accessed": False,

        "files": files
    }

    manifest_file = (
        output_dir / "conv3_vectors_manifest.json"
    )

    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=4)

    print("--------------------------------------")
    print("CONV3 GOLDEN VECTOR GENERATION PASS")
    print("--------------------------------------")
    print("Golden images:", verified_images)
    print("Input vectors:", input_features.size)
    print("Accumulators:", expected_accumulators.size)
    print("Output vectors:", expected_outputs.size)
    print("Final logits: EXACT MATCH")
    print("Saturation:", saturation_counts)
    print("Output:", output_dir)


if __name__ == "__main__":
    main()
