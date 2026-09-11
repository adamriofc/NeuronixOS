"""
Unit tests for Universal Execution Fabric (UEF) ExecutionProvider interface and data models.
Validates abstract lifecycle methods, type contracts, and error semantics.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any, Dict, List

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.uef.models import (
    CompatibilityReport,
    ExecutionReceiptData,
    OperationalContext,
    PreparedEnvironment,
    ProviderCapability,
    ResourceReleaseProof,
    WorkloadSpec,
)
from neuronix_core.uef.provider import ExecutionProvider


class MockProvider(ExecutionProvider):
    @property
    def provider_id(self) -> str:
        return "mock.provider"

    def discover(self) -> ProviderCapability:
        return ProviderCapability(
            provider_id=self.provider_id,
            provider_type="NATIVE_LINUX",
            supported_formats=["elf-binary", "posix-script"],
            isolation_level=0.1,
            startup_latency_class="SUB_MILLISECOND",
            resource_overhead_class="ZERO_OVERHEAD",
        )

    def inspect(self, workload: WorkloadSpec) -> CompatibilityReport:
        if workload.format in ["elf-binary", "posix-script"]:
            return CompatibilityReport(compatible=True, reason="Format natively supported")
        return CompatibilityReport(
            compatible=False,
            reason=f"Unsupported format: {workload.format}",
            missing_features=[workload.format],
        )

    def score(self, workload: WorkloadSpec, context: OperationalContext) -> float:
        report = self.inspect(workload)
        return 1.0 if report.compatible else 0.0

    def prepare(self, workload: WorkloadSpec) -> PreparedEnvironment:
        return PreparedEnvironment(
            prepared_id="prep-001",
            provider_id=self.provider_id,
            mounts=[],
            env_vars={"MOCK_ENV": "1"},
        )

    def execute(self, prepared: PreparedEnvironment, envelope: Dict[str, Any]) -> ExecutionReceiptData:
        return ExecutionReceiptData(
            receipt_id="rcpt-20260911-mock01",
            envelope_hash="a" * 64,
            provider_id=self.provider_id,
            exit_code=0,
            state_root_after="b" * 64,
            duration_ms=1.5,
            resource_usage={"peak_rss_bytes": 1024, "cpu_time_ms": 1.0},
            evidence_digest="c" * 64,
        )

    def cleanup(self, prepared: PreparedEnvironment) -> ResourceReleaseProof:
        return ResourceReleaseProof(
            freed_bytes=1024,
            unmounted_targets=[],
            timestamp_ns=1789045600000000000,
            clean=True,
        )


class TestUefProviderInterface(unittest.TestCase):
    def test_abstract_class_cannot_be_instantiated(self) -> None:
        """ExecutionProvider is an ABC and cannot be directly instantiated."""
        with self.assertRaises(TypeError):
            ExecutionProvider()  # type: ignore

    def test_mock_provider_lifecycle(self) -> None:
        """Validates standard lifecycle: discover -> inspect -> score -> prepare -> execute -> cleanup."""
        provider = MockProvider()
        self.assertEqual(provider.provider_id, "mock.provider")

        cap = provider.discover()
        self.assertEqual(cap.provider_id, "mock.provider")
        self.assertIn("elf-binary", cap.supported_formats)

        workload = WorkloadSpec(
            workload_id="wl-01",
            format="elf-binary",
            entrypoint=["/bin/echo", "hello"],
        )
        report = provider.inspect(workload)
        self.assertTrue(report.compatible)

        ctx = OperationalContext(requested_isolation_tier="TIER_0_HOST")
        score = provider.score(workload, ctx)
        self.assertEqual(score, 1.0)

        prep = provider.prepare(workload)
        self.assertEqual(prep.provider_id, "mock.provider")

        envelope = {"envelope_id": "oce-001", "intent": {"action": "system.status"}}
        receipt = provider.execute(prep, envelope)
        self.assertEqual(receipt.exit_code, 0)
        self.assertEqual(receipt.provider_id, "mock.provider")

        proof = provider.cleanup(prep)
        self.assertTrue(proof.clean)

    def test_incompatible_workload_inspection(self) -> None:
        """Incompatible formats return compatible=False with diagnostic reasons."""
        provider = MockProvider()
        workload = WorkloadSpec(
            workload_id="wl-02",
            format="oci-image",
            entrypoint=["sh"],
        )
        report = provider.inspect(workload)
        self.assertFalse(report.compatible)
        self.assertIn("oci-image", report.missing_features)


if __name__ == "__main__":
    unittest.main()
