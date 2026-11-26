import argparse
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np


def load_reference(path):
    spec = importlib.util.spec_from_file_location(
        "rupiahvision_ptq_reference", path
    )

    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load PTQ reference module.")

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
            raise RuntimeError(f"Missing reference function: {name}")

    return module


def make_records(feature, pooled, layer_id):
    channels, height, width = feature.shape

    if height % 2 or width % 2:
        raise ValueError("Feature map dimensions must be even.")

    expected_shape = (channels, height // 2, width // 2)

    if pooled.shape != expected_shape:
        raise ValueError("Unexpected pooled output shape.")

    records = []

    for ch in range(channels):
        for y in range(0, height, 2):
            for x in range(0, width, 2):

                p00 = int(feature[ch, y, x])
                p01 = int(feature[ch, y, x + 1])
                p10 = int(feature[ch, y + 1, x])
                p11 = int(feature[ch, y + 1, x + 1])

                expected = int(pooled[ch, y // 2, x // 2])

                if expected != max(p00, p01, p10, p11):
                    raise RuntimeError("Python MaxPool reference mismatch.")

                # 48-bit record:
                # [47:40] pixel00
                # [39:32] pixel01
                # [31:24] pixel10
                # [23:16] pixel11
                # [15:8]  expected output
                # [7:0]   layer ID

                word = (
                    (p00 << 40)
                    | (p01 << 32)
                    | (p10 << 24)
                    | (p11 << 16)
                    | (expected << 8)
                    | layer_id
                )

                records.append(f"{word:012X}")

    return records


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument("--ptq-script", required=True)
    parser.add_argument("--parameters", required=True)
    parser.add_argument("--golden", required=True)
    parser.add_argument("--output", required=True)

    args = parser.parse_args()

    ptq = load_reference(args.ptq_script)

    with np.load(args.parameters, allow_pickle=False) as z:
        q = {key: z[key] for key in z.files}

    with np.load(args.golden, allow_pickle=False) as z:
        inputs = z["input_chw"]
        expected_logits = z["expected_logits_int32"]

    if inputs.shape[1:] != (3, 32, 32):
        raise RuntimeError("Unexpected golden input shape.")

    all_records = []

    pool1_count = 0
    pool2_count = 0

    for image_index, raw in enumerate(inputs):

        raw = raw.astype(np.uint8, copy=False)

        # Conv1 -> ReLU -> Requantization
        acc1 = ptq.conv2d_int32(
            raw,
            q["conv1_weight"],
            q["conv1_bias"]
        )

        q1, _ = ptq.requantize_relu_uint8(
            acc1,
            q["conv1_multiplier_q31"],
            q["conv1_shift"]
        )

        # Pool1
        p1 = ptq.maxpool2x2_u8(q1)

        records1 = make_records(q1, p1, 1)

        all_records.extend(records1)
        pool1_count += len(records1)

        # Conv2 -> ReLU -> Requantization
        acc2 = ptq.conv2d_int32(
            p1,
            q["conv2_weight"],
            q["conv2_bias"]
        )

        q2, _ = ptq.requantize_relu_uint8(
            acc2,
            q["conv2_multiplier_q31"],
            q["conv2_shift"]
        )

        # Pool2
        p2 = ptq.maxpool2x2_u8(q2)

        records2 = make_records(q2, p2, 2)

        all_records.extend(records2)
        pool2_count += len(records2)

        # Continue CNN to verify golden logits
        acc3 = ptq.conv2d_int32(
            p2,
            q["conv3_weight"],
            q["conv3_bias"]
        )

        q3, _ = ptq.requantize_relu_uint8(
            acc3,
            q["conv3_multiplier_q31"],
            q["conv3_shift"]
        )

        # Global Average Pooling
        gap_sum = q3.astype(np.int64).sum(axis=(1, 2))

        fc_acc64 = np.sum(
            gap_sum[None, :] * q["fc_weight"].astype(np.int64),
            axis=1
        )

        fc_acc64 += q["fc_bias"].astype(np.int64)

        if np.any(fc_acc64 < -(2**31)) or np.any(fc_acc64 > 2**31 - 1):
            raise OverflowError("FC accumulator exceeds INT32.")

        logits = fc_acc64.astype(np.int32)

        if not np.array_equal(logits, expected_logits[image_index]):
            raise RuntimeError(
                f"Golden logits mismatch at image {image_index}."
            )

        print(
            f"Image {image_index + 1}/{len(inputs)}: "
            f"Pool1={len(records1)}, Pool2={len(records2)}, "
            "logits EXACT MATCH"
        )

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    with output.open("w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(all_records) + "\n")

    manifest = {
        "method": "Actual CNN MaxPool verification",
        "golden_images": len(inputs),
        "pool1_vectors": pool1_count,
        "pool2_vectors": pool2_count,
        "total_vectors": len(all_records),
        "record_width_bits": 48,
        "record_width_hex": 12,
        "layer_ids": {
            "1": "Pool1 after Conv1",
            "2": "Pool2 after Conv2"
        },
        "golden_logits_exact_match": True,
        "output": output.name
    }

    manifest_path = output.with_suffix(".json")

    manifest_path.write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8"
    )

    if pool1_count != 28672 or pool2_count != 14336:
        raise RuntimeError("Unexpected MaxPool vector counts.")

    if len(all_records) != 43008:
        raise RuntimeError("Unexpected total vector count.")

    print("--------------------------------------")
    print("MAXPOOL VECTOR GENERATION PASS")
    print("--------------------------------------")
    print("Golden images:", len(inputs))
    print("Pool1 vectors:", pool1_count)
    print("Pool2 vectors:", pool2_count)
    print("Total vectors:", len(all_records))
    print("Final logits: EXACT MATCH")
    print("Output:", output)
    print("Manifest:", manifest_path)


if __name__ == "__main__":
    main()
