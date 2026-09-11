"""
Universal Execution Fabric (UEF) ExecutionProvider Base Interface.
Defines the abstract contract all on-demand execution providers must fulfill.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, List

from .models import (
    CapabilityVector,
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

    def evaluate_capabilities(
        self,
        workload: WorkloadSpec,
        context: OperationalContext,
        report: Optional[CompatibilityReport] = None,
    ) -> CapabilityVector:
        """Evaluate factual capability vector for this workload under given context.

        Subclasses should provide empirical metrics. Default implementation
        derives vector from inspect and score.
        """
        if report is None:
            report = self.inspect(workload)
        if not report.compatible:
            return CapabilityVector(
                compatible=False,
                policy_fit=0.0,
                isolation_fit=0.0,
                resource_cost=0.0,
                startup_latency=0.0,
                provenance=0.0,
            )
        s = self.score(workload, context)
        return CapabilityVector(
            compatible=True,
            policy_fit=s,
            isolation_fit=s,
            resource_cost=s,
            startup_latency=s,
            provenance=s,
        )

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
