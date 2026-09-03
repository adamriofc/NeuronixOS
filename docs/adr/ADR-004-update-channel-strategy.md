# ADR-004: Strategi Saluran Pembaruan Upstream

## Status
**Accepted** (Disetujui untuk Fase 4 Distro NEURONIX)

## Konteks & Masalah
Beberapa distro Linux turunan (misalnya Manjaro di ekosistem Arch) menahan paket upstream selama beberapa minggu dalam repositori internal mereka. Praktik ini sering menimbulkan konflik ketergantungan paket, celah keamanan zero-day yang lambat ditambal, dan friksi dengan komunitas upstream.

## Keputusan Arsitektur
NEURONIX **TIDAK PERNAH mem-fork atau menahan repositori Nixpkgs resmi**:
- Konfigurasi Flake merujuk langsung ke upstream resmi: `github:NixOS/nixpkgs/nixos-unstable` (atau `nixos-24.11` / `nixos-26.05`).
- Seluruh modul kustom NEURONIX adalah layer tambahan (*additive modular overlays*) yang bersih.

## Konsekuensi
- **Positif:** Pengguna mendapatkan patch keamanan dan paket software terkini secara langsung; kompatibilitas dengan ekosistem Nixpkgs global dijamin 100%; proyek dihormati oleh komunitas inti NixOS.
