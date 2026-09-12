#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_welcome() {
    local cli_mode=0
    local flag_disable=0
    local flag_enable=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cli)
                cli_mode=1
                shift
                ;;
            --disable-autostart)
                flag_disable=1
                shift
                ;;
            --enable-autostart)
                flag_enable=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}${PROGRAM_NAME} welcome${RESET} [OPTIONS]\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--cli${RESET}                Jalankan panduan selamat datang langsung di terminal"
                echo -e "  ${GREEN}--disable-autostart${RESET}  Nonaktifkan peluncuran otomatis panduan saat pertama login"
                echo -e "  ${GREEN}--enable-autostart${RESET}   Aktifkan kembali peluncuran otomatis saat login"
                echo -e "  ${GREEN}-h, --help${RESET}           Tampilkan bantuan ini\n"
                return 0
                ;;
            *)
                log_error "Opsi tidak dikenali: $1"
                return 1
                ;;
        esac
    done

    local marker_dir="${XDG_CONFIG_HOME:-$HOME/.config}/neuronix"
    local marker_file="${marker_dir}/no-welcome-autostart"

    if [[ "$flag_disable" -eq 1 ]]; then
        mkdir -p "$marker_dir" 2>/dev/null || true
        touch "$marker_file" 2>/dev/null || true
        log_success "Autostart NEURONIX Welcome berhasil dinonaktifkan."
        return 0
    fi

    if [[ "$flag_enable" -eq 1 ]]; then
        rm -f "$marker_file" 2>/dev/null || true
        log_success "Autostart NEURONIX Welcome berhasil diaktifkan kembali."
        return 0
    fi

    # Cek apakah GUI aktif dan neuronix-center tersedia jika bukan --cli
    if [[ "$cli_mode" -eq 0 && (-n "$DISPLAY" || -n "$WAYLAND_DISPLAY") ]]; then
        local repo_center
        repo_center="$(dirname "$(readlink -f "$0")")/../packages/neuronix-center/neuronix_center.py"
        if command -v neuronix-center &>/dev/null; then
            neuronix-center --welcome &
            return 0
        elif [[ -f "$repo_center" ]]; then
            python3 "$repo_center" --welcome 2>/dev/null &
            return 0
        fi
    fi

    # Terminal Interactive Welcome
    print_banner
    echo -e "${BOLD}${CYAN}🚀 SELAMAT DATANG DI NEURONIX OPERATING SYSTEM!${RESET}"
    echo -e "${GRAY}Distribusi Linux Deklaratif Cerdas Generasi Baru Berbasis NixOS Substrate${RESET}\n"

    echo -e "${BOLD}STATUS SISTEM SAAT INI:${RESET}"
    echo -e "  ${GREEN}•${RESET} Generasi Aktif : ${CYAN}#$(get_current_generation)${RESET} (Rollback instan via '${CYAN}neuronix undo${RESET}')"
    echo -e "  ${GREEN}•${RESET} Kernel Aktif   : ${BOLD}$(uname -r 2>/dev/null || echo "Linux")${RESET}"
    echo -e "  ${GREEN}•${RESET} Lingkungan DE  : ${BOLD}${XDG_CURRENT_DESKTOP:-Headless/Terminal}${RESET} (${XDG_SESSION_TYPE:-tty})"
    echo -e "  ${GREEN}•${RESET} Desktop Wallp  : ${GRAY}/etc/neuronix/artwork/neuronix-cyber-neural-dark.svg${RESET}\n"

    echo -e "${BOLD}PANDUAN CEPAT MEMULAI (QUICK START ACTIONS):${RESET}"
    echo -e "  ${BOLD}1. Katalog Aplikasi Cepat${RESET}    : Jalankan '${CYAN}neuronix quickstart list${RESET}'"
    echo -e "     Pasang browser, IDE, editor grafis, chat via Flathub tanpa merusak Nix store."
    echo -e "  ${BOLD}2. Pemeriksaan Sistem${RESET}        : Jalankan '${CYAN}neuronix doctor${RESET}'"
    echo -e "     Diagnosa menyeluruh & siapkan laporan tersanitasi untuk GitHub issues."
    echo -e "  ${BOLD}3. Manajemen Kernel${RESET}          : Jalankan '${CYAN}neuronix kernel list${RESET}'"
    echo -e "     Pilih varian kernel: Default, Zen (Low-latency/Gaming), LTS, atau Hardened."
    echo -e "  ${BOLD}4. Pusat Kontrol Grafis${RESET}      : Jalankan '${CYAN}neuronix center${RESET}'"
    echo -e "     Kelola profil AI, isolasi sandbox, daya tahan baterai, dan timer diet."
    echo -e "  ${BOLD}5. Pembaruan Sistem${RESET}          : Jalankan '${CYAN}neuronix upgrade${RESET}'"
    echo -e "     Staged build di latar belakang, aktif aman saat reboot.\n"

    echo -e "${BOLD}LINK & EKOSISTEM KOMUNITAS:${RESET}"
    echo -e "  ${CYAN}•${RESET} GitHub Repository : https://github.com/adamriofc/NeuronixOS"
    echo -e "  ${CYAN}•${RESET} Dokumentasi Lengkap: https://github.com/adamriofc/NeuronixOS/blob/main/README.md"
    echo -e "  ${CYAN}•${RESET} Laporkan Masalah   : https://github.com/adamriofc/NeuronixOS/issues\n"

    echo -e "${GRAY}Ketik 'neuronix help' untuk melihat seluruh kapabilitas sistem.${RESET}"
}

cmd_quickstart() {
    local action="${1:-list}"
    shift 2>/dev/null || true

    case "$action" in
        list|"")
            echo -e "${BOLD}${CYAN}📦 KATALOG APLIKASI CEPAT NEURONIX (QUICKSTART APP HUB)${RESET}"
            echo -e "${GRAY}Aplikasi terkurasi Flathub/Flatpak: Terisolasi, aman, tidak merusak immutability Nix store.${RESET}\n"

            echo -e "${BOLD}[🌐 Web Browsers]${RESET}"
            echo -e "  ${GREEN}brave${RESET}       - Brave Privacy Browser           (${GRAY}com.brave.Browser${RESET})"
            echo -e "  ${GREEN}chrome${RESET}      - Google Chrome                   (${GRAY}com.google.Chrome${RESET})"
            echo -e "  ${GREEN}firefox${RESET}     - Mozilla Firefox                 (${GRAY}org.mozilla.firefox${RESET})"
            echo
            echo -e "${BOLD}[💻 Development & Engineering]${RESET}"
            echo -e "  ${GREEN}vscode${RESET}      - Visual Studio Code              (${GRAY}com.visualstudio.code${RESET})"
            echo -e "  ${GREEN}vscodium${RESET}    - VSCodium (Telemetry-free)       (${GRAY}com.vscodium.codium${RESET})"
            echo -e "  ${GREEN}postman${RESET}     - Postman API Platform            (${GRAY}com.getpostman.Postman${RESET})"
            echo -e "  ${GREEN}dbeaver${RESET}     - DBeaver Universal Database      (${GRAY}io.dbeaver.DBeaverCommunity${RESET})"
            echo
            echo -e "${BOLD}[💬 Communication & Social]${RESET}"
            echo -e "  ${GREEN}discord${RESET}     - Discord Chat & Voice            (${GRAY}com.discordapp.Discord${RESET})"
            echo -e "  ${GREEN}telegram${RESET}    - Telegram Desktop                (${GRAY}org.telegram.desktop${RESET})"
            echo -e "  ${GREEN}slack${RESET}       - Slack Workspace Client          (${GRAY}com.slack.Slack${RESET})"
            echo
            echo -e "${BOLD}[🎨 Multimedia & Design]${RESET}"
            echo -e "  ${GREEN}vlc${RESET}         - VLC Media Player                (${GRAY}org.videolan.VLC${RESET})"
            echo -e "  ${GREEN}obs${RESET}         - OBS Studio Live Streaming       (${GRAY}com.obsproject.Studio${RESET})"
            echo -e "  ${GREEN}spotify${RESET}     - Spotify Music Desktop           (${GRAY}com.spotify.Client${RESET})"
            echo -e "  ${GREEN}gimp${RESET}        - GIMP GNU Image Manipulation     (${GRAY}org.gimp.GIMP${RESET})"
            echo
            echo -e "${BOLD}[📝 Productivity & Notes]${RESET}"
            echo -e "  ${GREEN}libreoffice${RESET} - LibreOffice Productivity Suite  (${GRAY}org.libreoffice.LibreOffice${RESET})"
            echo -e "  ${GREEN}obsidian${RESET}    - Obsidian Knowledge Base         (${GRAY}md.obsidian.Obsidian${RESET})"
            echo
            echo -e "${BOLD}CARA INSTALASI:${RESET}"
            echo -e "  ${CYAN}neuronix quickstart install <nama_alias_atau_app_id>${RESET}"
            echo -e "  Contoh: ${CYAN}neuronix quickstart install brave${RESET} atau ${CYAN}neuronix quickstart install com.discordapp.Discord${RESET}\n"
            ;;
        install)
            local target_app="$1"
            if [[ -z "$target_app" ]]; then
                log_error "Harap tentukan aplikasi yang ingin dipasang."
                echo -e "Jalankan '${CYAN}${PROGRAM_NAME} quickstart list${RESET}' untuk melihat daftar aplikasi."
                return 1
            fi

            # Mapping alias to Flatpak App ID
            local app_id="$target_app"
            case "$target_app" in
                brave) app_id="com.brave.Browser" ;;
                chrome) app_id="com.google.Chrome" ;;
                firefox) app_id="org.mozilla.firefox" ;;
                vscode) app_id="com.visualstudio.code" ;;
                vscodium) app_id="com.vscodium.codium" ;;
                postman) app_id="com.getpostman.Postman" ;;
                dbeaver) app_id="io.dbeaver.DBeaverCommunity" ;;
                discord) app_id="com.discordapp.Discord" ;;
                telegram) app_id="org.telegram.desktop" ;;
                slack) app_id="com.slack.Slack" ;;
                vlc) app_id="org.videolan.VLC" ;;
                obs) app_id="com.obsproject.Studio" ;;
                spotify) app_id="com.spotify.Client" ;;
                gimp) app_id="org.gimp.GIMP" ;;
                libreoffice) app_id="org.libreoffice.LibreOffice" ;;
                obsidian) app_id="md.obsidian.Obsidian" ;;
            esac

            log_step "Memverifikasi runtime Flatpak & repository Flathub..."
            if ! command -v flatpak &>/dev/null; then
                log_warn "Flatpak belum aktif di sistem host saat ini."
                echo -e "Pastikan modul Flatpak aktif pada konfigurasi NixOS Anda:\n"
                echo -e "  ${CYAN}neuronix.services.flatpak.enable = true;${RESET}\n"
                log_info "Mencoba menjalankan flatpak via nix-shell/nix run fallback..."
            fi

            log_step "Memasang '${app_id}' via Flathub..."
            if command -v flatpak &>/dev/null; then
                flatpak install -y flathub "$app_id"
                log_success "Aplikasi '${app_id}' berhasil dipasang!"
            else
                log_error "Perintah flatpak tidak ditemukan di PATH. Pasang Flatpak terlebih dahulu."
                return 1
            fi
            ;;
        search)
            local query="$1"
            if [[ -z "$query" ]]; then
                log_error "Harap tentukan kata kunci pencarian."
                return 1
            fi
            log_step "Mencari aplikasi Flathub dengan kata kunci '${query}'..."
            if command -v flatpak &>/dev/null; then
                flatpak search "$query"
            else
                log_error "Perintah flatpak tidak tersedia untuk pencarian langsung."
                return 1
            fi
            ;;
        -h|--help)
            echo -e "${BOLD}USAGE:${RESET}"
            echo -e "  ${CYAN}${PROGRAM_NAME} quickstart${RESET} [COMMAND] [ARGS]\n"
            echo -e "${BOLD}COMMANDS:${RESET}"
            echo -e "  ${GREEN}list${RESET}                 Tampilkan seluruh katalog aplikasi terkurasi"
            echo -e "  ${GREEN}install <alias/id>${RESET}   Pasang aplikasi secara instan dari Flathub"
            echo -e "  ${GREEN}search <keyword>${RESET}    Cari aplikasi di repositori Flathub"
            echo -e "  ${GREEN}-h, --help${RESET}           Tampilkan panduan ini\n"
            ;;
        *)
            log_error "Subcommand quickstart tidak dikenali: $action"
            echo -e "Jalankan '${CYAN}${PROGRAM_NAME} quickstart --help${RESET}' untuk panduan."
            return 1
            ;;
    esac
}

cmd_kernel() {
    local action="${1:-status}"
    shift 2>/dev/null || true

    case "$action" in
        status|current)
            echo -e "${BOLD}${CYAN}🐧 MANAJEMEN PROFIL KERNEL NEURONIX (DECLARATIVE KERNEL MANAGER)${RESET}"
            echo -e "${GRAY}Parity dengan Arch Kernel Manager (akm) namun berprinsip deklaratif murni.${RESET}\n"

            local current_running="$(uname -r 2>/dev/null || echo "Unknown")"
            local configured_flavor="default"
            if [[ -f "/etc/neuronix/kernel-profile" ]]; then
                configured_flavor="$(cat /etc/neuronix/kernel-profile 2>/dev/null | tr -d '[:space:]')"
            else
                local boot_nix_path="/etc/nixos/modules/hardware/boot.nix"
                if [[ ! -f "$boot_nix_path" && -f "./modules/hardware/boot.nix" ]]; then
                    boot_nix_path="./modules/hardware/boot.nix"
                fi

                if [[ -f "$boot_nix_path" ]]; then
                    local detected
                    detected="$(grep -oP 'kernelFlavor\s*=\s*"\K[^"]+' "$boot_nix_path" 2>/dev/null || true)"
                    if [[ -z "$detected" ]]; then
                        detected="$(grep -oP 'default\s*=\s*"\K[a-z]+(?=";\s*#\s*default)' "$boot_nix_path" 2>/dev/null || true)"
                    fi
                    if [[ -n "$detected" ]]; then
                        configured_flavor="$detected"
                    fi
                fi
            fi

            echo -e "  ${BOLD}Kernel Berjalan Saat Ini${RESET} : ${GREEN}${current_running}${RESET}"
            echo -e "  ${BOLD}Profil Terkonfigurasi${RESET}   : ${CYAN}${configured_flavor}${RESET}"
            echo -e "  ${BOLD}Dukungan Flavor${RESET}        : default, zen, lts, latest, hardened\n"
            echo -e "Gunakan '${CYAN}neuronix kernel list${RESET}' untuk membandingkan karakteristik setiap flavor."
            ;;
        list)
            echo -e "${BOLD}${CYAN}📋 PROFIL & FLAVOR KERNEL NEURONIX TERSEDIA:${RESET}\n"
            printf "  ${BOLD}%-12s %-22s %-45s${RESET}\n" "FLAVOR" "PACKAGE UPSTREAM" "KARAKTERISTIK & KASUS PENGGUNAAN"
            echo -e "  --------------------------------------------------------------------------------"
            printf "  ${GREEN}%-12s${RESET} %-22s %-45s\n" "default" "linuxPackages" "Stabil, seimbang, teruji resmi upstream NixOS"
            printf "  ${GREEN}%-12s${RESET} %-22s %-45s\n" "zen" "linuxPackages_zen" "Tuning latency rendah, ideal untuk gaming & multimedia"
            printf "  ${GREEN}%-12s${RESET} %-22s %-45s\n" "lts" "linuxPackages_lts" "Long Term Support, stabilitas mission-critical"
            printf "  ${GREEN}%-12s${RESET} %-22s %-45s\n" "latest" "linuxPackages_latest" "Bleeding-edge, driver hardware generasi paling baru"
            printf "  ${GREEN}%-12s${RESET} %-22s %-45s\n" "hardened" "linuxPackages_hardened" "Patch keamanan memori ketat & proteksi exploitasi"
            echo
            echo -e "${BOLD}CARA MENGGANTI FLAVOR KERNEL:${RESET}"
            echo -e "  Deklarasikan di konfigurasi sistem Anda:"
            echo -e "  ${CYAN}neuronix.hardware.kernelFlavor = \"zen\";${RESET}"
            echo -e "  Atau atur via CLI: '${CYAN}neuronix kernel set zen${RESET}' (menyimpan ke /etc/neuronix/kernel-profile)"
            echo -e "  Lalu jalankan '${CYAN}neuronix upgrade${RESET}' untuk kompilasi generasi baru secara aman.\n"
            ;;
        set)
            local target_flavor="$1"
            if [[ -z "$target_flavor" ]]; then
                log_error "Harap tentukan flavor kernel (default, zen, lts, latest, hardened)."
                return 1
            fi

            case "$target_flavor" in
                default|zen|lts|latest|hardened)
                    log_step "Memilih profil kernel flavor '${target_flavor}' secara deklaratif..."
                    local profile_file="/etc/neuronix/kernel-profile"
                    local profile_dir="/etc/neuronix"
                    if [[ $EUID -eq 0 ]]; then
                        mkdir -p "$profile_dir"
                        echo "$target_flavor" > "$profile_file"
                        log_success "Profil kernel deklaratif berhasil disimpan ke ${profile_file} (${target_flavor})!"
                    else
                        if sudo mkdir -p "$profile_dir" 2>/dev/null && echo "$target_flavor" | sudo tee "$profile_file" >/dev/null 2>&1; then
                            log_success "Profil kernel deklaratif berhasil disimpan ke ${profile_file} (${target_flavor})!"
                        else
                            log_warn "Tidak dapat menulis ke ${profile_file} tanpa hak root."
                            log_info "Deklarasikan baris berikut pada konfigurasi NixOS Anda:"
                            echo -e "  ${CYAN}neuronix.hardware.kernelFlavor = \"$target_flavor\";${RESET}"
                        fi
                    fi

                    echo
                    log_info "Langkah berikutnya: Terapkan perubahan kernel dengan Staged Upgrade aman:"
                    echo -e "  ${BOLD}${CYAN}neuronix upgrade --staged${RESET}"
                    echo -e "  Generasi kernel baru akan dimuat saat reboot tanpa mengganggu sesi Anda saat ini."
                    ;;
                *)
                    log_error "Flavor '${target_flavor}' tidak valid."
                    echo -e "Pilihan yang tersedia: ${GREEN}default${RESET}, ${GREEN}zen${RESET}, ${GREEN}lts${RESET}, ${GREEN}latest${RESET}, ${GREEN}hardened${RESET}"
                    return 1
                    ;;
            esac
            ;;
        -h|--help)
            echo -e "${BOLD}USAGE:${RESET}"
            echo -e "  ${CYAN}${PROGRAM_NAME} kernel${RESET} [COMMAND] [ARGS]\n"
            echo -e "${BOLD}COMMANDS:${RESET}"
            echo -e "  ${GREEN}status${RESET}          Tampilkan profil kernel yang aktif & terkonfigurasi"
            echo -e "  ${GREEN}list${RESET}            Tampilkan daftar semua flavor kernel beserta deskripsi"
            echo -e "  ${GREEN}set <flavor>${RESET}    Ubah profil kernel target (default/zen/lts/latest/hardened)"
            echo -e "  ${GREEN}-h, --help${RESET}      Tampilkan panduan ini\n"
            ;;
        *)
            log_error "Subcommand kernel tidak dikenali: $action"
            echo -e "Jalankan '${CYAN}${PROGRAM_NAME} kernel --help${RESET}' untuk panduan."
            return 1
            ;;
    esac
}

cmd_manual() {
    local topic="${1:-index}"
    local manual_dir="/etc/neuronix/manual"

    # Fallback to local repository documentation if system manual path does not exist
    if [[ ! -d "$manual_dir" ]]; then
        local real_bin
        real_bin="$(readlink -f "${BASH_SOURCE[0]}")"
        local script_dir
        script_dir="$(cd "$(dirname "$real_bin")" && pwd)"
        if [[ -d "${script_dir}/../share/neuronix/manual" ]]; then
            manual_dir="${script_dir}/../share/neuronix/manual"
        elif [[ -d "${script_dir}/../docs/manual" ]]; then
            manual_dir="${script_dir}/../docs/manual"
        fi
    fi

    if [[ ! -d "$manual_dir" && -n "${PROJECT_ROOT:-}" && -d "${PROJECT_ROOT}/docs/manual" ]]; then
        manual_dir="${PROJECT_ROOT}/docs/manual"
    fi

    if [[ ! -d "$manual_dir" && -d "$(pwd)/docs/manual" ]]; then
        manual_dir="$(pwd)/docs/manual"
    fi

    if [[ ! -d "$manual_dir" ]]; then
        log_error "System manual directory not found at /etc/neuronix/manual or docs/manual."
        return 1
    fi

    local target_file=""
    case "${topic,,}" in
        index|list|toc|"")
            target_file="$manual_dir/00_INDEX.md"
            ;;
        arch|architecture|platform)
            target_file="$manual_dir/01_ARCHITECTURE.md"
            ;;
        config|configuration|options)
            target_file="$manual_dir/02_CONFIGURATION_REFERENCE.md"
            ;;
        cli|commands|syntax)
            target_file="$manual_dir/03_CLI_REFERENCE.md"
            ;;
        storage|btrfs|rollback)
            target_file="$manual_dir/04_STORAGE_AND_ROLLBACK.md"
            ;;
        shadow|vm|sandbox|microvm|container)
            target_file="$manual_dir/05_SHADOW_VM_AND_SANDBOX.md"
            ;;
        dev|stacks|developer)
            target_file="$manual_dir/06_DEVELOPER_STACKS.md"
            ;;
        mcp|gateway|ai-gateway)
            target_file="$manual_dir/07_MCP_PROTOCOL_AND_AI_GATEWAY.md"
            ;;
        hardware|pillars|27-pillars)
            target_file="$manual_dir/08_HARDWARE_AND_27_PILLARS.md"
            ;;
        security|attestation|sbom)
            target_file="$manual_dir/09_SECURITY_AND_ATTESTATION.md"
            ;;
        ai|agent|copilot)
            target_file="$manual_dir/10_AI_AGENT_REFERENCE.md"
            ;;
        all)
            target_file="ALL"
            ;;
        -h|--help)
            echo -e "${BOLD}USAGE:${RESET}"
            echo -e "  ${CYAN}${PROGRAM_NAME} manual${RESET} [TOPIC]\n"
            echo -e "${BOLD}AVAILABLE TOPICS:${RESET}"
            echo -e "  ${GREEN}index${RESET}        Master Table of Contents and System Manual Map"
            echo -e "  ${GREEN}arch${RESET}         Platform Architecture, 4-Layer Model, and Nix Substrate"
            echo -e "  ${GREEN}config${RESET}       Declarative Option Reference and Schema Contracts"
            echo -e "  ${GREEN}cli${RESET}          Complete Command-Line Interface Manual (24 Subcommands)"
            echo -e "  ${GREEN}storage${RESET}      Btrfs 5-Subvolume Topology, Compression, and Rollback"
            echo -e "  ${GREEN}shadow${RESET}       Shadow Micro-VM Sandbox and Smoke Testing Engine"
            echo -e "  ${GREEN}dev${RESET}          Hermetic Developer Environments and Manifests"
            echo -e "  ${GREEN}mcp${RESET}          Model Context Protocol JSON-RPC 2.0 AI Gateway"
            echo -e "  ${GREEN}hardware${RESET}     Hardware Profiles and 27 Industrial Optimization Pillars"
            echo -e "  ${GREEN}security${RESET}     Security Boundaries, Privilege Allowlist, TPM2, and SBOM"
            echo -e "  ${GREEN}ai${RESET}           AI Copilot Integration Directives and Guardrails"
            echo -e "  ${GREEN}all${RESET}          Display Entire Technical Manual"
            return 0
            ;;
        *)
            log_error "Unknown manual topic: '${topic}'"
            echo -e "Available topics: index, arch, config, cli, storage, shadow, dev, mcp, hardware, security, ai, all"
            echo -e "Run '${CYAN}${PROGRAM_NAME} manual --help${RESET}' for topic descriptions."
            return 1
            ;;
    esac

    render_manual() {
        if [[ -t 1 ]] && command -v less >/dev/null 2>&1 && [[ "${PAGER:-}" != "cat" ]]; then
            ${PAGER:-less -R}
        else
            cat
        fi
    }

    if [[ "$target_file" == "ALL" ]]; then
        {
            echo -e "# NEURONIX OS COMPLETE SYSTEM-EMBEDDED TECHNICAL MANUAL\n"
            for f in "$manual_dir"/[0-9][0-9]_*.md; do
                if [[ -f "$f" ]]; then
                    cat "$f"
                    echo -e "\n\n---\n"
                fi
            done
        } | render_manual
    elif [[ -f "$target_file" ]]; then
        cat "$target_file" | render_manual
    else
        log_error "Manual file not found: $target_file"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Autonomous Boot Assessment & Fallback Sentinel
# ------------------------------------------------------------------------------
cmd_sentinel() {
    local sub=""
    local json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${PROGRAM_NAME} sentinel [status|confirm] [OPTIONS]\n"
                echo -e "  Inspects autonomous boot assessment state and emergency rollback history.\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${CYAN}--json${RESET}     Output status in structured JSON"
                echo -e "  ${CYAN}-h, --help${RESET} Show this help"
                return 0
                ;;
            status|confirm|test)
                sub="$1"
                shift
                ;;
            *)
                sub="$1"
                shift
                ;;
        esac

    done
    sub="${sub:-status}"

    local active_gen
    active_gen="$(get_current_generation)"

    if [[ "$sub" == "confirm" ]]; then
        mkdir -p /var/lib/neuronix 2>/dev/null || sudo -n mkdir -p /var/lib/neuronix 2>/dev/null || true
        if [[ -w "/var/lib/neuronix" ]] || [[ "$EUID" -eq 0 ]]; then
            echo "$active_gen" > /var/lib/neuronix/last-known-good 2>/dev/null || true
            rm -f /run/neuronix/booting-generation 2>/dev/null || true
        else
            echo "$active_gen" | sudo -n tee /var/lib/neuronix/last-known-good >/dev/null 2>&1 || true
            sudo -n rm -f /run/neuronix/booting-generation 2>/dev/null || true
        fi
        systemctl stop neuronix-boot-sentinel-watchdog.timer 2>/dev/null || sudo -n systemctl stop neuronix-boot-sentinel-watchdog.timer 2>/dev/null || true

        if [[ "$json_output" -eq 1 ]]; then
            jq -n -c \
                --arg active "$active_gen" \
                '{
                    status: "success",
                    action: "confirmed",
                    confirmed_generation: $active,
                    watchdog_timer: "disarmed"
                }'
            return 0
        fi
        log_success "Boot-Sentinel confirmed generation #${active_gen} as last-known-good profile. Watchdog disarmed."
        return 0
    fi

    local last_good="Unknown"
    if [[ -f "/var/lib/neuronix/last-known-good" ]]; then
        last_good=$(cat /var/lib/neuronix/last-known-good | tr -d '[:space:]')
    fi

    local booting_gen=""
    if [[ -f "/run/neuronix/booting-generation" ]]; then
        booting_gen=$(cat /run/neuronix/booting-generation | tr -d '[:space:]')
    fi

    local watchdog_active="inactive"
    if systemctl is-active neuronix-boot-sentinel-watchdog.timer >/dev/null 2>&1; then
        watchdog_active="active"
    fi

    local crash_log=""
    if [[ -f "/var/log/neuronix/boot-fallback.log" ]]; then
        crash_log=$(tail -n 10 /var/log/neuronix/boot-fallback.log)
    fi

    if [[ "$json_output" -eq 1 ]]; then
        jq -n -c \
            --arg active "$active_gen" \
            --arg last_good "$last_good" \
            --arg booting "$booting_gen" \
            --arg watchdog "$watchdog_active" \
            --arg log "$crash_log" \
            '{
                status: "success",
                active_generation: $active,
                last_known_good_generation: $last_good,
                in_assessment: (if $booting != "" then true else false end),
                assessment_boot_generation: $booting,
                watchdog_timer_active: (if $watchdog == "active" then true else false end),
                fallback_history: $log
            }'
        return 0
    fi

    print_banner
    log_step "NEURONIX Boot-Sentinel Status (Autonomous Zero-Brick Watchdog)"
    echo
    echo -e "  ${BOLD}SENTINEL HEALTH & PROFILE ASSESSMENT${RESET}"
    echo -e "  ├─ Active Generation       : ${BOLD}Gen #${active_gen}${RESET}"
    echo -e "  ├─ Last Known Good Profile : ${GREEN}Gen #${last_good}${RESET}"
    if [[ -n "$booting_gen" ]]; then
        echo -e "  ├─ Assessment Window       : ${YELLOW}ACTIVE${RESET} (Currently assessing Gen #${booting_gen})"
    else
        echo -e "  ├─ Assessment Window       : ${GREEN}CONFIRMED & STABLE${RESET} (Normal system runtime)"
    fi
    if [[ "$watchdog_active" == "active" ]]; then
        echo -e "  ├─ Watchdog Timer          : ${YELLOW}ARMED & COUNTING${RESET} (Emergency fallback on timeout)"
    else
        echo -e "  ├─ Watchdog Timer          : ${GREEN}DISARMED${RESET} (System confirmed stable)"
    fi

    if [[ -f "/var/log/neuronix/boot-fallback.log" ]]; then
        echo -e "  └─ Fallback Event History  : ${YELLOW}Detected${RESET}"
        echo
        echo -e "  ${DIM}Recent Sentinel Fallback Log:${RESET}"
        tail -n 5 /var/log/neuronix/boot-fallback.log | sed 's/^/    /'
    else
        echo -e "  └─ Fallback Event History  : ${GREEN}Clean (No emergency fallbacks recorded)${RESET}"
    fi
    echo
}

# ------------------------------------------------------------------------------
# Generational Forensic & Security Diff Engine
# ------------------------------------------------------------------------------
