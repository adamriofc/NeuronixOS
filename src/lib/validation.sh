#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Library: Substrate Path & Runtime Validation
# Part of Phase 4 Distribution Architecture
# ==============================================================================

resolve_python() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif ls -d /nix/store/*-python3-3.13*/bin/python3 >/dev/null 2>&1; then
        ls -d /nix/store/*-python3-3.13*/bin/python3 2>/dev/null | tail -n 1
    elif ls -d /nix/store/*-python3-*/bin/python3 >/dev/null 2>&1; then
        ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1
    else
        echo ""
    fi
}

resolve_core_path() {
    local ref_path="${1:-$0}"
    local script_dir
    script_dir="$(dirname "$(readlink -f "$ref_path")")"
    if [[ -d "${script_dir}/../packages/neuronix-core" ]]; then
        echo "${script_dir}/../packages/neuronix-core"
    elif [[ -d "${script_dir}/../share/neuronix/packages/neuronix-core" ]]; then
        echo "${script_dir}/../share/neuronix/packages/neuronix-core"
    elif [[ -d "/etc/nixos/packages/neuronix-core" ]]; then
        echo "/etc/nixos/packages/neuronix-core"
    elif [[ -d "/etc/neuronix/packages/neuronix-core" ]]; then
        echo "/etc/neuronix/packages/neuronix-core"
    else
        echo ""
    fi
}

resolve_daemon_bin() {
    local ref_path="${1:-$0}"
    if command -v neuronix-daemon >/dev/null 2>&1; then
        command -v neuronix-daemon
    elif [[ -x "$(dirname "$(readlink -f "$ref_path")")/../packages/neuronix-daemon/target/release/neuronix-daemon" ]]; then
        echo "$(dirname "$(readlink -f "$ref_path")")/../packages/neuronix-daemon/target/release/neuronix-daemon"
    elif [[ -x "/run/current-system/sw/bin/neuronix-daemon" ]]; then
        echo "/run/current-system/sw/bin/neuronix-daemon"
    else
        echo ""
    fi
}
