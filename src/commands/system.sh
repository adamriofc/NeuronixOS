#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_shield() {
    local as_json=0
    for arg in "$@"; do
        if [[ "$arg" == "--json" ]]; then
            as_json=1
        fi
    done

    if [[ "$as_json" -eq 1 ]]; then
        python3 -c '
import os, sys, json, subprocess

swaps = []
if os.path.exists("/proc/swaps"):
    with open("/proc/swaps") as f:
        for line in f.readlines()[1:]:
            p = line.split()
            if len(p) >= 5:
                is_zram = "zram" in p[0]
                used = int(p[3])
                swaps.append({
                    "device": p[0],
                    "type": p[1],
                    "size_kb": int(p[2]),
                    "used_kb": used,
                    "priority": int(p[4]),
                    "tier": "ZRAM_COMPRESSED_RAM" if is_zram else "COLD_DISK_FALLBACK",
                    "zero_wear_protected": (used == 0) if not is_zram else None
                })

zswap_enabled = False
if os.path.exists("/sys/module/zswap/parameters/enabled"):
    with open("/sys/module/zswap/parameters/enabled") as f:
        zswap_enabled = f.read().strip().lower() in ("y", "1")

def get_sysctl(key):
    try:
        out = subprocess.check_output(["sysctl", "-n", key], stderr=subprocess.DEVNULL).decode().strip()
        return int(out) if out.isdigit() else out
    except Exception:
        return None

sysctl_data = {
    "vm.swappiness": get_sysctl("vm.swappiness"),
    "vm.page-cluster": get_sysctl("vm.page-cluster"),
    "vm.vfs_cache_pressure": get_sysctl("vm.vfs_cache_pressure"),
    "vm.max_map_count": get_sysctl("vm.max_map_count")
}

def is_active(srv):
    try:
        res = subprocess.run(["systemctl", "is-active", "--quiet", srv], check=False)
        return res.returncode == 0
    except Exception:
        return False

oom_status = {
    "systemd_oomd": is_active("systemd-oomd"),
    "earlyoom": is_active("earlyoom")
}

psi = {}
if os.path.exists("/proc/pressure/memory"):
    with open("/proc/pressure/memory") as f:
        for line in f:
            parts = line.strip().split()
            if parts:
                psi[parts[0]] = {kv.split("=")[0]: kv.split("=")[1] for kv in parts[1:] if "=" in kv}

payload = {
    "schema_version": "1.0.0",
    "timestamp": subprocess.check_output(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"]).decode().strip(),
    "zram_active": any("zram" in s["device"] for s in swaps),
    "zswap_enabled": zswap_enabled,
    "double_compression_eliminated": not zswap_enabled,
    "swaps": swaps,
    "kernel_parameters": sysctl_data,
    "oom_daemon": oom_status,
    "psi": psi
}
print(json.dumps(payload, indent=2))
'
        return 0
    fi

    print_banner
    log_step ""
    echo
    echo -e "  ${BOLD}MEMORY & SWAP PRESSURE DIAGNOSTICS${RESET}"
    
    if command -v zramctl &>/dev/null && [[ $(zramctl 2>/dev/null | wc -l) -gt 1 ]]; then
        echo -e "  ${BOLD}ZRAM Compressed Block Devices:${RESET}"
        zramctl 2>/dev/null | sed 's/^/    /'
    else
        echo -e "  ├─ ZRAM Swap Pool    : $(grep -q "zram" /proc/swaps 2>/dev/null && echo -e "${GREEN}ONLINE${RESET}" || echo -e "${YELLOW}STANDBY${RESET}")"
    fi
    echo
    
    echo -e "  ${BOLD}Layered Swap Hierarchy & Storage Protection:${RESET}"
    if [[ -f /proc/swaps ]] && [[ $(wc -l < /proc/swaps) -gt 1 ]]; then
        awk 'NR>1 {
            dev=$1; type=$2; size=int($3/1024)"MB"; used=int($4/1024)"MB"; prio=$5;
            if (dev ~ /zram/) {
                printf "  ├─ %-16s [%-9s] Size: %-7s Used: %-7s Prio: %-6s \033[32m[ZRAM TIER 1 - IN-RAM]\033[0m\n", dev, type, size, used, prio
            } else {
                if ($4 == 0) {
                    printf "  └─ %-16s [%-9s] Size: %-7s Used: %-7s Prio: %-6s \033[36m[ZERO-WEAR STANDBY - HIBERNATION READY]\033[0m\n", dev, type, size, used, prio
                } else {
                    printf "  └─ %-16s [%-9s] Size: %-7s Used: %-7s Prio: %-6s \033[33m[COLD FALLBACK ACTIVE]\033[0m\n", dev, type, size, used, prio
                }
            }
        }' /proc/swaps
    else
        echo -e "  └─ Swap Devices      : ${YELLOW}None active${RESET}"
    fi
    echo
    
    if [[ -f /sys/module/zswap/parameters/enabled ]]; then
        local zval zswap_status zswap_msg
        zval=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null | tr -d '\n')
        if [[ "$zval" == "N" || "$zval" == "0" ]]; then
            zswap_status="${GREEN}DISABLED (N)${RESET}"
            zswap_msg="Double-compression CPU overhead eliminated (100% ZRAM ZSTD)"
        else
            zswap_status="${YELLOW}ENABLED (Y)${RESET}"
            zswap_msg="In-kernel zswap active (potential double-compression with ZRAM)"
        fi
        echo -e "  ${BOLD}In-Kernel Zswap Status:${RESET}"
        echo -e "  └─ zswap.enabled      : ${zswap_status} - ${zswap_msg}"
        echo
    fi

    local swappiness vfs_pressure page_cluster max_map
    swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "unknown")
    vfs_pressure=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "unknown")
    page_cluster=$(sysctl -n vm.page-cluster 2>/dev/null || echo "unknown")
    max_map=$(sysctl -n vm.max_map_count 2>/dev/null || echo "unknown")
    
    echo -e "  ${BOLD}Kernel Memory Parameters:${RESET}"
    echo -e "  ├─ vm.swappiness      : ${CYAN}${swappiness}${RESET} (Standard: 180 - Proactive ZRAM compression)"
    echo -e "  ├─ vm.page-cluster    : ${CYAN}${page_cluster}${RESET} (Standard: 0 - Zero readahead latency)"
    echo -e "  ├─ vm.vfs_cache_press : ${CYAN}${vfs_pressure}${RESET} (Standard: 50 - Retain dentries/inodes)"
    echo -e "  └─ vm.max_map_count   : ${CYAN}${max_map}${RESET} (SteamOS standard: 2147483642)"
    echo

    local oom_status="STANDBY"
    if systemctl is-active --quiet systemd-oomd 2>/dev/null; then
        oom_status="${GREEN}ACTIVE (systemd-oomd PSI)${RESET}"
    elif systemctl is-active --quiet earlyoom 2>/dev/null; then
        oom_status="${GREEN}ACTIVE (earlyoom)${RESET}"
    fi
    echo -e "  ${BOLD}Out-Of-Memory (OOM) Protection:${RESET}"
    echo -e "  └─ OOM Monitor        : ${oom_status}"
    echo
    
    if [[ -f /proc/pressure/memory ]]; then
        echo -e "  ${BOLD}Kernel PSI (Pressure Stall Information):${RESET}"
        cat /proc/pressure/memory | sed 's/^/    /'
        echo
        log_success "Active Memory Pressure Shield siap melindungi desktop dari OOM Freeze."
    else
        log_info "Kernel PSI tidak tersedia di kernel saat ini."
    fi
}

cmd_battery() {
    local target="${1:-status}"
    local batt_file=""
    for candidate in charge_control_end_threshold charge_control_limit_max charge_stop_threshold; do
        batt_file=$(find /sys/class/power_supply/ -name "$candidate" 2>/dev/null | head -n 1 || true)
        if [[ -n "$batt_file" && -f "$batt_file" ]]; then
            break
        fi
    done
    
    if [[ -z "$batt_file" || ! -f "$batt_file" ]]; then
        log_warn "Laptop battery hardware with charge threshold control was not detected."
        echo -e "Perangkat beroperasi dalam mode desktop / AC permanen."
        return 0
    fi
    
    case "$target" in
        80|limit|on)
            log_step "Mengonfigurasi ambang batas pengisian daya baterai (Maksimal 80%)..."
            if echo 80 | sudo tee "$batt_file" &>/dev/null; then
                local readback
                readback=$(cat "$batt_file" 2>/dev/null || echo "")
                if [[ "$readback" == "80" ]]; then
                    log_success "Battery charge threshold successfully configured to 80% (verified: ${readback}%)."
                else
                    log_error "Verifikasi gagal: nilai terbaca '${readback}%', bukan '80%'."
                    return 1
                fi
            else
                log_error "Gagal menyetel ambang batas baterai. Butuh akses root."
                return 1
            fi
            ;;
        100|full|off)
            log_step "Menonaktifkan batasan pengisian daya (Maksimal 100%)..."
            if echo 100 | sudo tee "$batt_file" &>/dev/null; then
                local readback
                readback=$(cat "$batt_file" 2>/dev/null || echo "")
                if [[ "$readback" == "100" ]]; then
                    log_success "Baterai kini dapat diisi penuh hingga 100% (verified: ${readback}%)."
                else
                    log_error "Verifikasi gagal: nilai terbaca '${readback}%', bukan '100%'."
                    return 1
                fi
            else
                log_error "Gagal menyetel ambang batas baterai. Butuh akses root."
                return 1
            fi
            ;;
        status|*)
            local cur
            cur=$(cat "$batt_file" 2>/dev/null || echo "100")
            print_banner
            echo -e "  ${BOLD}BATTERY LONGEVITY STATUS${RESET}"
            echo -e "  ├─ Batas Pengisian Saat Ini : ${BOLD}${cur}%${RESET}"
            if [[ "$cur" -le 80 ]]; then
                echo -e "  └─ Mode Longevity           : ${GREEN}AKTIF (Baterai awet berumur panjang)${RESET}"
            else
                echo -e "  └─ Mode Longevity           : ${YELLOW}NONAKTIF (Pengisian penuh 100%)${RESET}"
            fi
            echo
            echo -e "Gunakan: ${CYAN}neuronix battery 80${RESET} (aktifkan limit) atau ${CYAN}neuronix battery 100${RESET} (cas penuh)"
            ;;
    esac
}

cmd_center() {
    local center_py
    center_py="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/neuronix-center/neuronix_center.py"
    if [[ ! -f "$center_py" ]]; then
        center_py="/run/current-system/sw/bin/neuronix-center"
    fi
    
    if [[ -f "$center_py" ]]; then
        if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
            python3 "$center_py" --cli
        else
            python3 "$center_py" &
        fi
    else
        log_error "NEURONIX Center is not installed on this system."
        exit 1
    fi
}

cmd_check_update() {
    print_banner
    log_step "Memeriksa Status Pembaruan Sistem & Flake Upstream..."
    echo

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        echo -e "${BOLD}USAGE:${RESET}"
        echo -e "  ${CYAN}${PROGRAM_NAME} check-update${RESET}\n"
        echo -e "${BOLD}DESCRIPTION:${RESET}"
        echo -e "  Queries upstream git repository to check for available system updates."
        return 0
    fi

    local current_lock="/etc/nixos/flake.lock"
    local remote_repo="https://github.com/adamriofc/NeuronixOS.git"

    log_info "Memeriksa konektivitas jaringan..."
    if ! ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        log_warn "Jaringan offline atau tidak dapat dijangkau. Tidak dapat memeriksa update."
        return 0
    fi

    log_info "Memeriksa rilis upstream dari ${remote_repo}..."
    local remote_head
    remote_head=$(git ls-remote --heads "$remote_repo" main 2>/dev/null | awk '{print $1}')
    if [[ -z "$remote_head" ]]; then
        log_warn "Gagal mengueri repositori upstream."
        return 0
    fi

    local local_head=""
    local repo_root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null || true)"
    if [[ -d "${repo_root}/.git" ]]; then
        local_head=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)
    elif [[ -f "/etc/neuronix/release.json" ]] && command -v jq >/dev/null 2>&1; then
        local_head=$(jq -r '.commit // empty' /etc/neuronix/release.json 2>/dev/null || true)
    elif [[ -f "/etc/nixos/flake.lock" ]] && command -v jq >/dev/null 2>&1; then
        local_head=$(jq -r '.nodes.self.locked.rev // empty' /etc/nixos/flake.lock 2>/dev/null || true)
    fi

    echo -e "  ├─ Upstream Commit SHA : ${CYAN}${remote_head:0:12}${RESET}"
    if [[ -n "$local_head" && "$local_head" == "$remote_head" ]]; then
        echo -e "  ├─ Local System Status : ${GREEN}UP TO DATE (SYNCHRONIZED - ${local_head:0:12})${RESET}"
        echo -e "  └─ Action Recommended  : Sistem mutakhir pada Generasi #$(get_current_generation)."
    elif [[ -n "$local_head" ]]; then
        echo -e "  ├─ Local System Status : ${YELLOW}UPDATE AVAILABLE (Local: ${local_head:0:12} -> Upstream: ${remote_head:0:12})${RESET}"
        echo -e "  └─ Action Recommended  : Jalankan '${CYAN}${PROGRAM_NAME} upgrade${RESET}' untuk menerapkan pembaruan bertahap."
    else
        echo -e "  ├─ Local System Status : ${DIM}UNKNOWN / UNPINNED (Upstream: ${remote_head:0:12})${RESET}"
        echo -e "  └─ Action Recommended  : Jalankan '${CYAN}${PROGRAM_NAME} upgrade${RESET}' untuk menyinkronkan dengan rilis upstream."
    fi
    echo
    log_success "Pemeriksaan pembaruan selesai."
}

cmd_upgrade() {
    print_banner
    log_step "Memulai Orkestrasi Pembaruan Sistem NEURONIX (Atomic Upgrade)..."
    echo

    local mode="staged"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --switch)
                mode="switch"
                shift
                ;;
            --staged|--boot)
                mode="staged"
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}${PROGRAM_NAME} upgrade${RESET} [OPTIONS]\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--staged, --boot${RESET}  Build generation and stage for next boot (Default, zero disruption)"
                echo -e "  ${GREEN}--switch${RESET}          Immediately switch active system symlink to new generation"
                echo -e "  ${GREEN}-h, --help${RESET}        Display this help message\n"
                return 0
                ;;
            *)
                log_error "Opsi tidak dikenali: $1"
                echo -e "Run '${CYAN}${PROGRAM_NAME} upgrade --help${RESET}' for usage."
                return 1
                ;;
        esac
    done

    local config_dir="/etc/nixos"
    if [[ ! -d "$config_dir" && -f "./flake.nix" ]]; then
        config_dir="."
    fi

    acquire_lock "upgrade"

    if [[ "$mode" == "staged" ]]; then
        log_step "1/2. Menjalankan Staged Upgrade via Transaction Core (stage_system_update)..."
        log_info "Generasi baru akan disiapkan di /nix/store dan ditautkan ke bootloader tanpa mengganggu sesi aktif."
        local py_bin core_path
        py_bin="$(resolve_python)"
        core_path="$(resolve_core_path)"

        if [[ -n "$py_bin" && -n "$core_path" ]]; then
            local stage_output stage_code=0
            stage_output="$("$py_bin" -c "
import sys, json
sys.path.insert(0, '${core_path}')
from neuronix_core.update import stage_system_update
ok, code, res = stage_system_update(flake_uri='${config_dir}')
print(json.dumps(res, indent=2))
sys.exit(code)
" 2>&1)" || stage_code=$?

            echo -e "${stage_output}"
            if [[ $stage_code -ne 0 ]]; then
                echo
                log_error "Pembaruan bertahap gagal dibangun (stage_system_update error code: ${stage_code})."
                return $stage_code
            fi
        else
            log_error "Transactional engine unavailable. Refusing unmanaged staged upgrade command."
            return 1
        fi

        echo
        log_step "2/2. Menautkan Generasi Baru ke Bootloader..."
        log_success "Pembaruan bertahap (Staged Upgrade) sukses dibangun dan dijurnalkan!"
        echo -e "  ${GREEN}✔${RESET} Generasi baru akan aktif secara otomatis pada saat komputer dinyalakan kembali (reboot)."
    else
        log_step "1/2. Menjalankan Instant Switch (nixos-rebuild switch)..."
        local py_bin core_path
        py_bin="$(resolve_python)"
        core_path="$(resolve_core_path)"

        if [[ -n "$py_bin" && -n "$core_path" ]]; then
            log_step "Executing transactional upgrade via unified engine (neuronix_core.update)..."
            local up_output up_code=0
            up_output="$("$py_bin" -c "
import sys, json
sys.path.insert(0, '${core_path}')
from neuronix_core.update import apply_system_update
ok, code, res = apply_system_update(flake_uri='${config_dir}', auto_rollback=True)
print(json.dumps(res, indent=2))
sys.exit(code)
" 2>&1)" || up_code=$?

            echo -e "${up_output}"
            if [[ $up_code -eq 0 ]]; then
                echo
                log_step "2/2. Mengaktifkan Generasi Baru..."
                log_success "Sistem berhasil diperbarui dan diverifikasi secara transaksional!"
                return 0
            else
                log_error "Pembaruan sistem gagal atau secara otomatis di-rollback."
                return $up_code
            fi
        else
            log_error "Transactional engine unavailable. Refusing unmanaged switch upgrade command."
            return 1
        fi
    fi
}

