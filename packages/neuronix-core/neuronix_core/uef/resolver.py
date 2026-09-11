"""
Universal Execution Fabric (UEF) Dynamic Multi-Factor Scoring Provider Resolver.
Dynamically maps workloads to the optimal execution provider using multi-factor evaluation.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

from .models import (
    CapabilityVector,
    CompatibilityReport,
    OperationalContext,
    WorkloadSpec,
)
from .native_provider import NativeLinuxProvider
from .oci_provider import OciContainerProvider
from .provider import ExecutionProvider
from .rootfs_provider import RootfsBwrapProvider


class NoCompatibleProviderError(Exception):
    """Raised when no registered provider can execute the workload."""

    def __init__(
        self,
        workload: WorkloadSpec,
        diagnostic_reports: Dict[str, CompatibilityReport],
    ) -> None:
        self.workload = workload
        self.diagnostic_reports = diagnostic_reports
        reasons = [f"{pid}: {rep.reason}" for pid, rep in diagnostic_reports.items()]
        summary = "; ".join(reasons)
        super().__init__(
            f"No compatible execution provider found for workload '{workload.workload_id}' "
            f"(format: '{workload.format}'). Diagnostics: {summary}"
        )


class ProviderResolver:
    """Dynamic multi-factor scoring resolver mapping workloads to execution providers."""

    def __init__(self) -> None:
        self._providers: Dict[str, ExecutionProvider] = {}
        # Default scoring weights summing to 1.0
        self.w_policy = 0.25
        self.w_isolation = 0.25
        self.w_resource = 0.20
        self.w_latency = 0.20
        self.w_provenance = 0.10

    def set_weights(
        self,
        policy: float,
        isolation: float,
        resource: float,
        latency: float,
        provenance: float,
    ) -> None:
        """Configure custom scoring weights. Must sum to 1.0."""
        total = policy + isolation + resource + latency + provenance
        if abs(total - 1.0) > 1e-4:
            raise ValueError(f"Scoring weights must sum to 1.0, got {total}")
        self.w_policy = policy
        self.w_isolation = isolation
        self.w_resource = resource
        self.w_latency = latency
        self.w_provenance = provenance

    def compute_score(self, vector: CapabilityVector) -> float:
        """Compute scalar score using the formal multi-factor formula:
        Score = C_compat * (w_policy * P + w_isolation * I + w_resource * R + w_latency * L + w_provenance * Q)
        """
        if not vector.compatible:
            return 0.0
        raw = (
            self.w_policy * vector.policy_fit
            + self.w_isolation * vector.isolation_fit
            + self.w_resource * vector.resource_cost
            + self.w_latency * vector.startup_latency
            + self.w_provenance * vector.provenance
        )
        return round(raw, 4)

    def register(self, provider: ExecutionProvider) -> None:
        """Register an execution provider with the resolver."""
        self._providers[provider.provider_id] = provider

    def get_provider(self, provider_id: str) -> Optional[ExecutionProvider]:
        """Retrieve a registered provider by its ID."""
        return self._providers.get(provider_id)

    def list_providers(self) -> List[ExecutionProvider]:
        """List all registered execution providers."""
        return list(self._providers.values())

    def resolve(
        self,
        workload: WorkloadSpec,
        context: OperationalContext,
    ) -> Tuple[ExecutionProvider, float, Dict[str, float]]:
        """Evaluate all providers and select the optimal match for the workload.

        Returns:
            Tuple of (SelectedProvider, best_score, score_breakdown_by_provider_id)

        Raises:
            NoCompatibleProviderError if no provider scores > 0.0.
        """
        scores: Dict[str, float] = {}
        reports: Dict[str, CompatibilityReport] = {}

        for pid, provider in self._providers.items():
            report = provider.inspect(workload)
            reports[pid] = report
            if not report.compatible:
                scores[pid] = 0.0
                continue

            vector = provider.evaluate_capabilities(workload, context, report=report)
            score = self.compute_score(vector)
            scores[pid] = score

        best_score = -1.0
        best_provider: Optional[ExecutionProvider] = None

        # Deterministic preference order in case of exact score ties
        preference_order = ["native.linux", "rootfs.bwrap", "oci.crun"]

        for pid in sorted(
            scores.keys(),
            key=lambda p: (
                scores[p],
                -preference_order.index(p) if p in preference_order else -99,
            ),
            reverse=True,
        ):
            if scores[pid] > 0.0:
                best_score = scores[pid]
                best_provider = self._providers[pid]
                break

        if not best_provider or best_score <= 0.0:
            raise NoCompatibleProviderError(workload, reports)

        return best_provider, best_score, scores


def create_default_resolver() -> ProviderResolver:
    """Instantiate and populate a resolver with the 3 canonical MVP providers."""
    resolver = ProviderResolver()
    resolver.register(NativeLinuxProvider())
    resolver.register(RootfsBwrapProvider())
    resolver.register(OciContainerProvider())
    return resolver
