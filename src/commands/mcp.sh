#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_mcp() {
    local script_dir
    script_dir="$(dirname "$(readlink -f "$0")")"
    if [[ -f "${script_dir}/mcp_server.sh" ]]; then
        exec "${script_dir}/mcp_server.sh" "$@"
    elif [[ -f "${script_dir}/../share/neuronix/mcp_server.sh" ]]; then
        exec "${script_dir}/../share/neuronix/mcp_server.sh" "$@"
    elif [[ -f "${script_dir}/../src/mcp_server.sh" ]]; then
        exec "${script_dir}/../src/mcp_server.sh" "$@"
    else
        log_error "Server script mcp_server.sh tidak ditemukan di ${script_dir}."
        exit 1
    fi
}

