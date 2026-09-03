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

## 5. Fleksibilitas Pengaturan Auto-TRIM: Kendali Penuh di Tangan Pengguna

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

## 6. Toko Aplikasi Grafis (GUI Software Marketplace: Flatpak & Flathub Bawaan)

Salah satu kelemahan terbesar yang membuat pengguna frustrasi saat pertama kali menginstal NixOS adalah **ketiadaan App Store visual**. Pengguna biasa terpaksa membuka browser dan mencari nama paket di `search.nixos.org`, lalu menulis baris deklaratif hanya untuk menginstal aplikasi desktop sehari-hari seperti Spotify atau Discord.

**NEURONIX Fase 4 memecahkan masalah ini dengan Arsitektur Perangkat Lunak Dua Lapis (*Dual-Layer Software Architecture*):**

1. **Lapis 1 (Core OS & Developer Stack):** Dikelola secara murni oleh **Nixpkgs / Flakes / CLI**. Menjamin kernel, compiler, Python, Node, dan Docker kebal rusak dan memiliki riwayat rollback instan.
2. **Lapis 2 (Desktop Graphical Applications):** Dikelola oleh **Flatpak & Flathub Marketplace**. Pengguna dapat menginstal Spotify, Discord, Telegram, Steam, Obsidian, Blender, dan browser pihak ketiga secara visual dengan satu klik.

### Integrasi Visual Out-of-the-Box:
- **GNOME Edition:** Mengintegrasikan **GNOME Software** dengan plugin Flatpak dan repositori Flathub aktif otomatis.
- **KDE Plasma Edition:** Mengintegrasikan **KDE Discover** dengan backend Flatpak dan repositori Flathub aktif otomatis.
- **Sinkronisasi Tema & Kursor Sempurna:** Memasang `xdg-desktop-portal` dan `xdg-desktop-portal-gtk/kde` sehingga aplikasi Flatpak otomatis mengikuti tema *Dark Slate*, palet warna *Tokyo Cyber*, dan ukuran kursor sistem tanpa ada desinkronisasi visual.

---

## 7. Kompatibilitas Biner & Ergonomi Pengembang Out-of-the-Box

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

## 8. Strategi Hardware & Instalasi Offline 100%

- **Dual-Boot Mode pada Menu ISO:**
  - `Boot NEURONIX Installer (Standard / Open-Source AMD/Intel)`
  - `Boot NEURONIX Installer (NVIDIA Proprietary - Locked LTS Kernel)`
- **Instalasi Offline Penuh (*Zero Network Dependency*):**  
  Seluruh paket dasar desktop, compiler GCC, Git, browser, dan biner `neuronix` sudah dipaketkan ke dalam image `squashfs` ISO. Instalasi dapat diselesaikan 100% tanpa sambungan internet.

---

## 9. Matriks Analisis Celah Fatal Tersembunyi & Solusi Brilian Rekayasa

Di luar kelemahan umum, terdapat **4 celah fatal tersembunyi (*latent fatal traps*)** yang kerap menghancurkan proyek distro turunan NixOS, dan berikut adalah solusi rekayasa cerdas yang dirancang dalam NEURONIX:

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
