# ADR-003: Arsitektur Dua Lapis (Immutable Nix Core vs Mutable Flatpak Apps)

## Status
**Accepted** (Disetujui untuk Fase 4 Distro NEURONIX)

## Konteks & Masalah
Di NixOS murni, menginstal aplikasi desktop harian (seperti Spotify, Discord, atau Obsidian) mengharuskan pengguna menambahkan baris deklaratif ke konfigurasi sistem dan menjalankan `nixos-rebuild switch`. 
Hal ini menimbulkan friksi berat bagi pengguna baru:
- Waktu rebuild lambat hanya untuk memasang aplikasi obrolan.
- Tidak ada pengalaman browsing visual toko aplikasi (*App Store*).

## Keputusan Arsitektur
NEURONIX menerapkan **Arsitektur Perangkat Lunak Dua Lapis (*Dual-Layer Software Architecture*)**:
1. **Lapis 1 (Core OS & Dev Stacks):** Dikelola secara murni oleh **Nixpkgs & Flakes**. Menjamin kernel, pustaka dasar, toolchain compiler, dan layanan server kebal terhadap kerusakan.
2. **Lapis 2 (Desktop GUI Apps):** Dikelola oleh **Flatpak & Flathub** via GNOME Software / KDE Discover.
3. Seluruh integrasi tema, kursor, dan dialog berkas disinkronkan secara mulus melalui protokol `xdg-desktop-portal`.

## Konsekuensi
- **Positif:** Onboarding pengguna berlangsung tanpa gesekan; jutaan aplikasi Flathub siap dipasang dengan satu klik; integritas sistem inti di `/nix/store` tetap aman 100%.
