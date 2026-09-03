# ADR-005: Arsitektur Deteksi Perangkat Keras Hibrida

## Status
**Accepted** (Disetujui untuk Fase 4 Distro NEURONIX)

## Konteks & Masalah
Komputer modern (terutama laptop gaming) memiliki kombinasi perangkat keras yang kompleks:
- Dual GPU (Intel/AMD iGPU + NVIDIA dGPU) yang rentan boros baterai jika salah konfigurasi.
- Chip Wi-Fi Broadcom/Realtek yang membutuhkan firmware proprietary offline.
- Profil manajemen daya Modern Standby S0ix.

## Keputusan Arsitektur
NEURONIX mengotomatiskan konfigurasi ini melalui **27 Pilar Pertahanan Kedap Peluru**:
1. Calamares mendeteksi konfigurasi PCI bus untuk kartu grafis ganda dan otomatis mengaktifkan modul `hardware.nvidia.prime.offload`.
2. Image ISO memaketkan firmware proprietary lengkap (`hardware.enableAllFirmware = true`) agar instalasi offline 100% mulus.
3. Mengaktifkan `power-profiles-daemon`, `thermald`, dan parameter kernel `mem_sleep_default=deep`.

## Konsekuensi
- **Positif:** Pengguna tidak mengalami fenomena baterai laptop bocor atau Wi-Fi mati pasca instalasi.
- **Kompromi:** Ukuran image Live ISO bertambah sekitar 600 MB untuk menampung seluruh koleksi firmware offline.
