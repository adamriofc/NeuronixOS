#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Library: Concurrency Lock Management
# Part of Phase 4 Distribution Architecture
# ==============================================================================

LOCK_FD=200
LOCK_FILE=""

acquire_lock() {
    local op_name="${1:-operation}"
    local lock_dir="/run"
    if [[ ! -d "$lock_dir" || ! -w "$lock_dir" ]]; then
        lock_dir="/tmp"
    fi
    LOCK_FILE="${lock_dir}/neuronix-operation.lock"

    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_warn "Another NEURONIX system operation is currently running. Waiting for lock..."
        if ! flock -w 30 200; then
            log_error "Could not acquire system operation lock (${LOCK_FILE}). Aborting."
            exit 1
        fi
    fi
}

release_lock() {
    if [[ -n "${LOCK_FILE:-}" ]]; then
        flock -u 200 2>/dev/null || true
    fi
}
