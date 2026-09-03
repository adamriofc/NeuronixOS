# ADR-001: Penggunaan Nix Flakes sebagai Antarmuka Sistem Utama

## Status
**Accepted** (Disetujui untuk Fase 4 Distro NEURONIX)

## Konteks & Masalah
Pada NixOS tradisional (non-Flakes), konfigurasi sistem bergantung pada saluran global (*channels*) dan variabel lingkungan `$NIX_PATH`. Hal ini menimbulkan beberapa masalah fatal:
1. **Ketidakpastian Versi (Non-Deterministic Builds):** Menjalankan `nixos-rebuild switch` di dua mesin berbeda dengan channel yang sama dapat menghasilkan versi paket yang berbeda jika waktu unduh berbeda.
2. **Ketergantungan State Tersembunyi:** Saluran sistem dimutasi secara imperatif (`nix-channel --update`).
3. **Kesulitan Kolaborasi Git:** Tidak ada file pengunci (*lockfile*) standar yang mengikat dependensi sistem secara kriptografis.

## Keputusan Arsitektur
NEURONIX menetapkan **Nix Flakes murni (`flake.nix` & `flake.lock`)** sebagai standar wajib bagi seluruh konfigurasi sistem, packaging, dan sub-perintah:
- Seluruh instalasi menghasilkan file `flake.nix` di disk pengguna.
- Pinning dependensi diatur secara atomik di dalam `flake.lock`.
- Memungkinkan fitur portabel seperti `neuronix dev <stack>` dan simulasi Micro-VM `neuronix try`.

## Konsekuensi
- **Positif:** Reproduktibilitas 100% terjamin di mesin apa pun; rollback dan time-travel dapat diprediksi secara matematis; audit keamanan dependensi jauh lebih mudah.
- **Kompromi:** Membutuhkan `nix.settings.experimental-features = [ "nix-command" "flakes" ]` yang kami aktifkan secara bawaan di seluruh citra instalasi.
