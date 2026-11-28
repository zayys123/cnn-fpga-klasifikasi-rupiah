# CNN FPGA - Quartus ROM Test Project

## Target Hardware

- Board: Terasic DE10-Standard
- FPGA: Cyclone V SX SoC
- Device: 5CSXFC6D6F31C6
- FPGA Family: Cyclone V
- Quartus: Prime Lite 25.1std

## Current Implementation

The current Quartus project implements a ROM verification interface.

Top-level module:

- cnn_rom_test_top

Supporting modules:

- cnn_rom_bank
- sync_rom_mif

The ROM bank contains 14 initialized memories for:

- Conv1 weights, bias and requantization parameters
- Conv2 weights, bias and requantization parameters
- Conv3 weights, bias and requantization parameters
- Fully connected weights and bias

IMPORTANT:
This top-level is currently a ROM access test interface.
It is not yet the complete end-to-end CNN inference architecture.

## Memory Initialization

ROM initialization files are located in:

../weights/mif/

Total:
- 14 MIF files
- 5,143 memory words

Generate MIF files:

From repository root:

```powershell
python .\verilog\fpga\quartus\prepare_quartus_mif.py
```

Verify MIF contents:

```powershell
python .\verilog\fpga\quartus\verify_quartus_mif.py
```

Expected result:

QUARTUS MIF VERIFICATION PASS
ALL 5143 WORDS EXACT MATCH

## Quartus Project

Project files:

- cnn_fpga.qpf
- cnn_fpga.qsf
- cnn_fpga.sdc

Open cnn_fpga.qpf using Quartus Prime.

## Full Compilation

Run from repository root:

```powershell
$Q = 'D:\altera_lite\25.1std\quartus'

Push-Location .\verilog\fpga\quartus

& "$Q\bin64\quartus_sh.exe" --flow compile cnn_fpga

$compileResult = $LASTEXITCODE

Pop-Location

if ($compileResult -eq 0) {
    Write-Output "QUARTUS FULL COMPILATION PASS"
} else {
    Write-Output "QUARTUS FULL COMPILATION FAILED"
}
```

This runs the Quartus compilation flow.
It does not program the physical FPGA board.

## Current Validation Status

- Device recognition: PASS
- ROM generation: PASS
- ROM verification: PASS
- RTL compilation: PASS
- Quartus Fitter: PASS
- Timing Analyzer: Successful, but design is not fully constrained.

## Known Limitations

1. Clock input is assigned to PIN_AF14.
2. The clock is constrained to 50 MHz.
3. Remaining 48 top-level I/O pins have not been assigned.
4. Complete board-level pin mapping is pending.
5. Input/output timing constraints are not yet complete.
6. Physical FPGA programming has not been performed.
7. Full CNN inference integration is still pending.

Complete physical pin assignments and timing constraints
before treating the design as ready for hardware validation.

## Repository Policy

Keep source files, MIF files, project configuration,
and reproducible scripts under version control.

Do not commit Quartus temporary databases or generated
compilation directories.
