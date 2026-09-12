"""
NEURONIX Conductor MCP 2026-07-28 Universal Agent Adapter.
Bridges external AI assistants into the canonical NEURONIX Skill Registry
and Vital Laboratory Observatory over standard MCP JSON-RPC.
Adheres strictly to SPEC-NRX-CND-018, SPEC-NRX-SKL-019, and SPEC-NRX-CND-021.
"""

from .server import McpServer, main

__version__ = "1.0.5"
__all__ = ["McpServer", "main"]
