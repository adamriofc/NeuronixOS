# Chapter 7: Model Context Protocol (MCP) Server & AI Gateway

## 1. Protocol Architecture & Standards

The NEURONIX MCP Server bridges external AI agents to the operating system using the standardized **Model Context Protocol** (Protocol Version: `2024-11-05`, Transport: JSON-RPC 2.0 over `stdio`).

This architecture decouples the AI reasoning engine from unconstrained root terminal execution:

* **Structured Communication:** All AI queries pass through schema-validated JSON-RPC calls.
* **Safe Dry-Run Evaluation:** Mutating tools support a `dry_run: true` parameter for non-destructive inspection.
* **Exclusive Concurrency Lock:** All mutating operations acquire a non-blocking `flock` lock on `/run/neuronix-operation.lock`. If another operation holds the lock, the server responds with a standard `-32000` JSON-RPC error.

---

## 2. Supported Tools Catalog

| Tool Name | Parameters | Description |
| :--- | :--- | :--- |
| `neuronix_status` | None | Returns kernel version, generation pointers, and storage metrics. |
| `neuronix_diet` | `{"dry_run": <bool>}` | Performs garbage collection, hardlink deduplication, and TRIM. |
| `neuronix_verify` | `{"package": "<string>"}` | Evaluates pure derivation validity in `nixpkgs` closure. |
| `neuronix_undo` | `{"dry_run": "<bool>"}` | Initiates instant atomic rollback to preceding generation. |
| `neuronix_list_generations` | None | Returns chronological list of system generation symlinks. |
| `neuronix_shadow_eval` | `{"config_path": "<string>"}` | Boots ephemeral Micro-VM in `/dev/shm` to verify proposed configuration. |
| `neuronix_check_update` | None | Queries upstream git repository for available updates. |
| `neuronix_upgrade` | `{"mode": "staged\|switch", "dry_run": <bool>}` | Orchestrates atomic system upgrade. |
| `neuronix_doctor` | None | Produces sanitized JSON diagnostic report (schema version 1.0.0). |
| `neuronix_manual` | `{"topic": "<string>"}` | Queries system-embedded technical manual and AI directives. |

---

## 3. Client Integration Examples

### 3.1 Claude Desktop / Antigravity / Cursor Configuration
Add to `claude_desktop_config.json` or `mcp_config.json`:

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

### 3.2 Testing via Terminal
```bash
# Query available tools
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | neuronix mcp

# Call system manual tool
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"neuronix_manual","arguments":{"topic":"storage"}}}' | neuronix mcp
```
