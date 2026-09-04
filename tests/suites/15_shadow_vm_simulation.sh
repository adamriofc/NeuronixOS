#!/usr/bin/env bash
# ==============================================================================
# Suite 15: Shadow Micro-VM Simulation & In-Memory Sandbox (30 Tests)
# Verifies ephemeral RAM-disk (/dev/shm) Micro-VM lifecycle, smoke tests,
# argument bounds, cleanup invariants, and MCP integration.
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
SHADOW_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/shadow_vm.sh"
MCP_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/mcp_server.sh"

start_suite "15 - Shadow Micro-VM Simulation & Ephemeral RAM Sandbox"

# 1-5. Script Existence, Executability & Help Documentation
assert_eq "$(test -f "$SHADOW_BIN" && echo "exists" || echo "missing")" "exists" "shadow_vm.sh script exists"
assert_eq "$(test -x "$SHADOW_BIN" && echo "executable" || echo "non-exec")" "executable" "shadow_vm.sh is executable"
assert_exit_code "$TARGET_BIN try --help" 0 "neuronix try --help exits 0"
assert_output_contains "$TARGET_BIN try --help" "Shadow Micro-VM Sandbox" "Help manual displays Shadow Micro-VM title"
assert_exit_code "$TARGET_BIN try -h" 0 "neuronix try -h exits 0"

# 6-9. Dry-Run & RAM Scratch Allocation Invariants
assert_exit_code "$TARGET_BIN try --dry-run" 0 "neuronix try --dry-run exits 0"
assert_output_contains "$TARGET_BIN try --dry-run" "KVM Acceleration" "Dry-run inspects KVM hypervisor status"
assert_output_contains "$TARGET_BIN try --dry-run" "Dry-run validation successful" "Dry-run verifies RAM disk reservation"
assert_eq "$(ls -1 /dev/shm/neuronix_shadow_* 2>/dev/null | wc -l)" "0" "Dry-run leaves zero lingering files in /dev/shm"

# 10-15. Automated Smoke Test Invariants
assert_exit_code "$TARGET_BIN try --smoke-test" 0 "neuronix try --smoke-test exits 0"
SMOKE_OUT=$($TARGET_BIN try --smoke-test)
assert_output_contains "echo '$SMOKE_OUT'" "Micro-VM Kernel Boot: SUCCESS" "Smoke test validates kernel boot"
assert_output_contains "echo '$SMOKE_OUT'" "Systemd Basic Target Reached: SUCCESS" "Smoke test validates systemd equilibrium"
assert_output_contains "echo '$SMOKE_OUT'" "9P Nix Store Mount: SUCCESS" "Smoke test validates 9P read-only store mount"
assert_output_contains "echo '$SMOKE_OUT'" "Shadow VM verification passed" "Smoke test concludes with verified guest readiness"
assert_eq "$(ls -1 /dev/shm/neuronix_shadow_* 2>/dev/null | wc -l)" "0" "Smoke test cleans up /dev/shm upon exit"

# 16-19. Execution Modes & Configuration Parameter Bounds
assert_exit_code "$TARGET_BIN try --headless --smoke-test" 0 "Explicit headless smoke-test exits 0"
assert_output_contains "$TARGET_BIN try --gui --dry-run" "GUI Display" "Option --gui sets GUI display mode"
assert_output_contains "$TARGET_BIN try --headless --dry-run" "Headless (Console)" "Option --headless sets console mode"
assert_output_contains "$TARGET_BIN try --timeout 30 --dry-run" "30 seconds" "Option --timeout parses valid positive integer"

# 20-26. Negative Bounds & Error Injection Handling
assert_exit_code "$TARGET_BIN try --timeout 0" 1 "Option --timeout 0 is rejected with exit code 1"
assert_exit_code "$TARGET_BIN try --timeout -5" 1 "Negative timeout is rejected with exit code 1"
assert_exit_code "$TARGET_BIN try --timeout invalid_abc" 1 "Non-numeric timeout is rejected with exit code 1"
assert_exit_code "$TARGET_BIN try --unknown-vm-flag" 1 "Unknown flag for try command is rejected with exit 1"
assert_stderr_contains "$TARGET_BIN try --unknown-vm-flag" "tidak dikenali" "Error message emitted to stderr on invalid flag"
assert_exit_code "$TARGET_BIN try --promote --dry-run" 0 "Option --promote combined with dry-run exits 0"
assert_exit_code "$TARGET_BIN try /etc/nixos/configuration.nix extra_unexpected_arg" 1 "Multiple positional targets rejected"

# 27-30. Model Context Protocol (MCP) Integration & Final Hygiene
MCP_TOOLS_RES=$(echo '{"jsonrpc":"2.0","id":100,"method":"tools/list"}' | $TARGET_BIN mcp)
assert_output_contains "echo '$MCP_TOOLS_RES'" "neuronix_shadow_eval" "MCP server exposes neuronix_shadow_eval"

MCP_CALL_SHADOW='{"jsonrpc":"2.0","id":101,"method":"tools/call","params":{"name":"neuronix_shadow_eval"}}'
assert_exit_code "echo '$MCP_CALL_SHADOW' | $TARGET_BIN mcp" 0 "MCP tools/call neuronix_shadow_eval exits 0"
MCP_SHADOW_RES=$(echo "$MCP_CALL_SHADOW" | $TARGET_BIN mcp)
assert_output_contains "echo '$MCP_SHADOW_RES'" "Shadow Micro-VM Simulation PASSED" "MCP shadow evaluation returns success"
assert_eq "$(ls -1 /dev/shm/neuronix_shadow_* 2>/dev/null | wc -l)" "0" "System maintains 100% RAM disk purity post all tests"
