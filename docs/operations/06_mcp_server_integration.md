# NEURONIX OS Runbook: Model Context Protocol (MCP) Server

## 1. Architecture and Protocol

NEURONIX embeds a Model Context Protocol (MCP) server adhering to the JSON-RPC 2.0 specification over standard input/output (protocol version: `2024-11-05`). This enables AI agents and developer copilots (such as Claude Desktop, OpenCode, and Antigravity) to query system telemetry, verify package derivations, and safely request rollbacks.

## 2. Server Invocation

The MCP server can be invoked directly from the CLI or linked to client configuration files:

```bash
# Direct stdio invocation
neuronix mcp
```

### Example Client Configuration (`claude_desktop_config.json`)
```json
{
  "mcpServers": {
    "neuronix": {
      "command": "neuronix",
      "args": ["mcp"]
    }
  }
}
```

## 3. Supported MCP Tools

- `neuronix_status`: Queries runtime kernel telemetry, generation pointers, and storage metrics.
- `neuronix_diet`: Executes or simulates (`dry_run: true`) store garbage collection and deduplication.
- `neuronix_verify`: Declaratively dry-evaluates package derivations before installation.
- `neuronix_undo`: Executes or simulates (`dry_run: true`) atomic generation rollback.
- `neuronix_list_generations`: Returns chronological generation links.
- `neuronix_shadow_eval`: Triggers in-memory RAM micro-VM simulation.
- `neuronix_check_update`: Checks upstream git repository for pinned updates.
- `neuronix_upgrade`: Prepares staged or switch mode system upgrades.
- `neuronix_doctor`: Produces sanitized markdown or structured JSON diagnostics.

## 4. Concurrency and Safety Protections

All mutating tools (`neuronix_diet`, `neuronix_undo`, `neuronix_upgrade`) acquire exclusive `flock` locks on `/run/neuronix-operation.lock`. If another operation holds the lock, the server returns a standard `-32000` JSON-RPC error rather than corrupting state.

## 5. AI/MCP Production Safety Matrix

| Operation Category | Tools / Actions | Policy & Execution Boundary |
| :--- | :--- | :--- |
| **Telemetry & Observability** | `neuronix_status`, `neuronix_doctor`, `neuronix_list_generations` | **Automatic:** Read-only inspection without system mutation. |
| **Derivation & Simulation** | `neuronix_verify`, `neuronix_shadow_eval`, `neuronix_manual` | **Automatic:** Sandboxed evaluation in RAM (`/dev/shm`) without host promotion. |
| **System Hygiene** | `neuronix_diet` | **Policy-Controlled:** Garbage collection with mandatory `dry_run` simulation support. |
| **State Mutation** | `neuronix_upgrade`, `neuronix_undo` | **Policy-Controlled:** Atomic generation transitions with staged fallbacks and health verification. |
| **Destructive Actions** | Disk re-partitioning, storage wipe, bare-metal overwrite | **NEVER AUTONOMOUS:** Strictly forbidden and excluded from the MCP tool registry. |
| **Arbitrary Execution** | Shell execution (`bash`, `sh`, `exec`) | **NEVER AUTONOMOUS:** Zero arbitrary shell access through MCP. |

