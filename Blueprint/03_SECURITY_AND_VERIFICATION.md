# NEURONIX Specification: Security Architecture & Verification Protocol

> **Document ID:** `NRX-SEC-003`  
> **Status:** APPROVED  
> **Path:** `Blueprint/03_SECURITY_AND_VERIFICATION.md`  

---

## 1. Threat Model & Security Posture (Zero-Trust)

Arsitektur **NEURONIX** mengadopsi prinsip **Zero-Trust**: Agen AI diperlakukan sebagai entitas *untrusted* (tidak dipercaya secara buta) yang berpotensi menghasilkan kode salah, halusinasi, atau instruksi destruktif.

### 1.1 Analisis Ancaman (STRIDE Matrix)

| Ancaman (Threat) | Risiko pada Distro Biasa | Mitigasi Bertingkat di NEURONIX |
| :--- | :--- | :--- |
| **Spoofing (Pemalsuan Identitas)** | Proses liar memalsukan hak akses root. | Seluruh eksekusi sub-proses dibatasi di dalam *unprivileged user namespaces* (`bwrap`). |
| **Tampering (Manipulasi Sistem)** | AI salah menghapus `/lib` atau `/bin`. | Direktori `/nix/store` di-mount **Read-Only** di tingkat kernel; root pun tidak bisa memutasi file. |
| **Repudiation (Ketiadaan Riwayat)** | Admin tidak tahu perintah apa yang merusak server. | Setiap perubahan dicatat dalam **Generations atomik** yang terhubung dengan hash kriptografis Git. |
| **Information Disclosure (Kebocoran Rahasia)** | API key tersimpan dalam plaintext di skrip bash. | Menggunakan modul **`sops-nix` / `agenix`** dengan enkripsi kunci simetris `Age` di dalam Git. |
| **Denial of Service (DoS / Disk Full)** | Instalasi software liar membuat harddisk 100% penuh hingga sistem mati. | Sensor `min-free` (1 GiB) memicu pembersihan darurat otomatis sebelum disk penuh. |
| **Elevation of Privilege (Eskalasi Liar)** | Script luar mengambil alih hak akses root host. | Batasan isolasi hypervisor KVM (Guest OS tidak dapat menyentuh host OS di Arch/Windows). |

---

## 2. Pipa Verifikasi Multi-Tahap (The 5-Stage Verification Pipeline)

Setiap perubahan konfigurasi sistem yang diusulkan oleh Agen AI **wajib melewati 5 gerbang verifikasi ketat** sebelum diizinkan menyentuh sistem operasional:

```text
  [ Intensi AI ]
        │
        ▼
  ┌───────────┐    Gagal
  │ Stage 1   │ ───────────► [ Auto-Reject & Inform AI to Fix Syntax ]
  │ AST Check │
  └─────┬─────┘
        │ Lolos
        ▼
  ┌───────────┐    Gagal
  │ Stage 2   │ ───────────► [ Abort: Zero Blast Radius to Live OS ]
  │ Dry-Build │
  └─────┬─────┘
        │ Lolos
        ▼
  ┌───────────┐    Gagal
  │ Stage 3   │ ───────────► [ Destroy Shadow VM & Log Diagnostics ]
  │ Shadow VM │
  └─────┬─────┘
        │ Lolos
        ▼
  ┌───────────┐
  │ Stage 4   │ ───────────► [ Atomic Switch: 1-Step Symlink Flip ]
  │ Promotion │
  └─────┬─────┘
        │
        ▼
  ┌───────────┐    Gagal
  │ Stage 5   │ ───────────► [ Trigger Instant Rollback: 2 Seconds ]
  │ Telemetry │
  └───────────┘
```

### Penjelasan Detail Tiap Tahap:

#### Stage 1: Static AST Analysis & Syntax Validation
- Kode konfigurasi Nix yang dihasilkan AI di-parsing menjadi *Abstract Syntax Tree* (AST).
- Memastikan tidak ada kurung kurawal yang hilang, kesalahan pengetikan nama variabel, atau sintaksis terlarang.

#### Stage 2: Pure Nix Derivation Evaluation (`dry-build`)
- Sistem memanggil `nixos-rebuild dry-build` tanpa hak istimewa root.
- Compiler fungsional Nix mengevaluasi seluruh graf dependensi.
- Jika AI memanggil paket yang tidak ada atau salah menetapkan tipe data (misal: memberikan string pada opsi boolean), evaluasi **gagal seketika**. Sistem yang sedang berjalan 100% aman dan tidak tersentuh.

#### Stage 3: Shadow Micro-VM Simulation (Canary Testing di RAM)
- Untuk perubahan sistem yang kompleks (seperti driver kartu grafis, display server, atau aturan firewall):
  Sistem mengeksekusi `nixos-rebuild build-vm` untuk menghasilkan *script QEMU micro-VM* sementara di dalam direktori memori (`/dev/shm` atau `tmpfs`).
- Micro-VM bayangan di-boot di latar belakang selama 5 detik.
- Skrip diagnostik memeriksa: *Apakah service systemd aktif? Apakah port jaringan merespons? Apakah layar GUI menyala?*
- Jika ada service yang crash di dalam VM bayangan, promosi dibatalkan seketika.

#### Stage 4: Atomic Symlink Promotion
- Jika Stage 1 s/d 3 lulus 100%, sistem utama diperbarui dengan satu operasi atomik: membalik symlink `/run/current-system` ke generasi baru.
- Tidak ada masa transisi di mana sistem berada dalam kondisi "setengah terinstal".

#### Stage 5: Telemetry Regression & Instant Rollback Guard
- Sistem memonitor kesehatan sistem selama 60 detik pasca-promosi (*canary window*).
- Jika terdeteksi *kernel panic*, kegagalan autentikasi, atau crash jaringan, sistem memicu:
  ```bash
  nixos-rebuild switch --rollback
  ```
- Sistem seketika kembali ke generasi stabil sebelumnya dalam waktu $< 2$ detik.

---

## 3. Sandboxing & Principle of Least Privilege

### 3.1 Unprivileged User Namespaces
Perintah `neuronix run` mengeksekusi aplikasi menggunakan isolasi Linux Namespaces:
- **Mount Namespace:** File sistem luar dipasang *read-only*, hanya folder kerja `$PWD` yang bersifat *read-write*.
- **PID Namespace:** Aplikasi tidak dapat melihat proses lain yang sedang berjalan di komputer host.
- **Network Namespace (Opsional via flag `--offline`):** Menutup akses soket internet sama sekali untuk software yang mencurigakan.

### 3.2 Sudo Escalation Governance
Di dalam lingkungan virtualisasi terisolasi (Quickemu / KVM):
- Hak akses `security.sudo.wheelNeedsPassword = false;` diaktifkan **khusus untuk user di dalam VM** guna memungkinkan otomasi otonom tanpa henti.
- **Keamanan Host Terjamin:** Karena berjalan di atas KVM, hak akses root di dalam VM **tidak memiliki kemampuan mengekskalasi diri menjadi root di komputer host (Arch Linux atau Windows)**.

---

## 4. Secret Management as Code (`sops-nix`)

Untuk portofolio enterprise, kunci rahasia (*API keys*, token GitHub, kredensial cloud) **dilarang keras disimpan dalam teks polos**:
1. Setiap rahasia dienkripsi menggunakan perkakas **`age`** (*modern encryption tool*).
2. File rahasia berekstensi `.yaml` yang terenkripsi aman disimpan langsung di dalam Git repositori publik.
3. Dekripsi hanya terjadi di memori RAM pada saat boot sistem menggunakan kunci privat yang berada di `/etc/ssh/ssh_host_ed25519_key`.
