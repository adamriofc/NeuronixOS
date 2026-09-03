#!/usr/bin/env bash
# ==============================================================================
# Suite 19: Distro ADRs & Architecture Document Contracts (35 Tests)
# Validates technical decision records, platform layering, and specifications
# ==============================================================================

DOCS_PATH="${PROJECT_ROOT}/Distro/docs"

start_suite "19 - Distro ADRs & Platform Architecture Contracts"

# 1-7. ADR-001 Invariants
assert_output_contains "grep -F 'ADR-001' '${DOCS_PATH}/adr/ADR-001-why-flakes.md'" "ADR-001" "ADR-001 header exists"
assert_output_contains "grep -F 'Accepted' '${DOCS_PATH}/adr/ADR-001-why-flakes.md'" "Accepted" "ADR-001 is Accepted"
assert_output_contains "grep -F 'Context & Problem Statement' '${DOCS_PATH}/adr/ADR-001-why-flakes.md'" "Context" "ADR-001 has context section"
assert_output_contains "grep -F 'Architectural Decision' '${DOCS_PATH}/adr/ADR-001-why-flakes.md'" "Decision" "ADR-001 has decision section"
assert_output_contains "grep -F 'Consequences' '${DOCS_PATH}/adr/ADR-001-why-flakes.md'" "Consequences" "ADR-001 has consequences section"
assert_output_contains "grep -F 'flake.lock' '${DOCS_PATH}/adr/ADR-001-why-flakes.md'" "flake.lock" "ADR-001 specifies flake.lock pinning"
assert_output_contains "grep -F 'NIX_PATH' '${DOCS_PATH}/adr/ADR-001-why-flakes.md'" "NIX_PATH" "ADR-001 addresses NIX_PATH impurities"

# 8-14. ADR-002 Invariants
assert_output_contains "grep -F 'ADR-002' '${DOCS_PATH}/adr/ADR-002-why-calamares-flake-generator.md'" "ADR-002" "ADR-002 header exists"
assert_output_contains "grep -F 'Accepted' '${DOCS_PATH}/adr/ADR-002-why-calamares-flake-generator.md'" "Accepted" "ADR-002 is Accepted"
assert_output_contains "grep -F 'Declarative Flake Generator' '${DOCS_PATH}/adr/ADR-002-why-calamares-flake-generator.md'" "Declarative Flake Generator" "ADR-002 establishes Calamares role"
assert_output_contains "grep -F 'neuronix-install-engine.sh' '${DOCS_PATH}/adr/ADR-002-why-calamares-flake-generator.md'" "neuronix-install-engine.sh" "ADR-002 cites engine script"
assert_output_contains "grep -F 'nixos-install' '${DOCS_PATH}/adr/ADR-002-why-calamares-flake-generator.md'" "nixos-install" "ADR-002 uses official nixos-install"
assert_output_contains "grep -F 'Context & Problem Statement' '${DOCS_PATH}/adr/ADR-002-why-calamares-flake-generator.md'" "Context" "ADR-002 has context section"
assert_output_contains "grep -F 'Consequences' '${DOCS_PATH}/adr/ADR-002-why-calamares-flake-generator.md'" "Consequences" "ADR-002 has consequences section"

# 15-21. ADR-003 Invariants
assert_output_contains "grep -F 'ADR-003' '${DOCS_PATH}/adr/ADR-003-immutable-store-vs-flatpak.md'" "ADR-003" "ADR-003 header exists"
assert_output_contains "grep -F 'Accepted' '${DOCS_PATH}/adr/ADR-003-immutable-store-vs-flatpak.md'" "Accepted" "ADR-003 is Accepted"
assert_output_contains "grep -F 'Dual-Layer' '${DOCS_PATH}/adr/ADR-003-immutable-store-vs-flatpak.md'" "Dual-Layer" "ADR-003 defines Dual-Layer model"
assert_output_contains "grep -F 'Immutable Nix Core' '${DOCS_PATH}/adr/ADR-003-immutable-store-vs-flatpak.md'" "Immutable Nix Core" "ADR-003 guarantees core immutability"
assert_output_contains "grep -F 'Flathub' '${DOCS_PATH}/adr/ADR-003-immutable-store-vs-flatpak.md'" "Flathub" "ADR-003 enables Flathub marketplace"
assert_output_contains "grep -F 'xdg-desktop-portal' '${DOCS_PATH}/adr/ADR-003-immutable-store-vs-flatpak.md'" "xdg-desktop-portal" "ADR-003 enforces portal integration"
assert_output_contains "grep -F 'Consequences' '${DOCS_PATH}/adr/ADR-003-immutable-store-vs-flatpak.md'" "Consequences" "ADR-003 has consequences section"

# 22-28. ADR-004 & ADR-005 Invariants
assert_output_contains "grep -F 'ADR-004' '${DOCS_PATH}/adr/ADR-004-update-channel-strategy.md'" "ADR-004" "ADR-004 header exists"
assert_output_contains "grep -F 'Accepted' '${DOCS_PATH}/adr/ADR-004-update-channel-strategy.md'" "Accepted" "ADR-004 is Accepted"
assert_output_contains "grep -F 'strictly avoids forking' '${DOCS_PATH}/adr/ADR-004-update-channel-strategy.md'" "forking" "ADR-004 strictly prohibits fork"
assert_output_contains "grep -F 'ADR-005' '${DOCS_PATH}/adr/ADR-005-hardware-detection-architecture.md'" "ADR-005" "ADR-005 header exists"
assert_output_contains "grep -F 'Accepted' '${DOCS_PATH}/adr/ADR-005-hardware-detection-architecture.md'" "Accepted" "ADR-005 is Accepted"
assert_output_contains "grep -F 'NVIDIA' '${DOCS_PATH}/adr/ADR-005-hardware-detection-architecture.md'" "NVIDIA" "ADR-005 specifies NVIDIA PRIME offload"
assert_output_contains "grep -F 'enableAllFirmware' '${DOCS_PATH}/adr/ADR-005-hardware-detection-architecture.md'" "enableAllFirmware" "ADR-005 mandates full offline firmware"

# 29-35. Architecture & Installation Guides
assert_output_contains "grep -F '4-Layer Platform' '${DOCS_PATH}/architecture.md'" "4-Layer Platform" "Architecture guide contains 4-Layer model"
assert_output_contains "grep -F 'UX LAYER' '${DOCS_PATH}/architecture.md'" "UX LAYER" "Architecture guide defines UX Layer"
assert_output_contains "grep -F 'SYSTEM LAYER' '${DOCS_PATH}/architecture.md'" "SYSTEM LAYER" "Architecture guide defines System Layer"
assert_output_contains "grep -F 'INFRASTRUCTURE LAYER' '${DOCS_PATH}/architecture.md'" "INFRASTRUCTURE LAYER" "Architecture guide defines Infrastructure Layer"
assert_output_contains "grep -F 'System Requirements' '${DOCS_PATH}/installation.md'" "Requirements" "Installation guide specifies requirements"
assert_output_contains "grep -F 'Btrfs ZSTD:3' '${DOCS_PATH}/installation.md'" "Btrfs" "Installation guide specifies Btrfs ZSTD"
assert_output_contains "grep -F 'Calamares Installation' '${DOCS_PATH}/installation.md'" "Calamares" "Installation guide outlines Calamares workflow"
