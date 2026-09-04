#!/usr/bin/env bash
# ==============================================================================
# Suite 14: Model Context Protocol (MCP) & JSON-RPC 2.0 Compliance (30 Tests)
# Verifies standard compliance with MCP protocol version 2024-11-05.
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
MCP_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/mcp_server.sh"

start_suite "14 - MCP & JSON-RPC 2.0 Protocol Compliance"

# 1-6. MCP Lifecycle & Initialize Handshake
assert_eq "$(test -f "$MCP_BIN" && echo "exists" || echo "missing")" "exists" "MCP server script exists"
assert_exit_code "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}' | $TARGET_BIN mcp" 0 "MCP initialize invocation exits 0"
INIT_RES=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | $TARGET_BIN mcp)
assert_output_contains "echo '$INIT_RES'" '"jsonrpc":"2.0"' "Initialize response contains JSON-RPC 2.0 header"
assert_output_contains "echo '$INIT_RES'" '2024-11-05' "Initialize specifies protocol version 2024-11-05"
assert_output_contains "echo '$INIT_RES'" 'neuronix-mcp' "Server reports name neuronix-mcp"
assert_output_contains "echo '$INIT_RES'" "$CANONICAL_VERSION" "Server reports canonical version $CANONICAL_VERSION"

# 7-12. Tools Enumeration (tools/list)
assert_exit_code "echo '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}' | $TARGET_BIN mcp" 0 "tools/list exits 0"
TOOLS_RES=$(echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | $TARGET_BIN mcp)
assert_output_contains "echo '$TOOLS_RES'" 'neuronix_status' "tools/list exposes neuronix_status"
assert_output_contains "echo '$TOOLS_RES'" 'neuronix_diet' "tools/list exposes neuronix_diet"
assert_output_contains "echo '$TOOLS_RES'" 'neuronix_verify' "tools/list exposes neuronix_verify"
assert_output_contains "echo '$TOOLS_RES'" 'neuronix_undo' "tools/list exposes neuronix_undo"
assert_output_contains "echo '$TOOLS_RES'" 'neuronix_list_generations' "tools/list exposes neuronix_list_generations"

# 13-17. Tool Invocations (tools/call)
STATUS_CALL='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"neuronix_status"}}'
assert_exit_code "echo '$STATUS_CALL' | $TARGET_BIN mcp" 0 "tools/call neuronix_status exits 0"
STATUS_RES=$(echo "$STATUS_CALL" | $TARGET_BIN mcp)
assert_output_contains "echo '$STATUS_RES'" 'NEURONIX Substrate Telemetry' "neuronix_status returns telemetry payload"
assert_output_contains "echo '$STATUS_RES'" 'Active Generation:' "neuronix_status returns generation data"

DIET_CALL='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"neuronix_diet"}}'
assert_exit_code "echo '$DIET_CALL' | $TARGET_BIN mcp" 0 "tools/call neuronix_diet exits 0"
DIET_RES=$(echo "$DIET_CALL" | $TARGET_BIN mcp)
assert_output_contains "echo '$DIET_RES'" 'Storage optimization' "neuronix_diet returns truthful optimization status"

# 18-22. Declarative Verification Gatekeeper via MCP
VERIFY_OK='{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"neuronix_verify","package":"hello"}}'
assert_exit_code "echo '$VERIFY_OK' | $TARGET_BIN mcp" 0 "tools/call neuronix_verify with hello exits 0"
VERIFY_OK_RES=$(echo "$VERIFY_OK" | $TARGET_BIN mcp)
assert_output_contains "echo '$VERIFY_OK_RES'" 'Declarative Build Verification PASSED' "Valid package passes declarative verification"

VERIFY_BAD='{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"neuronix_verify","package":"nonexistent_xyz_404"}}'
assert_exit_code "echo '$VERIFY_BAD' | $TARGET_BIN mcp" 0 "tools/call neuronix_verify with nonexistent package exits 0"
VERIFY_BAD_RES=$(echo "$VERIFY_BAD" | $TARGET_BIN mcp)
assert_output_contains "echo '$VERIFY_BAD_RES'" 'Declarative Build Verification FAILED' "Invalid package fails declarative verification"

UNDO_CALL='{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"neuronix_undo"}}'
UNDO_RES=$(echo "$UNDO_CALL" | $TARGET_BIN mcp)
assert_output_contains "echo '$UNDO_RES'" 'Rollback' "neuronix_undo reports rollback status cleanly"

GENS_CALL='{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"neuronix_list_generations"}}'
GENS_RES=$(echo "$GENS_CALL" | $TARGET_BIN mcp)
assert_output_contains "echo '$GENS_RES'" 'Available generations:' "neuronix_list_generations executes cleanly"

# 23-25. JSON-RPC Error Handling (-32602, -32601, -32600)
UNKNOWN_TOOL='{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"unknown_tool_test"}}'
UNKNOWN_TOOL_RES=$(echo "$UNKNOWN_TOOL" | $TARGET_BIN mcp)
assert_output_contains "echo '$UNKNOWN_TOOL_RES'" '-32602' "Unknown tool emits error code -32602"

UNKNOWN_METHOD='{"jsonrpc":"2.0","id":10,"method":"nonexistent_method"}'
UNKNOWN_METHOD_RES=$(echo "$UNKNOWN_METHOD" | $TARGET_BIN mcp)
assert_output_contains "echo '$UNKNOWN_METHOD_RES'" '-32601' "Unknown method emits error code -32601"

MALFORMED_REQ='{"jsonrpc":"2.0","id":11}'
MALFORMED_REQ_RES=$(echo "$MALFORMED_REQ" | $TARGET_BIN mcp)
assert_output_contains "echo '$MALFORMED_REQ_RES'" '-32600' "Missing method emits error code -32600"

# 26-30. Direct CLI Declarative Verification Ergonomics
assert_exit_code "$TARGET_BIN verify hello" 0 "CLI verify hello returns exit 0"
assert_output_contains "$TARGET_BIN verify hello" "Declarative Build Verification PASSED" "CLI verify displays success banner"
assert_exit_code "$TARGET_BIN verify nonexistent_fake_pkg_xyz" 1 "CLI verify nonexistent package exits 1"
assert_stderr_contains "$TARGET_BIN verify nonexistent_fake_pkg_xyz" "Declarative Build Verification FAILED" "CLI verify displays rejection in stderr"
assert_exit_code "$TARGET_BIN verify" 1 "CLI verify without arguments exits 1"
