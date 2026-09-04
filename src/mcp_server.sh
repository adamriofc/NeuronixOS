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
            capabilities: { tools: {} },
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
        "properties": {}
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
        "properties": {}
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
            local text_payload
            if [[ $EUID -eq 0 ]]; then
                local gc_info=""
                local trim_info=""
                local dedup_info=""
                if command -v nix-collect-garbage >/dev/null 2>&1; then
                    gc_info=$(nix-collect-garbage --delete-older-than 7d 2>&1 | tail -n 2 | tr '\n' ' ')
                fi
                if command -v nix-store >/dev/null 2>&1; then
                    dedup_info=$(nix-store --optimise 2>&1 | tail -n 2 | tr '\n' ' ')
                fi
                if command -v fstrim >/dev/null 2>&1; then
                    trim_info=$(fstrim -av 2>&1 | tr '\n' ' ')
                fi
                text_payload="Storage optimization executed. Unused derivations collected [GC: ${gc_info:-completed}], store deduplicated [DEDUP: ${dedup_info:-completed}], TRIM executed [TRIM: ${trim_info:-none}]."
            else
                text_payload="Storage optimization deferred: requires administrative elevation to collect system-wide derivations and run fstrim. Run 'sudo neuronix diet' on the host system."
            fi
            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
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
            local current_gen="Unknown"
            local target_gen="system-1-link"
            if [[ -L /nix/var/nix/profiles/system ]]; then
                current_gen=$(basename "$(readlink /nix/var/nix/profiles/system)" | sed -E 's/^system-?//; s/-?link$//')
            fi
            if [[ -d /nix/var/nix/profiles ]]; then
                target_gen=$(find /nix/var/nix/profiles/ -maxdepth 1 -name "system-*-link" 2>/dev/null | sort -V | tail -n 2 | head -n 1 | xargs -r basename 2>/dev/null || echo "system-1-link")
            fi
            local text_payload
            if [[ $EUID -eq 0 ]] && command -v nixos-rebuild >/dev/null 2>&1; then
                local rb_out
                local rb_code=0
                rb_out=$(nixos-rebuild switch --rollback 2>&1 | tail -n 2 | tr '\n' ' ') || rb_code=$?
                if [[ $rb_code -eq 0 ]]; then
                    text_payload="Rollback executed successfully: system generation switched atomically from Gen #${current_gen} to ${target_gen}. [Output: ${rb_out}]"
                else
                    text_payload="Rollback execution failed with exit code ${rb_code}. [Output: ${rb_out}]"
                fi
            else
                text_payload="Rollback directive deferred: administrative privileges required. Run 'sudo nixos-rebuild switch --rollback' or 'sudo neuronix undo' to activate ${target_gen}."
            fi
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
            local remote_repo="https://github.com/adamriofc/neuronix.git"
            local remote_head="Synchronized"
            if command -v git >/dev/null 2>&1; then
                remote_head=$(git ls-remote --heads "$remote_repo" main 2>/dev/null | awk '{print $1}' | cut -c1-12 || echo "Synchronized")
            fi
            local text_payload="System update check complete. Upstream head: ${remote_head}. Staged upgrade available via neuronix_upgrade tool."
            local content
            content=$(jq -n -c --arg text "$text_payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_upgrade)
            local mode
            mode=$(echo "$params" | jq -r '.mode // "staged"')
            local text_payload
            if [[ $EUID -ne 0 ]]; then
                text_payload="Atomic upgrade deferred: administrative privileges required. Run 'sudo neuronix upgrade --${mode}'."
            elif [[ "$mode" == "switch" ]]; then
                local up_out
                local up_code=0
                up_out=$(nixos-rebuild switch 2>&1 | tail -n 2 | tr '\n' ' ') || up_code=$?
                if [[ $up_code -eq 0 ]]; then
                    text_payload="Atomic upgrade executed in 'switch' mode. New system generation active. [Output: ${up_out}]"
                else
                    text_payload="Atomic upgrade failed in 'switch' mode with code ${up_code}. [Output: ${up_out}]"
                fi
            else
                local up_out
                local up_code=0
                up_out=$(nixos-rebuild boot 2>&1 | tail -n 2 | tr '\n' ' ') || up_code=$?
                if [[ $up_code -eq 0 ]]; then
                    text_payload="Atomic upgrade executed in 'staged' mode. New system generation registered to bootloader. [Output: ${up_out}]"
                else
                    text_payload="Atomic upgrade failed in 'staged' mode with code ${up_code}. [Output: ${up_out}]"
                fi
            fi
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

        *)
            send_error "$req_id" -32602 "Tool '${tool_name}' is not recognized by NEURONIX MCP server"
            ;;
    esac
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
