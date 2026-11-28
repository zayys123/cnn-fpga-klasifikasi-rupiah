import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


NUM_IMAGES = 14
NUM_CHANNELS = 24
HEIGHT = 8
WIDTH = 8
VALUES_PER_IMAGE = NUM_CHANNELS * HEIGHT * WIDTH
GAP_ACCUMULATOR_MAX = 255 * HEIGHT * WIDTH


def read_hex(path, expected_count, max_value):
    values = []

    with open(path, "r", encoding="ascii") as f:
        for line_number, line in enumerate(f, 1):
            token = line.strip()

            if not token:
                continue

            try:
                value = int(token, 16)
            except ValueError as exc:
                raise ValueError(
                    f"Invalid hex at {path}:{line_number}"
                ) from exc

            if value < 0 or value > max_value:
                raise ValueError(
                    f"Out-of-range value at line {line_number}"
                )

            values.append(value)

    if len(values) != expected_count:
        raise ValueError(
            f"{path}: expected {expected_count} values, "
            f"got {len(values)}"
        )

    return np.asarray(values, dtype=np.uint8)


def write_hex(path, values, digits):
    with open(path, "w", encoding="ascii", newline="\n") as f:
        for value in np.asarray(values).reshape(-1):
            f.write(f"{int(value):0{digits}X}\n")


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

    parser.add_argument("--conv3-output", required=True)
    parser.add_argument("--parameters", required=True)
    parser.add_argument("--golden", required=True)
    parser.add_argument("--output", required=True)

    args = parser.parse_args()

    print("======================================")
    print("GENERATING GAP GOLDEN VECTORS")
    print("======================================")

    # Load Conv3 UINT8 output.
    q3 = read_hex(
        args.conv3_output,
        NUM_IMAGES * VALUES_PER_IMAGE,
        255
    )

    q3 = q3.reshape(
        NUM_IMAGES,
        NUM_CHANNELS,
        HEIGHT,
        WIDTH
    )

    # GAP: SUM, NOT AVERAGE.
    gap = q3.astype(np.uint32).sum(
        axis=(2, 3),
        dtype=np.uint32
    )

    if gap.shape != (NUM_IMAGES, NUM_CHANNELS):
        raise RuntimeError("Invalid GAP output shape.")

    if int(gap.max()) > GAP_ACCUMULATOR_MAX:
        raise OverflowError("GAP exceeds UINT14 range.")

    # Load FC parameters.
    with np.load(
        args.parameters,
        allow_pickle=False
    ) as p:

        fc_weight = p["fc_weight"].copy()
        fc_bias = p["fc_bias"].copy()

    if fc_weight.shape != (7, 24):
        raise ValueError("Invalid FC weight shape.")

    if fc_bias.shape != (7,):
        raise ValueError("Invalid FC bias shape.")

    # Load original golden logits.
    with np.load(
        args.golden,
        allow_pickle=False
    ) as g:

        expected_logits = g[
            "expected_logits_int32"
        ].copy()

    if expected_logits.shape != (NUM_IMAGES, 7):
        raise ValueError("Invalid golden logits shape.")

    # Validate downstream FC using GAP results.
    logits64 = (
        gap.astype(np.int64)
        @ fc_weight.astype(np.int64).T
    )

    logits64 += fc_bias.astype(np.int64)[None, :]

    if np.any(logits64 < -(2**31)) or np.any(
        logits64 > 2**31 - 1
    ):
        raise OverflowError("FC INT32 overflow.")

    logits = logits64.astype(np.int32)

    if not np.array_equal(logits, expected_logits):
        raise RuntimeError(
            "FC golden logits mismatch."
        )

    # Prepare output directory.
    output_dir = Path(args.output)

    if output_dir.exists() and any(output_dir.iterdir()):
        raise RuntimeError(
            "Output directory is not empty. "
            "Use a new directory."
        )

    output_dir.mkdir(
        parents=True,
        exist_ok=True
    )

    # Write input and expected GAP values.
    input_file = (
        output_dir / "gap_input_features_u8.mem"
    )

    expected_file = (
        output_dir / "gap_expected_sums_u14.mem"
    )

    write_hex(input_file, q3, 2)
    write_hex(expected_file, gap, 4)

    files = {}

    for path in (input_file, expected_file):
        files[path.name] = {
            "sha256": sha256(path),
            "lines": sum(
                1 for _ in open(path, encoding="ascii")
            )
        }

    manifest = {
        "status": "PASS",
        "golden_images": NUM_IMAGES,
        "input_shape": list(q3.shape),
        "output_shape": list(gap.shape),
        "input_layout": "[image][channel][y][x]",
        "output_layout": "[image][channel]",
        "operation": "unsigned_sum_over_8x8",
        "division_by_64": False,
        "input_values": int(q3.size),
        "output_values": int(gap.size),
        "accumulator_width_bits": 14,
        "maximum_theoretical_sum": GAP_ACCUMULATOR_MAX,
        "actual_minimum": int(gap.min()),
        "actual_maximum": int(gap.max()),
        "fc_logits_verification": "EXACT MATCH",
        "fc_mismatches": 0,
        "test_split_accessed": False,
        "files": files
    }

    manifest_file = (
        output_dir / "gap_vectors_manifest.json"
    )

    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=4)

    print("--------------------------------------")
    print("GAP GOLDEN VECTOR GENERATION PASS")
    print("--------------------------------------")
    print("Images:", NUM_IMAGES)
    print("Input values:", q3.size)
    print("GAP outputs:", gap.size)
    print("GAP minimum:", int(gap.min()))
    print("GAP maximum:", int(gap.max()))
    print("FC logits: EXACT MATCH")
    print("FC mismatches: 0")
    print("Output:", output_dir)


if __name__ == "__main__":
    main()
