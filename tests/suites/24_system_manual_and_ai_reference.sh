#!/usr/bin/env bash
# ==============================================================================
# Suite 24: System-Embedded Technical Manual & Native AI Reference Verification
# Validates offline documentation corpus, NixOS packaging, CLI, MCP, and AI copilot.
# ==============================================================================

DISTRO_PATH="${PROJECT_ROOT}"

start_suite "24 - System Manual & Native AI Reference Verification"

# 1-4. Declarative Packaging & Flake Contracts
assert_eq "$(test -f "${DISTRO_PATH}/modules/core/manual.nix" && echo "present" || echo "absent")" "present" "modules/core/manual.nix exists"
assert_eq "$(nix-instantiate --parse "${DISTRO_PATH}/modules/core/manual.nix" >/dev/null 2>&1 && echo "valid" || echo "invalid")" "valid" "modules/core/manual.nix parses cleanly"
assert_output_contains "grep -F './manual.nix' '${DISTRO_PATH}/modules/core/default.nix'" "manual.nix" "modules/core/default.nix imports manual.nix"
assert_output_contains "grep -F 'manual = import ./modules/core/manual.nix;' '${DISTRO_PATH}/flake.nix'" "manual" "flake.nix exports manual in nixosModules"

# 5-15. Manual Corpus Existence (All 11 Chapters)
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/00_INDEX.md" && echo "present" || echo "absent")" "present" "docs/manual/00_INDEX.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/01_ARCHITECTURE.md" && echo "present" || echo "absent")" "present" "docs/manual/01_ARCHITECTURE.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/02_CONFIGURATION_REFERENCE.md" && echo "present" || echo "absent")" "present" "docs/manual/02_CONFIGURATION_REFERENCE.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/03_CLI_REFERENCE.md" && echo "present" || echo "absent")" "present" "docs/manual/03_CLI_REFERENCE.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/04_STORAGE_AND_ROLLBACK.md" && echo "present" || echo "absent")" "present" "docs/manual/04_STORAGE_AND_ROLLBACK.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/05_SHADOW_VM_AND_SANDBOX.md" && echo "present" || echo "absent")" "present" "docs/manual/05_SHADOW_VM_AND_SANDBOX.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/06_DEVELOPER_STACKS.md" && echo "present" || echo "absent")" "present" "docs/manual/06_DEVELOPER_STACKS.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/07_MCP_PROTOCOL_AND_AI_GATEWAY.md" && echo "present" || echo "absent")" "present" "docs/manual/07_MCP_PROTOCOL_AND_AI_GATEWAY.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/08_HARDWARE_AND_27_PILLARS.md" && echo "present" || echo "absent")" "present" "docs/manual/08_HARDWARE_AND_27_PILLARS.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/09_SECURITY_AND_ATTESTATION.md" && echo "present" || echo "absent")" "present" "docs/manual/09_SECURITY_AND_ATTESTATION.md exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/manual/10_AI_AGENT_REFERENCE.md" && echo "present" || echo "absent")" "present" "docs/manual/10_AI_AGENT_REFERENCE.md exists"

# 16-17. Compact Footprint (< 350 KB) and Invariant Zero Em Dashes
TOTAL_MANUAL_KB=$(du -sk "${DISTRO_PATH}/docs/manual" | awk '{print $1}')
assert_eq "$(( TOTAL_MANUAL_KB < 350 ? 1 : 0 ))" "1" "Total manual corpus footprint is compact (< 350 KB: ${TOTAL_MANUAL_KB} KB)"
EM_DASH_COUNT=$(LC_ALL=C grep -rn $'\xe2\x80\x94' "${DISTRO_PATH}/docs/manual" 2>/dev/null | wc -l)
assert_eq "$EM_DASH_COUNT" "0" "Zero em dashes invariant maintained in docs/manual/"

# 18-29. Unified CLI Subcommand neuronix manual
NEURONIX_BIN="${DISTRO_PATH}/bin/neuronix"
assert_exit_code "'${NEURONIX_BIN}' manual --help" 0 "neuronix manual --help returns exit code 0"
assert_output_contains "'${NEURONIX_BIN}' manual --help" "AVAILABLE TOPICS" "neuronix manual --help lists available topics"
assert_output_contains "'${NEURONIX_BIN}' manual index" "NEURONIX OS Technical Manual" "neuronix manual index renders index"
assert_output_contains "'${NEURONIX_BIN}' manual arch" "Platform Architecture" "neuronix manual arch renders chapter 1"
assert_output_contains "'${NEURONIX_BIN}' manual config" "Declarative Configuration" "neuronix manual config renders chapter 2"
assert_output_contains "'${NEURONIX_BIN}' manual cli" "Unified CLI Command Reference" "neuronix manual cli renders chapter 3"
assert_output_contains "'${NEURONIX_BIN}' manual storage" "Storage Architecture & Atomic Rollback Engine" "neuronix manual storage renders chapter 4"
assert_output_contains "'${NEURONIX_BIN}' manual shadow" "Shadow Micro-VM" "neuronix manual shadow renders chapter 5"
assert_output_contains "'${NEURONIX_BIN}' manual dev" "Developer Environments" "neuronix manual dev renders chapter 6"
assert_output_contains "'${NEURONIX_BIN}' manual mcp" "Model Context Protocol" "neuronix manual mcp renders chapter 7"
assert_output_contains "'${NEURONIX_BIN}' manual hardware" "27 Hardware Configuration Pillars" "neuronix manual hardware renders chapter 8"
assert_output_contains "'${NEURONIX_BIN}' manual security" "Platform Security, Cryptography & Supply Chain" "neuronix manual security renders chapter 9"
assert_output_contains "'${NEURONIX_BIN}' manual ai" "AI Copilot System Directive" "neuronix manual ai renders chapter 10"
assert_exit_code "'${NEURONIX_BIN}' manual unknown_subtopic_xyz" 1 "neuronix manual rejects unknown topics with code 1"

# 30-32. Native MCP Server neuronix_manual Tool Verification
MCP_SERVER="${DISTRO_PATH}/src/mcp_server.sh"
assert_output_contains "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}' | '${MCP_SERVER}'" "neuronix_manual" "MCP server exports neuronix_manual tool"
assert_output_contains "echo '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"neuronix_manual\",\"topic\":\"arch\"}}' | '${MCP_SERVER}'" "Platform Architecture" "MCP server tool call returns chapter 1 content"
assert_output_contains "echo '{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"neuronix_manual\",\"topic\":\"ai\"}}' | '${MCP_SERVER}'" "AI Copilot System Directive" "MCP server tool call returns chapter 10 content"

# 33-35. OpenCode AI Copilot Integration
OPENCODE_BIN="${DISTRO_PATH}/packages/opencode/opencode-launcher.sh"
assert_output_contains "'${OPENCODE_BIN}' help" "manual [topic]" "OpenCode help lists manual command"
assert_output_contains "'${OPENCODE_BIN}' manual cli" "Unified CLI Command Reference" "OpenCode manual cli renders chapter 3"
assert_output_contains "echo '/manual config' | '${OPENCODE_BIN}'" "Declarative Configuration" "OpenCode interactive /manual renders chapter 2"

# 36-39. MCP Resources & Prompts Engine
assert_output_contains "echo '{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"resources/list\"}' | '${MCP_SERVER}'" "neuronix://manual/ai-directives" "MCP server exports resources/list with manual URIs"
assert_output_contains "echo '{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"resources/read\",\"params\":{\"uri\":\"neuronix://manual/ai-directives\"}}' | '${MCP_SERVER}'" "AI Copilot System Directive" "MCP server resources/read returns chapter 10"
assert_output_contains "echo '{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"prompts/list\"}' | '${MCP_SERVER}'" "neuronix_system_directive" "MCP server prompts/list exports system directive"
assert_output_contains "echo '{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"prompts/get\",\"params\":{\"name\":\"neuronix_system_directive\"}}' | '${MCP_SERVER}'" "AI Copilot System Directive" "MCP server prompts/get returns system prompt"

# 40-42. Ambient System Prompts & Autonomous AI Grounding
assert_output_contains "grep -F 'SYSTEM_PROMPT.md' '${DISTRO_PATH}/modules/core/manual.nix'" "SYSTEM_PROMPT.md" "manual.nix provisions root SYSTEM_PROMPT.md"
assert_output_contains "grep -F 'NEURONIX_MANUAL_DIR' '${DISTRO_PATH}/modules/core/manual.nix'" "NEURONIX_MANUAL_DIR" "manual.nix sets ambient NEURONIX_MANUAL_DIR"
assert_output_contains "echo 'exit' | '${OPENCODE_BIN}'" "Auto-Loaded (10_AI_AGENT_REFERENCE.md)" "OpenCode auto-loads system reference without user command"
