
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[3]

SOURCE_DIR = (
    ROOT
    / "artifacts"
    / "ptq_int8_32x32_20261127_run1"
    / "weights_mem"
)

OUTPUT_DIR = ROOT / "verilog" / "fpga" / "weights" / "mif"


# source, destination, width, depth, encoding
SPECS = [
    ("conv1_weights_int8.mem", "conv1_weights_int8.mif", 8, 216, "hex"),
    ("conv1_bias_int32.mem", "conv1_bias_int32.mif", 32, 8, "hex"),
    ("conv1_requant_multiplier_q31.mem", "conv1_requant_multiplier_q31.mif", 32, 8, "hex"),
    ("conv1_requant_shift.txt", "conv1_requant_shift_s8.mif", 8, 8, "signed"),

    ("conv2_weights_int8.mem", "conv2_weights_int8.mif", 8, 1152, "hex"),
    ("conv2_bias_int32.mem", "conv2_bias_int32.mif", 32, 16, "hex"),
    ("conv2_requant_multiplier_q31.mem", "conv2_requant_multiplier_q31.mif", 32, 16, "hex"),
    ("conv2_requant_shift.txt", "conv2_requant_shift_s8.mif", 8, 16, "signed"),

    ("conv3_weights_int8.mem", "conv3_weights_int8.mif", 8, 3456, "hex"),
    ("conv3_bias_int32.mem", "conv3_bias_int32.mif", 32, 24, "hex"),
    ("conv3_requant_multiplier_q31.mem", "conv3_requant_multiplier_q31.mif", 32, 24, "hex"),
    ("conv3_requant_shift.txt", "conv3_requant_shift_s8.mif", 8, 24, "signed"),

    ("fc_weights_int8.mem", "fc_weights_int8.mif", 8, 168, "hex"),
    ("fc_bias_int32.mem", "fc_bias_int32.mif", 32, 7, "hex"),
]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_values(path, width, depth, encoding):
    lines = [
        line.strip()
        for line in path.read_text(encoding="ascii").splitlines()
        if line.strip()
    ]

    if len(lines) != depth:
        raise ValueError(
            f"{path.name}: expected {depth} words, got {len(lines)}"
        )

    values = []
    maximum = (1 << width) - 1

    for index, token in enumerate(lines):

        if encoding == "signed":
            value = int(token, 10)

            minimum_signed = -(1 << (width - 1))
            maximum_signed = (1 << (width - 1)) - 1

            if not minimum_signed <= value <= maximum_signed:
                raise ValueError(
                    f"{path.name}: invalid signed value at {index}: {value}"
                )

            value &= maximum

        else:
            value = int(token, 16)

            if not 0 <= value <= maximum:
                raise ValueError(
                    f"{path.name}: invalid hexadecimal value at {index}"
                )

        values.append(value)

    return values


def generate_mif(path, width, values):
    depth = len(values)
    digits = width // 4

    lines = [
        f"WIDTH={width};",
        f"DEPTH={depth};",
        "",
        "ADDRESS_RADIX=UNS;",
        "DATA_RADIX=HEX;",
        "",
        "CONTENT BEGIN",
    ]

    for address, value in enumerate(values):
        lines.append(
            f"    {address} : {value:0{digits}X};"
        )

    lines.append("END;")

    path.write_text(
        "\n".join(lines) + "\n",
        encoding="ascii",
        newline="\n"
    )


def main():
    print("=" * 50)
    print("PREPARING QUARTUS ROM INITIALIZATION FILES")
    print("=" * 50)

    if not SOURCE_DIR.is_dir():
        raise FileNotFoundError(SOURCE_DIR)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    manifest = {
        "project": "RupiahVision CNN FPGA",
        "format": "Intel Quartus MIF",
        "source": str(SOURCE_DIR.relative_to(ROOT)),
        "total_roms": len(SPECS),
        "total_words": 0,
        "roms": []
    }

    total_words = 0

    for source, destination, width, depth, encoding in SPECS:

        source_path = SOURCE_DIR / source
        output_path = OUTPUT_DIR / destination

        if not source_path.is_file():
            raise FileNotFoundError(source_path)

        values = load_values(
            source_path,
            width,
            depth,
            encoding
        )

        generate_mif(
            output_path,
            width,
            values
        )

        total_words += depth

        entry = {
            "source": source,
            "output": destination,
            "width": width,
            "depth": depth,
            "encoding": encoding,
            "source_sha256": sha256(source_path),
            "output_sha256": sha256(output_path)
        }

        manifest["roms"].append(entry)

        print(
            f"PASS: {destination:<38} "
            f"WIDTH={width:<2} DEPTH={depth}"
        )

    manifest["total_words"] = total_words

    if len(SPECS) != 14 or total_words != 5143:
        raise RuntimeError("Unexpected ROM inventory.")

    manifest_path = OUTPUT_DIR / "rom_manifest.json"

    manifest_path.write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8"
    )

    print("=" * 50)
    print("QUARTUS MIF GENERATION PASS")
    print("=" * 50)
    print("ROM files :", len(SPECS))
    print("ROM words :", total_words)
    print("Output    :", OUTPUT_DIR)
    print("Manifest  :", manifest_path)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("ERROR:", exc)
        sys.exit(1)
