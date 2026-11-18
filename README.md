# Implementasi CNN Berbasis FPGA untuk Klasifikasi Nominal Uang Kertas Rupiah

**Nama  :** Zayyan Sabilillah

**NIM   :** 101022300020

**Nama proyek:** Rupiah-Vision  
**Platform target:** Terasic DE10-Standard (Cyclone V SoC FPGA)  
**Metode:** Convolutional Neural Network (CNN)  
**Target implementasi:** CNN INT8 pada FPGA, dengan integrasi SoC sebagai rancangan yang akan dievaluasi.

## 1. Ringkasan

Proyek ini mengembangkan sistem klasifikasi nominal uang kertas Rupiah menggunakan citra dan Convolutional Neural Network (CNN). Model akan dilatih dan dievaluasi menggunakan Python, kemudian dikonversi ke representasi numerik yang sesuai untuk implementasi hardware. Selanjutnya, blok-blok CNN akan dirancang dalam Verilog HDL, diverifikasi menggunakan ModelSim, dan diintegrasikan ke proyek Quartus untuk target Terasic DE10-Standard.

Proyek ini berfokus pada **penerapan dan evaluasi CNN accelerator pada FPGA**, bukan autentikasi uang.

## 2. Ruang lingkup awal

Konfigurasi berikut merupakan **baseline perencanaan** dan masih dapat disesuaikan setelah dataset serta hasil eksperimen awal diperiksa.

| Aspek | Rencana awal |
|---|---|
| Objek | Uang kertas Rupiah |
| Kelas | 7 nominal: Rp1.000, Rp2.000, Rp5.000, Rp10.000, Rp20.000, Rp50.000, Rp100.000 |
| Input CNN | Minimum 32 × 32 piksel |
| Format input kandidat | RGB, 8-bit per kanal |
| Model | Tiny CNN yang dirancang dan dilatih untuk proyek ini |
| Kuantisasi | INT8 sebagai target implementasi |
| Board | Terasic DE10-Standard |
| FPGA | Cyclone V SoC |
| Tool | Python, ModelSim, Quartus Prime |
| SoC | Nios V dan Avalon-MM sebagai rancangan integrasi yang akan dievaluasi |

**Catatan:** ukuran 32×32 adalah batas minimum requirement proyek. Eksperimen dapat membandingkan resolusi yang lebih besar apabila detail visual pada 32×32 tidak cukup untuk klasifikasi yang andal. Jangan mengunci arsitektur CNN, jumlah MAC, atau ukuran buffer sebelum pengujian dataset dan estimasi resource.

## 3. Batasan fungsi

Sistem ditujukan untuk mengenali **nominal uang kertas**, bukan menentukan keaslian uang. Hasil klasifikasi citra tidak boleh digunakan sebagai bukti bahwa uang tersebut asli atau palsu.

## 4. Rencana alur kerja

1. Menetapkan sumber dataset, izin penggunaan, dan protokol pengambilan gambar.
2. Mengumpulkan serta memberi label citra setiap nominal.
3. Membagi dataset menjadi train, validation, dan test tanpa kebocoran antar-foto dari uang fisik yang sama.
4. Melakukan preprocessing dan memvalidasi ukuran citra.
5. Melatih baseline CNN menggunakan Python.
6. Mengevaluasi accuracy, precision, recall, F1-score, dan confusion matrix.
7. Mengevaluasi kuantisasi INT8 dan dampaknya terhadap akurasi.
8. Mengekspor bobot serta parameter kuantisasi untuk hardware.
9. Mengimplementasikan blok CNN menggunakan Verilog HDL.
10. Memverifikasi RTL dengan testbench ModelSim dan membandingkannya dengan model referensi Python.
11. Mengintegrasikan accelerator ke desain Quartus/Platform Designer.
12. Mengukur resource utilization, fMAX, latency, throughput, dan estimasi daya jika tersedia.

## 5. Struktur repository

- `dataset/` — dataset mentah, split, hasil preprocessing, dan metadata.
- `algoritma/python/` — pipeline dataset, training, evaluasi, quantization, dan ekspor bobot.
- `algoritma/C/` — software host/embedded, termasuk aplikasi Nios jika digunakan.
- `algoritma/matlab/` — skrip analisis tambahan jika diperlukan.
- `verilog/fpga/rtl/` — source RTL.
- `verilog/fpga/testbench/` — testbench dan file simulasi.
- `verilog/fpga/quartus/` — project dan konfigurasi Quartus.
- `verilog/fpga/platform_designer/` — konfigurasi sistem SoC.
- `verilog/fpga/weights/` — bobot dan parameter hasil ekspor untuk hardware.
- `output/` — hasil training, simulasi, Quartus, publikasi, dan laporan.
- `docs/` — dokumentasi arsitektur, metodologi, dan register map.
- `progress/` — catatan milestone dan perubahan.

## 6. Dataset dan reproduksibilitas

Simpan sumber dataset, izin/lisensi, tanggal pengambilan, metode pengambilan, dan aturan pembagian data. Gunakan `dataset/metadata_template.csv` sebagai format metadata awal.

**Penting:** foto bagian depan dan belakang dari lembar uang fisik yang sama harus berada pada split yang sama. Hindari menempatkan hasil augmentasi dari satu foto sumber ke split yang berbeda. Ini mencegah data leakage dan estimasi akurasi yang terlalu optimistis.

Jangan mengunggah dataset pihak ketiga ke repository publik sebelum lisensinya mengizinkan redistribusi. Jika dataset berukuran besar atau dibatasi lisensi, simpan petunjuk unduh dan metadata, bukan salinan dataset tersebut.

## 7. Reproduksi

Instruksi instalasi dependency, preprocessing, training, quantization, simulasi, dan build FPGA akan ditambahkan setelah toolchain serta versi software ditetapkan. Setiap eksperimen harus mencatat seed, versi dataset, konfigurasi model, dan parameter kuantisasi.

## 8. Status

Lihat [`progress/PROGRESS.md`](progress/PROGRESS.md) untuk status pekerjaan terkini.

## 9. Disclaimer

Proyek akademik ini melakukan klasifikasi nominal berdasarkan citra. Proyek ini bukan perangkat autentikasi, penilai kondisi resmi, atau alat untuk mendeteksi uang palsu.
