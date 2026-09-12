"""
NEURONIX Conductor Capability Runtime Broker.
Provides a zero-idle, socket-activated JSON-RPC 2.0 control interface
for humans, external AI agents, and visual surfaces.
Adheres strictly to SPEC-NRX-CND-018 and SPEC-NRX-CND-021.
"""

from .server import ConductorServer, LifecycleState, resolve_socket_path

__version__ = "1.0.5"
__all__ = ["ConductorServer", "LifecycleState", "resolve_socket_path"]
