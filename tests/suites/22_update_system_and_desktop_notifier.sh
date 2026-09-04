#!/usr/bin/env bash
# ==============================================================================
# Suite 22: Autonomous Update System, Desktop Notifier & Storage Diet Contracts
# Validates update policy, desktop notifications, staged rebuilds, and diet lifecycle.
# ==============================================================================

DISTRO_PATH="${PROJECT_ROOT}"
TARGET_BIN="${DISTRO_PATH}/src/neuronix"

start_suite "22 - Autonomous Update Policy & Desktop Notifier Contracts"

# 1-2. File Existence & Derivation Syntactic Parsing
assert_eq "$(test -f "${DISTRO_PATH}/modules/services/update.nix" && echo "present" || echo "absent")" "present" "modules/services/update.nix exists"
assert_eq "$(nix-instantiate --parse "${DISTRO_PATH}/modules/services/update.nix" >/dev/null 2>&1 && echo "valid" || echo "invalid")" "valid" "modules/services/update.nix parses cleanly"

# 3-8. Declarative Update Module Option Contracts
assert_output_contains "grep -F 'neuronix.services.updates' '${DISTRO_PATH}/modules/services/update.nix'" "neuronix.services.updates" "Module declares updates option hierarchy"
assert_output_contains "grep -F 'enable = lib.mkOption' '${DISTRO_PATH}/modules/services/update.nix'" "enable" "Module defines enable option"
assert_output_contains "grep -F 'enableNotifier' '${DISTRO_PATH}/modules/services/update.nix'" "enableNotifier" "Module defines enableNotifier option"
assert_output_contains "grep -F 'checkInterval' '${DISTRO_PATH}/modules/services/update.nix'" "checkInterval" "Module defines checkInterval option"
assert_output_contains "grep -F 'autoUpgrade' '${DISTRO_PATH}/modules/services/update.nix'" "autoUpgrade" "Module defines autoUpgrade option"
assert_output_contains "grep -F 'staged' '${DISTRO_PATH}/modules/services/update.nix'" "staged" "Module defines staged option"

# 9-12. Background Systemd Automation & Timer Binding
assert_output_contains "grep -F 'systemd.services.neuronix-update-check' '${DISTRO_PATH}/modules/services/update.nix'" "neuronix-update-check" "Systemd update-check service is declared"
assert_output_contains "grep -F 'systemd.timers.neuronix-update-check' '${DISTRO_PATH}/modules/services/update.nix'" "neuronix-update-check" "Systemd update-check timer is declared"
assert_output_contains "grep -F 'OnCalendar = cfg.checkInterval;' '${DISTRO_PATH}/modules/services/update.nix'" "checkInterval" "Timer respects configured interval"
assert_output_contains "grep -F 'wantedBy = [ \"timers.target\" ];' '${DISTRO_PATH}/modules/services/update.nix'" "timers.target" "Timer binds to timers.target"

# 13-14. Flake Output & Module Registration Invariants
assert_output_contains "grep -F 'update = import ./modules/services/update.nix;' '${DISTRO_PATH}/flake.nix'" "update" "Flake exports update in nixosModules"
assert_output_contains "grep -F './modules/services/update.nix' '${DISTRO_PATH}/flake.nix'" "update.nix" "Flake includes update in neuronix-desktop"

# 15-19. CLI Update Subcommands & Fault Injection Defense
assert_output_contains "${TARGET_BIN} help" "check-update" "CLI help index exposes check-update command"
assert_output_contains "${TARGET_BIN} help" "upgrade" "CLI help index exposes upgrade command"
assert_exit_code "${TARGET_BIN} check-update --help" 0 "Command neuronix check-update --help exits 0"
assert_exit_code "${TARGET_BIN} upgrade --help" 0 "Command neuronix upgrade --help exits 0"
assert_exit_code "${TARGET_BIN} upgrade --invalid-bogus-arg" 1 "Illegal upgrade argument is rejected with exit 1"

# 20-22. Control Center GUI & CLI Action Contracts
assert_output_contains "grep -F '--upgrade' '${DISTRO_PATH}/packages/neuronix-center/neuronix_center.py'" "--upgrade" "Center parser supports --upgrade flag"
assert_output_contains "grep -F '--check-update' '${DISTRO_PATH}/packages/neuronix-center/neuronix_center.py'" "--check-update" "Center parser supports --check-update flag"
assert_output_contains "grep -F 'on_upgrade' '${DISTRO_PATH}/packages/neuronix-center/neuronix_center.py'" "on_upgrade" "Center implements staged on_upgrade action"

# 23-24. MCP JSON-RPC Server Schema Verification
assert_output_contains "grep -F 'neuronix_check_update' '${DISTRO_PATH}/src/mcp_server.sh'" "neuronix_check_update" "MCP server exports neuronix_check_update tool"
assert_output_contains "grep -F 'neuronix_upgrade' '${DISTRO_PATH}/src/mcp_server.sh'" "neuronix_upgrade" "MCP server exports neuronix_upgrade tool"

# 25-26. Installer Target Generation & Manifest Invariants
MOCK_CONFIG="/tmp/neuronix-mock-install/etc/nixos/configuration.nix"
MOCK_MANIFEST="/tmp/neuronix-mock-install/etc/neuronix/release.json"
assert_output_contains "grep -F 'neuronix.services.updates' '$MOCK_CONFIG'" "neuronix.services.updates" "Installer configures update policy in target configuration"
assert_output_contains "grep -F '\"update_notifier\": \"enabled\"' '$MOCK_MANIFEST'" "enabled" "Target release manifest registers update_notifier"

# 27-30. Unified Storage Diet Invariants & Status Telemetry
assert_output_contains "grep -F 'nix.gc' '${DISTRO_PATH}/modules/services/storage.nix'" "nix.gc" "Storage module declares autonomous nix.gc"
assert_output_contains "grep -F 'nix.optimise' '${DISTRO_PATH}/modules/services/storage.nix'" "nix.optimise" "Storage module declares store deduplication"
assert_output_contains "grep -F 'min-free' '${DISTRO_PATH}/modules/services/storage.nix'" "min-free" "Storage module declares Dynamic Storage Guard"
assert_output_contains "${TARGET_BIN} status" "Desktop Update Mon" "Telemetry dashboard reports Desktop Update Monitor status"
