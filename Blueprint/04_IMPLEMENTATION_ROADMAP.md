# NEURONIX Specification: Implementation Roadmap & Phased Execution

> **Document ID:** `NRX-ROAD-004`  
> **Status:** APPROVED  
> **Path:** `Blueprint/04_IMPLEMENTATION_ROADMAP.md`  

---

## 1. Phased Execution Methodology

Untuk menjamin kualitas perangkat lunak kelas dunia tanpa risiko *overwhelmed*, pengembangan **NEURONIX** dipecah menjadi **5 Fase Disiplin Bertahap**. 

Setiap fase wajib lolos kriteria verifikasi ketat (*Exit Gate*) sebelum tim/pengembang diizinkan melangkah ke fase berikutnya.

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   FASE 0     │ ──► │   FASE 1     │ ──► │   FASE 2     │ ──► │   FASE 3     │ ──► │   FASE 4     │
│  Foundations │     │   Core MVP   │     │  AI Copilot  │     │   Shadow VM  │     │ Standalone OS│
│  Workspace   │     │  CLI v0.1    │     │  Driver v0.2 │     │  Canary v0.3 │     │ ISO Distro   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

---

## 2. Rincian Fase Pengembangan

### FASE 0: Inisialisasi Proyek & Repositori Git
*Fokus: Meletakkan fondasi manajemen kode, lisensi, dan perkakas pengembangan lokal.*
- **Aktivitas Utama:**
  1. Inisialisasi Git repository di `the repository`.
  2. Setup struktur direktori standar: `src/`, `modules/`, `scripts/`, `tests/`, `docs/`.
  3. Konfigurasi lisensi `Apache-2.0` dan dokumen `README.md` pengantar berstandar global.
  4. Setup file `.gitignore` yang ketat agar tidak ada biner atau file temporer terunggah.
- **Kriteria Kelulusan Fase (Exit Gate 0):**
  - Git repository bersih, terstruktur rapi, dan commit perdana terverifikasi dengan hash SHA.

---

### FASE 1: Core CLI Guardian Engine (MVP - v0.1)
*Fokus: Membangun biner CLI fungsional tanpa AI yang langsung memecahkan masalah storage dan isolasi harian.*
- **Fitur yang Dibangun:**
  1. **`neuronix status`:** Menampilkan dashboard terminal interaktif berisi versi generasi sistem, sisa storage, dan statistik deduplikasi inode.
  2. **`neuronix diet`:** Menjalankan `nix-collect-garbage -d`, `nix-store --optimise`, dan memicu `fstrim -av` ke host Host Physical Storage secara otomatis.
  3. **`neuronix run <app>`:** Membuka subshell isolasi instan menggunakan `nix-shell` / `bwrap`.
  4. **`neuronix undo`:** Mengeksekusi rollback atomik ke generasi sebelumnya dalam $< 3$ detik.
- **Kriteria Kelulusan Fase (Exit Gate 1):**
  - Perintah `neuronix diet` terbukti memotong kapasitas file virtual disk di Host Physical Storage host.
  - Perintah `neuronix run` mampu menyalakan aplikasi tanpa meninggalkan file sampah pasca-exit.
  - Perintah `neuronix undo` berhasil memutar balik sistem dengan exit code `0`.

---

### FASE 2: Decoupled Cognitive Copilot (v0.2)
*Fokus: Menghubungkan lapisan AI modular sebagai driver bahasa alami opsional.*
- **Fitur yang Dibangun:**
  1. Integrasi protokol **Model Context Protocol (MCP)**.
  2. Parser bahasa alami ke ekspresi Nix AST (misal: menerjemahkan *"saya butuh python 3.12 dengan pandas"* menjadi derivasi nix yang valid).
  3. Flag aktivasi `--ai`: Sistem tetap 100% offline secara default, dan hanya memanggil AI jika flag ini dipanggil atau saat masuk mode chat interaktif.
  4. Dukungan backend LLM ganda: Model lokal (Ollama) dan API Cloud (Google Gemini / Anthropic / OpenAI / Grok).
- **Kriteria Kelulusan Fase (Exit Gate 2):**
  - AI mampu menyusun konfigurasi dan memverifikasinya via `dry-build`.
  - Jika koneksi internet dimatikan, Core Engine tetap berfungsi 100% tanpa error.

---

### FASE 3: Shadow Micro-VM Simulation (`neuronix try` - v0.3)
*Fokus: Menghadirkan fitur simulasi kembaran sistem operasi di RAM sebelum promosi ke sistem riil.*
- **Fitur yang Dibangun:**
  1. Otomasi perintah `nixos-rebuild build-vm` yang dikemas dalam perintah sederhana: `neuronix try "<konfigurasi>"`.
  2. Eksekusi Micro-VM tanpa layar (*headless*) atau dengan jendela GUI Spice sementara di dalam memori RAM (`/dev/shm`).
  3. Skrip uji coba otomatis (*smoke test harness*): Memeriksa status systemd unit di dalam VM simulasi.
  4. Promosi satu klik (*One-click promotion*): Menerapkan perubahan ke OS utama jika tes simulasi lulus 100%.
- **Kriteria Kelulusan Fase (Exit Gate 3):**
  - Konfigurasi yang rusak/berhalusinasi terbukti gagal di dalam Shadow VM tanpa merusak OS utama.

---

### FASE 4: Standalone OS Distribution & Calamares Installer (v1.0)
*Fokus: Mewujudkan "The Golden Sweet Spot" ala EndeavourOS di atas fondasi NixOS: Live ISO mandiri, installer grafis Calamares, pilihan desktop Wayland terkurasi, dan onboarding center yang ramah.*
- **Spesifikasi Teknis Rinci:** Lihat dokumen referensi lengkap di [06_STANDALONE_DISTRIBUTION_SPECIFICATION.md](file://Blueprint/06_STANDALONE_DISTRIBUTION_SPECIFICATION.md).
- **Fitur & Komponen Kunci yang Dibangun:**
  1. **Kompilasi Live ISO Mandiri (`iso.nix`):**
     - Menggunakan `nixos-generators` untuk memaketkan kernel Linux LTS, seluruh biner `neuronix`, server MCP, dan closure desktop ke dalam satu file ISO mandiri.
     - Mode instalasi 100% Offline via local image squashfs (instalasi selesai tanpa koneksi internet).
     - Menu boot ISO ganda: Opsi driver Open-Source (AMD/Intel/Mesa) dan Opsi NVIDIA Proprietary dengan modul kernel LTS terkunci.
  2. **Integrasi & Branding Calamares Installer:**
     - Tampilan grafis modern dengan palet warna *Dark Slate + Minimalist Cyan Accent* (zero AI-slop).
     - Resep partisi otomatis cerdas: **Btrfs Subvolumes dengan Kompresi Transparan ZSTD Level 3 (`compress=zstd:3`)**, memangkas ukuran fisik `/nix/store` hingga 40-50% tanpa beban CPU.
     - Dual-boot UEFI aman dan konfigurasi user dengan izin sudo ramah pengembang.
  3. **Katalog Desktop Environment Wayland Terkurasi:**
     - **KDE Plasma 6 Wayland:** Breeze Slate Glass, akselerasi GPU penuh, konsumsi RAM idle ~750 MB - 850 MB.
     - **GNOME 47/50 Wayland:** Palet warna Tokyo Cyber / Dark Slate, tipografi Inter + JetBrains Mono, gestur touchpad 3-jari sangat fluida.
     - **Hyprland Wayland:** Window auto-tiling, animasi fisika halus, Waybar terintegrasi dengan telemetri `neuronix`.
     - **Cinnamon / XFCE / Minimal:** Opsi desktop tradisional yang ringan atau instalasi headless server.
  4. **Aplikasi Sapaan Awal (NEURONIX Center ala `eos-welcome`):**
     - Dasbor grafis yang otomatis menyapa pengguna saat pertama kali boot.
     - Telemetri hardware instan (GPU, CPU, deteksi virtualisasi, dan kapasitas storage).
     - Satu klik aktivasi profil modular: Gaming & Steam (Proton GE), AI Developer (PyTorch + CUDA + Ollama), Web Developer.
     - Tombol cepat verifikasi sistem, rollback bencana (`neuronix undo`), dan simulasi RAM (`neuronix try`).
  5. **Ergonomi Pengembang & Kompatibilitas Biner Global Out-of-the-Box:**
     - **`nix-ld` Aktif Global:** Seluruh biner Linux standar (VS Code extensions, biner Go, Rust, script Python pip) langsung jalan tanpa error FHS.
     - **PipeWire & WirePlumber:** Subsistem audio latensi rendah untuk produksi audio dan gaming.
     - **Terminal Sadar Generasi:** Prompt terminal otomatis menampilkan status generasi sistem aktif (`[Gen #1] ➔ user@neuronix ~/code $`).
  6. **Toko Aplikasi Grafis & Fleksibilitas Pemeliharaan:**
     - **GUI App Store Bawaan:** GNOME Software / KDE Discover terintegrasi Flathub dengan sinkronisasi portal tema Wayland.
     - **Kustomisasi Penuh Auto-TRIM:** Kendali toggle switch di GUI (Calamares & NEURONIX Center) serta CLI (`neuronix config set auto-trim on|off`).
     - **Inklusi Otomatis `allowUnfree = true`:** Mengeliminasi error lisensi proprietary pada instalasi software umum (NVIDIA, Steam, Discord).
  7. **10 Pertahanan Perangkat Keras Kedap Peluru (*Bulletproof Hardware Shield*):**
     - Alokasi 1.0 GiB ESP `/boot` dengan auto-rotasi batas 15 generasi (anti-overflow EFI).
     - Firmware Wi-Fi/Bluetooth Realtek/Broadcom lengkap di ISO offline.
     - Manajemen Hybrid GPU (NVIDIA Optimus / AMD PRIME) hemat daya & HDMI out.
     - Dukungan Secure Boot Windows 11 via signed `shim` bootloader.
     - Penanganan sleep laptop S0ix modern standby (anti panas di dalam tas).
     - Pemetaan portal file-chooser Flatpak tanpa freeze DBus.
- **Kriteria Kelulusan Fase (Exit Gate 4):**
  - File ISO sukses di-compile secara hermetis dan dapat di-boot di mesin bare-metal maupun mesin virtual bersih (QEMU / Quickemu / VirtualBox).
  - Installer Calamares sukses mengeksekusi partisi Btrfs ZSTD:3 dan menyelesaikan instalasi hingga masuk ke desktop Wayland pilihan.
  - Seluruh biner Linux standar (non-Nix FHS) terbukti langsung berjalan via `nix-ld` bawaan.
  - Biner `neuronix` dan server MCP berfungsi 100% di sistem hasil instalasi.
  - Perangkat keras Wi-Fi, audio PipeWire, dan display manager terverifikasi berfungsi normal saat booting pertama kali tanpa internet.

---

### FASE 5: Ekspansi Lintas Platform (Windows WSL2 & macOS Darwin)
*Fokus: Membawa kekuatan NEURONIX ke ekosistem non-Linux.*
- **Fitur yang Dibangun:**
  1. Paket `neuronix-wsl` untuk Windows 10/11.
  2. Formula Homebrew / Flake Darwin untuk pengguna macOS.
- **Kriteria Kelulusan Fase (Exit Gate 5):**
  - Pengguna Windows bisa menjalankan `neuronix run` langsung dari PowerShell.
  - Pengguna macOS bisa mengisolasi software tanpa Docker Desktop.
