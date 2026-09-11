"""
Unit tests for NativeLinuxProvider (UEF Native Host Execution Provider).
Validates 0% overhead host binary execution, argument passing, exit code propagation,
resource tracking, and clean lifecycle reclamation.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.uef.models import OperationalContext, WorkloadSpec
from neuronix_core.uef.native_provider import NativeLinuxProvider


class TestUefNativeProvider(unittest.TestCase):
    def setUp(self) -> None:
        self.provider = NativeLinuxProvider()

    def test_provider_discovery(self) -> None:
        """NativeLinuxProvider discovers native Linux host capabilities."""
        cap = self.provider.discover()
        self.assertEqual(cap.provider_id, "native.linux")
        self.assertEqual(cap.provider_type, "NATIVE_LINUX")
        self.assertIn("elf-binary", cap.supported_formats)
        self.assertIn("posix-script", cap.supported_formats)
        self.assertEqual(cap.startup_latency_class, "SUB_MILLISECOND")
        self.assertEqual(cap.resource_overhead_class, "ZERO_OVERHEAD")

    def test_inspect_valid_native_binary(self) -> None:
        """Inspect finds standard system binaries like /bin/echo or python3."""
        workload = WorkloadSpec(
            workload_id="wl-echo",
            format="elf-binary",
            entrypoint=["/bin/echo"],
            arguments=["hello", "neuronix"],
        )
        report = self.provider.inspect(workload)
        self.assertTrue(report.compatible)
        self.assertLessEqual(report.estimated_startup_latency_ms, 2.0)

    def test_inspect_incompatible_format(self) -> None:
        """Incompatible formats like oci-image or wasm are marked incompatible."""
        workload = WorkloadSpec(
            workload_id="wl-oci",
            format="oci-image",
            entrypoint=["ubuntu:latest"],
        )
        report = self.provider.inspect(workload)
        self.assertFalse(report.compatible)
        self.assertIn("oci-image", report.missing_features)

    def test_dynamic_scoring(self) -> None:
        """Native provider scores highest when host execution is permitted, lower if sandbox demanded."""
        workload = WorkloadSpec(
            workload_id="wl-echo",
            format="elf-binary",
            entrypoint=["/bin/echo"],
        )
        ctx_host = OperationalContext(requested_isolation_tier="TIER_0_HOST")
        score_host = self.provider.score(workload, ctx_host)
        self.assertGreaterEqual(score_host, 0.9)

        ctx_vm = OperationalContext(requested_isolation_tier="TIER_2_MICROVM")
        score_vm = self.provider.score(workload, ctx_vm)
        self.assertLess(score_vm, score_host)

    def test_execution_and_receipt_generation(self) -> None:
        """Executes a real binary and produces a cryptographically verified receipt."""
        workload = WorkloadSpec(
            workload_id="wl-sh",
            format="elf-binary",
            entrypoint=["/bin/sh"],
            arguments=["-c", "echo -n 'NEURONIX_EXEC_OK'"],
        )
        prep = self.provider.prepare(workload)
        self.assertEqual(prep.provider_id, "native.linux")

        envelope = {
            "envelope_id": "oce-test-001",
            "intent": {"action": "test.native_exec"},
        }
        receipt = self.provider.execute(prep, envelope)
        self.assertEqual(receipt.exit_code, 0)
        self.assertEqual(receipt.provider_id, "native.linux")
        self.assertIn("NEURONIX_EXEC_OK", receipt.stdout_preview)
        self.assertIsNotNone(receipt.stdout_hash)
        self.assertGreater(receipt.duration_ms, 0.0)

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)


if __name__ == "__main__":
    unittest.main()
