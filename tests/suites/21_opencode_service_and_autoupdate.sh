#!/usr/bin/env bash
# ==============================================================================
# Suite 21: OpenCode Autonomous AI Coding Agent & Background Update Verification
# Validates package derivations, declarative options, systemd timers, and XDG entries.
# ==============================================================================

DISTRO_PATH="${PROJECT_ROOT}"

start_suite "21 - OpenCode AI Copilot & Autonomous Update Verification"

# 1-5. File Existence, Upstream Source & Derivation Syntactic Parsing
assert_eq "$(test -f "${DISTRO_PATH}/modules/services/opencode.nix" && echo "present" || echo "absent")" "present" "modules/services/opencode.nix exists"
assert_eq "$(test -f "${DISTRO_PATH}/packages/opencode/default.nix" && echo "present" || echo "absent")" "present" "packages/opencode/default.nix exists"
assert_output_contains "grep -F 'anomalyco/opencode' '${DISTRO_PATH}/packages/opencode/default.nix'" "anomalyco/opencode" "Package sources authentic upstream anomalyco/opencode"
assert_eq "$(nix-instantiate --parse "${DISTRO_PATH}/modules/services/opencode.nix" >/dev/null 2>&1 && echo "valid" || echo "invalid")" "valid" "modules/services/opencode.nix parses cleanly"
assert_eq "$(nix-instantiate --parse "${DISTRO_PATH}/packages/opencode/default.nix" >/dev/null 2>&1 && echo "valid" || echo "invalid")" "valid" "packages/opencode/default.nix parses cleanly"

# 6-9. OpenCode Authentic Package Derivation Invariants
assert_output_contains "grep -F 'pname = \"opencode\";' '${DISTRO_PATH}/packages/opencode/default.nix'" "opencode" "Derivation specifies pname opencode"
assert_output_contains "grep -F 'version = \"1.18.29\";' '${DISTRO_PATH}/packages/opencode/default.nix'" "1.18.29" "Derivation packages canonical upstream version 1.18.29"
assert_output_contains "grep -F 'opencode-linux-x64.tar.gz' '${DISTRO_PATH}/packages/opencode/default.nix'" "opencode-linux-x64.tar.gz" "Derivation targets upstream x86_64 release asset"
assert_output_contains "grep -F 'opencode-linux-arm64.tar.gz' '${DISTRO_PATH}/packages/opencode/default.nix'" "opencode-linux-arm64.tar.gz" "Derivation targets upstream aarch64 release asset"

# 10-14. Declarative Service Module & Option Invariants
assert_output_contains "grep -F 'services.opencode' '${DISTRO_PATH}/modules/services/opencode.nix'" "opencode" "Module declares opencode option hierarchy"
assert_output_contains "grep -F 'default = true;' '${DISTRO_PATH}/modules/services/opencode.nix'" "default = true;" "Module sets default = true for enablement"
assert_output_contains "grep -F 'autoUpdate' '${DISTRO_PATH}/modules/services/opencode.nix'" "autoUpdate" "Module defines autoUpdate sub-options"
assert_output_contains "grep -F 'interval' '${DISTRO_PATH}/modules/services/opencode.nix'" "interval" "Module defines autoUpdate interval"
assert_output_contains "grep -F 'desktopShortcut' '${DISTRO_PATH}/modules/services/opencode.nix'" "desktopShortcut" "Module defines desktopShortcut option"

# 15-17. Background Systemd Automation Invariants
assert_output_contains "grep -F 'systemd.services.neuronix-opencode-update' '${DISTRO_PATH}/modules/services/opencode.nix'" "neuronix-opencode-update" "Systemd update service is declared"
assert_output_contains "grep -F 'systemd.timers.neuronix-opencode-update' '${DISTRO_PATH}/modules/services/opencode.nix'" "neuronix-opencode-update" "Systemd update timer is declared"
assert_output_contains "grep -F 'ExecStart' '${DISTRO_PATH}/modules/services/opencode.nix'" "ExecStart" "Service configures background update ExecStart"

# 18-20. XDG Desktop Entry & Packaging Invariants
assert_output_contains "grep -F 'makeDesktopItem' '${DISTRO_PATH}/packages/opencode/default.nix'" "makeDesktopItem" "Package declares makeDesktopItem"
assert_output_contains "grep -F 'name = \"opencode\";' '${DISTRO_PATH}/packages/opencode/default.nix'" "name = \"opencode\";" "Package names desktop entry opencode"
assert_output_contains "grep -F 'Development' '${DISTRO_PATH}/packages/opencode/default.nix'" "Development" "Desktop entry categorized under Development"

# 21-23. Flake Output & Module Registration Invariants
assert_output_contains "grep -F 'opencode = import ./modules/services/opencode.nix;' '${DISTRO_PATH}/flake.nix'" "opencode" "Flake exports opencode in nixosModules"
assert_output_contains "grep -F './modules/services/opencode.nix' '${DISTRO_PATH}/flake.nix'" "opencode.nix" "Flake includes opencode in neuronix-desktop"
assert_output_contains "grep -F 'opencode = pkgs.callPackage ./packages/opencode { };' '${DISTRO_PATH}/flake.nix'" "packages/opencode" "Flake exports opencode in packages"

# 24-25. Installer Engine Target Generation & Manifest Invariants
MOCK_CONFIG="/tmp/neuronix-mock-install/etc/nixos/configuration.nix"
MOCK_MANIFEST="/tmp/neuronix-mock-install/etc/neuronix/release.json"
assert_output_contains "grep -F 'neuronix.services.opencode' '$MOCK_CONFIG'" "neuronix.services.opencode" "Installer configures opencode in target configuration"
assert_output_contains "grep -F '\"ai_agent\": \"opencode\"' '$MOCK_MANIFEST'" "opencode" "Target release manifest registers opencode"
