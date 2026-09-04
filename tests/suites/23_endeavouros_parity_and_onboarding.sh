#!/usr/bin/env bash
# ==============================================================================
# Suite 23: EndeavourOS Parity, Onboarding Experience & Distro Polish Contracts
# Validates Doctor diagnostics, Welcome onboarding, Quickstart catalog,
# Declarative Kernel manager, 4K Artwork assets, and desktop integration.
# ==============================================================================

DISTRO_PATH="${PROJECT_ROOT}"
TARGET_BIN="${DISTRO_PATH}/src/neuronix"

start_suite "23 - EndeavourOS Parity, Onboarding & Distro Polish Contracts"

# 1-7. Declarative Kernel Flavor Manager Contracts (boot.nix)
assert_eq "$(test -f "${DISTRO_PATH}/modules/hardware/boot.nix" && echo "present" || echo "absent")" "present" "modules/hardware/boot.nix exists"
assert_eq "$(nix-instantiate --parse "${DISTRO_PATH}/modules/hardware/boot.nix" >/dev/null 2>&1 && echo "valid" || echo "invalid")" "valid" "modules/hardware/boot.nix parses cleanly"
assert_output_contains "grep -F 'neuronix.hardware.kernelFlavor' '${DISTRO_PATH}/modules/hardware/boot.nix'" "kernelFlavor" "boot.nix defines kernelFlavor option"
assert_output_contains "grep -F 'types.enum [ \"default\" \"zen\" \"lts\" \"latest\" \"hardened\" ]' '${DISTRO_PATH}/modules/hardware/boot.nix'" "zen" "kernelFlavor supports zen, lts, latest, and hardened"
assert_output_contains "grep -F 'linuxPackages_zen' '${DISTRO_PATH}/modules/hardware/boot.nix'" "linuxPackages_zen" "boot.nix binds zen flavor to linuxPackages_zen"
assert_output_contains "grep -F 'linuxPackages_lts' '${DISTRO_PATH}/modules/hardware/boot.nix'" "linuxPackages_lts" "boot.nix binds lts flavor to linuxPackages_lts"
assert_output_contains "grep -F 'linuxPackages_hardened' '${DISTRO_PATH}/modules/hardware/boot.nix'" "linuxPackages_hardened" "boot.nix binds hardened flavor to linuxPackages_hardened"

# 8-12. Distro Artwork & Branding Polish Contracts
assert_eq "$(test -f "${DISTRO_PATH}/artwork/wallpapers/neuronix-cyber-neural-dark.svg" && echo "present" || echo "absent")" "present" "4K wallpaper SVG asset exists"
assert_output_contains "head -n 2 '${DISTRO_PATH}/artwork/wallpapers/neuronix-cyber-neural-dark.svg'" "<svg" "Wallpaper file is valid SVG"
assert_output_contains "grep -F 'viewBox=\"0 0 3840 2160\"' '${DISTRO_PATH}/artwork/wallpapers/neuronix-cyber-neural-dark.svg'" "3840" "Wallpaper asset adheres to 3840x2160 (4K UHD) resolution"
assert_eq "$(test -f "${DISTRO_PATH}/artwork/branding/neuronix-badge.svg" && echo "present" || echo "absent")" "present" "Branding badge SVG asset exists"
assert_output_contains "head -n 2 '${DISTRO_PATH}/artwork/branding/neuronix-badge.svg'" "<svg" "Badge file is valid SVG"

# 13-18. Desktop Welcome Onboarding & Autostart Integration
assert_eq "$(test -f "${DISTRO_PATH}/packages/neuronix-center/neuronix-welcome.desktop" && echo "present" || echo "absent")" "present" "neuronix-welcome.desktop entry exists"
assert_output_contains "grep -F 'Type=Application' '${DISTRO_PATH}/packages/neuronix-center/neuronix-welcome.desktop'" "Type=Application" "Desktop entry is Type=Application"
assert_output_contains "grep -F 'Exec=neuronix-center --welcome' '${DISTRO_PATH}/packages/neuronix-center/neuronix-welcome.desktop'" "--welcome" "Desktop entry invokes welcome experience"
assert_eq "$(nix-instantiate --parse "${DISTRO_PATH}/modules/services/desktop-tweaks.nix" >/dev/null 2>&1 && echo "valid" || echo "invalid")" "valid" "modules/services/desktop-tweaks.nix parses cleanly"
assert_output_contains "grep -F 'neuronix-cyber-neural-dark.svg' '${DISTRO_PATH}/modules/services/desktop-tweaks.nix'" "neuronix-cyber-neural-dark.svg" "desktop-tweaks.nix links 4K wallpaper"
assert_output_contains "grep -F 'neuronix-welcome.desktop' '${DISTRO_PATH}/modules/services/desktop-tweaks.nix'" "neuronix-welcome.desktop" "desktop-tweaks.nix provisions onboarding autostart"

# 19-23. Doctor Diagnostics & Privacy Scrubbing Invariants
assert_exit_code "${TARGET_BIN} doctor --help" 0 "Command neuronix doctor --help exits 0"
assert_output_contains "${TARGET_BIN} doctor --json" "\"os\":" "neuronix doctor --json produces valid JSON schema"
assert_output_contains "${TARGET_BIN} doctor --json" "<sanitized-user>" "neuronix doctor scrubs active username"
DOCTOR_REPORT="/tmp/neuronix-doctor.md"
rm -f "$DOCTOR_REPORT"
"${TARGET_BIN}" doctor >/dev/null 2>&1
assert_eq "$(test -f "$DOCTOR_REPORT" && echo "present" || echo "absent")" "present" "neuronix doctor generates markdown report file"
assert_output_contains "head -n 5 '$DOCTOR_REPORT'" "🩺 NEURONIX OS Diagnostic Report" "Doctor report contains standard header"

# 24-25. Welcome Experience & CLI Onboarding
assert_exit_code "${TARGET_BIN} welcome --help" 0 "Command neuronix welcome --help exits 0"
assert_output_contains "${TARGET_BIN} welcome --cli" "SELAMAT DATANG DI NEURONIX" "neuronix welcome --cli renders onboarding interface"

# 26-27. Curated Quickstart App Catalog (Flathub / Flatpak)
assert_exit_code "${TARGET_BIN} quickstart --help" 0 "Command neuronix quickstart --help exits 0"
assert_output_contains "${TARGET_BIN} quickstart list" "com.brave.Browser" "Quickstart catalog lists curated application IDs"

# 28-29. Kernel Flavor Management Subcommands
assert_exit_code "${TARGET_BIN} kernel --help" 0 "Command neuronix kernel --help exits 0"
assert_output_contains "${TARGET_BIN} kernel list" "linuxPackages_zen" "neuronix kernel list outlines upstream kernel packages"

# 30. MCP Server JSON-RPC Protocol Exposure
assert_output_contains "grep -F 'neuronix_doctor' '${DISTRO_PATH}/src/mcp_server.sh'" "neuronix_doctor" "MCP server exports neuronix_doctor tool schema"
