"""
Universal Execution Fabric (UEF) ExecutionProvider Base Interface.
Defines the abstract contract all on-demand execution providers must fulfill.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, List

from .models import (
    CompatibilityReport,
    ExecutionReceiptData,
    OperationalContext,
    PreparedEnvironment,
    ProviderCapability,
    ResourceReleaseProof,
    WorkloadSpec,
)


class ExecutionProvider(ABC):
    """Abstract base class for all on-demand execution providers in UEF."""

    @property
    @abstractmethod
    def provider_id(self) -> str:
        """Unique namespaced identifier for this provider (e.g. native.linux)."""
        pass

    @abstractmethod
    def discover(self) -> ProviderCapability:
        """Probe host system and return declared capabilities and isolation limits."""
        pass

    @abstractmethod
    def inspect(self, workload: WorkloadSpec) -> CompatibilityReport:
        """Inspect a workload to determine compatibility and missing features."""
        pass

    @abstractmethod
    def score(self, workload: WorkloadSpec, context: OperationalContext) -> float:
        """Calculate dynamic multi-factor score for this workload under given context.

        Returns 0.0 if incompatible, or a normalized float in (0.0, 1.0].
        """
        pass

    @abstractmethod
    def prepare(self, workload: WorkloadSpec) -> PreparedEnvironment:
        """Set up ephemeral sandboxed environment, namespaces, and mounts."""
        pass

    @abstractmethod
    def execute(
        self,
        prepared: PreparedEnvironment,
        envelope: Dict[str, Any],
    ) -> ExecutionReceiptData:
        """Execute the prepared workload and return a verified execution receipt."""
        pass

    @abstractmethod
    def cleanup(self, prepared: PreparedEnvironment) -> ResourceReleaseProof:
        """Tear down all ephemeral mounts, temporary directories, and processes.

        Guarantees zero memory leaks and complete state hygiene on exit.
        """
        pass
