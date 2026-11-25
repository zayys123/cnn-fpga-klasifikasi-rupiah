# Implementasi CNN Berbasis FPGA untuk Klasifikasi Nominal Uang Kertas Rupiah

**Nama proyek:** Rupiah-Vision
**Target platform:** Terasic DE10-Standard (Cyclone V SoC FPGA)
**Metode:** Convolutional Neural Network (CNN)
**Hardware precision:** INT8
**Tanggal pembaruan:** 25 November 2026

---

## 1. Ringkasan Proyek

Rupiah-Vision merupakan proyek implementasi Convolutional Neural Network (CNN) untuk mengklasifikasikan nominal uang kertas Rupiah berdasarkan citra digital.

Model CNN dikembangkan dan dilatih menggunakan Python. Model terpilih kemudian dikonversi menggunakan pendekatan Post-Training Quantization (PTQ) INT8 untuk mempersiapkan implementasi perangkat keras menggunakan Verilog HDL.

Target implementasi adalah FPGA Terasic DE10-Standard berbasis Cyclone V SoC. Desain akan diverifikasi menggunakan ModelSim dan dikembangkan menggunakan Quartus Prime.

Fokus proyek adalah klasifikasi nominal uang kertas, bukan autentikasi keaslian uang.

## 2. Ruang Lingkup

Sistem mencakup tujuh kelas nominal:

- Rp1.000
- Rp2.000
- Rp5.000
- Rp10.000
- Rp20.000
- Rp50.000
- Rp100.000

Konfigurasi baseline FPGA V1:

| Komponen | Konfigurasi |
|---|---|
| Model | RupiahTinyCNN |
| Input | RGB 32×32 |
| Preprocessing | V3 Full-Frame |
| Jumlah kelas | 7 |
| Checkpoint | Epoch 98 |
| Parameter model | 5.047 |
| Quantization | PTQ INT8 |
| Hardware description | Verilog/SystemVerilog |
| FPGA | Cyclone V SoC |
| Board | Terasic DE10-Standard |

Eksperimen resolusi 64×64 tetap dipertahankan sebagai pembanding. Baseline FPGA V1 menggunakan resolusi 32×32.

## 3. Dataset dan Preprocessing

Dataset terdiri dari 1.142 citra dengan pembagian:

| Split | Jumlah citra |
|---|---:|
| Train | 799 |
| Validation | 171 |
| Test | 172 |
| **Total** | **1.142** |

Preprocessing baseline menggunakan pendekatan V3 full-frame. Model menerima citra RGB dengan resolusi 32×32.

Audit dataset telah dilakukan, termasuk pemetaan metadata, pemeriksaan hash, dan pemeriksaan identitas uang fisik.

**Keterbatasan dataset:**

Audit menemukan bahwa tujuh `physical_note_id` muncul pada train, validation, dan test. Oleh karena itu, hasil evaluasi saat ini belum membuktikan generalisasi terhadap uang fisik yang benar-benar berbeda atau sesi pengambilan gambar baru.

Test split tidak digunakan dalam proses PTQ maupun pembuatan golden vectors.

Dataset mentah tidak disertakan dalam repository ini sebelum izin penggunaan dan redistribusinya dipastikan.

## 4. Hasil CNN Baseline

Baseline final menggunakan checkpoint epoch 98 dari eksperimen 32×32.

| Metrik | Hasil |
|---|---:|
| Best epoch | 98 |
| Epoch training | 100 |
| Validation images | 171 |
| Accuracy | 67,25% |
| Macro Precision | 67,16% |
| Macro Recall | 69,13% |
| Macro-F1 | 67,26% |
| Best validation loss | 0,779725 |
| Parameters | 5.047 |
| MAC/image | 737.448 |

Checkpoint epoch 98 ditetapkan sebagai baseline final CNN FPGA V1 dan tidak boleh ditimpa oleh eksperimen berikutnya.

## 5. Quantization INT8

Model FP32 dikonversi menggunakan metode Post-Training Quantization (PTQ) dengan kalibrasi aktivasi berdasarkan train split.

Ringkasan proses:

- Audit checkpoint FP32.
- Verifikasi SHA-256 checkpoint.
- Pemeriksaan kesesuaian ekspor FP32 NPZ.
- Reproduksi metrik validation FP32.
- Kalibrasi aktivasi menggunakan 799 gambar training.
- Evaluasi model integer INT8 menggunakan 171 gambar validation.
- Ekspor bobot dan parameter kuantisasi.
- Pembuatan golden vectors.

### Perbandingan FP32 dan INT8

| Metrik | FP32 | INT8 |
|---|---:|---:|
| Validation accuracy | 67,25% | 67,84% |
| Macro-F1 | 67,26% | 67,92% |

Prediction agreement antara FP32 dan INT8: **97,08%**.

Hasil tersebut merupakan hasil evaluasi validation dan belum merupakan hasil pengujian hardware FPGA.

### Golden Vectors

Sebanyak 14 golden vectors dihasilkan dari validation split, dengan dua sampel untuk setiap kelas nominal.

Golden vectors digunakan sebagai referensi untuk membandingkan hasil komputasi Python dengan implementasi RTL.

### Shift Memory

Parameter shift untuk tiga convolution layer telah dikonversi ke format signed 8-bit hexadecimal:

- Conv1: 8 channel.
- Conv2: 16 channel.
- Conv3: 24 channel.

## 6. Implementasi Verilog dan FPGA

Tahap berikutnya adalah menerjemahkan arsitektur CNN INT8 ke dalam Verilog HDL.

Rencana implementasi:

1. Audit kontrak numerik model INT8.
2. Implementasi MAC unit.
3. Implementasi convolution engine.
4. Implementasi ReLU dan pooling.
5. Implementasi fully connected classifier.
6. Implementasi controller dan memory interface.
7. Pembuatan testbench.
8. Verifikasi output RTL terhadap reference model Python.
9. Integrasi ke proyek Quartus.

Verifikasi harus memperhatikan signedness, lebar accumulator, rounding, saturation, multiplier, shift, dan urutan tensor.

Status kompilasi serta simulasi RTL belum dinyatakan berhasil sampai seluruh pengujian benar-benar dilakukan.

## 7. Target Jadwal

| Tanggal | Target pekerjaan |
|---|---|
| 25 November 2026 | Baseline CNN, PTQ INT8, dan golden vectors |
| 2 Desember 2026 | RTL terverifikasi dicoba pada Quartus |
| 9 Desember 2026 | Implementasi dan pengujian pada FPGA |

Tanggal tersebut merupakan target pengembangan proyek.

## 8. Struktur Repository

```text
cnn-fpga-klasifikasi-rupiah/
│
├── dataset/
│   ├── metadata_template.csv
│   └── README.md
│
├── algoritma/
│   ├── python/
│   ├── C/
│   └── matlab/
│
├── verilog/
│   └── fpga/
│       ├── rtl/
│       ├── testbench/
│       ├── weights/
│       ├── quartus/
│       └── platform_designer/
│
├── docs/
│   ├── arsitektur.md
│   ├── metodologi.md
│   └── register_map.md
│
├── output/
│   ├── laporan/
│   └── publikasi/
│
├── progress/
│   └── PROGRESS.md
│
└── README.md
```

## 9. Reproducibility

Setiap eksperimen harus mempertahankan:

- Checkpoint model dan hash.
- Konfigurasi arsitektur.
- Versi dataset dan preprocessing.
- Seed eksperimen.
- Parameter quantization.
- Golden vectors.
- Hasil validasi dan evaluasi.
- Log simulasi dan hasil sintesis FPGA.

Artefak baseline tidak boleh ditimpa. Setiap eksperimen baru harus menggunakan direktori output dan identitas versi yang berbeda.

## 10. Batasan Sistem

Rupiah-Vision dikembangkan untuk klasifikasi nominal uang kertas berdasarkan citra. Sistem tidak dirancang untuk menentukan keaslian uang, mendeteksi uang palsu, atau menggantikan proses autentikasi resmi.

Hasil evaluasi saat ini bersifat eksploratif karena keterbatasan identitas uang fisik pada pembagian dataset.

---

- **Project:** Rupiah-Vision
- **Research focus:** CNN-based Rupiah Banknote Denomination Classification on FPGA
**Hardware target:** Terasic DE10-Standard (Cyclone V SoC FPGA)
