#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_diff() {
    local gen_a=""
    local gen_b=""
    local json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}${PROGRAM_NAME} diff${RESET} [GEN_A] [GEN_B] [OPTIONS]\n"
                echo -e "  Compares package closures, kernel versions, and systemd units between generations."
                echo -e "  If arguments omitted, compares previous generation with current generation.\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--json${RESET}    Print comparison in structured JSON"
                echo -e "  ${GREEN}-h, --help${RESET}Show this help\n"
                return 0
                ;;
            *)
                if [[ -z "$gen_a" ]]; then
                    gen_a="$1"
                elif [[ -z "$gen_b" ]]; then
                    gen_b="$1"
                fi
                shift
                ;;
        esac
    done

    local py_bin core_path
    py_bin="$(resolve_python)"
    core_path="$(resolve_core_path)"

    if [[ -z "$py_bin" || -z "$core_path" ]]; then
        log_error "Python 3 or neuronix-core package not found."
        return 1
    fi

    PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.diff import compute_generation_diff

gen_a = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != '' else None
gen_b = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != '' else None
diff = compute_generation_diff(gen_a, gen_b)

if diff.get('status') == 'error':
    if int(sys.argv[3]) == 1:
        print(json.dumps(diff, indent=2))
    else:
        print(f'\033[38;5;196m✖ Error:\033[0m {diff.get(\"message\")}')
    sys.exit(1)

if int(sys.argv[3]) == 1:
    print(json.dumps(diff, indent=2))
    sys.exit(0)

print('\033[1m================================================================\033[0m')
print(f'  \033[1mNEURONIX 3-TIER GENERATIONAL FORENSIC DIFF\033[0m')
print('\033[1m================================================================\033[0m')
print('\033[1m[Tier 1: Generation & Kernel Metadata]\033[0m')
print(f'  Base Target A    : {diff[\"target_a\"][\"name\"]}')
print(f'  Compare Target B : {diff[\"target_b\"][\"name\"]}')
if diff[\"kernel_changed\"]:
    print(f'  \033[38;5;220m● Kernel Changed  : {diff[\"target_a\"][\"kernel\"]} -> {diff[\"target_b\"][\"kernel\"]}\033[0m')
else:
    print(f'  ● Kernel Version  : {diff[\"target_b\"][\"kernel\"]} (Unchanged)')
print('----------------------------------------------------------------')
t2 = diff.get('tier2_authoritative_closures', {})
c_add = t2.get('closures_added', [])
c_rem = t2.get('closures_removed', [])
c_upg = t2.get('closures_upgraded', [])
print(f'\033[1m[Tier 2: Authoritative Nix Store Closures]\033[0m (Total changes: {t2.get(\"total_changes\", 0)})')
print(f'  Closures Added   : +{len(c_add)}')
if c_add:
    for c in c_add[:5]:
        print(f'    \033[38;5;82m+ {c.get(\"name\")} {c.get(\"version\", \"\")} ({c.get(\"size_delta\", \"\")})\033[0m')
print(f'  Closures Removed : -{len(c_rem)}')
if c_rem:
    for c in c_rem[:5]:
        print(f'    \033[38;5;196m- {c.get(\"name\")} {c.get(\"version\", \"\")} ({c.get(\"size_delta\", \"\")})\033[0m')
print(f'  Closures Upgraded: ~{len(c_upg)}')
if c_upg:
    for c in c_upg[:5]:
        print(f'    \033[38;5;51m~ {c.get(\"name\")} {c.get(\"from_version\", \"\")} -> {c.get(\"to_version\", \"\")} ({c.get(\"size_delta\", \"\")})\033[0m')
print('----------------------------------------------------------------')
print('\033[1m[Tier 3: Convenience Executables & Services]\033[0m')
added = diff.get('packages_added', [])
removed = diff.get('packages_removed', [])
print(f'  User Executables Added   : +{len(added)}')
if added:
    sample = \", \".join(added[:10]) + ('...' if len(added) > 10 else '')
    print(f'    \033[38;5;82m+ {sample}\033[0m')
print(f'  User Executables Removed : -{len(removed)}')
if removed:
    sample = \", \".join(removed[:10]) + ('...' if len(removed) > 10 else '')
    print(f'    \033[38;5;196m- {sample}\033[0m')
svc_added = diff.get('services_added', [])
svc_removed = diff.get('services_removed', [])
print(f'  Systemd Services Added   : +{len(svc_added)}')
if svc_added:
    print(f'    \033[38;5;82m+ {\", \".join(svc_added[:6])}\033[0m')
print(f'  Systemd Services Removed : -{len(svc_removed)}')
if svc_removed:
    print(f'    \033[38;5;196m- {\", \".join(svc_removed[:6])}\033[0m')
print('\033[1m================================================================\033[0m')
" "$gen_a" "$gen_b" "$json_output"
}

# ------------------------------------------------------------------------------
# Imperative-to-Declarative Reverse Engine
# ------------------------------------------------------------------------------
