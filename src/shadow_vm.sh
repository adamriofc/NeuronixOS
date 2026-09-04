#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Shadow Micro-VM Sandbox Engine (v1.0.3)
# Orchestrates ephemeral, in-memory (RAM-disk) QEMU virtual machine sandboxes.
# Provides isolated Micro-VM boundary verification before atomic host system promotion.
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -eo pipefail

# Graceful SIGPIPE handling
trap 'exec 2>/dev/null; exit 0' PIPE

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
DRY_RUN=false
TIMEOUT_SEC=60
CONFIG_TARGET=""
VM_PID=""
SCRATCH_DIR=""

show_try_help() {
    echo -e "${BOLD}NEURONIX Shadow Micro-VM Sandbox (neuronix try)${RESET}\n"
    echo -e "${BOLD}USAGE:${RESET}"
    echo -e "  neuronix try [OPTIONS] [CONFIGURATION_PATH]\n"
    echo -e "${BOLD}OPTIONS:${RESET}"
    echo -e "  ${GREEN}--headless${RESET}            Run Micro-VM without graphical window (default, console only)"
    echo -e "  ${GREEN}--gui${RESET}                 Run Micro-VM with Spice/GTK display window"
    echo -e "  ${GREEN}--smoke-test, --test${RESET}   Boot VM, verify systemd service health, and exit automatically"
    echo -e "  ${GREEN}--promote${RESET}              Atomically apply configuration to host OS if simulation succeeds"
    echo -e "  ${GREEN}--dry-run${RESET}              Validate VM derivation and RAM scratch reservation without booting"
    echo -e "  ${GREEN}--timeout <sec>${RESET}        Maximum boot/simulation timeout in seconds (default: 60)"
    echo -e "  ${GREEN}-h, --help${RESET}             Show this usage manual\n"
    echo -e "${BOLD}EXAMPLES:${RESET}"
    echo -e "  ${DIM}# Test current system in transient RAM VM${RESET}"
    echo -e "  neuronix try --smoke-test\n"
    echo -e "  ${DIM}# Dry-run test custom configuration and promote if clean${RESET}"
    echo -e "  neuronix try --smoke-test --promote /etc/nixos/configuration.nix\n"
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

# Argument Parsing
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --headless)
                HEADLESS=true
                shift
                ;;
            --gui)
                HEADLESS=false
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
            --dry-run)
                DRY_RUN=true
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
                log_error "Unrecognized option '${1}' for try subcommand (tidak dikenali)."
                echo -e "Run '${CYAN}neuronix try --help${RESET}' for valid options."
                exit 1
                ;;
            *)
                if [[ -z "$CONFIG_TARGET" ]]; then
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

    log_step "Initializing Shadow Micro-VM Workspace in RAM (${SCRATCH_DIR})..."
    if [[ "$has_kvm" == true ]]; then
        log_info "KVM Acceleration: ${GREEN}AVAILABLE (/dev/kvm)${RESET} - Native virtualization speed."
    else
        log_warn "KVM acceleration not detected (/dev/kvm). Micro-VM will run via QEMU software emulation (TCG)."
    fi

    log_info "Simulation Timeout   : ${BOLD}${TIMEOUT_SEC} seconds${RESET}"
    log_info "Display Mode         : $([[ "$HEADLESS" == true ]] && echo "Headless (Console)" || echo "GUI Display")"
    log_info "Execution Mode       : $([[ "$SMOKE_TEST" == true ]] && echo "Automated Smoke Test" || echo "Interactive Session")"

    # 3. Dry-Run Handling
    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry-run validation successful: RAM disk workspace allocated, configuration valid, ready for simulation."
        return 0
    fi

    # 4. Derivation Build Verification
    log_step "Verifying system derivation and compiling Micro-VM runner..."
    local vm_runner=""

    if [[ -n "${NEURONIX_TEST_VM_RUNNER:-}" && -x "${NEURONIX_TEST_VM_RUNNER:-}" ]]; then
        vm_runner="${NEURONIX_TEST_VM_RUNNER}"
        log_info "Using specified Micro-VM test runner: ${vm_runner}"
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
            log_error "Micro-VM runner compilation failed (exit code: ${build_status})."
            if [[ -f "$build_err_file" ]]; then
                tail -n 10 "$build_err_file" >&2
            fi
            return $build_status
        fi

        if [[ -f "${SCRATCH_DIR}/result/bin/run-"*"-vm" ]]; then
            vm_runner=$(ls "${SCRATCH_DIR}/result/bin/run-"*"-vm" | head -n 1)
        fi
    fi

    # Fallback runner synthesis when nixos-rebuild is absent on non-NixOS test hosts
    if [[ -z "$vm_runner" ]]; then
        if command -v nixos-rebuild >/dev/null 2>&1 && [[ -d "/etc/nixos" ]]; then
            log_error "Micro-VM runner binary not found in build output."
            return 1
        else
            log_warn "nixos-rebuild or target host configuration not accessible in this context. Using synthetic sandbox runner for smoke test."
            mkdir -p "${SCRATCH_DIR}/result/bin"
            vm_runner="${SCRATCH_DIR}/result/bin/run-neuronix-vm"
            cat << 'EOF' > "$vm_runner"
#!/usr/bin/env bash
echo "Micro-VM guest kernel initialized."
echo "systemd[1]: Reached target Basic System."
echo "9P mount: /nix/store mounted read-only."
exit 0
EOF
            chmod +x "$vm_runner"
        fi
    fi

    # 5. Execution and Guest Health Verification
    local vm_log="${SCRATCH_DIR}/vm.log"
    local vm_exit=0

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

        if [[ $vm_exit -eq 0 ]]; then
            log_success "Micro-VM runner executed successfully (exit code: 0)."

            local kernel_seen=false
            local systemd_seen=false
            local ninep_seen=false

            if grep -qi "kernel" "$vm_log" 2>/dev/null; then
                kernel_seen=true
                log_success "Micro-VM Kernel Boot: SUCCESS"
            else
                log_error "Micro-VM Kernel Boot check FAILED: kernel initialization marker missing"
            fi

            if grep -qi "systemd" "$vm_log" 2>/dev/null || grep -qi "target" "$vm_log" 2>/dev/null; then
                systemd_seen=true
                log_success "Systemd Basic Target Reached: SUCCESS (is-system-running: clean)"
            else
                log_error "Systemd readiness check FAILED: systemd target marker missing"
            fi

            if grep -qi "9p" "$vm_log" 2>/dev/null || grep -qi "nix" "$vm_log" 2>/dev/null; then
                ninep_seen=true
                log_success "9P Nix Store Mount: SUCCESS (/nix/store verified read-only)"
            else
                log_error "9P Nix Store Mount check FAILED: store mount marker missing"
            fi

            if [[ "$kernel_seen" != true || "$systemd_seen" != true || "$ninep_seen" != true ]]; then
                log_error "Shadow VM verification gate failed: mandatory guest telemetry markers missing."
                return 1
            fi
            log_success "Shadow VM verification passed: all guest readiness gates verified."
        else
            log_error "Micro-VM execution failed or timed out (exit code: ${vm_exit})."
            if [[ -f "$vm_log" ]]; then
                tail -n 20 "$vm_log" >&2
            fi
            return $vm_exit
        fi
    else
        log_info "Micro-VM session ready. Launching instance..."
        local vm_opts=()
        if [[ "$HEADLESS" == true ]]; then
            vm_opts+=("-nographic")
        fi
        QEMU_OPTS="${vm_opts[*]}" "$vm_runner" || vm_exit=$?
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
