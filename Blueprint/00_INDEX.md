# NEURONIX Master Blueprint: Master Index & Executive Overview

> **Version:** 1.0.0-RELEASE  
> **Status:** RATIFIED & LOCKED  
> **Standard:** Enterprise Systems Architecture & Open-Source Production Grade  
> **Target Path:** `Blueprint`  
> **Classification:** Technical Specification & Project Master Plan  

---

## 1. Executive Summary

**NEURONIX** adalah platform sistem operasi mandiri (*Standalone Operating System Substrate*) dan perkakas sistem berbasis agen (*Agentic System Harness*) generasi baru yang mengawinkan **keandalan matematis deterministik NixOS** dengan **antarmuka kognitif kecerdasan buatan modular yang dapat diatur (Decoupled AI Driver)**.

Proyek ini dirancang untuk memecahkan tiga kegagalan laten komputasi modern:
1. **Developer Environment Decay:** Beban berlebih (*bloat*), kebocoran memori, dan fragmentasi dependensi yang disebabkan oleh Docker Desktop dan pengelola paket imperatif.
2. **AI Hallucination Blast-Radius:** Risiko kerusakan sistem ketika agen AI otonom diberikan hak akses sistem operasi tradisional yang bersifat *mutable*.
3. **Hypervisor Storage Bleed:** Pertumbuhan tidak terkontrol dari virtual disk image (`.qcow2` / `.vhdx`) pada sistem virtualisasi lokal (Quickemu/QEMU/WSL2) yang menguras kapasitas SSD fisik host (Host Physical Storage).

---

## 2. Struktur Dokumentasi Modular

Seluruh dokumen di dalam direktori ini disusun secara ortogonal, modular, dan mengikuti standar *RFC / Industrial Architecture Spec*:

```text
Blueprint/
├── 00_INDEX.md                           # Dokumen Ini (Navigasi Master & Ikhtisar Eksekutif)
├── 01_PRD_PRODUCT_REQUIREMENTS.md       # Product Requirements Document (PRD), Personas, User Stories
├── 02_SYSTEM_ARCHITECTURE.md            # Spesifikasi Teknis, Arsitektur Dua Lapis, Diagram Data
├── 03_SECURITY_AND_VERIFICATION.md      # Model Ancaman, Formal Verification, & Safe Sandbox Protocol
├── 04_IMPLEMENTATION_ROADMAP.md         # Roadmap Fase Bertahap (MVP s/d Standalone OS)
├── 05_QUALITY_GATES_AND_VALIDATION.md   # Metrik Kualitas, Testing Matrix, & Definition of Done (DoD)
└── 06_STANDALONE_DISTRIBUTION_SPECIFICATION.md # Spesifikasi Distribusi ISO, Calamares, & Wayland Suites
```

---

## 3. Peta Navigasi Dokumen

| Kode Dokumen | Nama Dokumen | Fokus Utama | Target Pembaca |
| :--- | :--- | :--- | :--- |
| **`01_PRD`** | [Product Requirements](file://Blueprint/01_PRD_PRODUCT_REQUIREMENTS.md) | Analisis kebutuhan pasar, *problem statement*, fitur kunci, KPI sukses, dan use-case non-NixOS. | Product Manager, Lead Architect, Users |
| **`02_ARCH`** | [System Architecture](file://Blueprint/02_SYSTEM_ARCHITECTURE.md) | Dua lapis (Core Engine vs AI Driver), subsistem storage, auto-TRIM, *content-addressed store*, dan FHS shim. | Systems Engineer, Core Developers |
| **`03_SEC`** | [Security & Verification](file://Blueprint/03_SECURITY_AND_VERIFICATION.md) | Eliminasi halusinasi AI via *pure functional compiler*, *shadow micro-VM canary*, dan isolasi namespaces. | Security Auditor, DevSecOps Leads |
| **`04_ROAD`** | [Implementation Roadmap](file://Blueprint/04_IMPLEMENTATION_ROADMAP.md) | Rencana fase implementasi berdisiplin tinggi dari v0.1 CLI Core hingga ISO standalone Calamares. | Engineering Manager, Contributors |
| **`05_QUAL`** | [Quality Gates & Validation](file://Blueprint/05_QUALITY_GATES_AND_VALIDATION.md) | Matriks pengujian deterministik, protokol *zero-bug*, *smoke tests*, kriteria rilis (*Release Gates*). | QA Engineers, System Integrators |
| **`06_DISTRO`**| [Standalone Distro Spec](file://Blueprint/06_STANDALONE_DISTRIBUTION_SPECIFICATION.md) | Spesifikasi ISO bootable, Calamares, Btrfs ZSTD:3, Wayland suites (KDE 6/GNOME/Hyprland), dan NEURONIX Center. | Distro Maintainers, UI/UX, Core Team |

---

## 4. Prinsip Arsitektur Utama (The Prime Directives)

Setiap baris kode yang ditulis di bawah payung proyek NEURONIX wajib mematuhi 4 pilar hukum berikut:

1. **Determinisme Mutlak di Level Inti (*Reliability-First*):**  
   Mesin inti (*Core Engine*) wajib beroperasi 100% deterministik, offline, tanpa dependensi jaringan atau API key AI. Jika AI mati atau offline, sistem inti tetap bekerja secepat kilat.
2. **Pencegahan Halusinasi di Tingkat Kompilasi (*Zero-Blast Radius*):**  
   Tidak ada kode konfigurasi AI yang boleh menyentuh sistem produksi sebelum lolos validasi pohon dependensi (*dry-build*) dan pengujian simulasi bayangan (*Shadow Micro-VM*).
3. **Sadar Lingkungan Perangkat Keras (*Hypervisor-Aware Storage*):**  
   Sistem harus aktif menghemat disk, menyatukan file kembar via *hardlink*, dan men-TRIM blok kosong kembali ke SSD fisik komputer host.
4. **Kemandirian Bebas Vendor (*Sovereignty & Open Source*):**  
   Bebas dari jebakan vendor cloud tertutup. 100% transparan, berlisensi open-source permissif, dan dapat direproduksi oleh siapa saja di dunia.
