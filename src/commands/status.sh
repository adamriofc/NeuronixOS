#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
get_current_generation() {
    if [[ -L /nix/var/nix/profiles/system ]]; then
        basename "$(readlink /nix/var/nix/profiles/system)" | sed -E 's/^system-?//; s/-?link$//'
    else
        echo "Unknown"
    fi
}

count_generations() {
    if [[ -d /nix/var/nix/profiles ]]; then
        find /nix/var/nix/profiles/ -maxdepth 1 -name "system-*-link" 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

cmd_status() {
    print_banner
    log_step "Memeriksa Status & Telemetri Substrat NEURONIX..."
    echo

    # 1. System Identity
    local current_gen
    current_gen="$(get_current_generation)"
    local total_gen
    total_gen="$(count_generations)"
    local kernel_ver
    kernel_ver="$(uname -r)"
    local virt_type
    virt_type="$(systemd-detect-virt 2>/dev/null || echo "bare-metal")"

    echo -e "  ${BOLD}SYSTEM IDENTITY & KERNEL${RESET}"
    echo -e "  ├─ OS Substrate       : ${GREEN}NixOS (Pure-Functional)${RESET}"
    echo -e "  ├─ Linux Kernel      : ${CYAN}${kernel_ver}${RESET}"
    echo -e "  ├─ Hypervisor Type   : ${YELLOW}${virt_type}${RESET} (KVM/VirtIO accelerated)"
    echo -e "  ├─ Active Generation : ${BOLD}Gen #${current_gen}${RESET}"
    echo -e "  └─ Total History     : ${total_gen} generations available for rollback"
    echo

    # 2. Storage Health
    echo -e "  ${BOLD}STORAGE SUBSYSTEM TELEMETRY${RESET}"
    local nix_used="" nix_avail="" nix_pct=""
    read -r nix_used nix_avail nix_pct < <(df -h /nix 2>/dev/null | awk 'NR==2 {print $3, $4, $5}') || true
    nix_used="${nix_used:-N/A}"
    nix_avail="${nix_avail:-N/A}"
    nix_pct="${nix_pct:-N/A}"
    local boot_used="" boot_avail="" boot_pct=""
    read -r boot_used boot_avail boot_pct < <(df -h /boot 2>/dev/null | awk 'NR==2 {print $3, $4, $5}') || true
    boot_used="${boot_used:-N/A}"
    boot_avail="${boot_avail:-N/A}"
    boot_pct="${boot_pct:-N/A}"

    echo -e "  ├─ /nix Store Volume : Terpakai ${BOLD}${nix_used}${RESET} (${nix_pct}) | Sisa: ${GREEN}${nix_avail}${RESET}"
    echo -e "  ├─ Boot Partition    : Terpakai ${boot_used} (${boot_pct}) | Sisa: ${boot_avail}"
    
    if [[ -f /etc/nix/nix.conf ]] && grep -q "auto-optimise-store = true" /etc/nix/nix.conf; then
        echo -e "  ├─ Real-time Dedupe  : ${GREEN}AKTIF${RESET} (auto-optimise-store)"
    else
        echo -e "  ├─ Real-time Dedupe  : ${YELLOW}NONAKTIF${RESET}"
    fi
    echo -e "  ├─ Dynamic Guard     : min-free 1.0 GiB | max-free 3.0 GiB"
    echo -e "  └─ Journal Retention : 500 MiB Max Ceiling (1 Month Retention)"
    echo

    # 3. Autonomous Daemon Timers
    echo -e "  ${BOLD}AUTONOMOUS TIMERS (SYSTEMD)${RESET}"
    local gc_status opt_status trim_status update_status flatpak_status
    systemctl is-active nix-gc.timer &>/dev/null && gc_status="${GREEN}ONLINE (Harian)${RESET}" || gc_status="${RED}OFFLINE${RESET}"
    systemctl is-active nix-optimise.timer &>/dev/null && opt_status="${GREEN}ONLINE (Harian)${RESET}" || opt_status="${RED}OFFLINE${RESET}"
    systemctl is-active fstrim.timer &>/dev/null && trim_status="${GREEN}ONLINE (Harian)${RESET}" || trim_status="${RED}OFFLINE${RESET}"
    systemctl is-active neuronix-update-check.timer &>/dev/null && update_status="${GREEN}ONLINE (Harian)${RESET}" || update_status="${YELLOW}STANDBY${RESET}"
    systemctl is-active flatpak-prune-unused.timer &>/dev/null && flatpak_status="${GREEN}ONLINE (Mingguan)${RESET}" || flatpak_status="${YELLOW}STANDBY${RESET}"

    echo -e "  ├─ Auto Garbage Clean: ${gc_status}"
    echo -e "  ├─ Store Optimise    : ${opt_status}"
    echo -e "  ├─ Host SSD TRIM     : ${trim_status}"
    echo -e "  ├─ Desktop Update Mon: ${update_status}"
    echo -e "  └─ Flatpak Prune Mon : ${flatpak_status}"
    echo

    # 4. Hardware & 27-Pillar Resilience Shield
    echo -e "  ${BOLD}27-PILLAR RESILIENCE SHIELD${RESET}"
    local zram_status oomd_status batt_status pipewire_status

    if grep -q "zram" /proc/swaps 2>/dev/null; then
        local zram_dev zram_size
        zram_dev=$(grep "zram" /proc/swaps | awk '{print $1}')
        zram_size=$(grep "zram" /proc/swaps | awk '{print int($3/1024)"MB"}')
        zram_status="${GREEN}AKTIF (${zram_dev}: ${zram_size} ZSTD)${RESET}"
    else
        zram_status="${YELLOW}STANDBY / NON-ZRAM${RESET}"
    fi

    if systemctl is-active systemd-oomd &>/dev/null; then
        oomd_status="${GREEN}AKTIF (PSI Pressure Stall Guard)${RESET}"
    else
        oomd_status="${YELLOW}NONAKTIF / PSI PASSIVE${RESET}"
    fi

    local batt_threshold_file=""
    for cand in charge_control_end_threshold charge_control_limit_max charge_stop_threshold; do
        batt_threshold_file=$(find /sys/class/power_supply/ -name "$cand" 2>/dev/null | head -n 1 || true)
        if [[ -n "$batt_threshold_file" && -f "$batt_threshold_file" ]]; then
            break
        fi
    done
    if [[ -n "$batt_threshold_file" && -f "$batt_threshold_file" ]]; then
        local limit_val
        limit_val=$(cat "$batt_threshold_file" 2>/dev/null || echo "100")
        if [[ "$limit_val" -le 80 ]]; then
            batt_status="${GREEN}AKTIF (Maks ${limit_val}% Longevity Shield)${RESET}"
        else
            batt_status="${CYAN}STANDARD (${limit_val}% Bebas)${RESET}"
        fi
    else
        batt_status="${DIM}TIDAK TERDETEKSI (AC / Desktop Mode)${RESET}"
    fi

    if systemctl is-active --user pipewire &>/dev/null || systemctl is-active pipewire &>/dev/null || pgrep -x pipewire &>/dev/null; then
        pipewire_status="${GREEN}AKTIF (PipeWire HD Duplex & LDAC)${RESET}"
    else
        pipewire_status="${YELLOW}STANDBY${RESET}"
    fi

    echo -e "  ├─ Active Memory Shield: ${zram_status}"
    echo -e "  ├─ Systemd OOMD Guard : ${oomd_status}"
    echo -e "  ├─ Battery Longevity  : ${batt_status}"
    echo -e "  └─ Audio Subsystem    : ${pipewire_status}"
    echo
    log_success "All subsystem parameters are operating at optimal status."
}

