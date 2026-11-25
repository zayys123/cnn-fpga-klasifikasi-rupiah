# Metodologi Penelitian

## 1. Desain Penelitian

Penelitian ini menggunakan pendekatan eksperimental untuk mengembangkan sistem klasifikasi nominal uang kertas Rupiah menggunakan Convolutional Neural Network (CNN) yang ditargetkan untuk implementasi pada FPGA.

Pengembangan dilakukan melalui dua tahapan utama, yaitu pengembangan model perangkat lunak menggunakan Python dan implementasi model terkuantisasi menggunakan Verilog HDL.

Model perangkat lunak digunakan sebagai reference model untuk mengevaluasi kesesuaian hasil komputasi hardware.

## 2. Dataset

Dataset terdiri atas 1.142 citra uang kertas Rupiah yang mencakup tujuh kelas nominal:

1. Rp1.000

2. Rp2.000

3. Rp5.000

4. Rp10.000

5. Rp20.000

6. Rp50.000

7. Rp100.000

Pembagian dataset aktual:

| Split | Jumlah |
|---|---:|
| Training | 799 |
| Validation | 171 |
| Testing | 172 |
| Total | 1.142 |

Metadata mencakup image identifier, denomination, physical note identifier, side, source path, cleaned path, dan SHA-256.

## 3. Audit Dataset

Audit dilakukan untuk memeriksa konsistensi metadata, pemetaan citra, duplikasi, serta potensi kebocoran data.

Hasil audit menunjukkan:

- Seluruh 1.142 citra berhasil dipetakan ke metadata.

- Tidak ditemukan citra yang tidak memiliki pasangan metadata.

- Tidak ditemukan hash identik lintas split.

- Terdapat tujuh physical_note_id yang masing-masing muncul pada training, validation, dan testing.

- Kolom split dan capture_group_id pada metadata awal tidak terisi.

Temuan physical_note_id lintas split menunjukkan bahwa citra dari uang fisik yang sama tersebar pada beberapa subset.

Oleh karena itu, hasil evaluasi validation belum dapat digunakan untuk menyimpulkan kemampuan generalisasi terhadap uang fisik yang benar-benar berbeda.

## 4. Preprocessing Citra

Preprocessing menggunakan pipeline V3 full-frame sebagai baseline implementasi CNN FPGA V1.

Tahapan preprocessing mencakup:

- Pengolahan citra sumber.

- Penyesuaian ukuran citra.

- Konversi format citra menjadi RGB.

- Penyimpanan hasil preprocessing berdasarkan kelas dan subset dataset.

Dua resolusi dievaluasi dalam eksperimen CNN, yaitu 32×32 dan 64×64 piksel.

Resolusi 32×32 dipilih sebagai konfigurasi baseline FPGA V1.

Input model memiliki tiga kanal warna RGB.

## 5. Augmentasi Data

Kebijakan augmentasi ditetapkan pada tingkat Moderate.

Augmentasi diterapkan dalam konteks pengembangan model untuk meningkatkan variasi data training.

Jenis transformasi, probabilitas, dan parameter augmentasi harus mengikuti implementasi aktual pada script training. Tidak boleh ditambahkan sebagai klaim metodologi apabila tidak ditemukan dalam source code.

## 6. Pengembangan dan Training CNN

Model yang digunakan adalah RupiahTinyCNN dengan tujuh output kelas.

Konfigurasi training baseline:

| Parameter | Nilai |
|---|---|
| Model | RupiahTinyCNN |
| Input | RGB 32×32 |
| Jumlah kelas | 7 |
| Epoch maksimum | 100 |
| Batch size | 32 |
| Patience | 15 |
| Random seed | 42 |
| Device aktual | CPU |
| Parameter model | 5.047 |

Checkpoint epoch 98 ditetapkan sebagai baseline final karena menjadi checkpoint dengan validation loss terbaik.

Checkpoint tersebut dipertahankan sebagai referensi utama untuk proses kuantisasi dan implementasi hardware.

## 7. Evaluasi Model

Evaluasi dilakukan menggunakan validation split.

Metrik yang digunakan meliputi:

- Accuracy.

- Macro Precision.

- Macro Recall.

- Macro-F1.

- Balanced Accuracy.

- Confusion Matrix.

- Per-class performance.

Hasil baseline CNN 32×32:

| Metrik | Hasil |
|---|---:|
| Accuracy | 67,25% |
| Macro Precision | 67,16% |
| Macro Recall | 69,13% |
| Macro-F1 | 67,26% |
| Balanced Accuracy | 69,13% |

Hasil tersebut merupakan evaluasi validation pada dataset yang tersedia dan harus ditafsirkan dengan mempertimbangkan keterbatasan physical_note_id lintas split.

## 8. Quantization INT8

Model FP32 dikonversi menggunakan pendekatan Post-Training Quantization (PTQ).

Kalibrasi aktivasi menggunakan data training, sedangkan validation digunakan untuk mengevaluasi hasil kuantisasi.

Konfigurasi proses:

- Baseline checkpoint: epoch 98.

- Calibration dataset: 799 gambar training.

- Validation dataset: 171 gambar.

- Test split: tidak diakses selama proses PTQ.

- Metode kalibrasi: maksimum aktivasi post-ReLU.

- Representasi hardware: INT8.

Sebelum kuantisasi, dilakukan audit checkpoint, verifikasi SHA-256, pencocokan ekspor FP32 NPZ, dan reproduksi metrik validation.

Hasil perbandingan:

| Metrik | FP32 | INT8 |
|---|---:|---:|
| Accuracy | 67,25% | 67,84% |
| Macro-F1 | 67,26% | 67,92% |

Prediction agreement antara FP32 dan INT8 sebesar 97,08%.

Hasil ini berasal dari evaluasi reference integer pada validation dataset, bukan dari implementasi FPGA.

## 9. Golden Vector Generation

Golden vectors dihasilkan untuk digunakan sebagai referensi verifikasi implementasi Verilog.

Sebanyak 14 sampel dipilih dari validation split, dengan dua sampel untuk masing-masing kelas.

Pemilihan sampel menggunakan prediksi benar dengan margin tertinggi dan kesalahan klasifikasi dengan confidence tertinggi. Jika tidak tersedia sampel salah klasifikasi, digunakan prediksi benar dengan margin terendah.

Golden vectors digunakan untuk membandingkan keluaran model Python dan RTL.

## 10. Konversi Parameter Hardware

Bobot dan parameter hasil kuantisasi diekspor untuk mempersiapkan implementasi hardware.

Parameter shift dikonversi ke representasi signed 8-bit hexadecimal.

Jumlah parameter shift yang diekspor:

| Layer | Jumlah |
|---|---:|
| Conv1 | 8 |
| Conv2 | 16 |
| Conv3 | 24 |

Format dan pemetaan bobot, bias, multiplier, shift, signedness, serta lebar accumulator harus dipertahankan secara konsisten antara reference model Python dan implementasi Verilog.

## 11. Implementasi dan Verifikasi FPGA

Implementasi hardware direncanakan menggunakan Verilog HDL dengan tahapan:

1. Perancangan MAC unit.

2. Perancangan convolution engine.

3. Implementasi fungsi aktivasi dan pooling.

4. Implementasi fully connected classifier.

5. Perancangan controller dan memory interface.

6. Pembuatan testbench.

7. Simulasi menggunakan ModelSim.

8. Perbandingan hasil RTL dengan golden vectors.

9. Sintesis dan evaluasi menggunakan Quartus Prime.

10. Implementasi pada Terasic DE10-Standard.

Keberhasilan verifikasi RTL harus dibuktikan melalui hasil simulasi. Evaluasi FPGA harus mencatat resource utilization, timing, latency, dan throughput apabila pengukurannya telah tersedia.

## 12. Keterbatasan Penelitian

Keterbatasan utama penelitian saat ini adalah jumlah identitas uang fisik yang terbatas dan penyebaran physical_note_id yang sama pada training, validation, serta testing.

Akibatnya, performa validation belum membuktikan generalisasi terhadap uang fisik baru.

Pengujian hardware juga masih memerlukan verifikasi RTL, sintesis Quartus, dan implementasi pada board FPGA.

Sistem hanya ditujukan untuk klasifikasi nominal uang kertas, bukan autentikasi keaslian uang.
