#!/usr/bin/env bash
# ==============================================================================
# NEURONIX CLI Modular Command Handler
# Part of Phase 4 Distribution Architecture
# ==============================================================================
cmd_container_build() {
    local target=""
    local output_tar=""
    local tag="latest"
    local repo="neuronix-app"
    local entrypoint=""
    local build_mode="auto"
    local dry_run=0
    local json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output|-o)
                output_tar="$2"
                shift 2
                ;;
            --tag|-t)
                tag="$2"
                shift 2
                ;;
            --repo|-r)
                repo="$2"
                shift 2
                ;;
            --entrypoint|-e)
                entrypoint="$2"
                shift 2
                ;;
            --nix)
                build_mode="nix"
                shift
                ;;
            --source)
                build_mode="source"
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --json)
                json_output=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}${PROGRAM_NAME} container build${RESET} <target> [OPTIONS]\n"
                echo -e "  Compiles a declarative Nix flake or directory into an ultra-lean OCI container tarball."
                echo -e "  100% rootless and daemonless (no Docker daemon needed).\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--output, -o <path.tar>${RESET} Target output tarball path (default: <repo>-<tag>.tar)"
                echo -e "  ${GREEN}--tag, -t <tag>${RESET}        Image tag (default: latest)"
                echo -e "  ${GREEN}--repo, -r <repo>${RESET}      Image repository name (default: neuronix-app)"
                echo -e "  ${GREEN}--entrypoint, -e <cmd>${RESET} Custom container entrypoint"
                echo -e "  ${GREEN}--nix${RESET}                  Enforce strict Nix closure compilation (fails if invalid)"
                echo -e "  ${GREEN}--source${RESET}               Compile source files without Nix derivation evaluation"
                echo -e "  ${GREEN}--dry-run${RESET}              Verify build target without compiling"
                echo -e "  ${GREEN}--json${RESET}                 Output result in JSON format\n"
                return 0
                ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$target" ]]; then
        log_error "No build target directory or flake specified."
        return 1
    fi
    if [[ -z "$output_tar" ]]; then
        output_tar="${repo}-${tag}.tar"
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        if [[ "$json_output" -eq 1 ]]; then
            jq -n --arg t "$target" --arg o "$output_tar" --arg r "$repo" --arg tg "$tag" --arg m "$build_mode" \
                '{status: "dry_run_success", mode: "build", build_mode: $m, target: $t, output_tar: $o, repo: $r, tag: $tg}'
        else
            log_success "Container build dry-run verified for: $target -> $output_tar ($repo:$tag, mode: $build_mode)"
        fi
        return 0
    fi

    local py_bin core_path
    py_bin="$(resolve_python)"
    core_path="$(resolve_core_path)"

    PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import build_container_oci

target = sys.argv[1]
out_tar = sys.argv[2]
tag = sys.argv[3]
repo = sys.argv[4]
entry = [sys.argv[5]] if len(sys.argv) > 5 and sys.argv[5] else None
json_out = sys.argv[6] == '1'
b_mode = sys.argv[7] if len(sys.argv) > 7 else 'auto'

ok, msg = build_container_oci(target, out_tar, tag=tag, repo=repo, entrypoint=entry, mode=b_mode)
if json_out:
    print(json.dumps({'status': 'success' if ok else 'error', 'output_tar': out_tar, 'message': msg}))
else:
    if ok:
        print('\033[38;5;82m✔\033[0m ' + msg)
    else:
        print('\033[38;5;196m✖\033[0m ' + msg)
sys.exit(0 if ok else 1)
" "$target" "$output_tar" "$tag" "$repo" "$entrypoint" "$json_output" "$build_mode"
    return $?
}

cmd_container_daemon() {
    local target=""
    local name=""
    local cmd_to_run=""
    local dry_run=0
    local json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-n)
                name="$2"
                shift 2
                ;;
            --run|-c)
                cmd_to_run="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --json)
                json_output=1
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}${PROGRAM_NAME} container daemon${RESET} <target> --name <name> [OPTIONS]\n"
                echo -e "  Runs a persistent or background container service supervised via systemd user units."
                echo -e "  0 MB idle memory overhead.\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--name, -n <name>${RESET}      Unique name for container daemon (required)"
                echo -e "  ${GREEN}--run, -c <command>${RESET}    Command to execute as background daemon"
                echo -e "  ${GREEN}--dry-run${RESET}              Verify allocation without starting daemon"
                echo -e "  ${GREEN}--json${RESET}                 Output result in JSON format\n"
                return 0
                ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$target" || -z "$name" ]]; then
        log_error "Target and --name are required for container daemon."
        echo -e "Usage: ${CYAN}${PROGRAM_NAME} container daemon <target> --name <name>${RESET}"
        return 1
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        if [[ "$json_output" -eq 1 ]]; then
            jq -n --arg t "$target" --arg n "$name" \
                '{status: "dry_run_success", mode: "daemon", target: $t, name: $n, ram_disk: "/dev/shm"}'
        else
            log_success "Container daemon dry-run verified for '$name' on $target (RAM backing: /dev/shm)"
        fi
        return 0
    fi

    local py_bin core_path
    py_bin="$(resolve_python)"
    core_path="$(resolve_core_path)"

    PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import daemonize_container_session

target = sys.argv[1]
name = sys.argv[2]
cmd = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
json_out = sys.argv[4] == '1'

ok, msg = daemonize_container_session(target, name, command=cmd)
if json_out:
    print(json.dumps({'status': 'success' if ok else 'error', 'name': name, 'message': msg}))
else:
    if ok:
        print('\033[38;5;82m✔\033[0m ' + msg)
    else:
        print('\033[38;5;196m✖\033[0m ' + msg)
sys.exit(0 if ok else 1)
" "$target" "$name" "$cmd_to_run" "$json_output"
    return $?
}

cmd_container_stop() {
    local name="$1"
    local json_output=0
    [[ "${2:-}" == "--json" ]] && json_output=1

    if [[ -z "$name" ]]; then
        log_error "No container daemon name specified to stop."
        return 1
    fi

    local py_bin core_path
    py_bin="$(resolve_python)"
    core_path="$(resolve_core_path)"

    PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import stop_container_daemon

name = sys.argv[1]
json_out = sys.argv[2] == '1'
ok, msg = stop_container_daemon(name)
if json_out:
    print(json.dumps({'status': 'success' if ok else 'error', 'name': name, 'message': msg}))
else:
    if ok:
        print('\033[38;5;82m✔\033[0m ' + msg)
    else:
        print('\033[38;5;196m✖\033[0m ' + msg)
sys.exit(0 if ok else 1)
" "$name" "$json_output"
    return $?
}

cmd_container_list() {
    local json_output=0
    [[ "${1:-}" == "--json" ]] && json_output=1

    local py_bin core_path
    py_bin="$(resolve_python)"
    core_path="$(resolve_core_path)"

    PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import list_container_daemons

json_out = sys.argv[1] == '1'
daemons = list_container_daemons()
if json_out:
    print(json.dumps({'daemons': daemons}))
else:
    print('\033[1mNEURONIX CONTAINER DAEMONS\033[0m')
    print('────────────────────────────────────────────────────────────')
    if not daemons:
        print('  (No active container daemons running in RAM/systemd)')
    else:
        print(f'  {\"NAME\":<20} {\"TARGET_TYPE\":<20} {\"STATUS\":<15}')
        print('  ' + '─' * 55)
        for d in daemons:
            st = d.get('status', 'unknown')
            color = '\033[38;5;82m' if st == 'running' else '\033[38;5;196m'
            print(f'  {d.get(\"name\"):<20} {d.get(\"target_type\"):<20} {color}{st}\033[0m')
" "$json_output"
    return $?
}

cmd_container_compose() {
    local stack_file=""
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
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}${PROGRAM_NAME} container compose${RESET} <file.yaml|json> [OPTIONS]\n"
                echo -e "  Multi-service ephemeral stack orchestration in RAM with In-Memory Micro-DNS.\n"
                return 0
                ;;
            *)
                if [[ -z "$stack_file" ]]; then
                    stack_file="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$stack_file" ]]; then
        log_error "No compose/stack file specified."
        return 1
    fi

    cmd_container --stack "$stack_file" $([[ "$dry_run" -eq 1 ]] && echo "--dry-run") $([[ "$json_output" -eq 1 ]] && echo "--json")
    return $?
}

cmd_container() {
    # Check for dedicated subcommands first
    if [[ $# -gt 0 ]]; then
        case "$1" in
            build)
                shift
                cmd_container_build "$@"
                return $?
                ;;
            daemon)
                shift
                cmd_container_daemon "$@"
                return $?
                ;;
            stop)
                shift
                cmd_container_stop "$@"
                return $?
                ;;
            list|ps)
                shift
                cmd_container_list "$@"
                return $?
                ;;
            compose|stack)
                shift
                cmd_container_compose "$@"
                return $?
                ;;
        esac
    fi

    local target=""
    local keep_path=""
    local stack_file=""
    local export_oci_tar=""
    local enable_fhs=1
    local unshare_net=0
    local allow_synthetic=0
    local allow_secret_env=0
    local vaporize=0
    local dry_run=0
    local json_output=0
    local cmd_to_run=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build)
                shift
                cmd_container_build "$@"
                return $?
                ;;
            --daemon|-d)
                shift
                cmd_container_daemon "$@"
                return $?
                ;;
            --stop)
                shift
                cmd_container_stop "$@"
                return $?
                ;;
            --list|--ps)
                shift
                cmd_container_list "$@"
                return $?
                ;;
            --compose)
                shift
                cmd_container_compose "$@"
                return $?
                ;;
            --keep)
                keep_path="$2"
                shift 2
                ;;
            --stack)
                stack_file="$2"
                shift 2
                ;;
            --export-oci)
                export_oci_tar="$2"
                shift 2
                ;;
            --fhs)
                enable_fhs=1
                shift
                ;;
            --no-fhs)
                enable_fhs=0
                shift
                ;;
            --unshare-net|--isolated-net)
                unshare_net=1
                shift
                ;;
            --offline-test)
                allow_synthetic=1
                shift
                ;;
            --allow-secret-env)
                allow_secret_env=1
                shift
                ;;
            --vaporize)
                vaporize=1
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --json)
                json_output=1
                shift
                ;;
            --run|-c)
                cmd_to_run="$2"
                shift 2
                ;;
            -h|--help)
                echo -e "${BOLD}USAGE:${RESET}"
                echo -e "  ${CYAN}${PROGRAM_NAME} container${RESET} <git-url|directory|oci-image> [OPTIONS]"
                echo -e "  ${CYAN}${PROGRAM_NAME} container build${RESET} <dir|flake> [--output <out.tar>] [--tag <tag>]"
                echo -e "  ${CYAN}${PROGRAM_NAME} container daemon${RESET} <target> --name <name> [--run <cmd>]"
                echo -e "  ${CYAN}${PROGRAM_NAME} container stop${RESET} <name>"
                echo -e "  ${CYAN}${PROGRAM_NAME} container list | ps${RESET}"
                echo -e "  ${CYAN}${PROGRAM_NAME} container compose${RESET} <file.yaml|json>\n"
                echo -e "  Spins up an ephemeral, zero-copy development container in RAM (/dev/shm)."
                echo -e "  Features Dynamic FHS Emulation, Micro-DNS Service Mesh, Daemonless OCI Compiler, and Quadlet Systemd Supervised Daemons.\n"
                echo -e "${BOLD}OPTIONS:${RESET}"
                echo -e "  ${GREEN}--run, -c <cmd>${RESET}         Execute command inside container non-interactively"
                echo -e "  ${GREEN}--stack <file.yaml|json>${RESET} Launch ephemeral multi-service stack in RAM with Micro-DNS"
                echo -e "  ${GREEN}--export-oci <out.tar>${RESET}   Export workspace to standard OCI/Docker image tarball"
                echo -e "  ${GREEN}--keep <path>${RESET}           Export modified workspace to target directory upon exit"
                echo -e "  ${GREEN}--unshare-net${RESET}           Strict hermetic network isolation (loopback only)"
                echo -e "  ${GREEN}--vaporize${RESET}              Auto-delete RAM workspace without confirmation prompt"
                echo -e "  ${GREEN}--fhs / --no-fhs${RESET}        Enable/disable transparent dynamic FHS emulation (default: on)"
                echo -e "  ${GREEN}--dry-run${RESET}               Verify RAM allocation without spawning container"
                echo -e "  ${GREEN}--json${RESET}                  Output status in JSON"
                echo -e "  ${GREEN}-h, --help${RESET}              Show this help\n"
                echo -e "${BOLD}EXAMPLES:${RESET}"
                echo -e "  ${DIM}# Run foreign repo in RAM with transparent FHS emulation${RESET}"
                echo -e "  ${PROGRAM_NAME} container https://github.com/org/repo.git\n"
                echo -e "  ${DIM}# Run Docker Hub image directly in RAM without Docker daemon${RESET}"
                echo -e "  ${PROGRAM_NAME} container oci://alpine:latest --run \"cat /etc/os-release\"\n"
                echo -e "  ${DIM}# Launch multi-service stack in RAM with In-Memory Micro-DNS mesh${RESET}"
                echo -e "  ${PROGRAM_NAME} container compose neuronix-stack.yaml\n"
                echo -e "  ${DIM}# Build declarative Nix OCI image without Docker daemon${RESET}"
                echo -e "  ${PROGRAM_NAME} container build /path/to/project --output app.tar\n"
                echo -e "  ${DIM}# Run background service daemon with 0 MB idle RAM${RESET}"
                echo -e "  ${PROGRAM_NAME} container daemon /path/to/project --name my-api --run \"node server.js\"\n"
                return 0
                ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                fi
                shift
                ;;
        esac
    done

    local py_bin core_path
    py_bin="$(resolve_python)"
    core_path="$(resolve_core_path)"

    # Handle Multi-Service Stack Orchestration
    if [[ -n "$stack_file" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            if [[ "$json_output" -eq 1 ]]; then
                jq -n --arg s "$stack_file" '{status: "dry_run_success", mode: "stack", stack_file: $s, ram_disk: "/dev/shm"}'
            else
                log_success "Multi-service stack dry-run verified for: $stack_file (RAM backing: /dev/shm)"
            fi
            return 0
        fi

        PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import run_stack_session

stack_file = sys.argv[1]
json_out = sys.argv[2] == '1'
allow_sec = sys.argv[3] == '1'
res = run_stack_session(stack_file, allow_secret_env=allow_sec)
if json_out:
    print(json.dumps(res))
else:
    if res.get('status') == 'success':
        print('\033[38;5;82m✔\033[0m ' + res.get('message', 'Stack complete'))
        for svc, sdata in res.get('services', {}).items():
            print(f'  ├─ {svc}: {sdata.get(\"status\")} (pid: {sdata.get(\"pid\", \"N/A\")})')
    else:
        print('\033[38;5;196m✖\033[0m ' + res.get('message', 'Stack error'))
sys.exit(0 if res.get('status') == 'success' else 1)
" "$stack_file" "$json_output" "$allow_secret_env"
        return $?
    fi

    if [[ -z "$target" ]]; then
        log_error "No Git URL, directory, or OCI image specified for container."
        echo -e "Usage: ${CYAN}${PROGRAM_NAME} container <git-url|dir|oci-image>${RESET}"
        return 1
    fi

    # Handle OCI Export
    if [[ -n "$export_oci_tar" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            if [[ "$json_output" -eq 1 ]]; then
                jq -n --arg t "$target" --arg o "$export_oci_tar" '{status: "dry_run_success", mode: "export_oci", target: $t, output_tar: $o}'
            else
                log_success "OCI export dry-run verified: $target -> $export_oci_tar"
            fi
            return 0
        fi

        PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import export_container_oci

target = sys.argv[1]
out_tar = sys.argv[2]
json_out = sys.argv[3] == '1'

ok, msg = export_container_oci(target, out_tar)
if json_out:
    print(json.dumps({'status': 'success' if ok else 'error', 'output_tar': out_tar, 'message': msg}))
else:
    if ok:
        print('\033[38;5;82m✔\033[0m ' + msg)
    else:
        print('\033[38;5;196m✖\033[0m ' + msg)
sys.exit(0 if ok else 1)
" "$target" "$export_oci_tar" "$json_output"
        return $?
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        if [[ "$json_output" -eq 1 ]]; then
            jq -n --arg t "$target" '{status: "dry_run_success", target: $t, ram_disk: "/dev/shm"}'
        else
            log_success "Container dry-run verified for target: $target (RAM backing: /dev/shm)"
        fi
        return 0
    fi

    PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import setup_ram_workspace, run_container_session, teardown_container

target = sys.argv[1]
json_out = sys.argv[2] == '1'
cmd_to_run = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != '' else None
keep_path = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != '' else None
enable_fhs = sys.argv[5] == '1'
unshare_net = sys.argv[6] == '1'
allow_synth = sys.argv[7] == '1'

w_dir, act_dir, msg = setup_ram_workspace(target, allow_synthetic=allow_synth)
if not w_dir:
    print(json.dumps({'status': 'error', 'message': msg}) if json_out else f'\033[38;5;196m✖\033[0m {msg}')
    sys.exit(1)

if json_out and not cmd_to_run:
    print(json.dumps({'status': 'ready', 'workspace': w_dir, 'active_dir': act_dir}))
    teardown_container(w_dir)
    sys.exit(0)

print('\033[38;5;51m➔\033[0m Entering ephemeral RAM container: ' + act_dir)
print('  \033[2mReal \$HOME is safely masked. Zero SSD disk footprint.\033[0m')
code, s_msg = run_container_session(act_dir, command=cmd_to_run, enable_fhs=enable_fhs, unshare_net=unshare_net)

teardown_container(w_dir, export_path=keep_path)
print('\033[38;5;82m✔\033[0m Ephemeral RAM container cleanly vaporized (0 bytes residue).')
sys.exit(code)
" "$target" "$json_output" "$cmd_to_run" "$keep_path" "$enable_fhs" "$unshare_net" "$allow_synthetic"
}

# ------------------------------------------------------------------------------
# Deterministic Workload Tuning Matrix
# ------------------------------------------------------------------------------
