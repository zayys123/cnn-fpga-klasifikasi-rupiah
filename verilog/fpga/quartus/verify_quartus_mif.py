
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]

SOURCE_DIR = (
    ROOT / "artifacts" /
    "ptq_int8_32x32_20261127_run1" /
    "weights_mem"
)

MIF_DIR = (
    ROOT / "verilog" / "fpga" /
    "weights" / "mif"
)

SPECS = [
    ("conv1_weights_int8.mif", "conv1_weights_int8.mem", 8, 216, "hex"),
    ("conv1_bias_int32.mif", "conv1_bias_int32.mem", 32, 8, "hex"),
    ("conv1_requant_multiplier_q31.mif", "conv1_requant_multiplier_q31.mem", 32, 8, "hex"),
    ("conv1_requant_shift_s8.mif", "conv1_requant_shift.txt", 8, 8, "decimal"),

    ("conv2_weights_int8.mif", "conv2_weights_int8.mem", 8, 1152, "hex"),
    ("conv2_bias_int32.mif", "conv2_bias_int32.mem", 32, 16, "hex"),
    ("conv2_requant_multiplier_q31.mif", "conv2_requant_multiplier_q31.mem", 32, 16, "hex"),
    ("conv2_requant_shift_s8.mif", "conv2_requant_shift.txt", 8, 16, "decimal"),

    ("conv3_weights_int8.mif", "conv3_weights_int8.mem", 8, 3456, "hex"),
    ("conv3_bias_int32.mif", "conv3_bias_int32.mem", 32, 24, "hex"),
    ("conv3_requant_multiplier_q31.mif", "conv3_requant_multiplier_q31.mem", 32, 24, "hex"),
    ("conv3_requant_shift_s8.mif", "conv3_requant_shift.txt", 8, 24, "decimal"),

    ("fc_weights_int8.mif", "fc_weights_int8.mem", 8, 168, "hex"),
    ("fc_bias_int32.mif", "fc_bias_int32.mem", 32, 7, "hex"),
]


def read_source(filename, width, data_type):
    path = SOURCE_DIR / filename

    if not path.exists():
        raise FileNotFoundError(path)

    tokens = [
        line.strip()
        for line in path.read_text(encoding="ascii").splitlines()
        if line.strip()
    ]

    mask = (1 << width) - 1

    if data_type == "decimal":
        values = [int(x, 10) & mask for x in tokens]
    else:
        values = [int(x, 16) for x in tokens]

    return values


def read_mif(filename, expected_width, expected_depth):
    path = MIF_DIR / filename

    if not path.exists():
        raise FileNotFoundError(path)

    content = path.read_text(encoding="ascii")

    width_match = re.search(
        r"WIDTH\s*=\s*(\d+)\s*;",
        content, re.I
    )

    depth_match = re.search(
        r"DEPTH\s*=\s*(\d+)\s*;",
        content, re.I
    )

    if not width_match or not depth_match:
        raise ValueError("Missing WIDTH or DEPTH header")

    width = int(width_match.group(1))
    depth = int(depth_match.group(1))

    if width != expected_width:
        raise ValueError(
            f"WIDTH mismatch: {width} != {expected_width}"
        )

    if depth != expected_depth:
        raise ValueError(
            f"DEPTH mismatch: {depth} != {expected_depth}"
        )

    if not re.search(r"DATA_RADIX\s*=\s*HEX\s*;", content, re.I):
        raise ValueError("DATA_RADIX must be HEX")

    if not re.search(r"ADDRESS_RADIX\s*=\s*UNS\s*;", content, re.I):
        raise ValueError("ADDRESS_RADIX must be UNS")

    body_match = re.search(
        r"CONTENT\s+BEGIN(.*?)END\s*;",
        content, re.I | re.S
    )

    if not body_match:
        raise ValueError("Invalid CONTENT section")

    entries = {}

    for line in body_match.group(1).splitlines():
        line = line.strip()

        if not line:
            continue

        match = re.fullmatch(
            r"(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;",
            line
        )

        if not match:
            raise ValueError(f"Invalid MIF entry: {line}")

        address = int(match.group(1))
        value = int(match.group(2), 16)

        if address in entries:
            raise ValueError(f"Duplicate address: {address}")

        if address < 0 or address >= depth:
            raise ValueError(f"Invalid address: {address}")

        if value >= (1 << width):
            raise ValueError(f"Value exceeds WIDTH at {address}")

        entries[address] = value

    expected_addresses = set(range(depth))

    if set(entries) != expected_addresses:
        missing = expected_addresses - set(entries)
        raise ValueError(f"Missing addresses: {sorted(missing)[:10]}")

    return [entries[i] for i in range(depth)]


def main():
    print("=" * 55)
    print("QUARTUS MIF CONTENT VERIFICATION")
    print("=" * 55)

    total_words = 0
    errors = 0

    for mif, source, width, depth, data_type in SPECS:

        try:
            expected = read_source(
                source, width, data_type
            )

            actual = read_mif(
                mif, width, depth
            )

            if len(expected) != depth:
                raise ValueError(
                    f"Source depth mismatch: {len(expected)}"
                )

            if expected != actual:
                mismatches = [
                    i for i, (a, b) in enumerate(
                        zip(expected, actual)
                    ) if a != b
                ]

                raise ValueError(
                    f"Data mismatch at addresses: {mismatches[:10]}"
                )

            total_words += depth

            print(
                f"PASS: {mif:40s} "
                f"WIDTH={width} DEPTH={depth}"
            )

        except Exception as exc:
            errors += 1
            print(f"FAIL: {mif}")
            print(f"      {exc}")

    print("=" * 55)
    print("ROM FILES :", len(SPECS))
    print("ROM WORDS :", total_words)
    print("ERRORS    :", errors)

    if errors == 0 and total_words == 5143:
        print("=" * 55)
        print("QUARTUS MIF VERIFICATION PASS")
        print("ALL 5143 WORDS EXACT MATCH")
        print("=" * 55)
    else:
        print("QUARTUS MIF VERIFICATION FAILED")
        sys.exit(1)


if __name__ == "__main__":
    main()
