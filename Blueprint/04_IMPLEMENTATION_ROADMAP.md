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
*Fokus: Memaketkan seluruh ekosistem menjadi file ISO mandiri yang bisa di-install di komputer fisik apa pun.*
- **Fitur yang Dibangun:**
  1. Modul **`nixos-generators`** untuk mengompilasi ISO mandiri dari satu file Flake.
  2. Integrasi tema dan alur instalasi grafis **Calamares**.
  3. Konfigurasi *out-of-the-box*: `nix-ld` bawaan, auto-TRIM aktif, dan `neuronix` CLI sudah terpasang di sistem pengguna.
  4. Wizard *First-Boot Onboarding*: Sapaan awal yang ramah untuk mengonfigurasi profil pengguna secara otomatis.
- **Kriteria Kelulusan Fase (Exit Gate 4):**
  - File ISO berhasil di-boot di mesin virtual bersih (VirtualBox / QEMU) dan di PC bare-metal.
  - Calamares sukses mempartisi disk dan menginstal sistem hingga masuk desktop dengan sukses.

---

### FASE 5: Ekspansi Lintas Platform (Windows WSL2 & macOS Darwin)
*Fokus: Membawa kekuatan NEURONIX ke ekosistem non-Linux.*
- **Fitur yang Dibangun:**
  1. Paket `neuronix-wsl` untuk Windows 10/11.
  2. Formula Homebrew / Flake Darwin untuk pengguna macOS.
- **Kriteria Kelulusan Fase (Exit Gate 5):**
  - Pengguna Windows bisa menjalankan `neuronix run` langsung dari PowerShell.
  - Pengguna macOS bisa mengisolasi software tanpa Docker Desktop.
