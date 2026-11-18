# Dataset Rupiah

Folder ini menampung dataset citra uang kertas Rupiah.

## Struktur

- `raw/`: citra sumber yang belum diproses.
- `train/`: data pelatihan.
- `validation/`: data validasi selama pengembangan model.
- `test/`: data evaluasi final yang tidak digunakan untuk memilih model.
- `processed_32x32_rgb/`: citra hasil preprocessing dengan resolusi 32×32 RGB.

Setiap split menggunakan subfolder per kelas:
`denomination_1000`, `denomination_2000`, `denomination_5000`, `denomination_10000`, `denomination_20000`, `denomination_50000`, dan `denomination_100000`.

## Aturan penting

1. Catat sumber dan izin penggunaan setiap dataset.
2. Gunakan foto uang fisik yang berbeda jika memungkinkan.
3. Kelompokkan foto berdasarkan `physical_note_id`.
4. Semua foto (termasuk sisi depan/belakang) dari satu lembar uang harus masuk split yang sama.
5. Augmentasi hanya dilakukan setelah split, pada data train saja kecuali ada alasan eksperimen yang terdokumentasi.
6. Jangan menganggap resize ke 32×32 pasti mempertahankan detail yang cukup. Evaluasi akurasi dan pertimbangkan resolusi lebih besar jika perlu.
7. Jangan mengunggah dataset pihak ketiga sebelum lisensi mengizinkan redistribusi.

## Metadata

Gunakan `metadata_template.csv` sebagai template pencatatan. Jangan mengisi nilai yang tidak diketahui dengan tebakan.
