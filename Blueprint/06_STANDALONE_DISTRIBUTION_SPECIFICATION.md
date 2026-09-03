# NEURONIX Blueprint: Spesifikasi Distribusi Mandiri & Installer Grafis (Fase 4)

> **Kode Dokumen:** `06_DISTRO_SPEC`  
> **Versi:** 1.0.0-draft  
> **Status:** Approved Architecture Specification  
> **Komponen:** Standalone Bootable ISO, Calamares Installer, Wayland Desktop Suites, & NEURONIX Center  

---

## 1. Visi & Filosofi Distribusi: "The Golden Sweet Spot"

NixOS diakui secara global sebagai sistem operasi dengan arsitektur komputasi paling maju di dunia: fungsional murni, kebal terhadap kerusakan akibat pembaruan, dan memiliki riwayat generasi (*atomic rollback*). Namun, adopsi globalnya terhambat oleh kurva belajar yang sangat curam, ketiadaan installer grafis yang ramah, serta ketidakcocokan alami terhadap biner Linux konvensional (isu FHS).

**NEURONIX Fase 4 hadir sebagai "EndeavourOS-nya dunia NixOS":**
- **Mengambil 100% Kekuatan Inti NixOS:** Katalog 100.000+ paket (*nixpkgs*), Flakes deklaratif, dan integritas penyimpanan kriptografis `/nix/store`.
- **Memangkas 90% Kerumitan Teknis:** Menyediakan antarmuka grafis yang ramah, biner CLI ergonomis (`neuronix run`, `neuronix try`, `neuronix diet`), dan kompatibilitas biner instan via `nix-ld`.
- **Menghindari Jebakan Manjaro (Menjaga Kehormatan Komunitas):** NEURONIX tidak memecah (*fork*) atau menahan repositori resmi Nixpkgs. Format konfigurasinya 100% Flakes murni, sehingga dihormati oleh purist NixOS dan menjadi jembatan adopsi terluas di dunia.

---

## 2. Arsitektur Installer Grafis Calamares & Partisi Cerdas

Calamares diintegrasikan secara deklaratif ke dalam file `iso.nix` menggunakan modul `nixos-generators`.

```text
┌──────────────────────────────────────────────────────────────┐
│                    ALUR INSTALASI CALAMARES                  │
├──────────────────────────────────────────────────────────────┤
│ 1. Booting Live ISO (Opsi Open-Source vs NVIDIA LTS)        │
│ 2. Pemilihan Bahasa, Papan Ketik, dan Lokasi Geografis       │
│ 3. Partisi Cerdas: Resep Btrfs Subvolumes + Kompresi ZSTD:3  │
│ 4. Pemilihan Desktop Environment (KDE 6 / GNOME / Hyprland)  │
│ 5. Pembuatan Kredensial Pengguna & Opsi Passwordless Sudo    │
│ 6. Eksekusi Nixos-Install via Chroot Bersih                  │
│ 7. Selesai: Reboot ke Sistem NEURONIX Siap Pakai             │
└──────────────────────────────────────────────────────────────┘
```

### Resep Partisi Default: Btrfs dengan Kompresi Transparan ZSTD:3
Untuk mengatasi kelemahan konsumsi disk `/nix/store`, Calamares menerapkan struktur subvolume Btrfs otomatis:
- `@` di-mount ke `/` dengan opsi `compress=zstd:3,noatime,space_cache=v2`.
- `@nix` di-mount ke `/nix` dengan opsi `compress=zstd:3,noatime,space_cache=v2`.
- `@home` di-mount ke `/home` dengan opsi `compress=zstd:3,noatime`.
- `@snapshots` di-mount ke `/.snapshots`.

> [!TIP]
> **Efisiensi Nyata:** Kompresi Btrfs `zstd:3` secara transparan memangkas ukuran fisik file di `/nix/store` sebesar **40% hingga 50%**, menghasilkan kecepatan baca disk yang lebih tinggi dan memperpanjang umur SSD host fisik.

---

## 3. Kurasi Desktop Environment Wayland-First

NEURONIX Fase 4 menyediakan kurasi visual berkelas tinggi tanpa *bloatware* kantor atau aplikasi yang tidak relevan:

```text
┌────────────────────────────────────────────────────────────────────────┐
│               KATALOG DESKTOP ENVIRONMENT CALAMARES                    │
├───────────────────────┬────────────────────────────────────────────────┤
│ Pilihan Desktop       │ Karakteristik & Karakter Visual                │
├───────────────────────┼────────────────────────────────────────────────┤
│ KDE Plasma 6 Wayland  │ - Breeze Slate Glass Theme (Translucent Blur)   │
│ (Default Fleksibel)   │ - Konsumsi RAM idle ~750 MB - 850 MB           │
│                       │ - Akselerasi GPU Vulkan/Wayland penuh          │
├───────────────────────┼────────────────────────────────────────────────┤
│ GNOME 47/50 Wayland   │ - Tokyo Cyber / Dark Slate Palette             │
│ (Workflow Gestur)     │ - Gestur touchpad 3-jari sangat fluida         │
│                       │ - Tipografi terkurasi: Inter + JetBrains Mono  │
├───────────────────────┼────────────────────────────────────────────────┤
│ Hyprland Wayland      │ - Animasi fisika dinamis & auto-tiling         │
│ (Power-User Elit)     │ - Waybar minimalis dengan status `neuronix`    │
│                       │ - Terintegrasi dengan Wofi/Rofi application hub│
├───────────────────────┼────────────────────────────────────────────────┤
│ Cinnamon / XFCE       │ - Tampilan klasik tradisional (mirip Windows)  │
│ (Konservatif & Irit)  │ - Sangat ramah untuk laptop spek rendah        │
├───────────────────────┼────────────────────────────────────────────────┤
│ Minimalist / Headless │ - Terminal-only murni tanpa display manager    │
│ (Server/Container)    │ - Khusus dev minimalis atau server produksi    │
└───────────────────────┴────────────────────────────────────────────────┘
```

---

## 4. NEURONIX Center: Aplikasi Sapaan Awal (*First-Boot Onboarding*)

Mirip dengan `eos-welcome` pada EndeavourOS, saat pengguna pertama kali masuk ke desktop, sistem akan memunculkan aplikasi grafis ringan **NEURONIX Center**:

```text
┌──────────────────────────────────────────────────────────────┐
│  NEURONIX CENTER v1.0                                [ _ X ] │
├──────────────────────────────────────────────────────────────┤
│  Selamat Datang di Sistem Operasi NEURONIX (NixOS Substrate) │
│                                                              │
│  [ TELEMETRI PERANGKAT KERAS ]                               │
│  • GPU       : NVIDIA RTX 4070 (Driver 550.xx + CUDA Ready)   │
│  • Storage   : 42.1 GB Bebas (Btrfs ZSTD:3 Aktif)            │
│  • Substrat  : Generasi Sistem #1 (Generasi Awal Bersih)     │
│  • Auto-TRIM : Aktif (Siklus Harian)                         │
│                                                              │
│  [ AKSI CEPAT DOKUMEN & SISTEM ]                             │
│  [ 🚀 Buka Terminal ]     [ 🧪 Uji Shadow VM ]               │
│  [ 🧹 Jalankan Diet ]     [ 🤖 Hubungkan AI MCP ]            │
│                                                              │
│  [ PROFIL MODULAR SIAP PAKAI ]                               │
│  [✓] Aktifkan Profil Gaming & Steam (Proton GE)              │
│  [✓] Aktifkan Profil AI Developer (PyTorch + Ollama + CUDA)  │
│  [ ] Aktifkan Profil Web Development (Node + Docker Podman)  │
└──────────────────────────────────────────────────────────────┘
```

Pengguna tidak perlu mengetik konfigurasi manual; mencentang opsi di NEURONIX Center akan langsung menambahkan modul deklaratif terkait ke `/etc/nixos/configuration.nix` dan mengujinya melalui `neuronix try` sebelum dipromosikan.

---

## 5. Kompatibilitas Biner & Ergonomi Pengembang Out-of-the-Box

1. **Aktivasi Global `nix-ld`:**  
   Menyelesaikan masalah mendasar ketiadaan FHS pada NixOS. Seluruh biner Linux standar (misal: binary VS Code, script Python pip yang mengompilasi modul C, biner Go, Rust, atau file tar.gz dari internet) dapat langsung dieksekusi secara instan tanpa perlu dibungkus (*wrapping*).
2. **Subsistem Audio PipeWire & WirePlumber:**  
   Latensi audio ultra-rendah untuk kebutuhan recording, streaming, gaming, dan Bluetooth audio.
3. **Shell Sadar Generasi Sistem:**  
   Prompt terminal menampilkan informasi nomor generasi aktif saat ini secara real-time:
   ```bash
   [Gen #1] ➔ user@neuronix ~/code $
   ```

---

## 6. Strategi Hardware & Instalasi Offline 100%

- **Dual-Boot Mode pada Menu ISO:**
  - `Boot NEURONIX Installer (Standard / Open-Source AMD/Intel)`
  - `Boot NEURONIX Installer (NVIDIA Proprietary - Locked LTS Kernel)`
- **Instalasi Offline Penuh (*Zero Network Dependency*):**  
  Seluruh paket dasar desktop, compiler GCC, Git, browser, dan biner `neuronix` sudah dipaketkan ke dalam image `squashfs` ISO. Instalasi dapat diselesaikan 100% tanpa sambungan internet.

---

## 7. Matriks Kelemahan, Risiko, dan Solusi Cerdas

| Kelemahan / Risiko Nyata | Akar Masalah | **Solusi Rekayasa Cerdas NEURONIX** |
| :--- | :--- | :--- |
| **Peningkatan Ruang Disk `/nix/store`** | Setiap versi paket memiliki hash terpisah di `/nix/store`. | Format partisi bawaan **Btrfs ZSTD:3** + deduplikasi hardlink real-time (`auto-optimise-store = true`) + timer pembersihan mandiri (`neuronix diet`). |
| **Instabilitas Driver GPU NVIDIA** | Modul kernel NVIDIA rentan rusak saat kernel Linux rolling update. | Mengunci konfigurasi desktop ke versi **Linux Kernel LTS** di file konfigurasi bawaan dan menyediakan fallback generasi instan di bootloader GRUB. |
| **Kurva Belajar File Konfigurasi `.nix`** | Pengguna awam asing dengan paradigma *functional programming*. | Menyediakan file modul siap pakai (misal: `gaming.nix`, `ai-dev.nix`) di `/etc/nixos/modules/` yang hanya memerlukan saklar `enable = true;`. |
| **Ukuran File ISO yang Besar** | Memaketkan beberapa Desktop Environment sekaligus dapat memperbesar file ISO. | Menggunakan kompresi ISO `squashfs` dengan algoritma `xz` tingkat tinggi untuk mempertahankan ukuran ISO di bawah 3.8 GB. |
