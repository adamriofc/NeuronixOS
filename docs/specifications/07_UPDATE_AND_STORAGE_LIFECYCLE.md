# NEURONIX Specification: Autonomous Update Policy & Storage Diet Lifecycle

**Status:** Accepted & Implemented  
**Domain:** System Maintenance, Desktop Notifications, Atomic Upgrades & Storage Retention  
**Canonical Reference:** `modules/services/update.nix` & `modules/services/storage.nix`  

---

## 1. Executive Context & Architectural Philosophy

Pada sistem operasi tradisional (Debian, Ubuntu, Arch Linux), pembaruan sistem beroperasi secara imperatif dengan menimpa berkas (*destructive in-place overwrite*), yang sering kali menyebabkan:
- Ketidakstabilan sistem jika pustaka bersama (*shared libraries*) diperbarui di tengah sesi aplikasi berjalan.
- Ketiadaan mekanisme *rollback* instan jika paket terbaru memiliki regresi atau *bug*.
- Pembaruan otomatis tak terkendali (*unattended silent updates*) yang menghabiskan kuota atau merusak modul driver grafis.

Sebaliknya, pada ekosistem murni NixOS, setiap modifikasi konfigurasi atau pembaruan menghasilkan **Generasi Baru** yang disimpan secara atomik di `/nix/store/`. Kelemahan yang sering timbul adalah **penumpukan ruang penyimpanan (*disk bloating*)** jika generasi lama tidak dikelola.

**NEURONIX OS menyelesaikan kedua permasalahan ini secara harmonis melalui arsitektur terpadu:**
1. **Kebijakan Pembaruan Terkawal (*Gated Update Policy*):** Menggabungkan pemantauan metadata upstream di latar belakang, notifikasi desktop yang elegan, dan eksekusi pembaruan bertahap (*Staged Upgrade* via `nixos-rebuild boot`) tanpa mengganggu sesi pengguna.
2. **Mesin Diet Penyimpanan 4 Lapis (*4-Tier Storage Diet Engine*):** Pembersihan generasi usang secara otomatis (> 14 hari), deduplikasi berkas via *hardlink inode*, perlindungan darurat *Dynamic Storage Guard*, dan penembakan instruksi SSD TRIM ke perangkat fisik atau host hypervisor.

---

## 2. Model Pembaruan Sistem (System Update Architecture)

### 2.1 Pilihan Mode Operasional

NEURONIX mendukung tiga moda pembaruan sistem deklaratif:

| Moda Pembaruan | Perilaku Operasional | Kasus Penggunaan Ideal |
| :--- | :--- | :--- |
| **1. Staged Upgrade (Default)** | Mengunduh dan membangun generasi baru di `/nix/store` di latar belakang, menautkannya ke bootloader, dan mengaktifkannya saat reboot berikutnya (`nixos-rebuild boot`). Nol gangguan pada sesi aktif. | Workstation harian, laptop pengembang, lingkungan produksi. |
| **2. Instant Switch** | Membangun generasi baru dan langsung mengalihkan symlink sistem aktif seketika (`nixos-rebuild switch`). | Administrasi langsung, pengujian konfigurasi cepat. |
| **3. Unattended Auto-Upgrade** | Daemon systemd mengorkestrasi pembaruan terjadwal secara mandiri tanpa dialog konfirmasi. | Server tanpa monitor (*headless server*), automated build nodes. |

### 2.2 Arsitektur Desktop Update Notifier
Layanan `systemd.services.neuronix-update-check` dan timer `neuronix-update-check.timer` beroperasi secara ringan:
1. Memeriksa konektivitas jaringan.
2. Membaca commit remote dari repositori upstream (`https://github.com/adamriofc/neuronix.git`) tanpa mengunduh seluruh closure paket (< 50 KB metadata).
3. Jika commit baru terdeteksi, memancarkan notifikasi desktop melalui `notify-send` ke seluruh sesi grafis pengguna aktif (KDE Plasma, GNOME, Hyprland).

### 2.3 Konfigurasi Deklaratif NixOS
Dideklarasikan pada `modules/services/update.nix`:

```nix
neuronix.services.updates = {
  enable = true;             # Mengaktifkan subsistem update
  enableNotifier = true;     # Menyalakan notifikasi desktop (Default: true)
  checkInterval = "daily";   # Frekuensi pengecekan upstream
  autoUpgrade = false;       # Full otomatis tanpa konfirmasi (Default: false)
  staged = true;             # Menggunakan nixos-rebuild boot (Default: true)
  allowReboot = false;       # Reboot otomatis pasca auto-upgrade
  channel = "github:adamriofc/neuronix";
};
```

---

## 3. Mesin Diet Penyimpanan (Storage Diet Lifecycle)

Untuk mencegah akumulasi generasi lama yang membengkak di `/nix/store`, NEURONIX menerapkan perlindungan 4 lapis:

```
┌─────────────────────────────────────────────────────────────┐
│       Lapis 1: Scheduled Garbage Collection (nix.gc)        │
│       Memutuskan symlink generasi yang berusia > 14 hari    │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│  Lapis 2: Inode Hardlink Deduplication (nix.optimise)        │
│  Menyatukan berkas kembar ke satu physical inode (hemat 30%)│
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│  Lapis 3: Dynamic Storage Guard (min-free / max-free)        │
│  Memicu GC darurat jika disk < 1 GiB hingga pulih ke 3 GiB   │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│        Lapis 4: Host Auto-TRIM Passthrough (fstrim)          │
│        Menembakkan sinyal TRIM fisik ke SSD / VirtIO Host    │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 Konfigurasi Deklaratif Storage
Dideklarasikan pada `modules/services/storage.nix`:

```nix
# Autonomous Storage Diet Policy
nix.gc = {
  automatic = lib.mkDefault true;
  dates = lib.mkDefault "weekly";
  options = lib.mkDefault "--delete-older-than 14d";
};

nix.optimise = {
  automatic = lib.mkDefault true;
  dates = [ "weekly" ];
};

nix.settings = {
  min-free = lib.mkDefault 1073741824; # 1 GiB Emergency Floor
  max-free = lib.mkDefault 3221225472; # 3 GiB Headroom Ceiling
};

services.fstrim = {
  enable = lib.mkDefault true;
  interval = "daily";
};
```

### 3.2 Kedaulatan Pengguna (Beralih ke Mode Manual)
Seluruh opsi dideklarasikan dengan `lib.mkDefault true`. Pengguna yang ingin mematikan otomatisasi ini cukup menambahkan baris berikut di `/etc/nixos/configuration.nix`:

```nix
# Beralih ke kontrol manual 100%
nix.gc.automatic = false;
nix.optimise.automatic = false;
services.fstrim.enable = false;
```

---

## 4. Antarmuka Operasional (CLI, GUI, & MCP)

### 4.1 Baris Perintah CLI (`neuronix`)
- **Pemeriksaan Pembaruan:**
  ```bash
  neuronix check-update
  ```
- **Penerapan Pembaruan Bertahap (*Staged Rebuild - Rekomendasi*):**
  ```bash
  neuronix upgrade --staged
  ```
- **Penerapan Pembaruan Langsung (*Instant Switch*):**
  ```bash
  neuronix upgrade --switch
  ```
- **Pembersihan Storage Terpadu (*Storage Diet*):**
  ```bash
  neuronix diet
  ```
- **Pemantauan Telemetri:**
  ```bash
  neuronix status
  ```

### 4.2 Pusat Kontrol Grafis (*NEURONIX Center*)
- Tombol **`🔄 System Upgrade (Staged)`**: Menjalankan pembaruan bertahap dengan konfirmasi dialog aman.
- Tombol **`🧹 Reclaim Storage (Diet)`**: Menjalankan siklus GC $\to$ Dedupe $\to$ TRIM dalam 1 klik.
- Tombol **`↩ Atomic Rollback`**: Mengembalikan sistem ke generasi stabil sebelumnya.

### 4.3 Integrasi AI Copilot via Model Context Protocol (MCP)
- `neuronix_check_update`: Mengueri status rilis upstream dalam format JSON terstruktur.
- `neuronix_upgrade`: Menjalankan pembaruan bertahap atau *switch* via instruksi AI.
- `neuronix_diet`: Memicu optimasi penyimpanan dan reklamasi blok SSD.
