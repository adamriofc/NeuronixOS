"""
Unit tests for OciContainerProvider (UEF OCI Container Standard Runtime Provider).
Validates OCI image format inspection, runtime detection (crun/runc/podman),
dynamic scoring prioritization, and ephemeral container lifecycle cleanup.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.uef.models import OperationalContext, WorkloadSpec
from neuronix_core.uef.oci_provider import OciContainerProvider


class TestUefOciProvider(unittest.TestCase):
    def setUp(self) -> None:
        self.provider = OciContainerProvider()

    def test_provider_discovery(self) -> None:
        """OciContainerProvider discovers OCI container capabilities."""
        cap = self.provider.discover()
        self.assertEqual(cap.provider_id, "oci.crun")
        self.assertEqual(cap.provider_type, "OCI_CONTAINER")
        self.assertIn("oci-image", cap.supported_formats)
        self.assertGreaterEqual(cap.isolation_level, 0.80)
        self.assertEqual(cap.resource_overhead_class, "MODERATE_CONTAINER")

    def test_inspect_oci_image_format(self) -> None:
        """Inspect accepts oci-image format."""
        workload = WorkloadSpec(
            workload_id="wl-oci",
            format="oci-image",
            entrypoint=["alpine:latest", "sh", "-c", "echo hello"],
        )
        report = self.provider.inspect(workload)
        self.assertTrue(report.compatible)
        self.assertGreater(report.estimated_startup_latency_ms, 0.0)

    def test_inspect_incompatible_format(self) -> None:
        """Inspect rejects pure elf-binary or wasm formats."""
        workload = WorkloadSpec(
            workload_id="wl-bin",
            format="wasm-module",
            entrypoint=["module.wasm"],
        )
        report = self.provider.inspect(workload)
        self.assertFalse(report.compatible)
        self.assertIn("wasm-module", report.missing_features)

    def test_scoring_prioritizes_oci_images(self) -> None:
        """Scoring rates oci-image format highest for container provider."""
        workload_oci = WorkloadSpec(
            workload_id="wl-oci",
            format="oci-image",
            entrypoint=["debian:stable-slim"],
        )
        ctx = OperationalContext(requested_isolation_tier="TIER_1_SANDBOX")
        score = self.provider.score(workload_oci, ctx)
        self.assertGreaterEqual(score, 0.90)

    @patch("subprocess.run")
    def test_container_execution_and_cleanup(self, mock_run: MagicMock) -> None:
        """Verifies container execution receipt and proof of resource cleanup."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout=b"OCI_CONTAINER_OUTPUT\n",
            stderr=b"",
        )
        workload = WorkloadSpec(
            workload_id="wl-run",
            format="oci-image",
            entrypoint=["crun", "run", "box"],
        )
        prep = self.provider.prepare(workload)
        envelope = {
            "envelope_id": "oce-oci-001",
            "intent": {"action": "container.execute"},
        }
        receipt = self.provider.execute(prep, envelope)
        self.assertEqual(receipt.exit_code, 0)
        self.assertEqual(receipt.provider_id, "oci.crun")
        self.assertIn("INV-SEC-008", receipt.invariants_verified)

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)


if __name__ == "__main__":
    unittest.main()
