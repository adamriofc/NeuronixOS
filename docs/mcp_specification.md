# NEURONIX Model Context Protocol (MCP) Interface Specification

**Protocol Standard:** Model Context Protocol (Protocol Version `2024-11-05`)  
**Transport Binding:** JSON-RPC 2.0 over `stdio`  
**Substrate Version:** 0.4.0-beta  

---

## 1. Abstract & Threat Model

Autonomous AI agents operating on mutable operating systems present severe availability risks: unconstrained file deletion, shared library mutation, and environment drift. 

NEURONIX decouples the AI reasoning agent from direct root execution. The NEURONIX Model Context Protocol (MCP) server acts as a **formal proof gatekeeper**:
1. All queries from the agent pass through structured, schema-validated JSON-RPC calls over `stdio`.
2. Any requested environment modification must pass through `neuronix_verify` (pure-functional evaluation) before receiving clearance.
3. System configurations can be tested in transient RAM-disk Micro-VMs (`neuronix_shadow_eval`) before promotion.
4. System rollback (`neuronix_undo`) remains an immutable guarantee (< 2 seconds atomic symlink swap) regardless of agent actions.

---

## 2. Server Invocation & Lifecycle

The MCP server is invoked directly as a child process of the hosting IDE/Agent environment:

```bash
neuronix mcp
```

The process listens for single-line JSON-RPC 2.0 messages on `stdin` and emits synchronous JSON-RPC 2.0 responses to `stdout`. Diagnostics and internal warnings are routed strictly to `stderr` or encapsulated in JSON-RPC error responses to prevent stream corruption.

---

## 3. Protocol Methods

### 3.1 `initialize`
Negotiates client-server protocol version and capabilities.

#### Request
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "antigravity",
      "version": "1.0.0"
    }
  }
}
```

#### Response
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "tools": {}
    },
    "serverInfo": {
      "name": "neuronix-mcp",
      "version": "0.4.0-beta"
    }
  }
}
```

### 3.2 `tools/list`
Enumerates available substrate primitives exposed to the AI agent.

#### Request
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list"
}
```

#### Available Tools Catalog

| Tool Name | Parameters | Description |
| :--- | :--- | :--- |
| `neuronix_status` | None | Returns kernel version, hypervisor environment, active generation, and storage telemetry. |
| `neuronix_diet` | None | Triggers garbage collection, store inode deduplication, and VirtIO TRIM block discard. |
| `neuronix_verify` | `{"package": "<string>"}` | Formally proves whether a package derivation is valid in pure `nixpkgs` closure without mutating system state. |
| `neuronix_undo` | None | Initiates instant atomic rollback to preceding generation. |
| `neuronix_list_generations` | None | Lists historical generations, active profile symlinks, and timestamps. |
| `neuronix_shadow_eval` | `{"config_path": "<string>"}` (optional) | Boots transient RAM-disk Micro-VM (/dev/shm) to run automated smoke tests on proposed system configuration. |

### 3.3 `tools/call`
Executes an exposed tool with caller arguments.

#### Example: Formal Derivation Verification
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "neuronix_verify",
    "package": "ripgrep"
  }
}
```

#### Response
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Declarative Verification PASSED: Package 'ripgrep' is a valid pure derivation in nixpkgs closure. Isolated sandbox verified."
      }
    ]
  }
}
```

---

## 4. Error Code Specification

Standard JSON-RPC 2.0 error payloads are returned for malformed or unauthorized invocations:

| Error Code | Error Type | Condition |
| :---: | :--- | :--- |
| `-32700` | Parse Error | Input payload cannot be parsed as valid JSON. |
| `-32600` | Invalid Request | Missing `method` or `jsonrpc` protocol header. |
| `-32601` | Method Not Found | Requested method is not registered on the MCP server. |
| `-32602` | Invalid Params | Unknown tool name in `tools/call` or missing required schema properties. |
| `-32603` | Internal Error | Substrate process error or execution timeout. |

---

## 5. Client Configuration Examples

### Antigravity / Claude Desktop Configuration (`mcp_config.json`)
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

### Direct CLI Verification
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | neuronix mcp
```
