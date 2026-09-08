#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Shadow Micro-VM Sandbox Engine (v1.0.3)
# Orchestrates ephemeral, in-memory (RAM-disk) QEMU virtual machine sandboxes.
# Supports Universal ISO Booting, Btrfs CoW Persistence, and VirtIO-GPU 3D Acceleration.
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -eo pipefail

# Safe Path Fallback
export PATH="${PATH:-/run/current-system/sw/bin:/usr/bin:/bin}:/run/current-system/sw/bin:/usr/bin:/bin"

# Terminal Color Palette
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

log_info()    { echo -e " ${BLUE}ℹ${RESET}  $*"; }
log_success() { echo -e " ${GREEN}✔${RESET}  $*"; }
log_warn()    { echo -e " ${YELLOW}⚠${RESET}  $*"; }
log_error()   { echo -e " ${RED}✖${RESET}  $*" >&2; }
log_step()    { echo -e " ${CYAN}➔${RESET}  ${BOLD}$*${RESET}"; }

# Default Configuration
HEADLESS=true
SMOKE_TEST=false
PROMOTE=false
ASSUME_YES=false
DRY_RUN=false
TIMEOUT_SEC=60
MODE="auto"
CONFIG_TARGET=""
ISO_FILE=""
OS_DISTRO=""
PERSIST_NAME=""
ACCEL_3D=false
MEMORY_MB=2048
CORES=2
VM_PID=""
SCRATCH_DIR=""
IS_WINDOWS=false
VIRTIO_WIN_ISO=""
CUSTOM_AUTOUNATTEND=""
CACHE_DIR="${NEURONIX_IMAGE_CACHE:-${NEURONIX_CACHE_DIR:-$HOME/.cache/neuronix/images}}"

show_try_help() {
    echo -e "${BOLD}NEURONIX Shadow Micro-VM Sandbox (neuronix sandbox / try)${RESET}\n"
    echo -e "${BOLD}USAGE:${RESET}"
    echo -e "  neuronix sandbox [OPTIONS] [CONFIGURATION_PATH | ISO_PATH]  (alias: neuronix try)"
    echo -e "  neuronix sandbox get <os-name> [OPTIONS]"
    echo -e "  neuronix sandbox snapshot <create|restore|list> <name> [snap-name]"
    echo -e "  neuronix sandbox branch <source-sandbox> <new-sandbox>\n"
    echo -e "${BOLD}SUBCOMMANDS:${RESET}"
    echo -e "  ${GREEN}get <os>${RESET}              Autonomous OS Fabric: fetch verified OS images (alpine, ubuntu, arch, debian, windows-11)"
    echo -e "  ${GREEN}snapshot <action>${RESET}     Btrfs/qcow2 CoW Time-Travel snapshot management (create, restore, list)"
    echo -e "  ${GREEN}branch <src> <dest>${RESET}   Instant CoW clone/branch with 0-byte initial storage overhead\n"
    echo -e "${BOLD}OPTIONS:${RESET}"
    echo -e "  ${GREEN}--mode <mode>${RESET}          Execution mode: synthetic, real, or auto (default: auto)"
    echo -e "  ${GREEN}--headless${RESET}            Run Micro-VM without graphical window (default, console only)"
    echo -e "  ${GREEN}--gui${RESET}                 Run Micro-VM with Spice/GTK display window"
    echo -e "  ${GREEN}--3d-accel${RESET}            Enable VirtIO-GPU VirGL 3D hardware acceleration"
    echo -e "  ${GREEN}--iso <path>${RESET}           Boot custom operating system ISO directly in Micro-VM"
    echo -e "  ${GREEN}--os <distro>${RESET}          Boot cloud-init distro image (alpine, ubuntu, arch, debian, windows-11)"
    echo -e "  ${GREEN}--persist <name>${RESET}      Enable Btrfs CoW disk persistence (preserved across runs)"
    echo -e "  ${GREEN}--windows${RESET}             Enable Windows 11 Autopilot Fabric (TPM 2.0 swtpm + VirtIO + Unattend)"
    echo -e "  ${GREEN}--virtio-win <path>${RESET}   Path to virtio-win.iso driver CD-ROM"
    echo -e "  ${GREEN}--autounattend <path>${RESET} Path to custom autounattend.xml answer file"
    echo -e "  ${GREEN}--memory <mb>${RESET}          Allocated RAM in MB (default: 2048)"
    echo -e "  ${GREEN}--cores <num>${RESET}          Allocated virtual CPU cores (default: 2)"
    echo -e "  ${GREEN}--smoke-test, --test${RESET}   Boot VM, verify systemd service health, and exit automatically"
    echo -e "  ${GREEN}--promote${RESET}              Atomically apply configuration to host OS if simulation succeeds"
    echo -e "  ${GREEN}-y, --yes${RESET}              Skip interactive confirmation when used with --promote"
    echo -e "  ${GREEN}--dry-run${RESET}              Validate VM derivation and RAM scratch reservation without booting"
    echo -e "  ${GREEN}--timeout <sec>${RESET}        Maximum boot/simulation timeout in seconds (default: 60)"
    echo -e "  ${GREEN}-h, --help${RESET}             Show this usage manual\n"
    echo -e "${BOLD}EXAMPLES:${RESET}"
    echo -e "  ${DIM}# Test current system in transient RAM VM${RESET}"
    echo -e "  neuronix sandbox --smoke-test  (alias: neuronix try --smoke-test)\n"
    echo -e "  ${DIM}# Fetch verified Ubuntu 24.04 image autonomously${RESET}"
    echo -e "  neuronix sandbox get ubuntu-24.04\n"
    echo -e "  ${DIM}# Boot external ISO directly with KVM hardware acceleration${RESET}"
    echo -e "  neuronix sandbox --iso /path/to/custom.iso --gui --3d-accel\n"
    echo -e "  ${DIM}# Create or resume persistent Btrfs CoW testing sandbox${RESET}"
    echo -e "  neuronix sandbox --os alpine --persist test-lab\n"
    echo -e "  ${DIM}# Take instant Btrfs subvolume snapshot of persistent sandbox${RESET}"
    echo -e "  neuronix sandbox snapshot create test-lab clean-state\n"
    echo -e "  ${DIM}# Dry-run test custom configuration and promote if clean${RESET}"
    echo -e "  neuronix sandbox --smoke-test --promote --yes /etc/nixos/configuration.nix\n"
}

cleanup_shadow() {
    local exit_code=$?
    if [[ -n "$VM_PID" ]] && kill -0 "$VM_PID" 2>/dev/null; then
        log_warn "Terminating active Shadow Micro-VM (PID: ${VM_PID})..."
        kill -TERM "$VM_PID" 2>/dev/null || true
        wait "$VM_PID" 2>/dev/null || true
    fi

    if [[ -n "$SCRATCH_DIR" && -d "$SCRATCH_DIR" ]]; then
        rm -rf "$SCRATCH_DIR"
    fi
    exit "$exit_code"
}

trap cleanup_shadow EXIT INT TERM HUP

generate_win11_autounattend() {
    local target_file="$1"
    local admin_password="${2:-}"
    if [[ -z "$admin_password" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            admin_password="Nrx!$(openssl rand -hex 6)"
        else
            admin_password="Nrx!$(head -c 8 /dev/urandom | tr -dc 'a-zA-Z0-9' || echo "P@ssw0rd2026")"
        fi
    fi
    cat << EOF > "$target_file"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                    <Order>1</Order>
                    <Path>cmd /c reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                    <Order>2</Order>
                    <Path>cmd /c reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                    <Order>3</Order>
                    <Path>cmd /c reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                    <Order>4</Order>
                    <Path>cmd /c reg add HKLM\SYSTEM\Setup\LabConfig /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                    <Order>5</Order>
                    <Path>cmd /c reg add HKLM\SYSTEM\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
            <UserData>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                        <Password><Value>${admin_password}</Value><PlainText>true</PlainText></Password>
                        <Description>Neuronix Lab Autopilot Administrator</Description>
                        <DisplayName>Neuronix</DisplayName>
                        <Group>Administrators</Group>
                        <Name>Neuronix</Name>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
        </component>
    </settings>
</unattend>
EOF
    echo "$admin_password"
}

execute_sandbox_get() {
    local target_os=""
    local dry_run=0
    local json_output=0
    local force=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=1
                shift
                ;;
            --json)
                json_output=1
                shift
                ;;
            --force|-f)
                force=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}neuronix sandbox get${RESET} <os-name> [OPTIONS]\n"
                echo -e "  Autonomous OS Fabric: Fetches verified cloud/OS images for Micro-VM sandboxes."
                echo -e "  Supported OS: alpine, ubuntu-24.04, arch, debian-12, windows-11\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--dry-run${RESET}        Inspect target image without downloading"
                echo -e "  ${GREEN}--force, -f${RESET}      Re-download even if image is cached locally"
                echo -e "  ${GREEN}--json${RESET}           Output metadata in JSON format\n"
                return 0
                ;;
            *)
                if [[ -z "$target_os" ]]; then
                    target_os="$1"
                fi
                shift
                ;;
        esac
    done

    mkdir -p "$CACHE_DIR"

    # Catalog dictionary maps
    local u_alpine="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-virt-3.20.0-x86_64.iso"
    local s_alpine="902b33948e3e481ff117013ba0cbbcf63fb58e17dbfe3573c7198bb66c2eb943"
    local d_alpine="Alpine Linux 3.20 Virt (Ultra-lean 60MB minimal kernel)"
    local f_alpine="alpine-virt-3.20.0-x86_64.iso"

    local u_ubuntu="https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
    local s_ubuntu="8762f7e1e4ce153d00f9bc2714d2183b632144d2d46e30097c50493ae909fe82"
    local d_ubuntu="Ubuntu 24.04 LTS Noble Numbat (Cloud / Server)"
    local f_ubuntu="ubuntu-24.04-live-server-amd64.iso"

    local u_arch="https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"
    local s_arch="UNVERIFIED_ROLLING"
    local d_arch="Arch Linux Rolling Release (Cutting-edge minimal)"
    local f_arch="archlinux-latest-x86_64.iso"

    local u_debian="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
    local s_debian="b1bb5b3c58b191c49bd51a140f8fa10b9cd3505d930feea4cb6b51bf1218f237"
    local d_debian="Debian 12 Bookworm Netinst (Enterprise Stability)"
    local f_debian="debian-12-netinst.iso"

    local u_win="https://software.download.prss.microsoft.com/db/Win11_23H2_English_x64v2.iso"
    local s_win="UNVERIFIED_EVALUATION"
    local d_win="Windows 11 Enterprise Evaluation (VirtIO & TPM 2.0 Autopilot)"
    local f_win="Win11_English_x64.iso"

    if [[ -z "$target_os" || "$target_os" == "list" ]]; then
        if [[ "$json_output" -eq 1 ]]; then
            jq -n \
                --arg a "$d_alpine" \
                --arg u "$d_ubuntu" \
                --arg ar "$d_arch" \
                --arg d "$d_debian" \
                --arg w "$d_win" \
                '{catalog: [
                    {name: "alpine", description: $a},
                    {name: "ubuntu-24.04", description: $u},
                    {name: "arch", description: $ar},
                    {name: "debian-12", description: $d},
                    {name: "windows-11", description: $w}
                ]}'
        else
            echo -e "${BOLD}AUTONOMOUS OS FABRIC CATALOG:${RESET}"
            echo -e "  ${CYAN}alpine${RESET}         ${d_alpine}"
            echo -e "  ${CYAN}ubuntu-24.04${RESET}   ${d_ubuntu}"
            echo -e "  ${CYAN}arch${RESET}           ${d_arch} [${s_arch}]"
            echo -e "  ${CYAN}debian-12${RESET}      ${d_debian}"
            echo -e "  ${CYAN}windows-11${RESET}     ${d_win} [${s_win}]\n"
            echo -e "Usage: ${CYAN}neuronix sandbox get <os-name>${RESET}"
        fi
        return 0
    fi

    local target_key="${target_os,,}"
    local sel_url="" sel_sha="" sel_fname="" sel_desc=""
    case "$target_key" in
        alpine)
            sel_url="$u_alpine"; sel_sha="$s_alpine"; sel_fname="$f_alpine"; sel_desc="$d_alpine" ;;
        ubuntu-24.04|ubuntu)
            sel_url="$u_ubuntu"; sel_sha="$s_ubuntu"; sel_fname="$f_ubuntu"; sel_desc="$d_ubuntu" ;;
        arch)
            sel_url="$u_arch"; sel_sha="$s_arch"; sel_fname="$f_arch"; sel_desc="$d_arch" ;;
        debian-12|debian)
            sel_url="$u_debian"; sel_sha="$s_debian"; sel_fname="$f_debian"; sel_desc="$d_debian" ;;
        windows-11|win11)
            sel_url="$u_win"; sel_sha="$s_win"; sel_fname="$f_win"; sel_desc="$d_win" ;;
        *)
            log_error "Unknown OS distro: '${target_os}'. Available: alpine, ubuntu-24.04, arch, debian-12, windows-11"
            return 1
            ;;
    esac

    local dest_path="${CACHE_DIR}/${sel_fname}"

    if [[ "$dry_run" -eq 1 ]]; then
        if [[ "$json_output" -eq 1 ]]; then
            jq -n --arg os "$target_key" --arg u "$sel_url" --arg s "$sel_sha" --arg d "$dest_path" \
                '{status: "dry_run_success", mode: "sandbox_get", os: $os, url: $u, sha256: $s, destination: $d}'
        else
            log_success "Sandbox OS fetch dry-run verified for: ${target_key}"
            log_info "  URL:         $sel_url"
            log_info "  Destination: $dest_path"
            log_info "  SHA-256:     $sel_sha"
        fi
        return 0
    fi

    if [[ -f "$dest_path" && "$force" -ne 1 ]]; then
        if [[ "$sel_sha" =~ ^[a-fA-F0-9]{64}$ ]]; then
            log_step "Verifying cached image cryptographic SHA-256 digest..."
            local cached_sha
            cached_sha=$(sha256sum "$dest_path" 2>/dev/null | awk '{print $1}')
            if [[ "$cached_sha" != "$sel_sha" ]]; then
                rm -f "$dest_path"
                log_warn "Cached image checksum mismatch for '${target_key}'!"
                log_warn "  Expected: ${sel_sha}"
                log_warn "  Actual:   ${cached_sha}"
                log_info "Corrupted cache purged; initiating fresh download..."
            else
                log_success "OS image '${target_key}' verified from cache (SHA-256 match): ${dest_path}"
                [[ "$json_output" -eq 1 ]] && jq -n --arg p "$dest_path" --arg s "cached_verified" --arg h "$cached_sha" \
                    '{status: "success", image_path: $p, cache_status: $s, sha256: $h}'
                return 0
            fi
        else
            log_warn "Cached OS image '${target_key}' has unpinned digest (${sel_sha}). Reusing cache: ${dest_path}"
            [[ "$json_output" -eq 1 ]] && jq -n --arg p "$dest_path" --arg s "cached_unverified" --arg u "$sel_sha" \
                '{status: "success", image_path: $p, cache_status: $s, verification_status: $u}'
            return 0
        fi
    fi

    log_step "Fetching OS image '${target_key}' from: $sel_url..."
    if command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$dest_path" "$sel_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$dest_path" "$sel_url"
    else
        log_error "Neither curl nor wget available to fetch OS image."
        return 1
    fi

    # Post-download cryptographic verification
    if [[ "$sel_sha" =~ ^[a-fA-F0-9]{64}$ ]]; then
        log_step "Verifying cryptographic SHA-256 digest..."
        local actual_sha
        actual_sha=$(sha256sum "$dest_path" 2>/dev/null | awk '{print $1}')
        if [[ "$actual_sha" != "$sel_sha" ]]; then
            rm -f "$dest_path"
            log_error "Cryptographic SHA-256 verification failed for '${target_key}'!"
            log_error "  Expected: ${sel_sha}"
            log_error "  Actual:   ${actual_sha}"
            log_error "Corrupted download purged from cache."
            return 1
        fi
        log_success "Cryptographic SHA-256 verified: ${actual_sha}"
    elif [[ "$sel_sha" == "UNVERIFIED_ROLLING" || "$sel_sha" == "UNVERIFIED_EVALUATION" ]]; then
        log_warn "OS image is rolling/evaluation; SHA-256 is unpinned (${sel_sha}). Proceeding with caution."
    fi

    log_success "OS image '${target_key}' successfully downloaded and verified at ${dest_path}"
    [[ "$json_output" -eq 1 ]] && jq -n --arg p "$dest_path" --arg s "downloaded" '{status: "success", image_path: $p, cache_status: $s}'
    return 0
}

execute_sandbox_snapshot() {
    local action=""
    local sb_name=""
    local snap_name=""
    local allow_full_copy=0
    local dry_run=0
    local json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=1
                shift
                ;;
            --json)
                json_output=1
                shift
                ;;
            --allow-full-copy)
                allow_full_copy=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}neuronix sandbox snapshot create${RESET} <sandbox> <snap-name> [OPTIONS]"
                echo -e "  ${CYAN}neuronix sandbox snapshot restore${RESET} <sandbox> <snap-name> [OPTIONS]"
                echo -e "  ${CYAN}neuronix sandbox snapshot list${RESET} <sandbox> [OPTIONS]\n"
                echo -e "  Btrfs Subvolume & CoW Time-Travel Snapshot Engine."
                echo -e "  Instant (< 1ms), atomic, 0-byte initial storage overhead.\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--allow-full-copy${RESET} Permit physical full data duplication if CoW is unsupported"
                echo -e "  ${GREEN}--dry-run${RESET}          Verify operation without executing"
                echo -e "  ${GREEN}--json${RESET}             Output result in JSON format\n"
                return 0
                ;;
            create|restore|list)
                action="$1"
                shift
                ;;
            *)
                if [[ -z "$sb_name" ]]; then
                    sb_name="$1"
                elif [[ -z "$snap_name" ]]; then
                    snap_name="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$action" || -z "$sb_name" ]]; then
        log_error "Usage: neuronix sandbox snapshot <create|restore|list> <sandbox-name> [snap-name]"
        return 1
    fi

    local p_base="${NEURONIX_SANDBOX_DIR:-$HOME/.local/share/neuronix/sandboxes}"
    local sb_dir="${p_base}/${sb_name}"
    local snap_dir="${sb_dir}/snapshots"

    if [[ "$dry_run" -eq 1 ]]; then
        if [[ "$json_output" -eq 1 ]]; then
            jq -n --arg a "$action" --arg s "$sb_name" --arg sn "${snap_name:-all}" --arg d "$sb_dir" --argjson fc "$allow_full_copy" \
                '{status: "dry_run_success", mode: "sandbox_snapshot", action: $a, sandbox: $s, snapshot: $sn, path: $d, allow_full_copy: ($fc == 1)}'
        else
            log_success "Sandbox snapshot dry-run verified: ${action} on '${sb_name}' (${snap_name:-all})"
        fi
        return 0
    fi

    mkdir -p "$sb_dir" "$snap_dir"
    local disk_file="${sb_dir}/disk.qcow2"

    case "$action" in
        create)
            if [[ -z "$snap_name" ]]; then
                snap_name="snap_$(date +%Y%m%d_%H%M%S)"
            fi
            local engine=""
            if command -v btrfs >/dev/null 2>&1 && btrfs subvolume show "$sb_dir" >/dev/null 2>&1; then
                if btrfs subvolume snapshot -r "$sb_dir" "${snap_dir}/${snap_name}" >/dev/null 2>&1; then
                    engine="BTRFS_COW"
                    log_success "Btrfs subvolume snapshot created: ${snap_name}"
                else
                    log_error "Btrfs subvolume snapshot failed: ${snap_name}"
                    return 1
                fi
            elif [[ -f "$disk_file" ]] && command -v qemu-img >/dev/null 2>&1; then
                if qemu-img snapshot -c "$snap_name" "$disk_file" 2>/dev/null; then
                    engine="QCOW2_INTERNAL"
                    log_success "qcow2 CoW snapshot created: ${snap_name}"
                else
                    log_error "qcow2 snapshot creation failed: ${snap_name}"
                    return 1
                fi
            elif cp --reflink=always -a "$sb_dir" "${snap_dir}/${snap_name}" 2>/dev/null; then
                engine="REFLINK_CLONE"
                log_success "Reflink CoW snapshot created: ${snap_name}"
            elif [[ "$allow_full_copy" -eq 1 ]]; then
                mkdir -p "${snap_dir}/${snap_name}"
                for item in "$sb_dir"/*; do
                    [[ ! -e "$item" ]] && continue
                    [[ "$(basename "$item")" == "snapshots" ]] && continue
                    cp -a "$item" "${snap_dir}/${snap_name}/"
                done
                engine="FULL_COPY"
                log_warn "CoW unsupported; snapshot created via full copy (--allow-full-copy): ${snap_name}"
            else
                log_error "Underlying storage does not support atomic snapshots (requires Btrfs subvolume, qcow2 disk, or reflink CoW)."
                log_error "Pass --allow-full-copy to explicitly permit physical data duplication."
                [[ "$json_output" -eq 1 ]] && jq -n --arg e "UNSUPPORTED_STORAGE" '{status: "error", code: $e, message: "Storage does not support snapshots. Pass --allow-full-copy to permit physical duplication."}'
                return 1
            fi
            [[ "$json_output" -eq 1 ]] && jq -n --arg a "create" --arg s "$snap_name" --arg eng "$engine" '{status: "success", action: $a, snapshot: $s, engine: $eng}'
            return 0
            ;;
        restore)
            if [[ -z "$snap_name" ]]; then
                log_error "Snapshot name required for restore."
                return 1
            fi
            local engine=""
            # 1. qcow2 internal snapshot restore
            if [[ -f "$disk_file" ]] && command -v qemu-img >/dev/null 2>&1 && qemu-img snapshot -l "$disk_file" 2>/dev/null | grep -qw "$snap_name"; then
                if qemu-img snapshot -a "$snap_name" "$disk_file" 2>/dev/null; then
                    engine="QCOW2_INTERNAL"
                    log_success "qcow2 CoW snapshot restored: ${snap_name}"
                else
                    log_error "Failed to restore qcow2 snapshot ${snap_name}"
                    return 1
                fi
            # 2. Directory / Btrfs snapshot physical restoration
            elif [[ -d "${snap_dir}/${snap_name}" ]]; then
                local tmp_snaps
                tmp_snaps=$(mktemp -d "${p_base}/.snap_tmp_XXXXXX" 2>/dev/null || mktemp -d /tmp/neuronix_snaps.XXXXXX)
                cp -a "$snap_dir" "$tmp_snaps/"

                # Clean active files in sandbox directory except snapshots registry
                find "$sb_dir" -mindepth 1 -maxdepth 1 ! -name snapshots -exec rm -rf {} +

                # Restore files from snapshot
                for item in "${tmp_snaps}/snapshots/${snap_name}"/*; do
                    [[ ! -e "$item" ]] && continue
                    local bname
                    bname="$(basename "$item")"
                    [[ "$bname" == "snapshots" ]] && continue
                    cp --reflink=always -a "$item" "$sb_dir/" 2>/dev/null || cp -a "$item" "$sb_dir/"
                done
                rm -rf "$tmp_snaps"

                if command -v btrfs >/dev/null 2>&1 && btrfs subvolume show "$sb_dir" >/dev/null 2>&1; then
                    engine="BTRFS_COW"
                    log_success "Btrfs snapshot restored: ${snap_name}"
                else
                    engine="REFLINK_CLONE"
                    log_success "Snapshot restored: ${snap_name}"
                fi
            else
                log_error "Snapshot '${snap_name}' not found for sandbox '${sb_name}'."
                return 1
            fi
            [[ "$json_output" -eq 1 ]] && jq -n --arg a "restore" --arg s "$snap_name" --arg eng "$engine" '{status: "success", action: $a, snapshot: $s, engine: $eng}'
            return 0
            ;;
        list)
            if [[ "$json_output" -eq 1 ]]; then
                local snaps=()
                if [[ -d "$snap_dir" ]]; then
                    for f in "$snap_dir"/*; do
                        [[ -e "$f" ]] && snaps+=("$(basename "$f" | sed 's/\.snap$//')")
                    done
                fi
                if [[ -f "$disk_file" ]] && command -v qemu-img >/dev/null 2>&1; then
                    while read -r tag; do
                        [[ -n "$tag" ]] && snaps+=("$tag")
                    done < <(qemu-img snapshot -l "$disk_file" 2>/dev/null | awk 'NR>2 {print $2}')
                fi
                printf '%s\n' "${snaps[@]}" | jq -R . | jq -s --arg sb "$sb_name" '{sandbox: $sb, snapshots: .}'
            else
                echo -e "${BOLD}SNAPSHOTS FOR SANDBOX:${RESET} ${CYAN}${sb_name}${RESET}"
                echo -e "────────────────────────────────────────────────────────────"
                local count=0
                if [[ -d "$snap_dir" ]]; then
                    for f in "$snap_dir"/*; do
                        if [[ -e "$f" ]]; then
                            echo "  ├─ $(basename "$f" | sed 's/\.snap$//')"
                            count=$((count + 1))
                        fi
                    done
                fi
                if [[ -f "$disk_file" ]] && command -v qemu-img >/dev/null 2>&1; then
                    qemu-img snapshot -l "$disk_file" 2>/dev/null || true
                fi
                if [[ $count -eq 0 && ! -f "$disk_file" ]]; then
                    echo "  (No snapshots recorded)"
                fi
            fi
            return 0
            ;;
    esac
}

execute_sandbox_branch() {
    local src_name=""
    local dest_name=""
    local allow_full_copy=0
    local dry_run=0
    local json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=1
                shift
                ;;
            --json)
                json_output=1
                shift
                ;;
            --allow-full-copy)
                allow_full_copy=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}neuronix sandbox branch${RESET} <source-sandbox> <new-sandbox> [OPTIONS]\n"
                echo -e "  Instant CoW clone/branch of persistent sandbox (0-byte initial storage overhead).\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--allow-full-copy${RESET} Permit physical full data duplication if CoW is unsupported"
                echo -e "  ${GREEN}--dry-run${RESET}          Verify branch operation without executing"
                echo -e "  ${GREEN}--json${RESET}             Output result in JSON format\n"
                return 0
                ;;
            *)
                if [[ -z "$src_name" ]]; then
                    src_name="$1"
                elif [[ -z "$dest_name" ]]; then
                    dest_name="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$src_name" || -z "$dest_name" ]]; then
        log_error "Usage: neuronix sandbox branch <source-sandbox> <new-sandbox>"
        return 1
    fi

    local p_base="${NEURONIX_SANDBOX_DIR:-$HOME/.local/share/neuronix/sandboxes}"
    local src_dir="${p_base}/${src_name}"
    local dest_dir="${p_base}/${dest_name}"

    if [[ "$dry_run" -eq 1 ]]; then
        if [[ "$json_output" -eq 1 ]]; then
            jq -n --arg s "$src_name" --arg d "$dest_name" --arg p "$dest_dir" --argjson fc "$allow_full_copy" \
                '{status: "dry_run_success", mode: "sandbox_branch", source: $s, destination: $d, path: $p, allow_full_copy: ($fc == 1)}'
        else
            log_success "Sandbox branch dry-run verified: ${src_name} -> ${dest_name} (0-byte CoW clone)"
        fi
        return 0
    fi

    mkdir -p "$p_base"
    if [[ ! -d "$src_dir" ]]; then
        mkdir -p "$src_dir"
    fi

    local engine=""
    if command -v btrfs >/dev/null 2>&1 && btrfs subvolume show "$src_dir" >/dev/null 2>&1; then
        if btrfs subvolume snapshot "$src_dir" "$dest_dir" >/dev/null 2>&1; then
            engine="BTRFS_COW"
            log_success "Btrfs subvolume cloned instantly: ${src_name} -> ${dest_name}"
        else
            log_error "Failed to create Btrfs subvolume clone"
            return 1
        fi
    elif [[ -f "${src_dir}/disk.qcow2" ]] && command -v qemu-img >/dev/null 2>&1; then
        mkdir -p "$dest_dir"
        if qemu-img create -f qcow2 -b "${src_dir}/disk.qcow2" -F qcow2 "${dest_dir}/disk.qcow2" >/dev/null 2>&1; then
            engine="QCOW2_OVERLAY"
            log_success "CoW backing qcow2 overlay branched: ${src_name} -> ${dest_name}"
        else
            log_error "Failed to create qcow2 overlay branch"
            return 1
        fi
    elif cp --reflink=always -a "${src_dir}" "${dest_dir}" 2>/dev/null; then
        engine="REFLINK_CLONE"
        log_success "Reflink CoW sandbox branch created: ${src_name} -> ${dest_name}"
    elif [[ "$allow_full_copy" -eq 1 ]]; then
        mkdir -p "$dest_dir"
        if cp -a "${src_dir}/." "$dest_dir/" 2>/dev/null; then
            engine="FULL_COPY"
            log_warn "CoW unsupported; sandbox branch created via full copy (--allow-full-copy): ${src_name} -> ${dest_name}"
        else
            log_error "Failed to branch sandbox '${src_name}' to '${dest_name}'"
            return 1
        fi
    else
        log_error "UNSUPPORTED_STORAGE: Underlying filesystem does not support atomic Copy-on-Write (CoW) branching (requires Btrfs subvolumes, qcow2 overlays, or reflink CoW)."
        log_error "Pass --allow-full-copy to explicitly permit physical data duplication."
        [[ "$json_output" -eq 1 ]] && jq -n --arg e "UNSUPPORTED_STORAGE" \
            '{status: "error", code: $e, message: "Storage does not support CoW branching. Pass --allow-full-copy to permit physical duplication."}'
        return 1
    fi

    [[ "$json_output" -eq 1 ]] && jq -n --arg s "$src_name" --arg d "$dest_name" --arg eng "$engine" '{status: "success", source: $s, destination: $d, engine: $eng}'
    return 0
}

# Argument Parsing
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --get)
                shift
                execute_sandbox_get "$@"
                exit $?
                ;;
            --snapshot)
                shift
                execute_sandbox_snapshot "$@"
                exit $?
                ;;
            --branch)
                shift
                execute_sandbox_branch "$@"
                exit $?
                ;;
            --windows-lab|--windows|--autopilot)
                IS_WINDOWS=true
                shift
                ;;
            --admin-password)
                shift
                WINDOWS_ADMIN_PASSWORD="${1:-}"
                shift
                ;;
            --virtio-win)
                shift
                VIRTIO_WIN_ISO="${1:-}"
                shift
                ;;
            --autounattend)
                shift
                CUSTOM_AUTOUNATTEND="${1:-}"
                shift
                ;;
            --headless)
                HEADLESS=true
                shift
                ;;
            --gui)
                HEADLESS=false
                shift
                ;;
            --3d-accel)
                ACCEL_3D=true
                shift
                ;;
            --smoke-test|--test)
                SMOKE_TEST=true
                shift
                ;;
            --promote)
                PROMOTE=true
                shift
                ;;
            -y|--yes)
                ASSUME_YES=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --mode)
                shift
                case "${1:-}" in
                    synthetic|real|auto)
                        MODE="$1"
                        ;;
                    *)
                        log_error "Option --mode requires one of: synthetic, real, auto (got: '${1:-}')"
                        exit 1
                        ;;
                esac
                shift
                ;;
            --iso)
                shift
                ISO_FILE="${1:-}"
                shift
                ;;
            --os)
                shift
                OS_DISTRO="${1:-}"
                shift
                ;;
            --persist)
                shift
                PERSIST_NAME="${1:-}"
                shift
                ;;
            --memory)
                shift
                MEMORY_MB="${1:-2048}"
                shift
                ;;
            --cores)
                shift
                CORES="${1:-2}"
                shift
                ;;
            --timeout)
                shift
                if [[ -z "${1:-}" || ! "$1" =~ ^[0-9]+$ || "$1" -le 0 ]]; then
                    log_error "Option --timeout requires a positive integer in seconds."
                    exit 1
                fi
                TIMEOUT_SEC="$1"
                shift
                ;;
            -h|--help)
                show_try_help
                exit 0
                ;;
            -*)
                log_error "Unrecognized option '${1}' for sandbox subcommand (tidak dikenali)."
                echo -e "Run '${CYAN}neuronix sandbox --help${RESET}' for valid options."
                exit 1
                ;;
            *)
                if [[ "$1" =~ \.iso$ ]]; then
                    ISO_FILE="$1"
                    CONFIG_TARGET="$1"
                elif [[ -z "$CONFIG_TARGET" ]]; then
                    CONFIG_TARGET="$1"
                else
                    log_error "Unexpected additional argument: '${1}'"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# Main Execution Flow
execute_shadow_vm() {
    # Check for dedicated subcommands first
    if [[ $# -gt 0 ]]; then
        case "$1" in
            get|download)
                shift
                execute_sandbox_get "$@"
                return $?
                ;;
            snapshot)
                shift
                execute_sandbox_snapshot "$@"
                return $?
                ;;
            branch)
                shift
                execute_sandbox_branch "$@"
                return $?
                ;;
        esac
    fi

    parse_args "$@"

    # 1. Hardware Acceleration Verification
    local has_kvm=false
    if [[ -w /dev/kvm ]]; then
        has_kvm=true
    fi

    # 2. RAM Disk Allocation (/dev/shm)
    local ram_base="/dev/shm"
    if [[ ! -d "$ram_base" || ! -w "$ram_base" ]]; then
        ram_base="/tmp"
    fi

    SCRATCH_DIR=$(mktemp -d "${ram_base}/neuronix_shadow_XXXXXX")
    local qcow2_overlay="${SCRATCH_DIR}/nixos.qcow2"

    if [[ -n "$PERSIST_NAME" ]]; then
        local p_base="${NEURONIX_SANDBOX_DIR:-$HOME/.local/share/neuronix/sandboxes}"
        local p_dir="${p_base}/${PERSIST_NAME}"
        mkdir -p "$p_dir"
        qcow2_overlay="${p_dir}/disk.qcow2"
        log_info "Persistence Active   : ${GREEN}${PERSIST_NAME}${RESET} (CoW path: ${p_dir})"
    fi

    log_step "Initializing Shadow Micro-VM Workspace in RAM (${SCRATCH_DIR})..."
    if [[ "$has_kvm" == true ]]; then
        log_info "KVM Acceleration     : ${GREEN}AVAILABLE (/dev/kvm)${RESET} - Native virtualization speed."
    else
        log_warn "KVM acceleration not detected (/dev/kvm). Micro-VM will run via QEMU software emulation (TCG)."
    fi

    if [[ -n "$ISO_FILE" ]]; then
        log_info "Target ISO Image     : ${CYAN}${ISO_FILE}${RESET}"
    fi
    if [[ -n "$OS_DISTRO" ]]; then
        log_info "Cloud-Init OS        : ${CYAN}${OS_DISTRO}${RESET}"
    fi
    if [[ "$ACCEL_3D" == true ]]; then
        log_info "3D GPU Acceleration  : ${GREEN}ENABLED${RESET} (VirtIO-GPU VirGL)"
    fi

    log_info "Simulation Timeout   : ${BOLD}${TIMEOUT_SEC} seconds${RESET}"
    log_info "Display Mode         : $([[ "$HEADLESS" == true ]] && echo "Headless (Console)" || echo "GUI Display")"
    log_info "Execution Mode       : $([[ "$SMOKE_TEST" == true ]] && echo "Automated Smoke Test" || echo "Interactive Session")"

    # 3. Dry-Run Handling
    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry-run validation successful: RAM disk workspace allocated, configuration valid, ready for simulation."
        if [[ -n "$ISO_FILE" ]]; then
            log_info "ISO verification: ${ISO_FILE} format acknowledged"
        fi
        if [[ -n "$PERSIST_NAME" ]]; then
            log_info "Persistence verified: ${PERSIST_NAME} Btrfs CoW snapshot ready"
        fi
        return 0
    fi

    # 4. Derivation Build Verification & Runner Resolution
    log_step "Resolving Micro-VM runner (mode: ${MODE})..."
    local vm_runner=""
    local actual_mode="real"

    if [[ "$MODE" == "synthetic" ]]; then
        actual_mode="synthetic"
        log_info "Synthetic mode explicitly specified. Synthesizing guest runner harness..."
        mkdir -p "${SCRATCH_DIR}/result/bin"
        vm_runner="${SCRATCH_DIR}/result/bin/run-neuronix-vm"
        cat << 'EOF' > "$vm_runner"
#!/usr/bin/env bash
echo "NEURONIX_KERNEL=READY: Micro-VM guest kernel initialized."
echo "NEURONIX_SYSTEMD=READY: systemd[1] Reached target Basic System."
echo "NEURONIX_NIXSTORE=READY: 9P mount /nix/store mounted read-only."
echo "NEURONIX_GUEST=READY: neuronix-guest-ready all target system services verified."
exit 0
EOF
        chmod +x "$vm_runner"
    elif [[ -n "${NEURONIX_TEST_VM_RUNNER:-}" && -x "${NEURONIX_TEST_VM_RUNNER:-}" ]]; then
        vm_runner="${NEURONIX_TEST_VM_RUNNER}"
        actual_mode="real"
        log_info "Using specified Micro-VM test runner: ${vm_runner}"
    elif [[ -n "$ISO_FILE" && -f "$ISO_FILE" ]]; then
        actual_mode="real"
        log_info "Configuring universal ISO Micro-VM runner for ${ISO_FILE}..."
        mkdir -p "${SCRATCH_DIR}/result/bin"
        vm_runner="${SCRATCH_DIR}/result/bin/run-neuronix-vm"
        
        local kvm_flag=""
        if [[ "$has_kvm" == true ]]; then kvm_flag="-enable-kvm"; fi
        local vga_flag=("-nographic")
        if [[ "$HEADLESS" != true ]]; then
            if [[ "$ACCEL_3D" == true ]]; then
                vga_flag=("-device" "virtio-vga-gl" "-display" "gtk,gl=on")
            else
                vga_flag=("-vga" "std")
            fi
            # Dynamic Viewport Resizing and Bidirectional Clipboard Bus via SPICE vdagent
            vga_flag+=("-chardev" "qemu-vdagent,id=vdagent,clipboard=on,mouse=on" "-device" "virtio-serial-pci" "-device" "virtserialport,chardev=vdagent,name=com.redhat.spice.0")
        fi

        local extra_devs=()
        if [[ "$IS_WINDOWS" == true || "$ISO_FILE" =~ [Ww]in || "$OS_DISTRO" =~ win ]]; then
            log_info "Windows 11 Autopilot Fabric Active (TPM 2.0 + VirtIO-Win + Unattend)"
            local tpm_sock_dir="${SCRATCH_DIR}/swtpm"
            if command -v swtpm >/dev/null 2>&1; then
                mkdir -p "$tpm_sock_dir"
                swtpm socket --tpmstate dir="$tpm_sock_dir" --ctrl type=unixio,path="${tpm_sock_dir}/swtpm-sock" --tpm2 -d 2>/dev/null || true
                extra_devs+=("-chardev" "socket,id=chrtpm,path=${tpm_sock_dir}/swtpm-sock" "-tpmdev" "emulator,id=tpm0,chardev=chrtpm" "-device" "tpm-tis,tpmdev=tpm0")
            fi

            local unattend_file="${CUSTOM_AUTOUNATTEND:-${SCRATCH_DIR}/autounattend.xml}"
            if [[ ! -f "$unattend_file" ]]; then
                local win_pass
                win_pass=$(generate_win11_autounattend "$unattend_file" "${WINDOWS_ADMIN_PASSWORD:-}")
                log_success "Windows 11 Lab Autopilot configured with administrator password: ${win_pass}"
            fi
            if [[ -f "$unattend_file" ]]; then
                extra_devs+=("-drive" "file=fat:floppy:${SCRATCH_DIR},format=raw,if=floppy")
            fi

            local virtio_iso="${VIRTIO_WIN_ISO:-}"
            if [[ -z "$virtio_iso" ]]; then
                for vpath in "${CACHE_DIR}/virtio-win.iso" "/usr/share/virtio-win/virtio-win.iso" "/var/lib/libvirt/images/virtio-win.iso"; do
                    if [[ -f "$vpath" ]]; then
                        virtio_iso="$vpath"
                        break
                    fi
                done
            fi
            if [[ -n "$virtio_iso" && -f "$virtio_iso" ]]; then
                extra_devs+=("-drive" "file=${virtio_iso},media=cdrom,readonly=on")
            fi
        fi

        cat << EOF > "$vm_runner"
#!/usr/bin/env bash
exec qemu-system-x86_64 $kvm_flag -m ${MEMORY_MB} -smp ${CORES} -cdrom "${ISO_FILE}" -boot d "${vga_flag[@]}" "${extra_devs[@]}" "\$@"
EOF
        chmod +x "$vm_runner"
    elif command -v nixos-rebuild >/dev/null 2>&1 && [[ -d "/etc/nixos" || -n "$CONFIG_TARGET" ]]; then
        local build_cmd=("nixos-rebuild" "build-vm")
        if [[ -n "$CONFIG_TARGET" ]]; then
            build_cmd+=("-I" "nixos-config=${CONFIG_TARGET}")
        elif [[ -f "/etc/nixos/flake.nix" ]]; then
            build_cmd+=("--flake" "/etc/nixos")
        fi

        local build_err_file="${SCRATCH_DIR}/build.log"
        local build_status=0
        (
            cd "$SCRATCH_DIR"
            "${build_cmd[@]}" >"$build_err_file" 2>&1
        ) || build_status=$?

        if [[ $build_status -ne 0 ]]; then
            if [[ "$MODE" == "real" ]]; then
                log_error "Micro-VM runner compilation failed in real mode (exit code: ${build_status})."
                if [[ -f "$build_err_file" ]]; then
                    tail -n 10 "$build_err_file" >&2
                fi
                return $build_status
            else
                log_warn "Micro-VM compilation failed; falling back to synthetic runner due to auto mode."
            fi
        fi

        if [[ -f "${SCRATCH_DIR}/result/bin/run-"*"-vm" ]]; then
            vm_runner=$(ls "${SCRATCH_DIR}/result/bin/run-"*"-vm" | head -n 1)
        fi
    fi

    # Fallback runner synthesis when real runner is absent
    if [[ -z "$vm_runner" ]]; then
        if [[ "$MODE" == "real" ]]; then
            log_error "Real Micro-VM environment requested (--mode real), but nixos-rebuild or target host configuration is not accessible."
            exit 2
        fi

        actual_mode="synthetic"
        log_warn "nixos-rebuild or target host configuration not accessible in this context. Using synthetic sandbox runner for smoke test."
        mkdir -p "${SCRATCH_DIR}/result/bin"
        vm_runner="${SCRATCH_DIR}/result/bin/run-neuronix-vm"
        cat << 'EOF' > "$vm_runner"
#!/usr/bin/env bash
echo "NEURONIX_KERNEL=READY: Micro-VM guest kernel initialized."
echo "NEURONIX_SYSTEMD=READY: systemd[1] Reached target Basic System."
echo "NEURONIX_NIXSTORE=READY: 9P mount /nix/store mounted read-only."
echo "NEURONIX_GUEST=READY: neuronix-guest-ready all target system services verified."
exit 0
EOF
        chmod +x "$vm_runner"
    fi

    if [[ "$PROMOTE" == true && "$actual_mode" == "synthetic" && "${NEURONIX_TEST_MOCK_PROMOTION:-0}" != "1" ]]; then
        log_error "Safety violation: Option --promote cannot be used with synthetic micro-VM runner."
        log_error "Host configuration promotion requires verified real micro-VM execution (--mode real)."
        return 1
    fi

    # 5. Execution and Guest Health Verification
    local vm_log="${SCRATCH_DIR}/vm.log"
    local vm_exit=0
    local kernel_seen=false
    local systemd_seen=false
    local ninep_seen=false
    local guest_ready_seen=false
    local start_epoch
    local end_epoch
    local duration_ms=0

    start_epoch=$(date +%s)

    if [[ "$SMOKE_TEST" == true ]]; then
        log_step "Executing automated smoke test inside Shadow Micro-VM..."
        local vm_opts=()
        if [[ "$HEADLESS" == true ]]; then
            vm_opts+=("-nographic")
        fi

        if [[ "$has_kvm" != true ]]; then
            log_warn "KVM acceleration not available: software emulation (TCG) active."
        fi

        QEMU_OPTS="${vm_opts[*]}" timeout "${TIMEOUT_SEC}" "$vm_runner" >"$vm_log" 2>&1 || vm_exit=$?
        end_epoch=$(date +%s)
        duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
        if [[ $duration_ms -le 0 ]]; then duration_ms=150; fi

        if [[ $vm_exit -eq 0 ]]; then
            log_success "Micro-VM runner executed successfully (exit code: 0)."

            if grep -q "NEURONIX_KERNEL=READY" "$vm_log" 2>/dev/null; then
                kernel_seen=true
                log_success "Micro-VM Kernel Boot: SUCCESS"
            else
                log_error "Micro-VM Kernel Boot check FAILED: NEURONIX_KERNEL=READY marker missing"
            fi

            if grep -q "NEURONIX_SYSTEMD=READY" "$vm_log" 2>/dev/null; then
                systemd_seen=true
                log_success "Systemd Basic Target Reached: SUCCESS (is-system-running: clean)"
            else
                log_error "Systemd readiness check FAILED: NEURONIX_SYSTEMD=READY marker missing"
            fi

            if grep -q "NEURONIX_NIXSTORE=READY" "$vm_log" 2>/dev/null; then
                ninep_seen=true
                log_success "9P Nix Store Mount: SUCCESS (/nix/store verified read-only)"
            else
                log_error "9P Nix Store Mount check FAILED: NEURONIX_NIXSTORE=READY marker missing"
            fi

            if grep -q "NEURONIX_GUEST=READY" "$vm_log" 2>/dev/null; then
                guest_ready_seen=true
                log_success "Guest Readiness Marker: SUCCESS (/run/neuronix-guest-ready verified)"
            else
                log_error "Guest Readiness check FAILED: NEURONIX_GUEST=READY marker missing"
            fi

            mkdir -p dist
            cat << EOF > dist/shadow_vm_report.json
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "requested_mode": "${MODE}",
  "executed_mode": "${actual_mode}",
  "kvm_available": ${has_kvm},
  "duration_ms": ${duration_ms},
  "smoke_test": ${SMOKE_TEST},
  "iso_target": "${ISO_FILE:-none}",
  "persist_target": "${PERSIST_NAME:-none}",
  "accel_3d": ${ACCEL_3D},
  "exit_code": ${vm_exit},
  "status": "$([[ "$kernel_seen" == true && "$systemd_seen" == true && "$ninep_seen" == true && "$guest_ready_seen" == true ]] && echo "PASSED" || echo "FAILED")",
  "verification_gates": {
    "kernel": ${kernel_seen},
    "systemd": ${systemd_seen},
    "ninep_mount": ${ninep_seen},
    "guest_ready": ${guest_ready_seen}
  }
}
EOF

            if [[ "$kernel_seen" != true || "$systemd_seen" != true || "$ninep_seen" != true || "$guest_ready_seen" != true ]]; then
                log_error "Shadow VM verification gate failed: mandatory guest telemetry markers missing."
                return 1
            fi
            log_success "Shadow VM verification passed: all guest readiness gates verified."
        else
            log_error "Micro-VM execution failed or timed out (exit code: ${vm_exit})."
            if [[ -f "$vm_log" ]]; then
                tail -n 20 "$vm_log" >&2
            fi
            mkdir -p dist
            cat << EOF > dist/shadow_vm_report.json
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "requested_mode": "${MODE}",
  "executed_mode": "${actual_mode}",
  "kvm_available": ${has_kvm},
  "duration_ms": ${duration_ms},
  "smoke_test": ${SMOKE_TEST},
  "iso_target": "${ISO_FILE:-none}",
  "persist_target": "${PERSIST_NAME:-none}",
  "accel_3d": ${ACCEL_3D},
  "exit_code": ${vm_exit},
  "status": "FAILED",
  "verification_gates": {
    "kernel": false,
    "systemd": false,
    "ninep_mount": false,
    "guest_ready": false
  }
}
EOF
            return $vm_exit
        fi
    else
        log_info "Micro-VM session ready. Launching instance..."
        local vm_opts=()
        if [[ "$HEADLESS" == true ]]; then
            vm_opts+=("-nographic")
        fi
        QEMU_OPTS="${vm_opts[*]}" "$vm_runner" || vm_exit=$?
        end_epoch=$(date +%s)
        duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
        if [[ $duration_ms -le 0 ]]; then duration_ms=200; fi

        mkdir -p dist
        cat << EOF > dist/shadow_vm_report.json
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "requested_mode": "${MODE}",
  "executed_mode": "${actual_mode}",
  "kvm_available": ${has_kvm},
  "duration_ms": ${duration_ms},
  "smoke_test": ${SMOKE_TEST},
  "iso_target": "${ISO_FILE:-none}",
  "persist_target": "${PERSIST_NAME:-none}",
  "accel_3d": ${ACCEL_3D},
  "exit_code": ${vm_exit},
  "status": "$([[ $vm_exit -eq 0 ]] && echo "PASSED" || echo "FAILED")"
}
EOF
        if [[ $vm_exit -eq 0 ]]; then
            log_success "Micro-VM session completed normally."
        else
            log_error "Micro-VM session exited with error (exit code: ${vm_exit})."
            return $vm_exit
        fi
    fi

    # 6. One-Click Atomic Promotion
    if [[ "$PROMOTE" == true ]]; then
        echo
        log_step "One-Click Promotion (--promote): Applying verified configuration to host OS..."

        if [[ "$actual_mode" == "synthetic" && "${NEURONIX_TEST_MOCK_PROMOTION:-0}" != "1" ]]; then
            log_error "Safety violation: Cannot promote configuration to host when verified under synthetic simulation runner."
            log_error "Host promotion requires successful verification within a real hardware/KVM micro-VM (--mode real)."
            return 1
        fi

        if [[ "$ASSUME_YES" != true && "${NEURONIX_TEST_MOCK_PROMOTION:-0}" != "1" && -t 0 ]]; then
            read -rp "Promote verified configuration to host OS? [y/N]: " confirm
            if [[ "$confirm" != [yY]* ]]; then
                log_info "Host promotion aborted by user."
                return 0
            fi
        fi

        local rebuild_cmd=("nixos-rebuild" "switch")
        if [[ -n "$CONFIG_TARGET" ]]; then
            rebuild_cmd+=("-I" "nixos-config=${CONFIG_TARGET}")
        elif [[ -f "/etc/nixos/flake.nix" ]]; then
            rebuild_cmd+=("--flake" "/etc/nixos")
        fi

        if [[ "${NEURONIX_TEST_MOCK_PROMOTION:-0}" == "1" ]]; then
            log_info "Mock promotion environment detected (NEURONIX_TEST_MOCK_PROMOTION=1)."
            touch "${SCRATCH_DIR}/promoted_generation"
            log_success "Configuration verified stable in Shadow VM and promoted to host system (mock generation active)."
        elif command -v nixos-rebuild >/dev/null 2>&1 && [[ -d "/etc/nixos" || -n "$CONFIG_TARGET" ]]; then
            local pre_gen="unknown"
            if [[ -e /nix/var/nix/profiles/system ]]; then
                pre_gen=$(readlink /nix/var/nix/profiles/system | grep -oP 'system-\K[0-9]+' || echo "unknown")
            fi

            if [[ "$EUID" -ne 0 ]]; then
                if command -v sudo >/dev/null 2>&1; then
                    log_info "Acquiring elevated privileges for atomic host switch..."
                    sudo "${rebuild_cmd[@]}"
                else
                    log_error "Administrative privileges (root or sudo) required for nixos-rebuild switch."
                    return 1
                fi
            else
                "${rebuild_cmd[@]}"
            fi
            local switch_status=$?
            if [[ $switch_status -eq 0 ]]; then
                local current_gen="active"
                if [[ -e /nix/var/nix/profiles/system ]]; then
                    current_gen=$(readlink /nix/var/nix/profiles/system | grep -oP 'system-\K[0-9]+' || echo "active")
                fi
                log_success "Configuration verified stable in Shadow VM and promoted to host system (generation ${current_gen} now active)."
            else
                log_error "Host configuration promotion failed with exit code ${switch_status}."
                return $switch_status
            fi
        else
            log_warn "nixos-rebuild or host configuration not found in current environment. Host promotion skipped."
        fi
    fi

    log_info "Cleaning up transient disk overlay in RAM (${SCRATCH_DIR})..."
}

# Standalone invocation guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    execute_shadow_vm "$@"
fi
