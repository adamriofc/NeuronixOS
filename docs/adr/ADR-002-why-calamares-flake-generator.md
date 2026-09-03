# ADR-002: Arsitektur Calamares sebagai Generator Flake Deklaratif

## Status
**Accepted** (Disetujui untuk Fase 4 Distro NEURONIX)

## Konteks & Masalah
Banyak installer Linux (termasuk distro turunan Debian/Arch) melakukan konfigurasi secara *imperatif*: skrip installer mengeksekusi serangkaian perintah `apt-get`, `useradd`, atau `sed` pada direktori target `/mnt`. 
Jika pendekatan ini digunakan di NixOS:
- Filosofi deklaratif akan rusak.
- Pengguna mendapatkan sistem yang tidak dapat direproduksi (*impure state*).

## Keputusan Arsitektur
Calamares pada NEURONIX diarsitekasikan secara khusus sebagai **Declarative Flake Generator**:
1. Calamares hanya bertugas mengumpulkan preferensi pengguna (keyboard, zona waktu, partisi Btrfs, username, desktop pilihan) melalui antarmuka grafis.
2. Modul eksekusi akhir (`neuronix-install-engine.sh`) mengubah parameter tersebut menjadi file deklaratif bersih: `/mnt/etc/nixos/flake.nix`, `configuration.nix`, dan `hardware-configuration.nix`.
3. Engine kemudian memanggil `nixos-install --flake /mnt/etc/nixos#neuronix-desktop`.

## Konsekuensi
- **Positif:** Sistem hasil instalasi 100% mematuhi prinsip deklaratif murni NixOS; pengguna baru langsung memiliki repositori Flake pribadi yang bersih sejak hari pertama.
- **Kompromi:** Membutuhkan templating skrip bash/nix yang teruji secara ketat agar tidak menghasilkan file konfigurasi yang cacat sintaks.
