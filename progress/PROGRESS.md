# Project Progress --- RupiahVision

**Judul:** Implementasi CNN Berbasis FPGA untuk Klasifikasi Nominal Uang
Kertas Rupiah\
**Target platform:** Terasic DE10-Standard (Cyclone V SoC FPGA)\
**Tanggal pembaruan:** 25 November 2026

## Status

Baseline CNN 32×32 dan PTQ INT8 selesai. Pengembangan RTL, simulasi
ModelSim, dan implementasi Quartus/FPGA masih berlangsung.

## 1. Konfigurasi proyek

  Parameter                Keputusan
  ------------------------ -----------------------
  Model                    RupiahTinyCNN
  Input                    RGB 32×32
  Kelas                    7 nominal Rupiah
  Preprocessing baseline   V3 full-frame
  Resolusi FPGA V1         32×32
  Checkpoint baseline      Epoch 98
  Parameter                5.047
  Quantization             PTQ INT8
  Board                    Terasic DE10-Standard
  HDL                      Verilog/SystemVerilog

Checkpoint epoch 98 adalah baseline final dan tidak boleh ditimpa. Hasil
64×64 tetap dipertahankan sebagai pembanding.

## 2. Dataset dan preprocessing

  Split          Jumlah gambar
  ------------ ---------------
  Train                    799
  Validation               171
  Test                     172
  **Total**          **1.142**

-   [x] Dataset tujuh nominal disiapkan.
-   [x] Seluruh 1.142 gambar dipetakan ke metadata.
-   [x] Preprocessing V3 full-frame tersedia.
-   [x] Audit hash gambar lintas split dilakukan.
-   [x] Audit `physical_note_id` lintas split dilakukan.

**Temuan audit:** tidak ditemukan hash gambar identik lintas split.
Namun, tujuh `physical_note_id` masing-masing tersebar pada train,
validation, dan test. Kolom `split` dan `capture_group_id` pada metadata
awal kosong. Dengan demikian, evaluasi belum membuktikan generalisasi
terhadap uang fisik baru atau sesi pengambilan gambar baru.

Izin redistribusi dataset publik masih perlu diperiksa. Jangan
mengunggah citra atau turunannya sebelum hak distribusinya dipastikan.

## 3. Baseline CNN

-   [x] RupiahTinyCNN dilatih pada resolusi 32×32 dan 64×64.
-   [x] Resolusi 32×32 dipilih untuk FPGA V1.
-   [x] Checkpoint epoch 98 ditetapkan sebagai baseline final.
-   [x] Confusion matrix dan metrik per kelas dihasilkan.
-   [x] Reproduksi metrik validation FP32 berhasil pada audit
    pra-quantization.

  Metrik baseline 32×32        Hasil
  ----------------------- ----------
  Best epoch                      98
  Epochs run                     100
  Parameters                   5.047
  Validation images              171
  Accuracy                    67,25%
  Macro Precision             67,16%
  Macro Recall                69,13%
  Macro-F1                    67,26%
  Best validation loss      0,779725
  MAC/image                  737.448

## 4. Quantization INT8

-   [x] Audit checkpoint FP32.
-   [x] SHA-256 checkpoint diverifikasi.
-   [x] Ekspor FP32 NPZ cocok dengan checkpoint.
-   [x] Reproduksi validation FP32 berhasil.
-   [x] PTQ INT8 selesai.
-   [x] Bobot INT8, bias INT32, multiplier, dan shift diekspor.
-   [x] Golden vectors tujuh kelas dibuat.
-   [x] Shift signed 8-bit dikonversi ke hexadecimal.

SHA-256 checkpoint:

`8d0a3bae06a6a7fae0f916832f4bf83f7d6d776f09460b2dc6b745d020af6a66`

  Metrik                    FP32     INT8
  --------------------- -------- --------
  Validation accuracy     67,25%   67,84%
  Macro-F1                67,26%   67,92%

Prediction agreement: **97,08%**.

Kalibrasi aktivasi menggunakan 799 gambar train split. Evaluasi
menggunakan 171 gambar validation. Test split tidak diakses selama PTQ.
Script menggunakan `train_loader` untuk mengumpulkan activation maxima.

Golden vectors berjumlah 14 sampel dari validation split (dua per
nominal). Sebelum dipublikasikan, pastikan hak redistribusi sumber
gambar mengizinkan publikasi citra tersebut.

  Layer     Jumlah channel Format shift
  ------- ---------------- --------------------------
  Conv1                  8 Signed 8-bit hexadecimal
  Conv2                 16 Signed 8-bit hexadecimal
  Conv3                 24 Signed 8-bit hexadecimal

## 5. Verilog RTL

Status: persiapan RTL. Kompilasi, simulasi, dan kesetaraan numerik belum
dinyatakan lulus.

-   [ ] Audit signedness, lebar accumulator, rounding, saturation,
    multiplier, dan shift terhadap reference Python.
-   [ ] Kompilasi modul primitive.
-   [ ] Jalankan unit test ModelSim.
-   [ ] Implementasikan datapath CNN secara bertahap.
-   [ ] Bandingkan output RTL dengan reference Python menggunakan golden
    vectors.

Draft RTL dan testbench lokal harus diaudit sebelum disalin ke
repository. Jangan menyatakan RTL terverifikasi sebelum simulasi lulus.

## 6. Quartus dan FPGA

-   [ ] Siapkan proyek Quartus, top-level, pin assignment, dan timing
    constraints.
-   [ ] Jalankan sintesis dan catat resource utilization.
-   [ ] Jalankan timing analysis.
-   [ ] Evaluasi integrasi Platform Designer/SoC jika diperlukan.
-   [ ] Implementasikan dan uji pada board.

  Tanggal           Target
  ----------------- --------------------------------------
  2 Desember 2026   RTL terverifikasi dicoba di Quartus
  9 Desember 2026   Implementasi dan pengujian pada FPGA

Tanggal tersebut adalah target jadwal, bukan klaim pekerjaan telah
selesai.

## 7. Experiment log

  -----------------------------------------------------------------------
  Tanggal                 Milestone               Hasil
  ----------------------- ----------------------- -----------------------
  18 November 2026        Repository setup        Struktur awal disiapkan

  25 November 2026        Dataset audit           1.142 gambar dipetakan;
                                                  masalah
                                                  `physical_note_id`
                                                  lintas split ditemukan

  25 November 2026        CNN training            Baseline 32×32,
                                                  checkpoint epoch 98

  25 November 2026        PTQ INT8                Accuracy validation
                                                  67,84%; prediction
                                                  agreement 97,08%

  25 November 2026        Golden vectors          14 sampel untuk tujuh
                                                  kelas

  25 November 2026        Shift conversion        Shift Conv1, Conv2,
                                                  Conv3 dikonversi

  25 November 2026        RTL preparation         Audit dan verifikasi
                                                  RTL menjadi pekerjaan
                                                  berikutnya
  -----------------------------------------------------------------------

## 8. Keputusan yang dipertahankan

1.  Baseline FPGA V1 menggunakan preprocessing V3 full-frame.
2.  Input CNN FPGA V1 adalah RGB 32×32.
3.  Checkpoint epoch 98 adalah baseline final dan tidak boleh ditimpa.
4.  Quantization menggunakan PTQ INT8.
5.  Golden vectors berasal dari validation split.
6.  Test split tidak digunakan untuk kalibrasi PTQ atau pembuatan golden
    vectors.
7.  Seluruh hasil eksperimen lama harus dipertahankan.
8.  Sistem mengklasifikasikan nominal uang kertas, bukan mengautentikasi
    keaslian uang.
9.  Klaim performa hardware hanya dibuat setelah pengukuran
    Quartus/FPGA.
