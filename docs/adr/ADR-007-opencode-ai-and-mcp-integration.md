# ADR-007: OpenCode AI Copilot Daemon and Model Context Protocol Integration

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Modern developers and systems engineers increasingly utilize local and remote AI agents for system administration, diagnostic investigation, and code authoring. Typical integration involves unmanaged global binaries or intrusive background services running with root privileges, introducing security risks, privilege escalation vectors, and silent background failures.

## Architectural Decision
NEURONIX implements a dual AI copilot and system telemetry integration:
1. **OpenCode AI Copilot Integration:** OpenCode is packaged as a first-class declarative system component with an isolated user-space systemd service and configurable autonomous update timers (`services.opencode.autoUpdate`).
2. **Model Context Protocol (MCP) Interface:** An embedded JSON-RPC 2.0 server (`neuronix mcp`) exposes standardized system inspection tools (`neuronix_system_info`, `neuronix_generation_list`, `neuronix_rollback`, `neuronix_doctor`, `neuronix_check_update`) strictly operating under user privileges.
3. **Structured Input Validation:** All MCP tool invocations enforce strict schema validation, rejecting injection vectors, shell meta-characters, and out-of-bound arguments with explicit JSON-RPC error codes.

## Consequences
- **Positive:** Standardized, secure AI agent integration for modern IDEs; zero root privilege escalation; auditable system diagnostic capabilities via structured JSON-RPC protocols.
- **Trade-off:** The MCP daemon requires local client configuration in editor plugins (e.g., Claude Desktop, VS Code, Cursor) to establish the JSON-RPC stdio transport channel.
