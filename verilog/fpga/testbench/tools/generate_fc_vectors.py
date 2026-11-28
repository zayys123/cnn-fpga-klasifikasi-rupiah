
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def read_hex(path, expected_count):
    values = []

    with open(path, "r", encoding="ascii") as f:
        for line in f:
            line = line.strip()

            if line:
                values.append(int(line, 16))

    if len(values) != expected_count:
        raise RuntimeError(
            f"{path}: expected {expected_count} values, "
            f"got {len(values)}"
        )

    return np.asarray(values, dtype=np.uint32)


def write_hex(path, values, width):
    mask = (1 << (width * 4)) - 1

    with open(path, "w", encoding="ascii", newline="\n") as f:
        for value in np.asarray(values).reshape(-1):
            f.write(
                f"{int(value) & mask:0{width}X}\n"
            )


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

    parser.add_argument("--gap-input", required=True)
    parser.add_argument("--parameters", required=True)
    parser.add_argument("--golden", required=True)
    parser.add_argument("--output", required=True)

    args = parser.parse_args()

    # =====================================
    # LOAD GAP GOLDEN INPUT
    # =====================================

    gap = read_hex(
        args.gap_input,
        14 * 24
    ).reshape(14, 24)

    if np.any(gap > 16320):
        raise RuntimeError(
            "GAP value exceeds theoretical UINT14 sum."
        )

    # =====================================
    # LOAD QUANTIZED PARAMETERS
    # =====================================

    with np.load(
        args.parameters,
        allow_pickle=False
    ) as z:

        fc_weight = z["fc_weight"].copy()
        fc_bias = z["fc_bias"].copy()

    if fc_weight.shape != (7, 24):
        raise RuntimeError(
            f"Invalid FC weight shape: {fc_weight.shape}"
        )

    if fc_weight.dtype != np.int8:
        raise RuntimeError("FC weight must be INT8.")

    if fc_bias.shape != (7,):
        raise RuntimeError(
            f"Invalid FC bias shape: {fc_bias.shape}"
        )

    if fc_bias.dtype != np.int32:
        raise RuntimeError("FC bias must be INT32.")

    # =====================================
    # LOAD ORIGINAL GOLDEN LOGITS
    # =====================================

    with np.load(
        args.golden,
        allow_pickle=False
    ) as z:

        expected_logits = (
            z["expected_logits_int32"].copy()
        )

    if expected_logits.shape != (14, 7):
        raise RuntimeError(
            "Invalid expected logits shape."
        )

    # =====================================
    # FC INTEGER INFERENCE
    # =====================================

    print("======================================")
    print("GENERATING FC GOLDEN VECTORS")
    print("======================================")

    fc_acc64 = (
        gap.astype(np.int64)
        @ fc_weight.astype(np.int64).T
    )

    fc_acc64 += fc_bias.astype(np.int64)[None, :]

    # =====================================
    # INT32 OVERFLOW CHECK
    # =====================================

    INT32_MIN = -(2**31)
    INT32_MAX = 2**31 - 1

    if np.any(fc_acc64 < INT32_MIN) or np.any(
        fc_acc64 > INT32_MAX
    ):
        raise OverflowError(
            "FC accumulator exceeds INT32."
        )

    logits = fc_acc64.astype(np.int32)

    # =====================================
    # EXACT GOLDEN VERIFICATION
    # =====================================

    if not np.array_equal(logits, expected_logits):

        mismatch = np.argwhere(
            logits != expected_logits
        )

        print("FC GOLDEN VERIFICATION FAILED")

        for image_index, class_index in mismatch[:20]:

            print(
                f"Image={image_index + 1}, "
                f"Class={class_index}, "
                f"Expected={expected_logits[image_index, class_index]}, "
                f"Actual={logits[image_index, class_index]}"
            )

        raise RuntimeError(
            f"FC mismatch count: {len(mismatch)}"
        )

    predicted_classes = np.argmax(
        logits, axis=1
    ).astype(np.uint8)

    print("--------------------------------------")

    for i in range(len(gap)):

        print(
            f"Image {i + 1}/{len(gap)}: "
            f"24 MAC operations/class, "
            f"7 logits EXACT MATCH, "
            f"Predicted class={predicted_classes[i]}"
        )

    # =====================================
    # OUTPUT DIRECTORY
    # =====================================

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

    # =====================================
    # WRITE GOLDEN OUTPUTS
    # =====================================

    logits_file = (
        output_dir / "fc_expected_logits_int32.mem"
    )

    classes_file = (
        output_dir / "fc_expected_classes_u3.mem"
    )

    write_hex(logits_file, logits, 8)

    write_hex(
        classes_file,
        predicted_classes,
        1
    )

    # =====================================
    # MANIFEST
    # =====================================

    manifest = {

        "status": "PASS",

        "golden_images": 14,

        "input_shape": [14, 24],

        "weight_shape": [7, 24],

        "bias_shape": [7],

        "output_shape": [14, 7],

        "input_dtype": "UINT14",

        "weight_dtype": "INT8",

        "bias_dtype": "INT32",

        "accumulator_dtype": "INT32",

        "input_layout": "[image][channel]",

        "weight_layout": "[class][channel]",

        "output_layout": "[image][class]",

        "mac_operations_per_image": 168,

        "total_mac_operations": 2352,

        "logits_count": 98,

        "class_count": 7,

        "requantization": False,

        "golden_logits_verification": "EXACT MATCH",

        "logit_mismatches": 0,

        "test_split_accessed": False,

        "predicted_classes": predicted_classes.tolist(),

        "files": {

            logits_file.name: {

                "sha256": sha256(logits_file),

                "lines": 98

            },

            classes_file.name: {

                "sha256": sha256(classes_file),

                "lines": 14

            }

        }

    }

    manifest_file = (
        output_dir / "fc_vectors_manifest.json"
    )

    with open(
        manifest_file,
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            manifest,
            f,
            indent=4
        )

    print("--------------------------------------")
    print("FC GOLDEN VECTOR GENERATION PASS")
    print("--------------------------------------")
    print("Images:", len(gap))
    print("GAP inputs:", gap.size)
    print("FC weights:", fc_weight.size)
    print("Total MAC operations:", 2352)
    print("FC logits:", logits.size)
    print("Logit mismatches:", 0)
    print("Predicted classes:", predicted_classes.tolist())
    print("Output:", output_dir)


if __name__ == "__main__":
    main()
