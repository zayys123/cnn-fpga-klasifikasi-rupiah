# Project Progress — Rupiah-Vision

Judul: **Implementasi CNN Berbasis FPGA untuk Klasifikasi Nominal Uang Kertas Rupiah**

Status keseluruhan: **Repository scaffold dibuat; riset dataset dan baseline model belum dimulai.**

## Milestone

### Phase 01 — Repository setup
- [x] Nama proyek dan judul ditetapkan.
- [x] Struktur direktori awal disiapkan.
- [ ] Scaffold diunggah ke repository GitHub.
- [ ] README diperiksa dan disesuaikan dengan ketentuan tugas/kontes.
- [ ] Versi toolchain dicatat.

### Phase 02 — Dataset
- [ ] Sumber dataset atau protokol pengambilan foto ditetapkan.
- [ ] Izin/lisensi penggunaan dan redistribusi diperiksa.
- [ ] Kelas dan definisi label dikonfirmasi.
- [ ] Metadata gambar dikumpulkan.
- [ ] Group split train/validation/test berdasarkan lembar uang fisik.
- [ ] Preprocessing dan validasi input minimum 32×32.
- [ ] Dataset leakage audit dilakukan.

### Phase 03 — CNN software baseline
- [ ] Baseline CNN Python dibuat.
- [ ] Training dan validation selesai.
- [ ] Test set dievaluasi satu kali setelah model dipilih.
- [ ] Accuracy, precision, recall, F1-score, dan confusion matrix disimpan.
- [ ] Model dan konfigurasi eksperimen diarsipkan.

### Phase 04 — Quantization and export
- [ ] Skema INT8 dipilih.
- [ ] Akurasi FP32 dan INT8 dibandingkan.
- [ ] Bobot/bias diekspor.
- [ ] Scale, zero-point, signedness, dan tensor layout didokumentasikan.
- [ ] Golden test vectors dibuat.

### Phase 05 — Verilog RTL
- [ ] Arsitektur datapath ditetapkan.
- [ ] MAC unit dibuat dan diuji.
- [ ] Convolution engine dibuat dan diuji.
- [ ] ReLU dan pooling dibuat dan diuji.
- [ ] Fully connected/classifier dibuat dan diuji.
- [ ] Controller dan memory interface dibuat.
- [ ] RTL dibandingkan dengan reference model Python.

### Phase 06 — SoC and Quartus
- [ ] Custom IP dibuat.
- [ ] Avalon-MM register map ditetapkan.
- [ ] Platform Designer system diintegrasikan.
- [ ] Nios V software dibuat jika digunakan.
- [ ] Quartus compilation berhasil.
- [ ] Timing dan resource utilization dicatat.
- [ ] Programming file final diarsipkan bila diperlukan.

### Phase 07 — Final evaluation
- [ ] End-to-end demo berhasil.
- [ ] Latency dan throughput diukur.
- [ ] Resource utilization dilaporkan.
- [ ] Limitasi dan risiko didokumentasikan.
- [ ] Laporan dan README final diselesaikan.

## Experiment log

| Tanggal | Milestone | Perubahan/hasil | Bukti/artefak |
|---|---|---|---|
| 2026-11-18 | Repository scaffold | Struktur awal disiapkan | Initial scaffold |

## Catatan keputusan

- Input CNN minimum: 32×32 piksel.
- RGB 32×32 merupakan kandidat awal, bukan keputusan final sebelum evaluasi informasi visual.
- Tujuh nominal Rupiah merupakan ruang lingkup awal yang perlu dikonfirmasi terhadap dataset aktual.
- Sistem mengklasifikasikan nominal, bukan memverifikasi keaslian uang.
- Jangan menetapkan klaim akurasi, latency, atau resource FPGA sebelum pengukuran dilakukan.
