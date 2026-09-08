"""
NEURONIX Core Shared Domain Logic Package
Exports canonical utilities for telemetry, generation management,
atomic rollback, storage optimization, and system update operations.
"""

__version__ = "1.0.4"

from .telemetry import get_system_telemetry, get_cpu_info, get_ram_info
from .generation import list_generations, get_active_generation, parse_generation_number
from .rollback import execute_rollback, simulate_rollback
from .storage import probe_storage_hygiene, calculate_store_size, create_workspace_branch, list_workspace_branches, revert_workspace_branch
from .update import check_upstream_update, get_pinned_commit, apply_system_update
from .lock import OperationLock, ConcurrentOperationError
from .journal import TransactionJournal, TransactionState, CorruptedJournalError
from .operations import execute_privileged_operation, is_operation_permitted
from .ca import enroll_certificate
from .doctor import get_sanitized_diagnostics, print_doctor_json
from .diff import compute_generation_diff
from .distill import distill_packages, verify_package_in_nixpkgs
from .daemon_client import is_daemon_active, query_system_ast, query_state_show, query_state_verify
from .container import (
    setup_ram_workspace,
    run_container_session,
    run_sandbox_session,
    run_stack_session,
    synthesize_micro_dns_hosts,
    build_container_oci,
    daemonize_container_session,
    stop_container_daemon,
    list_container_daemons,
    export_container_oci,
    teardown_container,
    teardown_sandbox,
    allocate_ram_workspace,
    vaporize_workspace,
)
from .tune import apply_tuning_profile, get_current_tuning_status, PROFILES as TUNING_PROFILES
from .mesh import get_mesh_status, discover_local_peers
from .state import ProvableStateEngine, get_current_state, verify_current_state
from .hyperion import (
    HyperionExecutionEngine,
    DeterministicVerifier,
    IsolationTier,
    negotiate_domain,
)

__all__ = [
    "__version__",
    "ProvableStateEngine",
    "get_current_state",
    "verify_current_state",
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
    "apply_system_update",
    "OperationLock",
    "ConcurrentOperationError",
    "TransactionJournal",
    "TransactionState",
    "CorruptedJournalError",
    "execute_privileged_operation",
    "is_operation_permitted",
    "enroll_certificate",
    "get_sanitized_diagnostics",
    "print_doctor_json",
    "compute_generation_diff",
    "distill_packages",
    "verify_package_in_nixpkgs",
    "setup_ram_workspace",
    "run_container_session",
    "run_sandbox_session",
    "run_stack_session",
    "synthesize_micro_dns_hosts",
    "build_container_oci",
    "daemonize_container_session",
    "stop_container_daemon",
    "list_container_daemons",
    "export_container_oci",
    "teardown_container",
    "teardown_sandbox",
    "allocate_ram_workspace",
    "vaporize_workspace",
    "apply_tuning_profile",
    "get_current_tuning_status",
    "TUNING_PROFILES",
    "get_mesh_status",
    "discover_local_peers",
    "query_state_show",
    "query_state_verify",
    "HyperionExecutionEngine",
    "DeterministicVerifier",
    "IsolationTier",
    "negotiate_domain",
]
