"""
Unit tests for ProviderResolver (UEF Dynamic Multi-Factor Scoring Engine).
Validates mathematical scoring, priority resolution, tie-breaking, and fail-closed diagnostics.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.uef.models import OperationalContext, WorkloadSpec
from neuronix_core.uef.native_provider import NativeLinuxProvider
from neuronix_core.uef.oci_provider import OciContainerProvider
from neuronix_core.uef.resolver import NoCompatibleProviderError, ProviderResolver
from neuronix_core.uef.rootfs_provider import RootfsBwrapProvider


class TestUefResolver(unittest.TestCase):
    def setUp(self) -> None:
        self.resolver = ProviderResolver()
        self.resolver.register(NativeLinuxProvider())
        self.resolver.register(RootfsBwrapProvider())
        self.resolver.register(OciContainerProvider())

    def test_registered_providers_count(self) -> None:
        """Resolver maintains registry of the 3 MVP execution providers."""
        providers = self.resolver.list_providers()
        self.assertEqual(len(providers), 3)
        self.assertIsNotNone(self.resolver.get_provider("native.linux"))
        self.assertIsNotNone(self.resolver.get_provider("rootfs.bwrap"))
        self.assertIsNotNone(self.resolver.get_provider("oci.crun"))

    def test_native_workload_resolves_to_native_provider(self) -> None:
        """Native ELF binary with TIER_0_HOST resolves to NativeLinuxProvider with top score."""
        workload = WorkloadSpec(
            workload_id="wl-native",
            format="elf-binary",
            entrypoint=["/bin/echo"],
            arguments=["hello"],
        )
        ctx = OperationalContext(requested_isolation_tier="TIER_0_HOST")
        provider, score, breakdown = self.resolver.resolve(workload, ctx)

        self.assertEqual(provider.provider_id, "native.linux")
        self.assertGreater(score, breakdown["rootfs.bwrap"])
        self.assertGreater(score, breakdown["oci.crun"])

    def test_foreign_rootfs_resolves_to_rootfs_bwrap_provider(self) -> None:
        """Rootfs-dir format resolves to RootfsBwrapProvider."""
        workload = WorkloadSpec(
            workload_id="wl-rootfs",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",
        )
        ctx = OperationalContext(requested_isolation_tier="TIER_1_SANDBOX")
        provider, score, breakdown = self.resolver.resolve(workload, ctx)

        self.assertEqual(provider.provider_id, "rootfs.bwrap")
        self.assertGreaterEqual(score, 0.80)

    def test_oci_image_resolves_to_oci_container_provider(self) -> None:
        """Oci-image format resolves to OciContainerProvider."""
        workload = WorkloadSpec(
            workload_id="wl-oci",
            format="oci-image",
            entrypoint=["debian:bookworm-slim"],
        )
        ctx = OperationalContext(requested_isolation_tier="TIER_1_SANDBOX")
        provider, score, breakdown = self.resolver.resolve(workload, ctx)

        self.assertEqual(provider.provider_id, "oci.crun")
        self.assertGreaterEqual(score, 0.80)

    def test_incompatible_workload_raises_typed_error(self) -> None:
        """Workload with unsupported format raises NoCompatibleProviderError with reports."""
        workload = WorkloadSpec(
            workload_id="wl-unknown",
            format="quantum-qasm-bytecode",
            entrypoint=["circuit.qasm"],
        )
        ctx = OperationalContext()
        with self.assertRaises(NoCompatibleProviderError) as cm:
            self.resolver.resolve(workload, ctx)

        err_msg = str(cm.exception)
        self.assertIn("quantum-qasm-bytecode", err_msg)
        self.assertIn("diagnostic_reports", dir(cm.exception))

    def test_compute_score_formula_and_weights(self) -> None:
        """Verifies mathematical vector scoring and weight customization."""
        from neuronix_core.uef.models import CapabilityVector

        vec = CapabilityVector(
            compatible=True,
            policy_fit=1.0,
            isolation_fit=0.8,
            resource_cost=0.6,
            startup_latency=0.4,
            provenance=0.2,
        )
        # Default weights: 0.25, 0.25, 0.20, 0.20, 0.10
        # Expected: 0.25*1.0 + 0.25*0.8 + 0.20*0.6 + 0.20*0.4 + 0.10*0.2
        # = 0.25 + 0.20 + 0.12 + 0.08 + 0.02 = 0.67
        score = self.resolver.compute_score(vec)
        self.assertAlmostEqual(score, 0.67, places=3)

        # Incompatible vector returns 0.0
        vec_incompat = CapabilityVector(
            compatible=False,
            policy_fit=1.0,
            isolation_fit=1.0,
            resource_cost=1.0,
            startup_latency=1.0,
            provenance=1.0,
        )
        self.assertEqual(self.resolver.compute_score(vec_incompat), 0.0)

        # Custom weights validation
        self.resolver.set_weights(
            policy=0.50, isolation=0.20, resource=0.10, latency=0.10, provenance=0.10
        )
        score_custom = self.resolver.compute_score(vec)
        # Expected: 0.5*1.0 + 0.2*0.8 + 0.1*0.6 + 0.1*0.4 + 0.1*0.2 = 0.5 + 0.16 + 0.06 + 0.04 + 0.02 = 0.78
        self.assertAlmostEqual(score_custom, 0.78, places=3)

        with self.assertRaises(ValueError):
            self.resolver.set_weights(0.5, 0.5, 0.5, 0.5, 0.5)  # Sums to 2.5


if __name__ == "__main__":
    unittest.main()
