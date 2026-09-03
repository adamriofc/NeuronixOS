# NEURONIX Specification: Product Requirements Document (PRD)

> **Document ID:** `NRX-PRD-001`  
> **Status:** APPROVED  
> **Path:** `Blueprint/01_PRD_PRODUCT_REQUIREMENTS.md`  

---

## 1. Vision & Mission Statement

### 1.1 Visi
Menjadi standar platform sistem operasi mandiri (*Standalone Operating System*) dan perkakas kerja pengembang (*Developer Harness*) nomor satu di dunia yang menyatukan komputasi fungsional deterministik dengan orkestrasi kecerdasan buatan otonom, menghilangkan friksi teknis sistem operasi bagi seluruh pengembang global.

### 1.2 Misi
1. **Membebaskan Pengembang:** Mengeliminasi Docker Desktop bloat dan problem *"works on my machine"* melalui ruang kerja sekali pakai (*ephemeral*) yang instan dan hemat memori.
2. **Menjinakkan AI:** Membangun dinding pengaman matematis (*formal compiler gates*) agar agen AI otonom dapat dipercaya mengelola infrastruktur tanpa risiko halusinasi destruktif.
3. **Mendemokratisasi NixOS:** Mengubah kekuatan fungsional NixOS yang rumit menjadi perkakas elegan yang dapat digunakan dengan mudah oleh pengguna awam sekalipun lewat bahasa alami.

---

## 2. Problem Statement & Market Analysis

| Titik Sakit (*Pain Point*) | Kondisi Industri Saat Ini (Status Quo) | Solusi yang Dihadirkan NEURONIX |
| :--- | :--- | :--- |
| **Docker Desktop Bloat** | Docker Desktop memakan 4–8 GB RAM, boros baterai, dan menimbun puluhan gigabyte layer image yang tak terpakai di laptop pengembang. | **Daemonless Ephemeral Substrate:** Berjalan murni sebagai proses CLI instan tanpa background daemon, menggunakan *content-addressed inode sharing*. |
| **Kerusakan Sistem Akibat AI** | Agen AI yang diberi akses shell di Ubuntu/Windows sering salah menghapus file sistem atau memicu konflik library permanen. | **Atomic State & 2-Second Rollback:** Perubahan diverifikasi di level *dry-build*, dan sistem dapat kembali ke kondisi semula dalam 2 detik. |
| **Storage Bleed pada VM (Host Physical Storage)** | Virtual disk image (`.qcow2`/`.vhdx`) pada Quickemu/WSL2 terus membesar dan tidak pernah menyusut otomatis saat file dihapus di dalam VM. | **Hypervisor-Aware Auto-TRIM:** Secara terjadwal dan otomatis memicu *VirtIO discard/TRIM* langsung ke SSD host fisik. |
| **Curamnya Kurva Belajar Nix** | 99% pengembang menyerah mempelajari NixOS karena sintaksis ekspresi Nix yang kaku dan dokumentasi yang terfragmentasi. | **Decoupled Natural Language Copilot:** AI menerjemahkan maksud pengguna menjadi graf deklaratif Nix secara otomatis dan aman. |

---

## 3. User Personas & Target Audience

### Persona 1: Rian — The AI & Web3 Polyglot Developer (Mac / Windows User)
- **Karakter:** Mengembangkan microservices dengan Python, Rust, dan Go. 
- **Frustrasi:** Laptopnya lambat setiap kali membuka Docker Desktop, dan ia sering menghabiskan waktu 2 jam memperbaiki *environment variable* atau konflik versi Python.
- **Kebutuhan:** Ruang kerja isolasi sekali pakai (`neuronix run`) yang menyala dalam hitungan milidetik dan lenyap tanpa jejak sampah di laptopnya.

### Persona 2: Sarah — Senior Site Reliability Engineer (Enterprise DevOps)
- **Karakter:** Mengelola armada ribuan server di Kubernetes cloud.
- **Frustrasi:** Dockerfile yang dibuat tim developer menghasilkan image berukuran 1 GB dengan puluhan celah keamanan (*CVE vulnerabilities*).
- **Kebutuhan:** Generator image minimalis (`neuronix export`) yang menghasilkan container OCI berukuran 20 MB murni dari dependensi esensial tanpa celah keamanan.

### Persona 3: David — The Enthusiastic Linux Learner (Power User / Novice)
- **Karakter:** Tertarik dengan stabilitas NixOS tetapi takut komputernya rusak atau kehabisan disk.
- **Frustrasi:** Bingung dengan file `.nix`, takut salah konfigurasi desktop.
- **Kebutuhan:** Sistem operasi mandiri dengan tombol *undo* instan dan penjaga storage otonom yang bisa diajak berdiskusi via bahasa manusia.

---

## 4. User Stories & Acceptance Criteria

### User Story 1: Menjalankan Software Sekali Pakai (*Disposable App*)
> *Sebagai seorang pengembang, saya ingin menjalankan software dari GitHub atau package manager tanpa menginstalnya secara permanen di OS saya, agar disk dan sistem saya tetap bersih.*
- **Kriteria Penerimaan (Acceptance Criteria):**
  - Perintah `neuronix run <pkg>` menyiapkan lingkungan terisolasi dalam $< 3$ detik.
  - Software dapat mengakses GPU, display Wayland/X11, dan audio tanpa konfigurasi manual.
  - Begitu terminal ditutup, 0 byte sampah tersisa di sistem global.

### User Story 2: Pemeliharaan Kapasitas Disk Virtual Host
> *Sebagai pengguna virtualisasi lokal (Quickemu / WSL2), saya ingin kapasitas file virtual disk di Host Physical Storage komputer saya menyusut saat file di dalam sistem dihapus.*
- **Kriteria Penerimaan:**
  - Perintah `neuronix diet` menggabungkan file duplikat menjadi hardlink dan menembakkan *VirtIO TRIM*.
  - Kapasitas fisik file `.qcow2` di host berkurang sebanding dengan ukuran data yang dihapus.

### User Story 3: Rollback Darurat Saat Terjadi Masalah
> *Sebagai pengguna, saya ingin dapat membatalkan perubahan konfigurasi sistem seketika jika software baru merusak alur kerja saya.*
- **Kriteria Penerimaan:**
  - Perintah `neuronix undo` memutar balik sistem ke generasi stabil sebelumnya dalam $< 3$ detik tanpa reboot.

### User Story 4: Ekspor OCI Container Image Minimalis
> *Sebagai insinyur DevOps, saya ingin mengekspor aplikasi saya menjadi image Docker yang siap dikirim ke Kubernetes tanpa perlu menginstal Docker daemon di laptop.*
- **Kriteria Penerimaan:**
  - Perintah `neuronix export <app>` menghasilkan tarball OCI/Docker standar.
  - Ukuran file image $\ge 70\%$ lebih kecil dibanding image berbasis Ubuntu/Debian.
  - Scanner keamanan (Trivy/Grype) melaporkan 0 CVE kritikal.

---

## 5. Functional Requirements (FR)

- **`FR-001` (Core CLI Engine):** Sistem wajib menyediakan biner CLI mandiri (`neuronix`) yang dapat berjalan di Linux POSIX tanpa dependensi daemon root.
- **`FR-002` (Ephemeral Runner):** Sistem wajib mampu meluncurkan subshell terisolasi dengan software sementara melalui integrasi graf dependensi Nix.
- **`FR-003` (Automated Storage Pruning):** Sistem wajib memiliki modul internal untuk menjadwalkan *garbage collection*, *hardlink deduplication*, dan *filesystem TRIM*.
- **`FR-004` (State Rollback):** Sistem wajib memelihara riwayat generasi deklaratif dan menyediakan fungsi pemulihan instan ke generasi sebelumnya.
- **`FR-005` (Non-FHS Binary Compatibility):** Sistem wajib secara transparan menyematkan loader dinamis (`nix-ld`) agar biner pihak ketiga non-Nix dapat dieksekusi tanpa modifikasi manual.
- **`FR-006` (Decoupled Cognitive Driver):** Fitur kecerdasan buatan wajib bersifat modular (*opt-in* via Model Context Protocol JSON-RPC 2.0 over `stdio`) dengan gerbang pembuktian formal (*Formal Proof Gatekeeper*).
- **`FR-007` (Standalone OS Distribution & Calamares Installer):** Sistem wajib menyediakan format bootable Live ISO mandiri yang dilengkapi installer grafis Calamares, partisi cerdas Btrfs ZSTD:3, serta katalog desktop Wayland terkurasi (KDE Plasma 6, GNOME Tokyo Cyber, Hyprland).
- **`FR-008` (First-Boot Onboarding & Hardware Telemetry):** Sistem wajib menyediakan aplikasi penyambutan visual (*NEURONIX Center*) untuk memeriksa kesehatan storage, deteksi GPU otomatis (NVIDIA CUDA/AMD Mesa), dan aktivasi profil modular satu klik.

---

## 6. Non-Functional Requirements (NFR)

- **`NFR-001` (Performance & Latency):**
  - Eksekusi CLI dasar (`status`, `undo`, `diet`) harus merespons dalam $< 500$ milidetik.
  - Startup lingkungan *ephemeral* yang sudah ter-cache harus selesai dalam $< 2$ detik.
- **`NFR-002` (Zero Cloud Lock-in):**
  - 100% fungsi manajemen sistem, isolasi, dan storage wajib berjalan normal dalam kondisi *air-gapped* (tanpa koneksi internet).
- **`NFR-003` (Storage Determinism):**
  - File kembar pada sistem wajib disatukan di tingkat *filesystem inode* sehingga redundansi storage berkurang minimal 20%.
- **`NFR-004` (Safety & Fault Tolerance):**
  - Tidak ada tindakan mutasi sistem yang boleh merusak *read-only store* (`/nix/store`).
- **`NFR-005` (Cross-Platform Extensibility):**
  - Arsitektur wajib siap dikompilasi untuk target Linux x86_64, aarch64, macOS (Darwin), dan Windows (WSL2).
