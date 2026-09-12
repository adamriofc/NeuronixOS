#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_generations() {
    print_banner
    log_step "Riwayat Generasi Sistem NEURONIX (Time-Travel Timeline)..."
    echo
    local current_gen
    current_gen="$(get_current_generation)"
    
    echo -e "  ${BOLD}GENERATION ID     TANGGAL / WAKTU             STATUS${RESET}"
    echo -e "  ────────────────────────────────────────────────────────────"
    
    local found=0
    for link in $(find /nix/var/nix/profiles/ -maxdepth 1 -name "system-*-link" 2>/dev/null | sort -V); do
        found=1
        local gen_num
        gen_num=$(basename "$link" | sed -E 's/^system-([0-9]+)-link$/\1/')
        local mod_time
        mod_time=$(date -r "$link" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown Date")
        if [[ "$gen_num" == "$current_gen" ]]; then
            echo -e "  ${GREEN}▶ Gen #${gen_num}${RESET}          ${CYAN}${mod_time}${RESET}       ${GREEN}* AKTIF (Current)${RESET}"
        else
            echo -e "    Gen #${gen_num}          ${mod_time}       ${DIM}Available for rollback${RESET}"
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo -e "    Gen #${current_gen}          $(date "+%Y-%m-%d %H:%M:%S")       ${GREEN}* AKTIF (Initial)${RESET}"
    fi
    echo
    log_info "Use '${CYAN}neuronix undo${RESET}' to instantly revert to the previous generation."
}

