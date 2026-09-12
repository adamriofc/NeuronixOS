#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Library: Version Resolution Logic
# Part of Phase 4 Distribution Architecture
# ==============================================================================

resolve_version() {
    local ref_path="${1:-$0}"
    local ver="1.0.5"
    local vnix="$(dirname "$(readlink -f "$ref_path")")/../version.nix"
    if [[ ! -f "$vnix" && -f "$(dirname "$(readlink -f "$ref_path")")/../share/neuronix/version.nix" ]]; then
        vnix="$(dirname "$(readlink -f "$ref_path")")/../share/neuronix/version.nix"
    elif [[ ! -f "$vnix" && -f "/etc/neuronix/version.nix" ]]; then
        vnix="/etc/neuronix/version.nix"
    fi
    if [[ -f "$vnix" ]]; then
        local parsed
        parsed=$(grep -E 'version\s*=' "$vnix" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
        if [[ -n "$parsed" ]]; then
            ver="$parsed"
        fi
    fi
    echo "$ver"
}
