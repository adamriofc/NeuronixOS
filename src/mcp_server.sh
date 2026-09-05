#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Model Context Protocol (MCP) Server
# Implements MCP JSON-RPC 2.0 over stdio (Protocol Version: 2024-11-05)
# Production-grade implementation utilizing robust jq parsing and serialization.
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

# Safe Path Fallback
export PATH="${PATH:-/run/current-system/sw/bin:/usr/bin:/bin}:/run/current-system/sw/bin:/usr/bin:/bin"

# Version Metadata
SERVER_NAME="neuronix-mcp"
SERVER_VERSION="1.0.3"
VERSION_NIX="$(dirname "$(readlink -f "$0")")/../version.nix"
if [[ -f "$VERSION_NIX" ]]; then
    SERVER_VERSION=$(grep -E 'version\s*=' "$VERSION_NIX" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
fi
PROTOCOL_VERSION="2024-11-05"

# Discover jq in environment, system profiles, or nix store
if ! command -v jq >/dev/null 2>&1; then
    for candidate in /run/current-system/sw/bin/jq /nix/store/*-jq-*/bin/jq; do
        if [[ -x "$candidate" ]]; then
            export PATH="$(dirname "$candidate"):$PATH"
            break
        fi
    done
fi

# Ensure jq is available
if ! command -v jq >/dev/null 2>&1; then
    echo "Fatal: jq is required for NEURONIX MCP JSON-RPC 2.0 server" >&2
    exit 1
fi

# Discover Python in environment, system profiles, or nix store
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
    local script_dir
    script_dir="$(dirname "$(readlink -f "$0")")"
    if [[ -d "${script_dir}/../packages/neuronix-core" ]]; then
        echo "${script_dir}/../packages/neuronix-core"
    elif [[ -d "/etc/nixos/packages/neuronix-core" ]]; then
        echo "/etc/nixos/packages/neuronix-core"
    else
        echo ""
    fi
}

# Concurrency lock helpers
acquire_mcp_lock() {
    local lock_dir="/run"
    if [[ ! -d "$lock_dir" || ! -w "$lock_dir" ]]; then
        lock_dir="/tmp"
    fi
    local lock_file="${lock_dir}/neuronix-operation.lock"
    exec 200>"$lock_file"
    flock -n 200
}

release_mcp_lock() {
    flock -u 200 2>/dev/null || true
}

# Helper for JSON-RPC 2.0 responses
send_response() {
    local raw_id="${1:-null}"
    local result_json="$2"
    local safe_id="null"
    if [[ -n "$raw_id" ]] && echo "$raw_id" | jq empty 2>/dev/null; then
        safe_id="$raw_id"
    elif [[ -n "$raw_id" && "$raw_id" != "null" ]]; then
        safe_id=$(jq -n -c --arg id "$raw_id" '$id')
    fi
    jq -n -c --argjson id "$safe_id" --argjson result "$result_json" \
        '{"jsonrpc":"2.0","id":$id,"result":$result}'
}

send_error() {
    local raw_id="${1:-null}"
    local code="$2"
    local message="$3"
    local safe_id="null"
    if [[ -n "$raw_id" ]] && echo "$raw_id" | jq empty 2>/dev/null; then
        safe_id="$raw_id"
    elif [[ -n "$raw_id" && "$raw_id" != "null" ]]; then
        safe_id=$(jq -n -c --arg id "$raw_id" '$id')
    fi
    jq -n -c --argjson id "$safe_id" --argjson code "$code" --arg msg "$message" \
        '{"jsonrpc":"2.0","id":$id,"error":{"code":$code,"message":$msg}}'
}

# Core MCP Methods
handle_initialize() {
    local req_id="$1"
    local result
    result=$(jq -n -c \
        --arg proto "$PROTOCOL_VERSION" \
        --arg name "$SERVER_NAME" \
        --arg ver "$SERVER_VERSION" \
        '{
            protocolVersion: $proto,
            capabilities: {
                tools: {},
                resources: { subscribe: false, listChanged: false },
                prompts: { listChanged: false }
            },
            serverInfo: { name: $name, version: $ver }
        }')
    send_response "$req_id" "$result"
}

handle_tools_list() {
    local req_id="$1"
    local result
    result=$(cat << 'JSON_EOF'
{
  "tools": [
    {
      "name": "neuronix_status",
      "description": "Inspect OS kernel parameters, active NixOS generation, storage telemetry, and autonomous timer status.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_diet",
      "description": "Trigger storage garbage collection, inode hardlink deduplication, and VirtIO TRIM unmap directives to shrink host disk.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "dry_run": {
            "type": "boolean",
            "description": "Simulate storage reclamation without modifying disk state."
          }
        }
      }
    },
    {
      "name": "neuronix_verify",
      "description": "Evaluate and validate a Nix package or expression derivation via dry-build dependency resolution prior to execution (Declarative Build Verification Gatekeeper).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "package": {
            "type": "string",
            "description": "Name of the nixpkgs package or flake derivation to verify."
          }
        },
        "required": ["package"]
      }
    },
    {
      "name": "neuronix_undo",
      "description": "Execute atomic system rollback to preceding generation (switches generation when elevated, or returns exact recovery directive).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "dry_run": {
            "type": "boolean",
            "description": "Simulate rollback validation without switching generation."
          }
        }
      }
    },
    {
      "name": "neuronix_list_generations",
      "description": "List historical system generations with active generation marker and symlink targets.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_shadow_eval",
      "description": "Simulate system configuration in an ephemeral in-memory Shadow Micro-VM in RAM (/dev/shm) with automated smoke test before host promotion.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "config_path": {
            "type": "string",
            "description": "Optional path to NixOS configuration file to test."
          }
        }
      }
    },
    {
      "name": "neuronix_check_update",
      "description": "Check upstream flake repository and remote commit status for available system updates.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_upgrade",
      "description": "Perform atomic system upgrade with generation creation (defaults to staged mode to prevent active session disruption).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "mode": {
            "type": "string",
            "enum": ["staged", "switch"],
            "description": "Upgrade mode: 'staged' prepares generation for next boot; 'switch' immediately switches running system."
          },
          "dry_run": {
            "type": "boolean",
            "description": "Simulate upgrade evaluation without switching or registering new bootloader entry."
          }
        }
      }
    },
    {
      "name": "neuronix_doctor",
      "description": "Execute deep system diagnostic probe and produce privacy-sanitized system report for issue tracking.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "format": {
            "type": "string",
            "enum": ["json", "markdown"],
            "description": "Output format for diagnostic report (default: json)"
          }
        }
      }
    },
    {
      "name": "neuronix_quickstart_list",
      "description": "List curated catalog of Flatpak/Flathub desktop and engineering applications for hermetic installation.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_manual",
      "description": "Access the system-embedded NEURONIX OS Technical Manual, configuration references, and AI directives.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "topic": {
            "type": "string",
            "description": "Manual topic to retrieve: index, arch, config, cli, storage, shadow, dev, mcp, hardware, security, ai, all (default: index)"
          }
        }
      }
    }
  ]
}
JSON_EOF
)
    result="$(echo "$result" | jq -c .)"
    send_response "$req_id" "$result"
}

handle_tools_call() {
    local req_id="$1"
    local tool_name="$2"
    local params="$3"

    case "$tool_name" in
        neuronix_status)
            local current_gen="Unknown"
            [[ -L /nix/var/nix/profiles/system ]] && current_gen=$(basename "$(readlink /nix/var/nix/profiles/system)" | sed -E 's/^system-?//; s/-?link$//')
            local total_gen
            total_gen=$(find /nix/var/nix/profiles/ -maxdepth 1 -name "system-*-link" 2>/dev/null | wc -l)
            local kernel_ver
            kernel_ver=$(uname -r)
            local virt_type
            virt_type=$(systemd-detect-virt 2>/dev/null || echo "bare-metal")
            local nix_used nix_avail
            read -r nix_used nix_avail < <(df -h /nix 2>/dev/null | awk 'NR==2 {print $3, $4}')

            local text_payload
            text_payload=$(printf 'NEURONIX Substrate Telemetry:\n- Kernel: %s\n- Hypervisor: %s\n- Active Generation: Gen #%s (Total: %s)\n- /nix Store: Used %s, Free %s\n- Real-time Dedupe: ACTIVE\n- Dynamic Guard: min-free 1.0G, max-free 3.0G' \
                "$kernel_ver" "$virt_type" "$current_gen" "$total_gen" "${nix_used:-N/A}" "${nix_avail:-N/A}")

            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_diet)
            local dry_run
            dry_run=$(echo "$params" | jq -r '.dry_run // false' 2>/dev/null || echo "false")
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local opt_arg=""
                [[ "$dry_run" == "true" ]] && opt_arg="--dry-run"
                local diet_res diet_code=0
                diet_res=$("$py_bin" -c "
import sys
sys.path.insert(0, '${core_path}')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('diet'${opt_arg:+, '$opt_arg'})
print(msg)
sys.exit(code)
" 2>&1) || diet_code=$?
                local content
                content=$(jq -n -c --arg text "$diet_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
                return 0
            fi

            local content
            content=$(jq -n -c --arg text "Storage optimization deferred: transactional engine (neuronix_core.operations) unavailable." '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_verify)
            local pkg
            pkg=$(echo "$params" | jq -r '.package // empty')
            [[ -z "$pkg" ]] && pkg="hello"

            if [[ ! "$pkg" =~ ^[A-Za-z0-9._+-]+$ ]]; then
                local text="Declarative Verification REJECTED: Package name '${pkg}' contains illegal characters. Allowed regex: ^[A-Za-z0-9._+-]+$."
                local content
                content=$(jq -n -c --arg text "$text" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif nix-instantiate '<nixpkgs>' -A "$pkg" >/dev/null 2>&1 && nix-build '<nixpkgs>' -A "$pkg" --dry-run >/dev/null 2>&1; then
                local text="Declarative Build Verification PASSED: Package derivation '${pkg}' evaluates cleanly and passes dry-build in nixpkgs closure."
                local content
                content=$(jq -n -c --arg text "$text" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                local text="Declarative Build Verification FAILED: Package derivation '${pkg}' failed dry-build evaluation in nixpkgs."
                local content
                content=$(jq -n -c --arg text "$text" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            fi
            ;;

        neuronix_undo)
            local dry_run
            dry_run=$(echo "$params" | jq -r '.dry_run // false' 2>/dev/null || echo "false")
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                if [[ "$dry_run" == "true" ]]; then
                    local sim_res sim_code=0
                    sim_res=$("$py_bin" -c "
import sys
sys.path.insert(0, '${core_path}')
from neuronix_core.rollback import simulate_rollback
ok, target, msg = simulate_rollback()
print(f'Rollback simulation: {msg}')
sys.exit(0 if ok else 1)
" 2>&1) || sim_code=$?
                    local content
                    content=$(jq -n -c --arg text "$sim_res" '{"content":[{"type":"text","text":$text}]}')
                    send_response "$req_id" "$content"
                    return 0
                fi

                local rb_res rb_code=0
                rb_res=$("$py_bin" -c "
import sys
sys.path.insert(0, '${core_path}')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('rollback')
print(msg)
sys.exit(code)
" 2>&1) || rb_code=$?
                local content
                content=$(jq -n -c --arg text "$rb_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
                return 0
            fi

            local text_payload="Rollback operation rejected: transactional rollback engine unavailable."
            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_list_generations)
            local gen_list
            gen_list=$(find /nix/var/nix/profiles/ -maxdepth 1 -name "system-*-link" -printf "%f -> %l\n" 2>/dev/null | sort -V | tr '\n' ';' | sed 's/;$//')
            [[ -z "$gen_list" ]] && gen_list="None detected (no profile links found in /nix/var/nix/profiles/)"
            local content
            content=$(jq -n -c --arg text "Available generations: ${gen_list}" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_shadow_eval)
            local script_dir
            script_dir="$(dirname "$(readlink -f "$0")")"
            local shadow_script="${script_dir}/shadow_vm.sh"
            if [[ -x "$shadow_script" ]]; then
                local res
                local exit_code=0
                res=$("$shadow_script" --smoke-test --headless 2>&1 | tr '\n' ' ') || exit_code=$?
                local text
                if [[ $exit_code -eq 0 ]]; then
                    text="Shadow Micro-VM Simulation PASSED in RAM: ${res}"
                else
                    text="Shadow Micro-VM Simulation FAILED (exit code ${exit_code}): ${res}"
                fi
                local content
                content=$(jq -n -c --arg text "$text" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                local content
                content=$(jq -n -c '{"content":[{"type":"text","text":"Shadow Micro-VM simulation engine (shadow_vm.sh) not found."}]}')
                send_response "$req_id" "$content"
            fi
            ;;

        neuronix_check_update)
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local chk_res
                chk_res=$("$py_bin" -c "
import sys, json
sys.path.insert(0, '${core_path}')
from neuronix_core.update import check_upstream_update
res = check_upstream_update()
status = res.get('status', 'UNKNOWN')
local_c = res.get('local_commit')
up_c = res.get('upstream_commit')
pinned = res.get('pinned_nixpkgs_commit')
tag = res.get('release_tag', 'v1.0.3')
channel = res.get('channel', 'nixos-26.05')

summary = f'NEURONIX OS Release Status: {status}\n'
summary += f'- Release Tag: {tag} (Channel: {channel})\n'
summary += f'- Local System Commit: {local_c or \"Clean Production Tag\"}\n'
summary += f'- Upstream Release Commit: {up_c or \"Unreachable\"}\n'
summary += f'- Pinned Nixpkgs Revision: {pinned or \"Unspecified\"}\n'
if status == 'UPDATE_AVAILABLE':
    summary += 'Action: Staged upgrade available via neuronix_upgrade tool.'
elif status == 'UP_TO_DATE':
    summary += 'System is fully synchronized with latest upstream release.'
else:
    summary += f'Note: Upstream check status is {status}.'
print(summary)
" 2>&1)
                local content
                content=$(jq -n -c --arg text "$chk_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
                return 0
            fi

            local text_payload="Release update status unavailable: Python core engine not found."
            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_upgrade)
            local mode
            mode=$(echo "$params" | jq -r '.mode // "staged"')
            local dry_run
            dry_run=$(echo "$params" | jq -r '.dry_run // false' 2>/dev/null || echo "false")
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local op_name="upgrade"
                [[ "$mode" == "staged" ]] && op_name="stage"
                local extra_args=""
                [[ "$dry_run" == "true" ]] && extra_args="--dry-run"

                local up_res up_code=0
                up_res=$("$py_bin" -c "
import sys
sys.path.insert(0, '${core_path}')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('${op_name}'${extra_args:+, '$extra_args'})
print(msg)
sys.exit(code)
" 2>&1) || up_code=$?
                local content
                content=$(jq -n -c --arg text "$up_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
                return 0
            fi

            local text_payload="System upgrade rejected: transactional upgrade engine unavailable."
            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_doctor)
            local script_dir
            script_dir="$(dirname "$(readlink -f "$0")")"
            local neuronix_bin="${script_dir}/neuronix"
            local text_payload
            if [[ -x "$neuronix_bin" ]]; then
                text_payload=$("$neuronix_bin" doctor --json 2>/dev/null || true)
            else
                text_payload="{\"system\":{\"os\":\"NEURONIX OS ${SERVER_VERSION}\"},\"privacy\":{\"user\":\"<sanitized-user>\",\"host\":\"<sanitized-host>\"}}"
            fi
            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_quickstart_list)
            local text_payload
            text_payload=$(cat << 'CATALOG_EOF'
{
  "categories": {
    "browsers": [
      {"id": "com.brave.Browser", "name": "Brave Privacy Browser"},
      {"id": "com.google.Chrome", "name": "Google Chrome"},
      {"id": "org.mozilla.firefox", "name": "Mozilla Firefox"}
    ],
    "development": [
      {"id": "com.visualstudio.code", "name": "Visual Studio Code"},
      {"id": "com.vscodium.codium", "name": "VSCodium"},
      {"id": "com.getpostman.Postman", "name": "Postman API Platform"},
      {"id": "io.dbeaver.DBeaverCommunity", "name": "DBeaver Universal Database"}
    ],
    "communication": [
      {"id": "com.discordapp.Discord", "name": "Discord"},
      {"id": "org.telegram.desktop", "name": "Telegram Desktop"},
      {"id": "com.slack.Slack", "name": "Slack Workspace Client"}
    ],
    "multimedia": [
      {"id": "org.videolan.VLC", "name": "VLC Media Player"},
      {"id": "com.obsproject.Studio", "name": "OBS Studio"},
      {"id": "com.spotify.Client", "name": "Spotify Music"},
      {"id": "org.gimp.GIMP", "name": "GIMP Image Manipulation"}
    ],
    "productivity": [
      {"id": "org.libreoffice.LibreOffice", "name": "LibreOffice"},
      {"id": "md.obsidian.Obsidian", "name": "Obsidian Notes"}
    ]
  }
}
CATALOG_EOF
)
            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_manual)
            local topic
            topic=$(echo "$params" | jq -r '.topic // .arguments.topic // "index"')
            [[ -z "$topic" || "$topic" == "null" ]] && topic="index"

            local manual_dir="/etc/neuronix/manual"
            if [[ ! -d "$manual_dir" ]]; then
                local real_bin
                real_bin="$(readlink -f "${BASH_SOURCE[0]}")"
                local script_dir
                script_dir="$(cd "$(dirname "$real_bin")" && pwd)"
                manual_dir="${script_dir}/../docs/manual"
            fi
            if [[ ! -d "$manual_dir" && -n "${PROJECT_ROOT:-}" && -d "${PROJECT_ROOT}/docs/manual" ]]; then
                manual_dir="${PROJECT_ROOT}/docs/manual"
            fi
            if [[ ! -d "$manual_dir" && -d "$(pwd)/docs/manual" ]]; then
                manual_dir="$(pwd)/docs/manual"
            fi

            local target_file=""
            case "${topic,,}" in
                index|list|toc|"")
                    target_file="$manual_dir/00_INDEX.md"
                    ;;
                arch|architecture|platform)
                    target_file="$manual_dir/01_ARCHITECTURE.md"
                    ;;
                config|configuration|options)
                    target_file="$manual_dir/02_CONFIGURATION_REFERENCE.md"
                    ;;
                cli|commands|syntax)
                    target_file="$manual_dir/03_CLI_REFERENCE.md"
                    ;;
                storage|btrfs|rollback)
                    target_file="$manual_dir/04_STORAGE_AND_ROLLBACK.md"
                    ;;
                shadow|vm|sandbox|microvm)
                    target_file="$manual_dir/05_SHADOW_VM_AND_SANDBOX.md"
                    ;;
                dev|stacks|developer)
                    target_file="$manual_dir/06_DEVELOPER_STACKS.md"
                    ;;
                mcp|gateway|ai-gateway)
                    target_file="$manual_dir/07_MCP_PROTOCOL_AND_AI_GATEWAY.md"
                    ;;
                hardware|pillars|27-pillars)
                    target_file="$manual_dir/08_HARDWARE_AND_27_PILLARS.md"
                    ;;
                security|attestation|sbom)
                    target_file="$manual_dir/09_SECURITY_AND_ATTESTATION.md"
                    ;;
                ai|agent|copilot)
                    target_file="$manual_dir/10_AI_AGENT_REFERENCE.md"
                    ;;
                all)
                    target_file="ALL"
                    ;;
                *)
                    target_file=""
                    ;;
            esac

            local text_payload=""
            if [[ "$target_file" == "ALL" ]]; then
                for f in "$manual_dir"/[0-9][0-9]_*.md; do
                    if [[ -f "$f" ]]; then
                        text_payload+="$(cat "$f")"$'\n\n---\n\n'
                    fi
                done
            elif [[ -n "$target_file" && -f "$target_file" ]]; then
                text_payload=$(cat "$target_file")
            else
                text_payload=$(printf 'Error: Manual topic "%s" not found in %s.\nAvailable topics: index, arch, config, cli, storage, shadow, dev, mcp, hardware, security, ai, all' "$topic" "$manual_dir")
            fi

            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        *)
            send_error "$req_id" -32602 "Tool '${tool_name}' is not recognized by NEURONIX MCP server"
            ;;
    esac
}

handle_resources_list() {
    local req_id="$1"
    local result
    result=$(cat << 'RES_EOF'
{
  "resources": [
    {
      "uri": "neuronix://manual/index",
      "name": "NEURONIX Technical Manual Index",
      "description": "Master navigation index and documentation structure for NEURONIX OS",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/architecture",
      "name": "Platform Architecture Specification",
      "description": "4-Layer platform model, pure-functional Nix substrate, and Proof Class taxonomy",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/configuration",
      "name": "Declarative Configuration Reference",
      "description": "Complete neuronix.* NixOS option schema and contracts",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/cli",
      "name": "Unified CLI Reference Manual",
      "description": "Syntax, options, and operational specification for all 18 CLI commands",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/storage",
      "name": "Storage Architecture and Rollback Engine",
      "description": "Btrfs 5-subvolume topology, ZSTD compression, and rollback state machine",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/shadow-vm",
      "name": "Shadow Micro-VM Sandbox",
      "description": "In-memory RAM sandbox execution and smoke testing engine",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/dev-stacks",
      "name": "Hermetic Developer Stacks",
      "description": "Isolated developer environments and JSON manifests",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/mcp",
      "name": "Model Context Protocol Gateway",
      "description": "JSON-RPC 2.0 stdio server specification and tool catalog",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/hardware",
      "name": "Hardware Profiles and 27 Optimization Pillars",
      "description": "Reference hardware qualification and Linux optimization pillars",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/security",
      "name": "Security Boundaries and Supply Chain",
      "description": "Privilege allowlist, TPM2, Secure Boot, and SPDX 2.3 SBOM",
      "mimeType": "text/markdown"
    },
    {
      "uri": "neuronix://manual/ai-directives",
      "name": "AI Copilot System Directives and Guardrails",
      "description": "Mandatory operational rules, semantic directives, and hallucination guardrails for AI models",
      "mimeType": "text/markdown"
    }
  ]
}
RES_EOF
)
    result="$(echo "$result" | jq -c .)"
    send_response "$req_id" "$result"
}

handle_resources_read() {
    local req_id="$1"
    local uri="$2"

    local manual_dir="/etc/neuronix/manual"
    if [[ ! -d "$manual_dir" ]]; then
        local real_bin
        real_bin="$(readlink -f "${BASH_SOURCE[0]}")"
        local script_dir
        script_dir="$(cd "$(dirname "$real_bin")" && pwd)"
        manual_dir="${script_dir}/../docs/manual"
    fi
    if [[ ! -d "$manual_dir" && -n "${PROJECT_ROOT:-}" && -d "${PROJECT_ROOT}/docs/manual" ]]; then
        manual_dir="${PROJECT_ROOT}/docs/manual"
    fi
    if [[ ! -d "$manual_dir" && -d "$(pwd)/docs/manual" ]]; then
        manual_dir="$(pwd)/docs/manual"
    fi

    local target_file=""
    case "$uri" in
        neuronix://manual/index) target_file="$manual_dir/00_INDEX.md" ;;
        neuronix://manual/architecture|neuronix://manual/arch) target_file="$manual_dir/01_ARCHITECTURE.md" ;;
        neuronix://manual/configuration|neuronix://manual/config) target_file="$manual_dir/02_CONFIGURATION_REFERENCE.md" ;;
        neuronix://manual/cli) target_file="$manual_dir/03_CLI_REFERENCE.md" ;;
        neuronix://manual/storage) target_file="$manual_dir/04_STORAGE_AND_ROLLBACK.md" ;;
        neuronix://manual/shadow-vm|neuronix://manual/shadow) target_file="$manual_dir/05_SHADOW_VM_AND_SANDBOX.md" ;;
        neuronix://manual/dev-stacks|neuronix://manual/dev) target_file="$manual_dir/06_DEVELOPER_STACKS.md" ;;
        neuronix://manual/mcp) target_file="$manual_dir/07_MCP_PROTOCOL_AND_AI_GATEWAY.md" ;;
        neuronix://manual/hardware) target_file="$manual_dir/08_HARDWARE_AND_27_PILLARS.md" ;;
        neuronix://manual/security) target_file="$manual_dir/09_SECURITY_AND_ATTESTATION.md" ;;
        neuronix://manual/ai-directives|neuronix://manual/ai) target_file="$manual_dir/10_AI_AGENT_REFERENCE.md" ;;
        *) target_file="" ;;
    esac

    if [[ -n "$target_file" && -f "$target_file" ]]; then
        local text_payload
        text_payload=$(cat "$target_file")
        local result
        result=$(jq -n -c --arg uri "$uri" --arg text "$text_payload" \
            '{"contents":[{"uri":$uri,"mimeType":"text/markdown","text":$text}]}')
        send_response "$req_id" "$result"
    else
        send_error "$req_id" -32002 "Resource URI not found: '$uri'"
    fi
}

handle_prompts_list() {
    local req_id="$1"
    local result
    result=$(cat << 'PROMPT_EOF'
{
  "prompts": [
    {
      "name": "neuronix_system_directive",
      "description": "Primary operating system guidelines, declarative contracts, and guardrails for AI agents",
      "arguments": []
    }
  ]
}
PROMPT_EOF
)
    result="$(echo "$result" | jq -c .)"
    send_response "$req_id" "$result"
}

handle_prompts_get() {
    local req_id="$1"
    local prompt_name="$2"

    if [[ "$prompt_name" != "neuronix_system_directive" ]]; then
        send_error "$req_id" -32602 "Prompt '$prompt_name' not found"
        return 0
    fi

    local manual_dir="/etc/neuronix/manual"
    if [[ ! -d "$manual_dir" ]]; then
        local real_bin
        real_bin="$(readlink -f "${BASH_SOURCE[0]}")"
        local script_dir
        script_dir="$(cd "$(dirname "$real_bin")" && pwd)"
        manual_dir="${script_dir}/../docs/manual"
    fi
    if [[ ! -d "$manual_dir" && -n "${PROJECT_ROOT:-}" && -d "${PROJECT_ROOT}/docs/manual" ]]; then
        manual_dir="${PROJECT_ROOT}/docs/manual"
    fi
    if [[ ! -d "$manual_dir" && -d "$(pwd)/docs/manual" ]]; then
        manual_dir="$(pwd)/docs/manual"
    fi

    local text_payload=""
    if [[ -f "$manual_dir/10_AI_AGENT_REFERENCE.md" ]]; then
        text_payload=$(cat "$manual_dir/10_AI_AGENT_REFERENCE.md")
    else
        text_payload="NEURONIX OS Declarative Platform Directives Active."
    fi

    local result
    result=$(jq -n -c --arg text "$text_payload" \
        '{"description":"NEURONIX AI System Directives","messages":[{"role":"user","content":{"type":"text","text":$text}}]}')
    send_response "$req_id" "$result"
}

# Main JSON-RPC 2.0 Loop over stdio
run_mcp_server() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignore empty lines
        [[ -z "${line// }" ]] && continue

        # Robust JSON Parsing via jq
        if ! echo "$line" | jq empty 2>/dev/null; then
            send_error "null" -32700 "Parse error: Invalid JSON received"
            continue
        fi

        # Extract ID (numeric, string, or null)
        local req_id
        req_id=$(echo "$line" | jq -c '.id // null')

        # Extract method
        local method
        method=$(echo "$line" | jq -r '.method // empty')

        if [[ -z "$method" ]]; then
            send_error "$req_id" -32600 "Invalid Request: missing or malformed 'method' field"
            continue
        fi

        case "$method" in
            initialize)
                handle_initialize "$req_id"
                ;;
            notifications/initialized)
                # Standard MCP notification: silent acknowledgment (no response needed)
                ;;
            tools/list)
                handle_tools_list "$req_id"
                ;;
            tools/call)
                local tool_name
                tool_name=$(echo "$line" | jq -r '.params.name // empty')
                local params
                params=$(echo "$line" | jq -c '.params // {}')
                handle_tools_call "$req_id" "$tool_name" "$params"
                ;;
            resources/list)
                handle_resources_list "$req_id"
                ;;
            resources/read)
                local uri
                uri=$(echo "$line" | jq -r '.params.uri // empty')
                handle_resources_read "$req_id" "$uri"
                ;;
            prompts/list)
                handle_prompts_list "$req_id"
                ;;
            prompts/get)
                local prompt_name
                prompt_name=$(echo "$line" | jq -r '.params.name // empty')
                handle_prompts_get "$req_id" "$prompt_name"
                ;;
            ping)
                send_response "$req_id" "{}"
                ;;
            *)
                send_error "$req_id" -32601 "Method not found: '${method}'"
                ;;
        esac
    done
}

run_mcp_server
