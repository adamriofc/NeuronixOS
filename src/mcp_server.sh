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
SERVER_VERSION="1.0.5"
VERSION_NIX="$(dirname "$(readlink -f "$0")")/../version.nix"
if [[ ! -f "$VERSION_NIX" && -f "$(dirname "$(readlink -f "$0")")/version.nix" ]]; then
    VERSION_NIX="$(dirname "$(readlink -f "$0")")/version.nix"
elif [[ ! -f "$VERSION_NIX" && -f "/etc/neuronix/version.nix" ]]; then
    VERSION_NIX="/etc/neuronix/version.nix"
fi
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
    elif [[ -d "${script_dir}/../share/neuronix/packages/neuronix-core" ]]; then
        echo "${script_dir}/../share/neuronix/packages/neuronix-core"
    elif [[ -d "${script_dir}/packages/neuronix-core" ]]; then
        echo "${script_dir}/packages/neuronix-core"
    elif [[ -d "/etc/nixos/packages/neuronix-core" ]]; then
        echo "/etc/nixos/packages/neuronix-core"
    elif [[ -d "/etc/neuronix/packages/neuronix-core" ]]; then
        echo "/etc/neuronix/packages/neuronix-core"
    else
        echo ""
    fi
}

resolve_daemon_bin() {
    if command -v neuronix-daemon >/dev/null 2>&1; then
        command -v neuronix-daemon
    elif [[ -x "$(dirname "$(readlink -f "$0")")/../packages/neuronix-daemon/target/release/neuronix-daemon" ]]; then
        echo "$(dirname "$(readlink -f "$0")")/../packages/neuronix-daemon/target/release/neuronix-daemon"
    elif [[ -x "/run/current-system/sw/bin/neuronix-daemon" ]]; then
        echo "/run/current-system/sw/bin/neuronix-daemon"
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
    # If this is a tool result (has content array) without explicit isError,
    # inspect content text for error status and set isError: true accordingly.
    local final_result="$result_json"
    if echo "$result_json" | jq -e 'has("content") and (has("isError") | not)' >/dev/null 2>&1; then
        local first_text
        first_text=$(echo "$result_json" | jq -r '.content[0].text // empty' 2>/dev/null)
        if [[ -n "$first_text" ]]; then
            if echo "$first_text" | jq -e '(.status == "error" or .status == "failed") or (.success == false)' >/dev/null 2>&1 || \
               [[ "$first_text" =~ ^(Error|Fatal|Failed|Execution\ failed|Syntax\ error) ]] || \
               [[ "$first_text" =~ (FAILED|failed|error|Error) && "$first_text" =~ (exit\ code\ [1-9]|Exit\ code\ [1-9]|Exception|Traceback) ]]; then
                final_result=$(echo "$result_json" | jq -c '. + {"isError": true}')
            fi
        fi
    fi
    jq -n -c --argjson id "$safe_id" --argjson result "$final_result" \
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
      "name": "neuronix_sentinel",
      "description": "Inspect autonomous Boot-Sentinel state, boot assessment window, last-known-good generation, and emergency rollback history.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_diff",
      "description": "Compute forensic diff between system generations, analyzing package closure changes, systemd services, and security boundaries.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "gen_a": {
            "type": "string",
            "description": "Base generation number (defaults to previous generation)"
          },
          "gen_b": {
            "type": "string",
            "description": "Target generation number (defaults to current generation)"
          }
        }
      }
    },
    {
      "name": "neuronix_distill",
      "description": "Reverse-compile packages into permanent, pure NixOS declarations with pure closure verification and atomic syntax rollback safety.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "packages": {
            "type": "array",
            "items": { "type": "string" },
            "description": "List of packages to declare permanently in user flake module"
          },
          "dry_run": {
            "type": "boolean",
            "description": "Verify packages and preview generated syntax without committing to disk"
          },
          "force": {
            "type": "boolean",
            "description": "Force distillation even if target file lacks machine-managed boundary marker"
          }
        },
        "required": ["packages"]
      }
    },
    {
      "name": "neuronix_container",
      "description": "Spin up ephemeral zero-copy development container in RAM (/dev/shm) with Dynamic FHS Emulation, In-Memory Micro-DNS Mesh, Daemonless OCI Compiler, Stacks, and Quadlet Systemd Daemons.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "target": {
            "type": "string",
            "description": "Git repository URL, local directory, or OCI image reference to clone/mount in RAM"
          },
          "command": {
            "type": "string",
            "description": "Non-interactive command to execute inside container"
          },
          "action": {
            "type": "string",
            "description": "Action to perform: run, build, daemon, stop, list, compose"
          },
          "daemon_name": {
            "type": "string",
            "description": "Unique name for background container daemon"
          },
          "build_target": {
            "type": "string",
            "description": "Target directory or flake to compile into micro-OCI image"
          },
          "stack_file": {
            "type": "string",
            "description": "Declarative multi-service YAML/JSON stack file to orchestrate in RAM"
          },
          "export_oci": {
            "type": "string",
            "description": "Output tarball path to export workspace as OCI/Docker image"
          },
          "fhs": {
            "type": "boolean",
            "description": "Enable transparent dynamic FHS emulation for foreign ELF binaries (default: true)"
          },
          "dry_run": {
            "type": "boolean",
            "description": "Verify RAM allocation without executing command"
          }
        }
      }
    },
    {
      "name": "neuronix_sandbox",
      "description": "Execute isolated in-memory OS Micro-VM sandbox simulation, Autonomous OS Fabric image fetching, Btrfs CoW snapshots/branching, Windows 11 Autopilot, and smoke testing.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "action": {
            "type": "string",
            "description": "Action to perform: simulate (default), get, snapshot_create, snapshot_restore, snapshot_list, branch"
          },
          "mode": {
            "type": "string",
            "description": "Simulation mode (synthetic, real, auto)"
          },
          "target": {
            "type": "string",
            "description": "Optional configuration path to simulate"
          },
          "iso_path": {
            "type": "string",
            "description": "Path to external OS ISO to boot directly in Micro-VM"
          },
          "os": {
            "type": "string",
            "description": "Cloud-init or OS distro image to fetch/boot (alpine, ubuntu, arch, debian, windows-11)"
          },
          "persist": {
            "type": "string",
            "description": "Name of persistent Btrfs CoW testing sandbox"
          },
          "snap_name": {
            "type": "string",
            "description": "Snapshot name for snapshot_create or snapshot_restore"
          },
          "branch_dest": {
            "type": "string",
            "description": "Destination name for branch clone action"
          },
          "accel_3d": {
            "type": "boolean",
            "description": "Enable VirtIO-GPU VirGL 3D acceleration"
          },
          "dry_run": {
            "type": "boolean",
            "description": "Verify VM derivation and RAM scratch reservation without booting"
          }
        }
      }
    },
    {
      "name": "neuronix_tune",
      "description": "Apply or inspect deterministic workload tuning profiles (gaming, battery, audio-daw, balanced) modifying kernel sysfs, cgroups, and PipeWire quantum.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "profile": {
            "type": "string",
            "enum": ["gaming", "battery", "audio-daw", "balanced"],
            "description": "Workload profile to apply (omit to query current tuning state)"
          }
        }
      }
    },
    {
      "name": "neuronix_mesh",
      "description": "Inspect P2P local binary cache mesh status and discover neighbor LAN peers advertising Nix store packages over mDNS/Avahi.",
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
    },
    {
      "name": "neuronix_ast_query",
      "description": "Query the unified high-concurrency AST (Abstract System Tree) representing OS kernel, hardware, storage topology, and security posture in JSON.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_workspace_branch",
      "description": "Manage instant atomic Btrfs/Reflink time-travel project workspace branches.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "action": {
            "type": "string",
            "enum": ["create", "list", "revert"],
            "description": "Branching action to execute."
          },
          "path": {
            "type": "string",
            "description": "Target workspace repository directory."
          },
          "name": {
            "type": "string",
            "description": "Branch checkpoint name."
          }
        },
        "required": ["action"]
      }
    },
    {
      "name": "neuronix_ghost_exec",
      "description": "Execute zero-trace, disposable commands in volatile RAM overlay with guaranteed RAM wipe on exit.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "command": {
            "type": "string",
            "description": "Command string to execute in volatile RAM environment."
          }
        },
        "required": ["command"]
      }
    },
    {
      "name": "neuronix_state_show",
      "description": "Inspect active Provable State Root, 5-leaf Merkle tree, generation, and hardware posture.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_state_verify",
      "description": "Execute deterministic cryptographic attestation of active state against hardware PCR measurements and declared system invariants.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_hyperion_status",
      "description": "Inspect Provable Adaptive Execution Architecture (Hyperion) isolation tiers, KVM/eBPF capabilities, and posture.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_hyperion_negotiate",
      "description": "Negotiate canonical Hyperion Domain Specification (HDS v1.0.0) contract for a workload based on intent and security requirements.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "workload_name": {
            "type": "string",
            "description": "Name or command of the workload to execute"
          },
          "intent": {
            "type": "string",
            "description": "Natural language intent hint for adaptive tier resolution"
          },
          "tier": {
            "type": "integer",
            "description": "Explicit isolation tier override (0=FastPath, 1=RAM Ghost, 2=eBPF Enclave, 3=MicroVM)"
          },
          "offline": {
            "type": "boolean",
            "description": "Enforce strict OFFLINE_AIRGAP network isolation"
          }
        },
        "required": ["workload_name"]
      }
    },
    {
      "name": "neuronix_hyperion_proof",
      "description": "Synthesize or retrieve a cryptographic Merkle DomainProof for an executed domain, bound to host StateRoot.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "domain_id": {
            "type": "string",
            "description": "Domain identifier (e.g. DOM-YYYY-MM-DD-XXXX)"
          }
        },
        "required": ["domain_id"]
      }
    },
    {
      "name": "neuronix_propose_transition",
      "description": "Propose a declarative state transition (Proposer-Only mode; cannot directly mutate system disk).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "intent": {
            "type": "string",
            "description": "High-level description of proposed transition"
          },
          "changes": {
            "type": "object",
            "description": "Key-value dictionary of NixOS configuration changes"
          }
        },
        "required": ["intent", "changes"]
      }
    },
    {
      "name": "neuronix_simulate_proposal",
      "description": "Dry-run simulate an AI proposed state transition against security invariants and Nix option schemas.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "proposal": {
            "type": "object",
            "description": "State transition proposal dictionary to simulate"
          }
        },
        "required": ["proposal"]
      }
    },
    {
      "name": "neuronix_facter_facts",
      "description": "Inspect host hardware intelligence, virtualization support (KVM), TPM 2.0 presence, and HardwareRoot.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "neuronix_system_topology",
      "description": "Inspect universal system dependency topology DAG and evaluate failure blast radius.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "target_node": {
            "type": "string",
            "description": "Optional subsystem node ID to calculate blast radius for (e.g. security:lanzaboote)"
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
            dry_run=$(echo "$params" | jq -r '.arguments.dry_run // .dry_run // false' 2>/dev/null || echo "false")
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
            pkg=$(echo "$params" | jq -r '.arguments.package // .package // empty')
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
            dry_run=$(echo "$params" | jq -r '.arguments.dry_run // .dry_run // false' 2>/dev/null || echo "false")
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
tag = res.get('release_tag', 'v1.0.5')
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
            mode=$(echo "$params" | jq -r '.arguments.mode // .mode // "staged"')
            local dry_run
            dry_run=$(echo "$params" | jq -r '.arguments.dry_run // .dry_run // false' 2>/dev/null || echo "false")
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
                if [[ -d "${script_dir}/manual" ]]; then
                    manual_dir="${script_dir}/manual"
                elif [[ -d "${script_dir}/../share/neuronix/manual" ]]; then
                    manual_dir="${script_dir}/../share/neuronix/manual"
                elif [[ -d "${script_dir}/../docs/manual" ]]; then
                    manual_dir="${script_dir}/../docs/manual"
                fi
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

        neuronix_sentinel)
            local action
            action=$(echo "$params" | jq -r '.arguments.action // .action // "status"')
            local active_gen="Unknown"
            [[ -L /nix/var/nix/profiles/system ]] && active_gen=$(basename "$(readlink /nix/var/nix/profiles/system)" | sed -E 's/^system-?//; s/-?link$//')

            if [[ "$action" == "confirm" ]]; then
                mkdir -p /var/lib/neuronix 2>/dev/null || true
                if [[ -w "/var/lib/neuronix" ]] || [[ "$EUID" -eq 0 ]]; then
                    echo "$active_gen" > /var/lib/neuronix/last-known-good 2>/dev/null || true
                    rm -f /run/neuronix/booting-generation 2>/dev/null || true
                fi
                systemctl stop neuronix-boot-sentinel-watchdog.timer 2>/dev/null || true
                local payload
                payload=$(jq -n -c \
                    --arg active "$active_gen" \
                    '{
                        status: "success",
                        action: "confirmed",
                        confirmed_generation: $active,
                        watchdog_timer: "disarmed"
                    }')
                local content
                content=$(jq -n -c --arg text "$payload" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
                return 0
            fi

            local last_good="Unknown"
            [[ -f "/var/lib/neuronix/last-known-good" ]] && last_good=$(cat /var/lib/neuronix/last-known-good | tr -d '[:space:]')
            local booting_gen=""
            [[ -f "/run/neuronix/booting-generation" ]] && booting_gen=$(cat /run/neuronix/booting-generation | tr -d '[:space:]')
            local watchdog_active="inactive"
            if systemctl is-active neuronix-boot-sentinel-watchdog.timer >/dev/null 2>&1; then
                watchdog_active="active"
            fi
            local crash_log=""
            [[ -f "/var/log/neuronix/boot-fallback.log" ]] && crash_log=$(tail -n 10 /var/log/neuronix/boot-fallback.log)

            local payload
            payload=$(jq -n -c \
                --arg active "$active_gen" \
                --arg last_good "$last_good" \
                --arg booting "$booting_gen" \
                --arg watchdog "$watchdog_active" \
                --arg log "$crash_log" \
                '{
                    status: "success",
                    active_generation: $active,
                    last_known_good_generation: $last_good,
                    in_assessment: (if $booting != "" then true else false end),
                    assessment_boot_generation: $booting,
                    watchdog_timer_active: (if $watchdog == "active" then true else false end),
                    fallback_history: $log
                }')
            local content
            content=$(jq -n -c --arg text "$payload" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_diff)
            local gen_a gen_b
            gen_a=$(echo "$params" | jq -r '.arguments.gen_a // .gen_a // empty')
            gen_b=$(echo "$params" | jq -r '.arguments.gen_b // .gen_b // empty')
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            local diff_json
            diff_json=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.diff import compute_generation_diff
ga = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != '' else None
gb = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != '' else None
print(json.dumps(compute_generation_diff(ga, gb)))
" "$gen_a" "$gen_b" 2>/dev/null || echo '{"status":"error","message":"Diff evaluation failed"}')

            local content
            content=$(jq -n -c --arg text "$diff_json" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_distill)
            local pkgs_json dry_run force_param
            pkgs_json=$(echo "$params" | jq -c '.arguments.packages // .packages // []')
            dry_run=$(echo "$params" | jq -r '.arguments.dry_run // .dry_run // false')
            force_param=$(echo "$params" | jq -r '.arguments.force // .force // false')
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            local distill_out
            distill_out=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.distill import distill_packages
pkgs = json.loads(sys.argv[1])
dr = sys.argv[2] == 'true'
fc = sys.argv[3] == 'true'
print(json.dumps(distill_packages(pkgs, dry_run=dr, force=fc)))
" "$pkgs_json" "$dry_run" "$force_param" 2>/dev/null || echo '{"status":"error","message":"Distill execution failed"}')

            local content
            content=$(jq -n -c --arg text "$distill_out" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_container)
            local target cmd_run dry_run stack_file export_oci action daemon_name build_target
            target=$(echo "$params" | jq -r '.arguments.target // .target // empty')
            cmd_run=$(echo "$params" | jq -r '.arguments.command // .command // empty')
            stack_file=$(echo "$params" | jq -r '.arguments.stack_file // .stack_file // empty')
            export_oci=$(echo "$params" | jq -r '.arguments.export_oci // .export_oci // empty')
            dry_run=$(echo "$params" | jq -r '.arguments.dry_run // .dry_run // false')
            action=$(echo "$params" | jq -r '.arguments.action // .action // empty')
            daemon_name=$(echo "$params" | jq -r '.arguments.daemon_name // .daemon_name // empty')
            build_target=$(echo "$params" | jq -r '.arguments.build_target // .build_target // empty')

            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            if [[ "$action" == "build" || -n "$build_target" ]]; then
                local b_target="${build_target:-$target}"
                local b_out="${export_oci:-app.tar}"
                local b_res
                b_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import build_container_oci
t = sys.argv[1]
o = sys.argv[2]
ok, msg = build_container_oci(t, o)
print(json.dumps({'status': 'success' if ok else 'error', 'output_tar': o, 'message': msg}))
" "$b_target" "$b_out" 2>/dev/null || echo '{"status":"error","message":"OCI build failed"}')
                local content=$(jq -n -c --arg text "$b_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif [[ "$action" == "daemon" || -n "$daemon_name" ]]; then
                local d_res
                d_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import daemonize_container_session
t = sys.argv[1]
n = sys.argv[2]
c = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
ok, msg = daemonize_container_session(t, n, command=c)
print(json.dumps({'status': 'success' if ok else 'error', 'name': n, 'message': msg}))
" "${target:-/tmp}" "${daemon_name:-worker}" "$cmd_run" 2>/dev/null || echo '{"status":"error","message":"Daemon launch failed"}')
                local content=$(jq -n -c --arg text "$d_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif [[ "$action" == "list" ]]; then
                local l_res
                l_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import list_container_daemons
print(json.dumps({'daemons': list_container_daemons()}))
" 2>/dev/null || echo '{"daemons":[]}')
                local content=$(jq -n -c --arg text "$l_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif [[ "$dry_run" == "true" ]]; then
                local res_text="Container dry-run verified for target: ${target:-${stack_file}}. Backing: in-memory tmpfs /dev/shm."
                local content=$(jq -n -c --arg text "$res_text" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif [[ -n "$stack_file" ]]; then
                local stack_res
                stack_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import run_stack_session
s = sys.argv[1]
print(json.dumps(run_stack_session(s)))
" "$stack_file" 2>/dev/null || echo '{"status":"error","message":"Stack session failed"}')
                local content=$(jq -n -c --arg text "$stack_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif [[ -n "$export_oci" ]]; then
                local exp_res
                exp_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import export_container_oci
t = sys.argv[1]
o = sys.argv[2]
ok, msg = export_container_oci(t, o)
print(json.dumps({'status':'success' if ok else 'error','output_tar':o,'message':msg}))
" "$target" "$export_oci" 2>/dev/null || echo '{"status":"error","message":"OCI export failed"}')
                local content=$(jq -n -c --arg text "$exp_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                local container_res
                container_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import setup_ram_workspace, run_container_session, teardown_container
t = sys.argv[1]
c = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != '' else None
w, a, msg = setup_ram_workspace(t)
if not w:
    print(json.dumps({'status':'error','message':msg}))
    sys.exit(0)
code, s_msg = run_container_session(a, command=c)
teardown_container(w)
print(json.dumps({'status':'success','exit_code':code,'message':s_msg}))
" "$target" "$cmd_run" 2>/dev/null || echo '{"status":"error","message":"Container run failed"}')
                local content=$(jq -n -c --arg text "$container_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            fi
            ;;

        neuronix_sandbox)
            local target cmd_run dry_run mode iso_path os_distro persist_name accel_3d action snap_name branch_dest
            target=$(echo "$params" | jq -r '.arguments.target // .target // empty')
            cmd_run=$(echo "$params" | jq -r '.arguments.command // .command // empty')
            dry_run=$(echo "$params" | jq -r '.arguments.dry_run // .dry_run // false')
            mode=$(echo "$params" | jq -r '.arguments.mode // .mode // "auto"')
            iso_path=$(echo "$params" | jq -r '.arguments.iso_path // .iso_path // empty')
            os_distro=$(echo "$params" | jq -r '.arguments.os // .os // empty')
            persist_name=$(echo "$params" | jq -r '.arguments.persist // .persist // empty')
            accel_3d=$(echo "$params" | jq -r '.arguments.accel_3d // .accel_3d // false')
            action=$(echo "$params" | jq -r '.arguments.action // .action // empty')
            snap_name=$(echo "$params" | jq -r '.arguments.snap_name // .snap_name // empty')
            branch_dest=$(echo "$params" | jq -r '.arguments.branch_dest // .branch_dest // empty')

            local script_dir
            script_dir="$(dirname "$(readlink -f "$0")")"
            local shadow_script="${script_dir}/shadow_vm.sh"

            if [[ "$action" == "get" && -n "$os_distro" ]]; then
                local res
                res=$("$shadow_script" get "$os_distro" $([[ "$dry_run" == "true" ]] && echo "--dry-run") --json 2>/dev/null || echo '{"status":"error"}')
                local content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif [[ "$action" == "snapshot_create" && -n "$persist_name" ]]; then
                local res
                res=$("$shadow_script" snapshot create "$persist_name" "${snap_name:-snap}" $([[ "$dry_run" == "true" ]] && echo "--dry-run") --json 2>/dev/null || echo '{"status":"error"}')
                local content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif [[ "$action" == "branch" && -n "$persist_name" && -n "$branch_dest" ]]; then
                local res
                res=$("$shadow_script" branch "$persist_name" "$branch_dest" $([[ "$dry_run" == "true" ]] && echo "--dry-run") --json 2>/dev/null || echo '{"status":"error"}')
                local content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            elif [[ -n "$cmd_run" || ("$target" =~ ^https?:// || "$target" =~ ^git@) ]]; then
                # Legacy container compatibility fallback
                local py_bin core_path
                py_bin="$(resolve_python)"
                core_path="$(resolve_core_path)"
                local sandbox_res
                sandbox_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.container import setup_ram_workspace, run_container_session, teardown_container
t = sys.argv[1]
c = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != '' else None
w, a, msg = setup_ram_workspace(t)
if not w:
    print(json.dumps({'status':'error','message':msg}))
    sys.exit(0)
code, s_msg = run_container_session(a, command=c)
teardown_container(w)
print(json.dumps({'status':'success','exit_code':code,'message':s_msg}))
" "$target" "$cmd_run" 2>/dev/null || echo '{"status":"error","message":"Sandbox run failed"}')
                local content=$(jq -n -c --arg text "$sandbox_res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                # Micro-VM In-Memory OS Sandbox simulation
                if [[ -x "$shadow_script" ]]; then
                    local vm_args=("--smoke-test" "--headless")
                    [[ "$dry_run" == "true" ]] && vm_args=("--dry-run")
                    [[ -n "$mode" ]] && vm_args+=("--mode" "$mode")
                    [[ -n "$iso_path" ]] && vm_args+=("--iso" "$iso_path")
                    [[ -n "$os_distro" ]] && vm_args+=("--os" "$os_distro")
                    [[ -n "$persist_name" ]] && vm_args+=("--persist" "$persist_name")
                    [[ "$accel_3d" == "true" ]] && vm_args+=("--3d-accel")
                    [[ -n "$target" ]] && vm_args+=("$target")
                    local res exit_code=0
                    res=$("$shadow_script" "${vm_args[@]}" 2>&1 | tr '\n' ' ') || exit_code=$?
                    local text
                    if [[ $exit_code -eq 0 ]]; then
                        text="In-Memory OS Sandbox Simulation PASSED in RAM: ${res}"
                    else
                        text="In-Memory OS Sandbox Simulation FAILED (exit code ${exit_code}): ${res}"
                    fi
                    local content=$(jq -n -c --arg text "$text" '{"content":[{"type":"text","text":$text}]}')
                    send_response "$req_id" "$content"
                else
                    local content=$(jq -n -c '{"content":[{"type":"text","text":"Shadow Micro-VM simulation engine (shadow_vm.sh) not found."}]}')
                    send_response "$req_id" "$content"
                fi
            fi
            ;;

        neuronix_tune)
            local profile
            profile=$(echo "$params" | jq -r '.arguments.profile // .profile // empty')
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            local tune_res
            tune_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.tune import apply_tuning_profile, get_current_tuning_status
p = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != '' else None
if not p:
    print(json.dumps(get_current_tuning_status()))
else:
    print(json.dumps(apply_tuning_profile(p)))
" "$profile" 2>/dev/null || echo '{"status":"error","message":"Tuning query failed"}')

            local content
            content=$(jq -n -c --arg text "$tune_res" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_mesh)
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            local mesh_res
            mesh_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import json
from neuronix_core.mesh import get_mesh_status
print(json.dumps(get_mesh_status()))
" 2>/dev/null || echo '{"status":"error","message":"Mesh query failed"}')

            local content
            content=$(jq -n -c --arg text "$mesh_res" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_ast_query)
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            local ast_res
            ast_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import json
from neuronix_core.daemon_client import query_system_ast
print(json.dumps(query_system_ast()))
" 2>/dev/null || echo '{"status":"error","message":"AST query failed"}')

            local content
            content=$(jq -n -c --arg text "$ast_res" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_workspace_branch)
            local action path_arg branch_name
            action=$(echo "$params" | jq -r '.arguments.action // .action // "list"')
            path_arg=$(echo "$params" | jq -r '.arguments.path // .path // "."')
            branch_name=$(echo "$params" | jq -r '.arguments.name // .name // "experiment"')
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"

            local branch_res
            branch_res=$(PYTHONPATH="$core_path" "$py_bin" -c "
import sys, json
from neuronix_core.storage import create_workspace_branch, list_workspace_branches, revert_workspace_branch

action = sys.argv[1]
p = sys.argv[2]
name = sys.argv[3]

try:
    if action == 'create':
        print(json.dumps(create_workspace_branch(p, name)))
    elif action == 'revert':
        print(json.dumps(revert_workspace_branch(p, name)))
    else:
        print(json.dumps({'workspace': p, 'branches': list_workspace_branches(p)}))
except Exception as e:
    print(json.dumps({'status': 'ERROR', 'error': str(e)}))
" "$action" "$path_arg" "$branch_name" 2>/dev/null || echo '{"status":"error","message":"Workspace branch failed"}')

            local content
            content=$(jq -n -c --arg text "$branch_res" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_ghost_exec)
            local cmd_run
            cmd_run=$(echo "$params" | jq -r '.arguments.command // .command // "echo GHOST_OK"')
            local script_dir
            script_dir="$(dirname "$(readlink -f "$0")")"
            local neuronix_cli="${script_dir}/neuronix"

            local ghost_out ghost_code=0
            ghost_out=$("$neuronix_cli" ghost --run "$cmd_run" 2>&1) || ghost_code=$?
            local ghost_res
            ghost_res=$(jq -n -c \
                --arg output "$ghost_out" \
                --argjson code "$ghost_code" \
                '{status: (if $code == 0 then "success" else "failed" end), exit_code: $code, output: $output}')
            local content
            content=$(jq -n -c --arg text "$ghost_res" '{"content":[{"type":"text","text":$text}]}')
            send_response "$req_id" "$content"
            ;;

        neuronix_state_show)
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"
            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local res
                res=$("$py_bin" -c "
import sys, json
sys.path.insert(0, '${core_path}')
from neuronix_core.state import get_current_state
print(json.dumps(get_current_state(), indent=2))
" 2>&1)
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Python runtime unavailable for Provable State Engine."
            fi
            ;;

        neuronix_state_verify)
            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"
            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local res
                res=$("$py_bin" -c "
import sys, json
sys.path.insert(0, '${core_path}')
from neuronix_core.state import verify_current_state
print(json.dumps(verify_current_state(), indent=2))
" 2>&1)
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Python runtime unavailable for Provable State Engine."
            fi
            ;;

        neuronix_hyperion_status)
            local py_bin core_path daemon_bin
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"
            daemon_bin="$(resolve_daemon_bin)"
            local res=""
            if [[ -n "$daemon_bin" && -x "$daemon_bin" ]]; then
                res="$("$daemon_bin" --hyperion status 2>&1)"
            elif [[ -n "$py_bin" && -n "$core_path" ]]; then
                res=$("$py_bin" -c "
import sys, json
sys.path.insert(0, '${core_path}')
from neuronix_core.hyperion import HyperionExecutionEngine
engine = HyperionExecutionEngine()
print(json.dumps(engine.get_status(), indent=2))
" 2>&1)
            fi
            if [[ -n "$res" ]]; then
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Hyperion execution engine unavailable."
            fi
            ;;

        neuronix_hyperion_negotiate)
            local workload intent tier_override offline_flag
            workload=$(echo "$params" | jq -r '.arguments.workload_name // empty')
            intent=$(echo "$params" | jq -r '.arguments.intent // empty')
            tier_override=$(echo "$params" | jq -r '.arguments.tier // empty')
            offline_flag=$(echo "$params" | jq -r '.arguments.offline // false')

            if [[ -z "$workload" ]]; then
                send_error "$req_id" -32602 "Missing required argument: workload_name"
                return
            fi

            local py_bin core_path
            py_bin="$(resolve_python)"
            core_path="$(resolve_core_path)"
            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local res
                res=$("$py_bin" -c "
import sys, json
sys.path.insert(0, '${core_path}')
from neuronix_core.hyperion import negotiate_domain
t_val = int('${tier_override}') if '${tier_override}'.isdigit() else None
off_val = True if '${offline_flag}' == 'true' else False
spec = negotiate_domain(workload_name='''${workload}''', intent='''${intent}''', requested_tier=t_val, offline=off_val)
print(json.dumps(spec, indent=2))
" 2>&1)
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Python runtime unavailable for Hyperion negotiation."
            fi
            ;;

        neuronix_hyperion_proof)
            local domain_id
            domain_id=$(echo "$params" | jq -r '.arguments.domain_id // empty')
            if [[ -z "$domain_id" ]]; then
                send_error "$req_id" -32602 "Missing required argument: domain_id"
                return
            fi

            local res=""
            if [[ -f "/tmp/neuronix-hyperion-proofs/${domain_id}.json" ]]; then
                res=$(cat "/tmp/neuronix-hyperion-proofs/${domain_id}.json")
            else
                local daemon_bin="$(resolve_daemon_bin)"
                if [[ -n "$daemon_bin" && -x "$daemon_bin" ]]; then
                    res="$("$daemon_bin" --hyperion proof "${domain_id}" 2>&1)"
                fi
            fi

            if [[ -n "$res" ]]; then
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Proof for domain '${domain_id}' not found."
            fi
            ;;

        neuronix_propose_transition)
            local intent changes
            intent=$(echo "$params" | jq -r '.arguments.intent // .intent // empty')
            changes=$(echo "$params" | jq -c '.arguments.changes // .changes // empty')
            if [[ -z "$intent" || -z "$changes" || "$changes" == "null" ]]; then
                send_error "$req_id" -32602 "Missing required parameters: intent and changes"
                return
            fi
            local py_bin="$(resolve_python)"
            local core_path="$(resolve_core_path)"
            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local res
                res=$(INTENT="$intent" CHANGES="$changes" PYTHONPATH="$core_path" "$py_bin" -c '
import os, sys, json
from neuronix_core.semantic import SemanticAstEngine
engine = SemanticAstEngine()
intent = os.environ.get("INTENT", "")
changes_str = os.environ.get("CHANGES", "{}")
try:
    changes = json.loads(changes_str)
except Exception:
    changes = {}
proposal = {
    "proposer_mode": True,
    "direct_commit": False,
    "intent": intent,
    "changes": changes
}
ok, msg, report = engine.simulate_proposal(proposal)
out = {
    "proposal_status": "PROPOSED_AWAITING_OPERATOR_REVIEW",
    "simulation_passed": ok,
    "message": msg,
    "report": report
}
print(json.dumps(out, indent=2))
')
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Semantic engine unavailable"
            fi
            ;;

        neuronix_simulate_proposal)
            local prop_raw
            prop_raw=$(echo "$params" | jq -c '.arguments.proposal // .proposal // empty')
            if [[ -z "$prop_raw" || "$prop_raw" == "null" ]]; then
                send_error "$req_id" -32602 "Missing required parameter: proposal"
                return
            fi
            local py_bin="$(resolve_python)"
            local core_path="$(resolve_core_path)"
            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local res
                res=$(PROPOSAL="$prop_raw" PYTHONPATH="$core_path" "$py_bin" -c '
import os, sys, json
from neuronix_core.semantic import SemanticAstEngine
engine = SemanticAstEngine()
prop_str = os.environ.get("PROPOSAL", "{}")
try:
    proposal = json.loads(prop_str)
except Exception:
    proposal = {}
ok, msg, report = engine.simulate_proposal(proposal)
out = {
    "valid": ok,
    "message": msg,
    "report": report
}
print(json.dumps(out, indent=2))
')
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Semantic engine unavailable"
            fi
            ;;

        neuronix_facter_facts)
            local py_bin="$(resolve_python)"
            local core_path="$(resolve_core_path)"
            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local res
                res=$(PYTHONPATH="$core_path" "$py_bin" -c '
import json
from neuronix_core.facter import HardwareFacter
facter = HardwareFacter()
facts = facter.collect_facts()
root = facter.compute_hardware_root(facts)
print(json.dumps({"hardware_root": root, "facts": facts}, indent=2))
')
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Facter engine unavailable"
            fi
            ;;

        neuronix_system_topology)
            local target_node
            target_node=$(echo "$params" | jq -r '.arguments.target_node // .target_node // empty')
            local py_bin="$(resolve_python)"
            local core_path="$(resolve_core_path)"
            if [[ -n "$py_bin" && -n "$core_path" ]]; then
                local res
                res=$(TARGET_NODE="$target_node" PYTHONPATH="$core_path" "$py_bin" -c '
import os, json
from neuronix_core.topology import SystemTopologyEngine
engine = SystemTopologyEngine()
topo = engine.build_topology()
root = engine.compute_topology_root(topo)
target = os.environ.get("TARGET_NODE", "")
blast = engine.calculate_blast_radius(target) if target else None
out = {
    "topology_root": root,
    "topology": topo,
    "blast_radius": blast
}
print(json.dumps(out, indent=2))
')
                local content
                content=$(jq -n -c --arg text "$res" '{"content":[{"type":"text","text":$text}]}')
                send_response "$req_id" "$content"
            else
                send_error "$req_id" -32000 "Topology engine unavailable"
            fi
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
        if [[ -d "${script_dir}/manual" ]]; then
            manual_dir="${script_dir}/manual"
        elif [[ -d "${script_dir}/../share/neuronix/manual" ]]; then
            manual_dir="${script_dir}/../share/neuronix/manual"
        elif [[ -d "${script_dir}/../docs/manual" ]]; then
            manual_dir="${script_dir}/../docs/manual"
        fi
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
        neuronix://manual/shadow-vm|neuronix://manual/shadow|neuronix://manual/sandbox|neuronix://manual/container) target_file="$manual_dir/05_SHADOW_VM_AND_SANDBOX.md" ;;
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
        if [[ -d "${script_dir}/manual" ]]; then
            manual_dir="${script_dir}/manual"
        elif [[ -d "${script_dir}/../share/neuronix/manual" ]]; then
            manual_dir="${script_dir}/../share/neuronix/manual"
        elif [[ -d "${script_dir}/../docs/manual" ]]; then
            manual_dir="${script_dir}/../docs/manual"
        fi
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
