# Spesifikasi Teknis: Onboarding Distro, Doctor Diagnostik, Katalog Quickstart & Manajemen Kernel Deklaratif (08_ONBOARDING_AND_DISTRO_EXPERIENCE)

> **Status:** Ratified & Active  
> **Target Release:** NEURONIX OS v1.0.3+  
> **Komponen:** `neuronix-welcome`, `neuronix doctor`, `neuronix quickstart`, `neuronix kernel`, `artwork/`, `modules/hardware/boot.nix`, `packages/neuronix-center/`  
> **Verifikasi:** Suite 23 Test Contracts (854 Total Assertions / 100% Pass)

---

## 1. Latar Belakang & Filosofi Rekayasa

EndeavourOS dikenal luas di ekosistem Linux karena memiliki daya tarik komunitas yang kuat: antarmuka sambutan (`eos-welcome`), alat pengumpul log dan diagnostik (`eos-log-tool`), penginstal aplikasi cepat (`eos-quickstart`), dan alat pengelola kernel (`akm`). Namun, di balik kemudahannya, sistem Arch-based tradisional memiliki kelemahan fundamental:
1. **Imperative Fragility:** Penambahan aplikasi, kernel, dan diagnostik di EndeavourOS mengandalkan perintah imperatif (`pacman`, `yay`) yang langsung mengubah sistem berjalan tanpa proteksi rollback atomik.
2. **Privacy Exposure:** Pengumpulan log pada distro konvensional sering kali mengekspos alamat IP, MAC address, username lokal, serta identifier sensitif hardware.
3. **Storage/State Corruption Risk:** Pergantian kernel secara manual rentan menyebabkan boot failure bila initramfs gagal dibangun.

**NEURONIX OS mengadopsi seluruh kemudahan UX tersebut sekaligus melampauinya secara radikal** dengan menerapkan fondasi **Pure-Functional NixOS Substrate**, **Declarative State**, **Zero Disruption Rollback**, dan **Privacy-Preserving Sanitization**.

---

## 2. Arsitektur Subkomponen

```
+---------------------------------------------------------------------------------------+
|                                    NEURONIX OS                                        |
|                          LAYER 4: USER EXPERIENCE & POLISH                            |
+---------------------------------------------------------------------------------------+
        |                             |                            |
        v                             v                            v
 [First-Boot Welcome]        [System Doctor & Audit]      [Quickstart App Hub]
  - neuronix-welcome.desktop  - Automated Data Sanitizer   - Curated Flatpak Apps
  - GUI & CLI Hybrid Wizard   - [REDACTED-IP/MAC] Masking  - Zero Nix Store Mutation
  - Auto-launch Controller    - GitHub Issue Ready Output  - Flathub Direct Pipeline
        |                             |                            |
        +-----------------------------+----------------------------+
                                      |
                                      v
                        [Declarative Kernel Manager]
                         - neuronix.hardware.kernelFlavor
                         - [default, zen, lts, latest, hardened]
                         - Staged Rollback Defense
```

---

## 3. Komponen 1: Onboarding Sambutan Interaktif (`neuronix welcome`)

### 3.1. Spesifikasi Perilaku
- **Desktop Auto-launch:** Disediakan melalui file XDG autostart `/etc/xdg/autostart/neuronix-welcome.desktop` yang aktif pada boot pertama pengguna baru.
- **Dukungan Dua Mode (Hybrid CLI + GUI):**
  - Bila berada di sesi grafis (Wayland/X11), memanggil antarmuka grafis `neuronix-center --welcome`.
  - Bila berada di terminal, SSH, atau headless server (atau via flag `--cli`), menyajikan panduan interaktif terminal berbasis ANSI visual.
- **Autostart Toggle:** Mendukung opsi `--disable-autostart` dan `--enable-autostart` untuk kenyamanan pengguna tanpa merusak konfigurasi sistem deklaratif.

---

## 4. Komponen 2: Diagnosa Sistem & Sanitasi Data Privasi (`neuronix doctor`)

### 4.1. Spesifikasi Pemeriksaan & Audit
Memeriksa integritas sistem secara komprehensif tanpa memerlukan izin root:
1. **Metadata Substrate:** Nama distribusi, versi kernel, arsitektur, uptime, nomor generasi aktif, dan total generasi tersimpan.
2. **Telemetri Hardware:** Model prosesor (CPU), core count, alokasi memori RAM, Swap, adaptor grafis (GPU).
3. **Kesehatan Storage:** Penggunaan root `/` dan `/nix/store`, status timer background (`neuronix-auto-diet.timer`, `neuronix-security-audit.timer`, `neuronix-auto-update.timer`).
4. **Kernel Dmesg Rings:** 15 baris error log terbaru dari buffer kernel untuk mendeteksi hardware failure dini.

### 4.2. Invarian Sanitasi Privasi (Privacy-Preserving Pipeline)
Sebelum laporan ditulis atau dicetak:
- Real local username direduksi menjadi `<sanitized-user>`.
- Real hostname direduksi menjadi `<sanitized-host>`.
- Alamat IPv4 / IPv6 diganti dengan token `[REDACTED-IP]`.
- Alamat MAC hardware diganti dengan token `[REDACTED-MAC]`.

Output disimpan secara default ke `/tmp/neuronix-doctor.md` dalam format Markdown yang siap ditempel ke GitHub Issues (`https://github.com/adamriofc/neuronix/issues/new`). Mendukung juga flag `--json` untuk integrasi Model Context Protocol (MCP) server.

---

## 5. Komponen 3: Katalog Aplikasi Cepat Terkurasi (`neuronix quickstart`)

### 5.1. Prinsip Deklaratif & Isolasi Flathub
Berbeda dengan `eos-quickstart` yang mengunduh paket binary native ke sistem root, `neuronix quickstart` memanfaatkan runtime **Flatpak via Flathub** yang telah diaktifkan secara bawaan di `modules/services/flatpak.nix`. Hal ini menjamin:
- `/nix/store` tetap **100% immutable** dan aman dari mutasi file sistem tak terkontrol.
- Seluruh aplikasi desktop berjalan dalam sandbox container terisolasi.

### 5.2. Katalog Terkurasi Bawaan
- **Web Browsers:** Brave (`com.brave.Browser`), Chrome (`com.google.Chrome`), Firefox (`org.mozilla.firefox`).
- **Development Tools:** VS Code (`com.visualstudio.code`), VSCodium (`com.vscodium.codium`), Postman (`com.getpostman.Postman`), DBeaver (`io.dbeaver.DBeaverCommunity`).
- **Communication:** Discord (`com.discordapp.Discord`), Telegram (`org.telegram.desktop`), Slack (`com.slack.Slack`).
- **Multimedia:** VLC (`org.videolan.VLC`), OBS Studio (`com.obsproject.Studio`), Spotify (`com.spotify.Client`), GIMP (`org.gimp.GIMP`).
- **Productivity:** LibreOffice (`org.libreoffice.LibreOffice`), Obsidian (`md.obsidian.Obsidian`).

Perintah CLI:
```bash
neuronix quickstart list
neuronix quickstart install brave
neuronix quickstart search <keyword>
```

---

## 6. Komponen 4: Pengelola Varian Kernel Deklaratif (`neuronix kernel`)

### 6.1. Opsi Modul NixOS
Dideklarasikan pada `modules/hardware/boot.nix`:
```nix
neuronix.hardware.kernelFlavor = lib.mkOption {
  type = lib.types.enum [ "default" "zen" "lts" "latest" "hardened" ];
  default = "default";
  description = "Linux kernel package flavor selection for NEURONIX OS.";
};
```

### 6.2. Karakteristik Varian Kernel
| Flavor | Nix Package Binding | Karakteristik Utama | Rekomendasi Penggunaan |
| :--- | :--- | :--- | :--- |
| `default` | `pkgs.linuxPackages` | Stabil, teruji upstream NixOS | Server, pemakaian umum |
| `zen` | `pkgs.linuxPackages_zen` | Low latency scheduler, responsiveness | Gaming, audio workstation, desktop harian |
| `lts` | `pkgs.linuxPackages_lts` | Long Term Support, stabilitas tinggi | Mission-critical workstations, enterprise |
| `latest` | `pkgs.linuxPackages_latest` | Bleeding-edge upstream kernel | Hardware generasi paling mutakhir |
| `hardened` | `pkgs.linuxPackages_hardened` | Keamanan memori ketat, mitigasi eksploit | Workstation dengan kebutuhan sekuriti tinggi |

Penerapan pergantian kernel dilakukan secara **Staged Upgrade** via `neuronix upgrade --staged`, sehingga kernel baru diuji pada generasi berikutnya tanpa merusak sesi boot saat ini dan dapat di-rollback seketika (`neuronix undo`) bila terjadi kegagalan hardware.

---

## 7. Komponen 5: Identitas Visual & 4K Artwork System

1. **Wallpaper Bawaan (4K UHD):**
   - Berkas: `artwork/wallpapers/neuronix-cyber-neural-dark.svg`
   - Resolusi: 3840x2160 (vektor SVG lossless murni, cyber-neural theme dengan gradient deep cyan, neural nodes, dan circuit traces).
   - Di-link secara deklaratif ke `/etc/neuronix/artwork/neuronix-cyber-neural-dark.svg`.
2. **Distro Branding Emblem:**
   - Berkas: `artwork/branding/neuronix-badge.svg` (512x512 vector badge).

---

## 8. Verifikasi & Pengujian Mutu (Quality Gates)

Implementasi fitur ini divalidasi melalui **Suite 23** pada test harness NEURONIX, yang mencakup 30 assertions spesifik:
- Integritas parsing sintaksis `boot.nix` dan `desktop-tweaks.nix`.
- Validitas schema SVG 4K wallpaper dan desktop autostart entry.
- Sanitasi data output `neuronix doctor` (username, hostname, IP).
- Eksekusi non-blocking dan error handling CLI `neuronix welcome`, `quickstart`, dan `kernel`.
- Integrasi schema tool `neuronix_doctor` dan `neuronix_quickstart_list` pada server MCP JSON-RPC 2.0.

Total pengujian seluruh ekosistem NEURONIX kini mencapai **851 assertions** dengan tingkat kelulusan **100%**.
