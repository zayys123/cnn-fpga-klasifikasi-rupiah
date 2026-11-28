
from pathlib import Path
import hashlib
import json

ROOT = Path("artifacts/ptq_int8_32x32_20261127_run1")

SOURCE = ROOT / "rtl_vectors" / "maxpool_actual_vectors.mem"

CONV2_INPUT = (
    ROOT / "rtl_vectors" / "conv2_golden"
    / "conv2_input_features_u8.mem"
)

CONV3_INPUT = (
    ROOT / "conv3_golden_run1"
    / "conv3_input_features_u8.mem"
)

OUTPUT = ROOT / "maxpool_golden_run1"

NUM_IMAGES = 14

POOL1_CHANNELS = 8
POOL1_INPUT_WIDTH = 32
POOL1_RECORDS = 8 * 16 * 16

POOL2_CHANNELS = 16
POOL2_INPUT_WIDTH = 16
POOL2_RECORDS = 16 * 8 * 8


def read_hex(path):
    return [
        int(line.strip(), 16)
        for line in path.read_text(encoding="ascii").splitlines()
        if line.strip()
    ]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unpack_pool(records, layer_id, channels, input_width):

    output_width = input_width // 2

    input_map = [
        None
    ] * (channels * input_width * input_width)

    expected_outputs = []

    expected_records = channels * output_width * output_width

    if len(records) != expected_records:
        raise ValueError(
            f"Layer {layer_id}: invalid record count"
        )

    for index, word in enumerate(records):

        p00 = (word >> 40) & 0xFF
        p01 = (word >> 32) & 0xFF
        p10 = (word >> 24) & 0xFF
        p11 = (word >> 16) & 0xFF

        expected = (word >> 8) & 0xFF
        actual_layer = word & 0xFF

        if actual_layer != layer_id:
            raise ValueError(
                f"Invalid layer ID at record {index}"
            )

        if max(p00, p01, p10, p11) != expected:
            raise ValueError(
                f"MaxPool mismatch at record {index}"
            )

        channel = index // (output_width * output_width)

        position = index % (output_width * output_width)

        out_y = position // output_width
        out_x = position % output_width

        base = channel * input_width * input_width

        addresses = [
            base + (2 * out_y) * input_width + (2 * out_x),
            base + (2 * out_y) * input_width + (2 * out_x) + 1,
            base + (2 * out_y + 1) * input_width + (2 * out_x),
            base + (2 * out_y + 1) * input_width + (2 * out_x) + 1,
        ]

        pixels = [p00, p01, p10, p11]

        for address, pixel in zip(addresses, pixels):

            if input_map[address] is not None:
                raise ValueError(
                    f"Duplicate input address: {address}"
                )

            input_map[address] = pixel

        expected_outputs.append(expected)

    if any(value is None for value in input_map):
        raise ValueError(
            f"Layer {layer_id}: missing input pixels"
        )

    return input_map, expected_outputs


def write_mem(path, values):

    path.parent.mkdir(parents=True, exist_ok=True)

    path.write_text(
        "".join(f"{int(v):02X}\n" for v in values),
        encoding="ascii"
    )

    return {
        "sha256": sha256(path),
        "lines": len(values)
    }


def main():

    print("=" * 40)
    print("GENERATING MAXPOOL GOLDEN VECTORS")
    print("=" * 40)

    records = read_hex(SOURCE)

    expected_total = NUM_IMAGES * (
        POOL1_RECORDS + POOL2_RECORDS
    )

    if len(records) != expected_total:
        raise ValueError(
            f"Expected {expected_total}, got {len(records)}"
        )

    pool1_inputs = []
    pool1_outputs = []

    pool2_inputs = []
    pool2_outputs = []

    cursor = 0

    for image in range(NUM_IMAGES):

        print(
            f"Processing image {image + 1}/{NUM_IMAGES}"
        )

        p1_records = records[
            cursor:cursor + POOL1_RECORDS
        ]

        cursor += POOL1_RECORDS

        p2_records = records[
            cursor:cursor + POOL2_RECORDS
        ]

        cursor += POOL2_RECORDS

        p1_in, p1_out = unpack_pool(
            p1_records,
            1,
            POOL1_CHANNELS,
            POOL1_INPUT_WIDTH
        )

        p2_in, p2_out = unpack_pool(
            p2_records,
            2,
            POOL2_CHANNELS,
            POOL2_INPUT_WIDTH
        )

        pool1_inputs.extend(p1_in)
        pool1_outputs.extend(p1_out)

        pool2_inputs.extend(p2_in)
        pool2_outputs.extend(p2_out)

    if cursor != len(records):
        raise ValueError("Unused source records detected")

    # Cross-check Pool1 against Conv2 input.
    conv2_input = read_hex(CONV2_INPUT)

    if pool1_outputs != conv2_input:
        raise ValueError(
            "Pool1 output does not match Conv2 input"
        )

    # Cross-check Pool2 against Conv3 input.
    conv3_input = read_hex(CONV3_INPUT)

    if pool2_outputs != conv3_input:
        raise ValueError(
            "Pool2 output does not match Conv3 input"
        )

    OUTPUT.mkdir(parents=True, exist_ok=True)

    files = {}

    files["pool1_input_features_u8.mem"] = write_mem(
        OUTPUT / "pool1_input_features_u8.mem",
        pool1_inputs
    )

    files["pool1_expected_outputs_u8.mem"] = write_mem(
        OUTPUT / "pool1_expected_outputs_u8.mem",
        pool1_outputs
    )

    files["pool2_input_features_u8.mem"] = write_mem(
        OUTPUT / "pool2_input_features_u8.mem",
        pool2_inputs
    )

    files["pool2_expected_outputs_u8.mem"] = write_mem(
        OUTPUT / "pool2_expected_outputs_u8.mem",
        pool2_outputs
    )

    manifest = {
        "status": "PASS",
        "golden_images": NUM_IMAGES,

        "pool1": {
            "input_shape": [14, 8, 32, 32],
            "output_shape": [14, 8, 16, 16],
            "input_values": len(pool1_inputs),
            "output_values": len(pool1_outputs),
            "crosscheck_conv2_input": "EXACT MATCH"
        },

        "pool2": {
            "input_shape": [14, 16, 16, 16],
            "output_shape": [14, 16, 8, 8],
            "input_values": len(pool2_inputs),
            "output_values": len(pool2_outputs),
            "crosscheck_conv3_input": "EXACT MATCH"
        },

        "operation": "2x2 unsigned maximum pooling",
        "stride": 2,
        "padding": "none",
        "input_layout": "[image][channel][y][x]",
        "output_layout": "[image][channel][y][x]",

        "files": files
    }

    manifest_path = OUTPUT / "maxpool_vectors_manifest.json"

    manifest_path.write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8"
    )

    print("-" * 40)
    print("MAXPOOL GOLDEN VECTOR GENERATION PASS")
    print("-" * 40)

    print("Images:", NUM_IMAGES)

    print("Pool1 input:", len(pool1_inputs))
    print("Pool1 output:", len(pool1_outputs))

    print("Pool2 input:", len(pool2_inputs))
    print("Pool2 output:", len(pool2_outputs))

    print("Pool1 vs Conv2: EXACT MATCH")
    print("Pool2 vs Conv3: EXACT MATCH")

    print("Output:", OUTPUT)


if __name__ == "__main__":
    main()
