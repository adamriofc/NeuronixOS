# NEURONIX Blueprint: Spesifikasi Distribusi Mandiri & Installer Grafis (Fase 4)

> **Kode Dokumen:** `06_DISTRO_SPEC`  
> **Versi:** 1.0.0-draft  
> **Status:** Approved Architecture Specification  
> **Komponen:** Standalone Bootable ISO, Calamares Installer, Wayland Desktop Suites, & NEURONIX Center  

---

## 1. Visi, Positioning, & Arsitektur 4-Layer Platform

### A. Pernyataan Positioning Resmi (*Official Positioning Statement*)
> **"A user-friendly, opinionated Linux distribution built on NixOS, engineered to deliver an EndeavourOS-like onboarding experience, automated hardware detection, graphical system management, and atomic generation rollbacks, while strictly preserving NixOS's declarative and reproducible architecture."**

NEURONIX bukan sekadar "NixOS yang diberi wallpaper dan tema berbeda". Itu adalah jebakan terbesar yang menurunkan nilai teknis menjadi sekadar *custom spin*. NEURONIX adalah **sebuah platform rekayasa sistem operasi utuh (*complete operating system distribution platform*)** yang dirancang dengan kedalaman rekayasa tingkat tinggi.

```text
                             NEURONIX PLATFORM
                                     │
      ┌──────────────────────────────┴──────────────────────────────┐
      │                                                             │
  UX LAYER                                                     SYSTEM LAYER
      │                                                             │
 • Calamares Installer (Flake-Generating)                      • NixOS Pure Substrate
 • NEURONIX Control Center (GUI System Center)                 • Declarative Flakes
 • First-Boot Welcome App & Hardware Profiler                  • Content-Addressed Store
 • Dual-Layer Software Marketplace (Flatpak)                   • Atomic Generations & Rollback
 • One-Click Developer Stacks (neuronix dev)                   • nix-ld Global Dynamic Loader
      │                                                             │
      └──────────────────────────────┬──────────────────────────────┘
                                     │
                           INFRASTRUCTURE LAYER
                                     │
                 • Hermetic ISO Image Compilation
                 • Automated CI/CD Headless QEMU VM Testing
                 • Automated Installer & Desktop Smoke Tests
                 • Hardware Driver Matrix (NVIDIA/PRIME/Wi-Fi)
                 • Architecture Decision Records (ADR-001 - 005)
```

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

## 4. NEURONIX Center & GUI System Control Center

NEURONIX tidak membiarkan pengguna tersesat dalam syntax NixOS. Seluruh kekuatan deklaratif disajikan melalui antarmuka grafis yang ramah namun bertenaga:

### A. First-Boot Welcome App (`neuronix-welcome`)
Saat pertama kali booting pasca-instalasi, aplikasi sapaan awal otomatis memandu pengguna melakukan orientasi sistem, pengaturan Wi-Fi, dan pemilihan profil perangkat lunak modular:
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

### B. GUI System Control Center (`neuronix-control-center`)
Sebagai pusat kendali operasional harian, Control Center menyajikan panel visual yang membungkus mekanisme NixOS di balik layar:
```text
┌──────────────────────────────────────────────────────────────┐
│  NEURONIX CONTROL CENTER                              [ _ X ]│
├──────────────────────────────────────────────────────────────┤
│  System                                                      │
│    ● OS Substrate     : NixOS 26.05 (Yarara)                 │
│    ● Active Generation: #42 (Committed: 2026-09-04 01:15)    │
│    ● Kernel           : Linux 6.12.x-zen-hardened            │
│                                                              │
│  Updates                                                     │
│    ● 14 packages updated in upstream Flake                   │
│    [ 🔄 Check Updates ]   [ ⬇️ Update & Rebuild System ]      │
│                                                              │
│  Hardware Telemetry                                          │
│    ● GPU : NVIDIA RTX 4070 Laptop (PRIME Offload Active)     │
│    ● CPU : AMD Ryzen 7 7840HS (8C/16T, 42°C)                 │
│    ● RAM : 16.0 GB Phys (ZRAM ZSTD Active: 28.4 GB Eff.)     │
│                                                              │
│  Maintenance & Generations                                   │
│    ● History : 42 Total Generations Preserved                │
│    [ ⏪ Rollback Instan ]  [ 📋 Kelola Generasi ]             │
│    [ 🧹 Bersihkan Store ]  [ 🔧 Perbaiki Sistem (Repair) ]    │
└──────────────────────────────────────────────────────────────┘
```

### C. Super User-Friendly Visual Rollback UX ("Time-Travel Safe Guard")
Salah satu keunggulan terbesar NixOS adalah kemampuannya kembali ke masa lalu (*time-travel rollback*). Jika pembaruan sistem menimbulkan masalah, pengguna disajikan dialog penyelamat visual tanpa perlu menyentuh terminal:
```text
┌──────────────────────────────────────────────────────────────┐
│  NEURONIX TIME-TRAVEL ROLLBACK                        [ _ X ]│
├──────────────────────────────────────────────────────────────┤
│  Terjadi masalah setelah pembaruan terakhir?                 │
│  Pilih generasi stabil sebelumnya untuk kembali instan:      │
│                                                              │
│  ● Generasi #43 — (Aktif Saat Ini / Pembaruan Terakhir)      │
│  ○ Generasi #42 — (2026-09-03 19:20) [Stabil - Rekomendasi] │
│  ○ Generasi #41 — (2026-09-01 14:05) [Stabil]                │
│  ○ Generasi #40 — (2026-08-28 09:12) [Generasi Pabrik ISO]   │
│                                                              │
│  [ ⏪ Putar Balik ke Generasi #42 ]    [ 🚀 Boot Sekali Coba ]│
└──────────────────────────────────────────────────────────────┘
```
*Di balik layar:* Memanggil `sudo nixos-rebuild switch --rollback` atau mengaktifkan generasi target di `/nix/var/nix/profiles/system` dalam $< 2$ detik.

---

## 5. Lingkungan Pengembang Satu-Perintah (*One-Command Dev Environments*)

Sebagai distro yang ramah pengembang (*developer-first distribution*), NEURONIX mengintegrasikan perintah cerdas `neuronix dev <stack>`. Perintah ini memanfaatkan lingkungan Nix Flakes hermetis yang instan, memaketkan seluruh rantai perkakas (*toolchain*) lengkap tanpa mengotori sistem induk:

```text
┌───────────────────────┬────────────────────────────────────────────────────────┐
│ Perintah CLI          │ Toolchain & Ekosistem yang Disediakan Otomatis         │
├───────────────────────┼────────────────────────────────────────────────────────┤
│ neuronix dev python   │ Python 3.12, uv, Ruff, Pyright linter, & PostgreSQL DB │
│ neuronix dev rust     │ rustc, cargo, rust-analyzer, clippy, & mold linker     │
│ neuronix dev node     │ Node.js LTS, pnpm, TypeScript, ESLint, & Prettier      │
│ neuronix dev ai       │ PyTorch, CUDA Toolkit, Ollama, JupyterLab, & Pandas    │
│ neuronix dev go       │ Go compiler, gopls, golangci-lint, & Delve debugger    │
│ neuronix dev web3     │ Rust, Foundry (cast, forge), Solana CLI, & Node.js     │
└───────────────────────┴────────────────────────────────────────────────────────┘
```
Pengembang baru tidak perlu menghabiskan 3 hari untuk mengonfigurasi compiler dan dependensi C; cukup satu baris perintah, seluruh lingkungan kerja langsung siap dalam hitungan detik.

---

## 6. Fleksibilitas Pengaturan Auto-TRIM: Kendali Penuh di Tangan Pengguna

Sebagaimana filosofi EndeavourOS yang tidak pernah memaksakan kehendak pada penggunanya, **fitur Auto-TRIM di NEURONIX bersifat 100% fleksibel dan dapat dikustomisasi**:

1. **Pilihan di Calamares Installer:**  
   Pada layar konfigurasi sistem, disediakan opsi eksplisit:  
   `[✓] Aktifkan Pemeliharaan Storage Otomatis (Auto-TRIM & Inode Deduplication) - Disarankan untuk SSD & Virtual Machine`. Pengguna yang menggunakan harddisk mekanis (HDD) konvensional atau ingin mengontrol TRIM secara manual dapat mematikan opsi ini.
2. **Kendali Visual di NEURONIX Center:**  
   Tersedia saklar tombol `[ ON / OFF ]` untuk mengaktifkan atau mematikan timer `fstrim.timer` dan scheduled diet hanya dengan satu kali klik.
3. **Kendali Baris Perintah CLI:**  
   ```bash
   # Menonaktifkan timer pemeliharaan otomatis
   neuronix config set auto-trim off

   # Mengaktifkan kembali timer pemeliharaan otomatis
   neuronix config set auto-trim on
   ```

---

## 7. Toko Aplikasi Grafis (GUI Software Marketplace: Flatpak & Flathub Bawaan)

Salah satu kelemahan terbesar yang membuat pengguna frustrasi saat pertama kali menginstal NixOS adalah **ketiadaan App Store visual**. Pengguna biasa terpaksa membuka browser dan mencari nama paket di `search.nixos.org`, lalu menulis baris deklaratif hanya untuk menginstal aplikasi desktop sehari-hari seperti Spotify atau Discord.

**NEURONIX Fase 4 memecahkan masalah ini dengan Arsitektur Perangkat Lunak Dua Lapis (*Dual-Layer Software Architecture*):**

1. **Lapis 1 (Core OS & Developer Stack):** Dikelola secara murni oleh **Nixpkgs / Flakes / CLI**. Menjamin kernel, compiler, Python, Node, dan Docker kebal rusak dan memiliki riwayat rollback instan.
2. **Lapis 2 (Desktop Graphical Applications):** Dikelola oleh **Flatpak & Flathub Marketplace**. Pengguna dapat menginstal Spotify, Discord, Telegram, Steam, Obsidian, Blender, dan browser pihak ketiga secara visual dengan satu klik.

### Integrasi Visual Out-of-the-Box:
- **GNOME Edition:** Mengintegrasikan **GNOME Software** dengan plugin Flatpak dan repositori Flathub aktif otomatis.
- **KDE Plasma Edition:** Mengintegrasikan **KDE Discover** dengan backend Flatpak dan repositori Flathub aktif otomatis.
- **Sinkronisasi Tema & Kursor Sempurna:** Memasang `xdg-desktop-portal` dan `xdg-desktop-portal-gtk/kde` sehingga aplikasi Flatpak otomatis mengikuti tema *Dark Slate*, palet warna *Tokyo Cyber*, dan ukuran kursor sistem tanpa ada desinkronisasi visual.

---

## 8. Kompatibilitas Biner & Ergonomi Pengembang Out-of-the-Box

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

## 9. Strategi Hardware & Instalasi Offline 100%

- **Dual-Boot Mode pada Menu ISO:**
  - `Boot NEURONIX Installer (Standard / Open-Source AMD/Intel)`
  - `Boot NEURONIX Installer (NVIDIA Proprietary - Locked LTS Kernel)`
- **Instalasi Offline Penuh (*Zero Network Dependency*):**  
  Seluruh paket dasar desktop, compiler GCC, Git, browser, dan biner `neuronix` sudah dipaketkan ke dalam image `squashfs` ISO. Instalasi dapat diselesaikan 100% tanpa sambungan internet.

---

## 10. Struktur Repositori Rekayasa Profesional & Architecture Decision Records (ADRs)

Struktur repositori NEURONIX dirancang dengan standar *enterprise systems engineering*:

```text
neuronix/
├── flake.nix                  # Entrypoint orkestrasi Flake murni
├── flake.lock                 # Lockfile pin dependensi hermetis
│
├── hosts/                     # Profil spesifik mesin target
│   ├── desktop/               # Desktop workstation (Multi-GPU/HiDPI)
│   ├── laptop/                # Laptop hemat daya (Optimus/S0ix sleep)
│   └── vm/                    # Virtual machine (QEMU / Quickemu / Cloud)
│
├── modules/                   # Modul konfigurasi deklaratif modular
│   ├── desktop/               # KDE 6, GNOME Tokyo, Hyprland Wayland
│   ├── hardware/              # NVIDIA PRIME, Wi-Fi blobs, Bluetooth audio
│   ├── networking/            # NetworkManager, Captive Portal, VPN, DNS
│   ├── security/              # Secure Boot Lanzaboote, Microcode, Hardening
│   └── services/              # ZRAM ZSTD, systemd-oomd, Flatpak portals
│
├── packages/                  # Derivasi paket kustom (NEURONIX Center, CLI)
├── installer/                 # Modul resep partisi Btrfs & branding Calamares
├── tooling/                   # Skrip automasi pembangunan ISO & rilis
├── docs/                      # Dokumentasi profesional
│   ├── architecture.md        # Diagram mendalam arsitektur 4-layer
│   ├── installation.md        # Panduan instalasi grafis & dual-boot
│   ├── development.md         # Petunjuk kontribusi & testing lokal
│   ├── troubleshooting.md     # Resolusi mandiri 27 skenario umum
│   └── adr/                   # Architecture Decision Records resmi
│       ├── ADR-001-why-flakes.md
│       ├── ADR-002-why-calamares-flake-generator.md
│       ├── ADR-003-immutable-store-vs-flatpak.md
│       ├── ADR-004-update-channel-strategy.md
│       └── ADR-005-hardware-detection-architecture.md
└── tests/                     # 15 Test Suites otomatis (336 Test Cases)
```

---

## 11. Pipeline Pengujian Otomatis Virtual Machine (CI/CD End-to-End VM Testing)

Nilai portofolio tertinggi bukan sekadar screenshot, melainkan **CI/CD pipeline yang menguji siklus hidup distro secara otomatis di headless QEMU VM**:

```text
┌──────────────────────────────────────────────────────────────┐
│        PIPELINE PENGUJIAN OTOMATIS GITHUB ACTIONS CI/CD      │
├──────────────────────────────────────────────────────────────┤
│ 1. Git Push / PR ➔ Pemicu Otomatis Pipeline                  │
│ 2. Nix Flake Check ➔ Validasi sintaks deklaratif & hermetis  │
│ 3. Build ISO Artifact ➔ Kompilasi image Live ISO installer   │
│ 4. Boot Headless QEMU VM ➔ Boot ISO di lingkungan bersih     │
│ 5. Automated Installer Test ➔ Uji partisi Btrfs via Calamares│
│ 6. Boot Installed System ➔ Booting pertama OS hasil install  │
│ 7. Test Services & Desktop ➔ Validasi Wayland, Audio, Store  │
│ 8. PASS & Rilis Artefak ➔ Sematkan Badge Status Portofolio   │
└──────────────────────────────────────────────────────────────┘
```

**Lencana Portofolio (*Portfolio Badges*):**  
`Build: Passing` | `Tests: 336/336 Passing` | `ISO: Verified` | `Installer: Verified` | `Reproducible: 100%`

---

## 12. Roadmap Kematangan Bertahap (*Phased Maturity Pipeline v0.1 to v1.0*)

Proyek dikembangkan secara metodis melalui 8 tahapan rilis bertahap untuk menjamin stabilitas kelas satu:

```text
v0.1 — Minimal Bootable ISO (Kernel + CLI `neuronix` + Network)
  ↓
v0.2 — Calamares Installer (Flake-Generating + Btrfs ZSTD:3 Recipe)
  ↓
v0.3 — Hardware Profiles & Auto-Detection (NVIDIA PRIME + Wi-Fi Blobs)
  ↓
v0.4 — Graphical Control Center (`neuronix-control-center` + Telemetri)
  ↓
v0.5 — User-Friendly Rollback & Generations UX (Time-Travel Guard)
  ↓
v0.6 — Automated CI/CD Headless VM Testing Pipeline
  ↓
v0.7 — One-Command Development Stacks (`neuronix dev <stack>`)
  ↓
v1.0 — Flagship Stable Public Release (Produksi Mandiri Siap Pakai)
```

---

## 13. Matriks Paripurna 27 Pilar Pertahanan Kedap Peluru (*The 27-Pillar Ironclad Shield*)

Di luar kelemahan umum, terdapat **27 celah fatal dan friksi desktop Linux** yang kerap menghancurkan adopsi pengguna, dan berikut adalah solusi rekayasa cerdas terintegrasi dalam NEURONIX:

| No | Celah Fatal Tersembunyi | Dampak Kegagalan Nyata | **Solusi Rekayasa Cerdas NEURONIX** |
| :---: | :--- | :--- | :--- |
| **1** | **Pemblokiran Lisensi Proprietary (`allowUnfree`)** | NixOS secara default menolak aplikasi seperti Steam, NVIDIA, Spotify, Discord dengan error `unfree license`. | Calamares otomatis menyisipkan `nixpkgs.config.allowUnfree = true;` pada konfigurasi yang digenerate. Pengguna tidak akan pernah diblokir saat instalasi software. |
| **2** | **Konflik Dual-Boot Windows (EFI / BitLocker / Fast Startup)** | Installer Linux sering gagal mendeteksi partisi Windows Boot Manager, menyebabkan Windows hilang dari menu boot. | Modul Calamares NEURONIX mengaktifkan `boot.loader.grub.useOSProber = true` secara otomatis dan menyelaraskan partisi ESP UEFI, serta memunculkan peringatan visual ramah jika *Windows Fast Startup* terdeteksi aktif. |
| **3** | **Fragmentasi Metadata Filesystem Btrfs** | Subvolume Btrfs dengan ribuan hardlink `/nix/store` dapat mengalami penumpukan chunk metadata kosong. | Menyematkan service pemeliharaan bulanan ringan di latar belakang (`btrfs-balance.timer`) dengan ambang batas rendah (`btrfs balance start -dusage=10 /`) yang berjalan senyap tanpa membebani I/O. |
| **4** | **Ketidakteraturan Izin Aplikasi Flatpak (Wayland/GPU)** | Beberapa aplikasi Flatpak sering crash karena tidak memiliki akses ke socket Wayland atau akselerasi GPU Mesa. | Menyetel izin dasar global Flatpak via declarative overrides (`flatpak override --system --socket=wayland --socket=fallback-x11 --device=dri`) sehingga seluruh aplikasi GUI Flatpak langsung terakselerasi GPU. |
| **5** | **Kepenuhan Partisi `/boot` (EFI Fat32 Overflow)** | Setiap generasi menyimpan kernel & initrd di `/boot`. Setelah 20-30 rebuild, partisi 512MB penuh dan sistem crash saat update. | Calamares mengalokasikan partisi ESP `/boot` sebesar **1.0 GiB** dan mengunci `boot.loader.systemd-boot.configurationLimit = 15;` sehingga generasi usang di `/boot` dirotasi otomatis tanpa pernah habis. |
| **6** | **Ketiadaan Driver Wi-Fi/Bluetooth Realtek & Broadcom** | Laptop ASUS/Lenovo/HP memakai chip Wi-Fi proprietary. Pasca install offline, Wi-Fi mati dan pengguna tidak bisa internetan. | File ISO menyematkan `hardware.enableAllFirmware = true;` dan memaketkan koleksi lengkap `linux-firmware` serta modul DKMS out-of-tree, menjamin 99.9% Wi-Fi laptop langsung menyala. |
| **7** | **Laptop Hybrid GPU Battery Drain (NVIDIA Optimus / PRIME)** | Laptop dengan dual GPU mengalami baterai boros (habis 1.5 jam) atau layar eksternal via port HDMI gelap gulita (*black screen*). | Deteksi otomatis di Calamares & NEURONIX Center: mengonfigurasi `hardware.nvidia.prime.offload` otomatis (dGPU tidur saat browsing) + applet tray untuk beralih instan ke mode Dedicated GPU. |
| **8** | **Penolakan Boot oleh UEFI Secure Boot Windows 11** | Laptop modern Windows 11 mengunci BIOS ke Secure Boot aktif; USB Linux ditolak dengan error *"Verification signature failed"*. | Menyediakan bootloader `shim` bersertifikat Microsoft Third-Party UEFI CA pada file ISO, serta dukungan framework `lanzaboote` untuk penandatanganan generasi kernel secara mandiri. |
| **9** | **File Chooser Flatpak Hang / Freeze pada Wayland** | Saat upload file di aplikasi Flatpak (Discord/Chrome), dialog file macet 30 detik atau memunculkan pemilih file GTK yang pecah. | Mengonfigurasi `/etc/xdg/xdg-desktop-portal/portals.conf` secara deklaratif untuk memetakan portal file chooser sesuai desktop: `kdialog` untuk KDE dan `gtk/nautilus` untuk GNOME tanpa DBus freeze. |
| **10** | **Baterai Panas Saat Laptop Ditutup (S0ix Modern Standby Drain)** | Laptop Intel/AMD baru tidak mendukung S3 sleep biasa; di dalam tas laptop tetap menyala dan baterai habis dalam 2 jam. | Mengaktifkan `services.power-profiles-daemon` bawaan + `services.thermald` untuk Intel + tuning parameter kernel `mem_sleep_default=deep` yang menghentikan clock CPU sepenuhnya saat layar ditutup. |
| **11** | **Desinkronisasi Jam Dual-Boot Windows (RTC Local Time Shift)** | Setiap kali reboot dari Linux ke Windows, jam di Windows bergeser salah 7 jam karena perbedaan standar UTC vs Local Time. | Calamares otomatis mendeteksi partisi Windows dan menyetel `time.hardwareClockInLocalTime = true;` di konfigurasi NixOS. Jam Windows dan Linux selalu sinkron 100%. |
| **12** | **Crash Game Berat / Anti-Cheat Proton (`vm.max_map_count`)** | Game modern (Counter-Strike 2, Hogwarts Legacy) atau IDE berat crash diam-diam karena batas alokasi memory map bawaan Linux terlalu kecil (65530). | Pre-konfigurasi parameter kernel standar SteamOS: `boot.kernel.sysctl."vm.max_map_count" = 2147483642;` dan `fs.file-max = 2097152;`. Game dan IDE berat bebas crash. |
| **13** | **Aplikasi Electron & XWayland Buram pada Layar HiDPI (4K)** | Pada skala fractional Wayland 125% atau 150%, teks di VS Code, Discord, Spotify, dan Steam terlihat buram/pecah (*blurry raster*). | Menyematkan flag Ozone Wayland global (`--ozone-platform=wayland`) dan mengaktifkan protokol `wp-fractional-scale-v1`. Tampilan tajam sempurna (*pixel-crisp*). |
| **14** | **Pemadaman Listrik Saat Transaksi Sistem (Boot Watchdog)** | Baterai habis atau listrik mati di tengah-tengah pergantian symlink generasi dan penulisan entri boot loader. | Integrasi UEFI Boot Assessment Watchdog: bootloader mempertahankan generasi sebelumnya sebagai entri default sampai generasi baru sukses mencapai `default.target` sekali. |
| **15** | **Kegagalan Input Huruf Non-Latin / IME Multibahasa (Fcitx5)** | Mengetik karakter Jepang, Korea, atau Mandarin di Wayland gagal karena desinkronisasi variabel lingkungan IME. | Integrasi deklaratif `i18n.inputMethod.type = "fcitx5"` dengan modul frontend Wayland aktif bawaan, dapat dipilih langsung di Calamares atau NEURONIX Center. |
| **16** | **Kegagalan Sertifikat SSL pada Jaringan Korporat / Kampus** | Di jaringan dengan inspeksi proxy (Zscaler/Fortinet), seluruh download paket Nix gagal karena error *self-signed certificate*. | Tombol satu klik *"Import Corporate Root CA"* di NEURONIX Center dan CLI `neuronix config add-ca <cert.pem>` yang otomatis mendaftarkan sertifikat ke trust-store OS dan Nix daemon. |
| **17** | **Desktop Freeze & Hard-Restart Saat Beban Berat (Linux OOM Lockup)** | Saat RAM penuh, kernel Linux biasa mengalami swap thrashing, mouse membeku beberapa menit, lalu PC tiba-tiba restart/kernel panic. | Mengaktifkan **ZRAM Swap Kompresi ZSTD** (efektif menambah RAM 50%-100%) + **`systemd-oomd` berbasis PSI (*Pressure Stall Information*)** + `vm.swappiness = 180`. Hanya tab/aplikasi rakus yang dihentikan; desktop tetap lancar dan PC **mustahil freeze/restart**. |
| **18** | **Suara Headset Bluetooth Mendadak Cempreng Saat Telepon (HFP/HSP AM Radio Trap)** | Saat menyalakan mic di Zoom/Discord, audio Bluetooth turun ke 64kbps mono AM radio yang sangat buruk. | Mengonfigurasi WirePlumber dengan codec Bluetooth modern: **LDAC, AptX HD, AAC, dan mSBC/LC3** (FastStream / LC3Plus) yang mendukung audio jernih HD saat mikrofon aktif bersamaan. |
| **19** | **Baterai Laptop Cepat Rusak / Usia Pendek (Ketiadaan Batas Cas 80%)** | Laptop dicolok charger 24 jam sehari mengalami degradasi kapasitas baterai hingga 30% dalam setahun karena Linux tidak membatasi charging ke 80%. | Integrasi kontroler ambang batas baterai bawaan di NEURONIX Center (`charge_control_limit_max`) untuk ASUS, Lenovo, ThinkPad, Dell, Framework: toggle satu klik *"Batas Pengisian Baterai 80% (Perpanjang Umur Baterai)"*. |
| **20** | **Kipas Laptop Berisik & CPU 80% Saat Nonton YouTube 4K (Ketiadaan VA-API Bawaan)** | Menonton video 4K/60fps di browser membuat CPU overheat dan kipas meraung kencang karena akselerasi video hardware tidak aktif. | Inklusi otomatis driver Mesa VA-API (`intel-media-driver`, `libva-mesa`, `nvidia-vaapi`) + flags deklaratif Firefox & Chromium hardware decode. Video 4K berjalan mulus dengan beban CPU $< 3\%$ dan kipas senyap. |
| **21** | **Wi-Fi Publik Cafe / Bandara Tidak Bisa Terkoneksi (Captive Portal Trap)** | Saat terhubung ke Wi-Fi Starbucks, hotel, atau bandara, halaman login persyaratan (*captive portal*) tidak pernah muncul otomatis di Linux. | Mengaktifkan NetworkManager connectivity check bawaan yang otomatis memunculkan pop-up jendela login otentikasi saat terdeteksi jaringan Wi-Fi publik dengan captive portal. |
| **22** | **Frustrasi Instalasi Printer & Scanner (Driverless AirPrint / Mopria)** | Mencolok printer USB atau menghubungkan printer Wi-Fi di kantor/rumah membutuhkan pencarian file PPD/driver yang rumit. | Mengaktifkan `services.printing` + `services.avahi` + `sane-airscan` bawaan dengan protokol modern **Apple AirPrint / Mopria IPP Everywhere**. 98% printer & scanner modern mencetak dan scan otomatis tanpa instal driver. |
| **23** | **Flashdisk / Harddisk Eksternal Windows Read-Only (NTFS / exFAT Mount)** | Colok flashdisk atau harddisk eksternal NTFS dari Windows sering kali tidak muncul otomatis di file manager atau berstatus *read-only*. | Mengaktifkan driver kernel resmi `ntfs3` berkecepatan tinggi + `udisks2` + `gvfs` bawaan. Harddisk eksternal Windows dan flashdisk exFAT otomatis ter-mount dengan izin tulis penuh dan kecepatan transfer 500+ MB/s. |
| **24** | **Suara Letupan "Pop" pada Headphone Kabel 3.5mm (ALSA Powersave Click)** | Saat jeda audio 5 detik di headphone kabel, chip audio DAC mati sendiri dan memicu bunyi letupan menjengkelkan saat audio berbunyi lagi. | Mengonfigurasi WirePlumber dan parameter ALSA `snd_hda_intel power_save=0` pada daya AC (serta delay timeout halus pada baterai) untuk mengeliminasi bunyi letupan audio 100%. |
| **25** | **Hibernasi Rusak & Btrfs Swap Corrupt (Swapfile CoW Hibernation Trap)** | Menjalankan hibernasi (suspend to disk) pada partisi Btrfs sering gagal atau merusak file karena swapfile mewarisi fitur Copy-on-Write (CoW). | Calamares otomatis mengalokasikan subvolume terpisah `@swap` dengan atribut `chattr +C` (CoW disabled) dan menghitung offset resume Btrfs secara otomatis pada bootloader. |
| **26** | **Kerentanan Hardware CPU & Microcode Usang (Spectre / Zenbleed / Downfall)** | CPU Intel/AMD tanpa microcode terbaru rentan terhadap kebocoran data hardware dan ketidakstabilan instruksi CPU. | Secara deklaratif mengaktifkan pembaruan microcode otomatis out-of-the-box (`hardware.cpu.intel.updateMicrocode = true` dan `hardware.cpu.amd.updateMicrocode = true`). |
| **27** | **Gagal Git Push SSH & Popup GPG Signing Macet di Wayland** | Menjalankan `git push` atau commit signing di terminal Wayland gagal karena SSH socket tidak terhubung atau popup `pinentry` dialog tidak muncul. | Integrasi otomatis `programs.gnupg.agent` dengan `pinentry-gnome3` / `pinentry-qt` dan pengikatan soket `SSH_AUTH_SOCK` terpadu ke systemd user session. |
