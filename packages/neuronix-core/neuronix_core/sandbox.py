"""
NEURONIX Sandbox Backward-Compatibility Proxy Module
Re-exports container engine primitives from neuronix_core.container to maintain 100%
zero-breakage compatibility with legacy code and tests.
"""

from .container import (
    sanitize_environment,
    is_git_url,
    is_oci_url,
    resolve_fhs_paths,
    pull_and_extract_oci_image,
    setup_ram_workspace,
    run_container_session,
    run_sandbox_session,
    run_stack_session,
    export_container_oci,
    teardown_container,
    teardown_sandbox,
    allocate_ram_workspace,
    vaporize_workspace,
    SENSITIVE_ENV_PATTERNS,
    SENSITIVE_ENV_EXACT,
)

__all__ = [
    "sanitize_environment",
    "is_git_url",
    "is_oci_url",
    "resolve_fhs_paths",
    "pull_and_extract_oci_image",
    "setup_ram_workspace",
    "run_container_session",
    "run_sandbox_session",
    "run_stack_session",
    "export_container_oci",
    "teardown_container",
    "teardown_sandbox",
    "allocate_ram_workspace",
    "vaporize_workspace",
    "SENSITIVE_ENV_PATTERNS",
    "SENSITIVE_ENV_EXACT",
]
