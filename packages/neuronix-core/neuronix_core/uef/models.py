"""
Universal Execution Fabric (UEF) Data Models and Specifications.
Defines immutable data structures for workloads, capabilities, contexts, and receipts.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional


@dataclass(frozen=True)
class WorkloadSpec:
    """Specification of an executable workload submitted to UEF."""

    workload_id: str
    format: str  # elf-binary, nix-closure, posix-script, rootfs-dir, oci-image, wasm-module
    entrypoint: List[str]
    env: Dict[str, str] = field(default_factory=dict)
    rootfs_path: Optional[str] = None
    working_dir: str = "/"
    timeout_seconds: float = 30.0
    arguments: List[str] = field(default_factory=list)


@dataclass(frozen=True)
class ProviderCapability:
    """Declared runtime and isolation capabilities of an ExecutionProvider."""

    provider_id: str
    provider_type: str  # NATIVE_LINUX, ROOTFS_BWRAP, OCI_CONTAINER, WASM_SANDBOX, MICRO_VM
    supported_formats: List[str]
    isolation_level: float  # 0.0 (host) to 1.0 (hardware-isolated microVM)
    startup_latency_class: str  # SUB_MILLISECOND, LOW_MILLISECOND, COLD_START_MODERATE, COLD_START_HEAVY
    resource_overhead_class: str  # ZERO_OVERHEAD, MINIMAL_NAMESPACES, MODERATE_CONTAINER, HEAVY_VIRTUALIZATION
    kvm_available: bool = False
    gpu_available: bool = False


@dataclass(frozen=True)
class CompatibilityReport:
    """Assessment of whether a workload can be executed on a specific provider."""

    compatible: bool
    reason: str
    missing_features: List[str] = field(default_factory=list)
    estimated_startup_latency_ms: float = 0.0


@dataclass(frozen=True)
class OperationalContext:
    """Runtime constraints, security posture, and resource limits for execution."""

    requested_isolation_tier: str = "TIER_0_HOST"
    network_allowed: bool = False
    max_memory_mb: int = 1024
    max_cpu_cores: float = 2.0
    operator_tier: str = "FULL_OPERATOR"
    target_disk_id: Optional[str] = None


@dataclass
class PreparedEnvironment:
    """Ephemeral runtime state prepared for workload execution."""

    prepared_id: str
    provider_id: str
    mounts: List[str] = field(default_factory=list)
    env_vars: Dict[str, str] = field(default_factory=dict)
    temp_dir: Optional[str] = None
    cleanup_handlers: List[Callable[[], None]] = field(default_factory=list)


@dataclass(frozen=True)
class ExecutionReceiptData:
    """Verifiable execution outcome bound to state root and evidence digest."""

    receipt_id: str
    envelope_hash: str
    provider_id: str
    exit_code: int
    state_root_after: str
    duration_ms: float
    resource_usage: Dict[str, Any]
    evidence_digest: str
    stdout_hash: Optional[str] = None
    stderr_hash: Optional[str] = None
    stdout_preview: str = ""
    stderr_preview: str = ""
    invariants_verified: List[str] = field(default_factory=list)


@dataclass(frozen=True)
class ResourceReleaseProof:
    """Proof that all ephemeral resources and mounts were safely reclaimed."""

    freed_bytes: int
    unmounted_targets: List[str]
    timestamp_ns: int
    clean: bool
    error: Optional[str] = None
