"""
NEURONIX Core Shared Domain Logic Package
Exports canonical utilities for telemetry, generation management,
atomic rollback, storage optimization, and system update operations.
"""

__version__ = "1.0.3"

from .telemetry import get_system_telemetry, get_cpu_info, get_ram_info
from .generation import list_generations, get_active_generation, parse_generation_number
from .rollback import execute_rollback, simulate_rollback
from .storage import probe_storage_hygiene, calculate_store_size
from .update import check_upstream_update, get_pinned_commit

__all__ = [
    "__version__",
    "get_system_telemetry",
    "get_cpu_info",
    "get_ram_info",
    "list_generations",
    "get_active_generation",
    "parse_generation_number",
    "execute_rollback",
    "simulate_rollback",
    "probe_storage_hygiene",
    "calculate_store_size",
    "check_upstream_update",
    "get_pinned_commit",
]
