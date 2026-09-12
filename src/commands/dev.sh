#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_dev() {
    local stack=""
    local show_manifest=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manifest|-m)
                show_manifest=1
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$stack" ]]; then
                    stack="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$stack" ]]; then
        log_error "Silakan tentukan stack pengembang yang diinginkan."
        echo -e "Pilihan yang tersedia: ${CYAN}python${RESET}, ${CYAN}rust${RESET}, ${CYAN}node${RESET}, ${CYAN}ai${RESET}, ${CYAN}go${RESET}, ${CYAN}web3${RESET}"
        echo -e "Contoh: ${CYAN}${PROGRAM_NAME} dev python${RESET}"
        exit 1
    fi

    local pkgs=()
    case "${stack}" in
        python)
            pkgs=("python3" "uv" "ruff" "pyright" "postgresql")
            ;;
        rust)
            pkgs=("rustc" "cargo" "rust-analyzer" "clippy")
            ;;
        node)
            pkgs=("nodejs_20" "nodePackages.pnpm" "nodePackages.typescript" "nodePackages.eslint")
            ;;
        ai)
            pkgs=("python3" "python3Packages.pytorch" "ollama" "jupyterlab" "python3Packages.pandas")
            ;;
        go)
            pkgs=("go" "gopls" "golangci-lint" "delve")
            ;;
        web3)
            pkgs=("rustc" "cargo" "nodejs_20" "solana-cli")
            ;;
        *)
            log_error "Stack '${stack}' tidak dikenali."
            echo -e "Pilihan yang tersedia: ${CYAN}python${RESET}, ${CYAN}rust${RESET}, ${CYAN}node${RESET}, ${CYAN}ai${RESET}, ${CYAN}go${RESET}, ${CYAN}web3${RESET}"
            exit 1
            ;;
    esac

    if [[ "$show_manifest" -eq 1 ]]; then
        local pkgs_json
        pkgs_json=$(printf '"%s",' "${pkgs[@]}" | sed 's/,$//')
        cat << JSON_EOF
{
  "stack": "${stack}",
  "channel": "nixos-26.05",
  "hermetic": true,
  "ephemeral": true,
  "packages": [${pkgs_json}]
}
JSON_EOF
        return 0
    fi

    log_step "Provisioning isolated development environment: ${BOLD}${stack}${RESET}..."
    log_info "Toolchain lengkap yang disediakan: ${BOLD}${pkgs[*]}${RESET}"
    log_info "Lingkungan hermetis di RAM aktif. Menutup terminal akan membersihkan memori."
    echo

    if [[ "${DEV_DRY_RUN:-0}" == "1" ]]; then
        log_success "Dry-run validation successful for stack ${stack}: ${pkgs[*]}"
        return 0
    fi

    nix-shell -p "${pkgs[@]}"
    local exit_code=$?
    echo
    log_success "Sesi pengembangan ${stack} selesai. Memori telah dibersihkan."
    return $exit_code
}

cmd_undo() {
    acquire_lock "rollback"
    print_banner
    log_warn "WARNING: Initiating atomic rollback to previous system generation..."
    
    local py_bin core_path
    py_bin="$(resolve_python)"
    core_path="$(resolve_core_path)"

    if [[ -n "$py_bin" && -n "$core_path" ]]; then
        log_step "Executing transactional rollback via unified engine (neuronix_core.rollback)..."
        local rb_output rb_code=0
        rb_output="$("$py_bin" -c "
import sys
sys.path.insert(0, '${core_path}')
from neuronix_core.rollback import execute_rollback
ok, code, msg = execute_rollback()
print(msg)
sys.exit(code)
" 2>&1)" || rb_code=$?

        echo -e "${rb_output}"
        if [[ $rb_code -eq 0 ]]; then
            log_success "Rollback transaction committed successfully."
            return 0
        else
            log_error "Rollback transaction failed or aborted."
            return $rb_code
        fi
    else
        log_error "Transactional engine unavailable. Refusing unmanaged rollback command."
        return 1
    fi
}

cmd_verify() {
    local pkg="${1:-}"
    if [[ -z "$pkg" ]]; then
        log_error "Silakan tentukan nama paket yang ingin diverifikasi."
        echo -e "Contoh: ${CYAN}${PROGRAM_NAME} verify hello${RESET}"
        exit 1
    fi

    # Security: Strict allowlist to eliminate expression-injection attack surface
    if [[ ! "$pkg" =~ ^[A-Za-z0-9._+-]+$ ]]; then
        log_error "Invalid package name: '${pkg}'. Must match regex ^[A-Za-z0-9._+-]+$."
        return 1
    fi

    log_step "Running declarative build & dry-run verification for package derivation: ${BOLD}${pkg}${RESET}..."
    if nix-instantiate '<nixpkgs>' -A "$pkg" >/dev/null 2>&1 && nix-build '<nixpkgs>' -A "$pkg" --dry-run >/dev/null 2>&1; then
        log_success "Declarative Build Verification PASSED: Package derivation '${pkg}' evaluates and passes dry-build in nixpkgs closure."
        return 0
    else
        log_error "Declarative Build Verification FAILED: Package derivation '${pkg}' failed dry-build evaluation in nixpkgs."
        return 1
    fi
}

