# Panduan Instalasi Sistem Operasi NEURONIX

## 1. Persyaratan Sistem Minimum
- **Prosesor:** 64-bit x86_64 Dual-Core (Intel atau AMD)
- **Memori RAM:** Minimal 4 GB (Disarankan 8 GB+ untuk kompilasi kode dan ZRAM ZSTD)
- **Penyimpanan:** Minimal 30 GB ruang kosong pada SSD/NVMe (Format Btrfs ZSTD:3 otomatis)
- **Display:** Resolusi layar minimal 1024x768 (Dukungan HiDPI / 4K aktif otomatis)

## 2. Pembuatan Media Bootable USB
Unduh file image `neuronix-os-x86_64.iso` dan tulis ke flashdisk USB menggunakan salah satu cara berikut:
- **Menggunakan dd di Linux:**
  ```bash
  sudo dd if=neuronix-os-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
  ```
- **Menggunakan Ventoy / BalenaEtcher:** Cukup salin file ISO ke dalam flashdisk berformat Ventoy.

## 3. Alur Instalasi Calamares
1. Boot flashdisk installer. Pilih `Standard Open-Source` atau `NVIDIA Proprietary`.
2. Pada sesi Live Desktop, Calamares Installer akan terbuka otomatis.
3. Pilih bahasa, zona waktu, dan layout keyboard.
4. Pada menu partisi, pilih **Erase Disk** (Btrfs ZSTD:3 otomatis) atau **Manual Partitioning**.
5. Masukkan nama pengguna dan kata sandi.
6. Klik **Install**. Engine `neuronix-install-engine` akan menyusun Flake deklaratif dan mengeksekusi `nixos-install`.
7. Setelah selesai, cabut USB dan restart ke sistem NEURONIX baru Anda!
