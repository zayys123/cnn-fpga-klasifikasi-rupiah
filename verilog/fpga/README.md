# FPGA implementation

Semua source dan konfigurasi yang diperlukan untuk mereproduksi desain FPGA disimpan di sini.

- `rtl/`: modul Verilog/SystemVerilog.
- `testbench/`: testbench, stimulus, dan script ModelSim/Questa.
- `quartus/`: file project dan konfigurasi Quartus (`.qpf`, `.qsf`, `.sdc`, `.qip`, serta source terkait).
- `platform_designer/`: file sistem Platform Designer dan dokumentasi koneksi.
- `weights/`: bobot, bias, skala, zero-point, dan file memori hasil ekspor model.
- `constraints/`: constraint timing dan pin yang relevan.

Jangan mengunggah database sementara Quartus (`db/`, `incremental_db/`) atau file waveform hasil simulasi. File programming final seperti `.sof` dapat disimpan sebagai release/artifact terpilih jika ukuran dan kebijakan repository mengizinkan; file tersebut tidak wajib disimpan pada setiap commit.
