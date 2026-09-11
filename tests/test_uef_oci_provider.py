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

    def test_missing_runtime_inspect_fails_closed(self) -> None:
        """Missing OCI runtime binary must report compatible=False (fail-closed)."""
        workload = WorkloadSpec(
            workload_id="wl-oci",
            format="oci-image",
            entrypoint=["alpine:latest"],
        )
        with patch.object(self.provider, "_detect_runtime_binary", return_value=None):
            report = self.provider.inspect(workload)
            self.assertFalse(report.compatible)
            self.assertIn("oci_runtime", report.missing_features)
            self.assertEqual(self.provider.score(workload, OperationalContext()), 0.0)

    @patch("subprocess.run")
    def test_execution_failure_fails_closed_no_synthetic_success(
        self, mock_run: MagicMock
    ) -> None:
        """Container execution errors must return non-zero exit code, never fake success."""
        mock_run.side_effect = Exception("OCI container start failed: cgroup limit")
        workload = WorkloadSpec(
            workload_id="wl-fail",
            format="oci-image",
            entrypoint=["alpine:latest"],
        )
        prep = self.provider.prepare(workload)
        envelope = {
            "envelope_id": "oce-fail-oci-001",
            "intent": {"action": "container.run"},
        }
        with patch.object(self.provider, "_detect_runtime_binary", return_value="/usr/bin/crun"):
            receipt = self.provider.execute(prep, envelope)
            self.assertNotEqual(receipt.exit_code, 0)
            self.assertNotIn("OCI_CONTAINER_OUTPUT", receipt.stdout_preview)
            self.assertIn("OCI container start failed", receipt.stderr_preview)
            self.assertEqual(receipt.invariants_verified, [])

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)

    def test_oci_bundle_config_json_generation(self) -> None:
        """Verifies that prepare() generates a valid OCI bundle specification (config.json)."""
        workload = WorkloadSpec(
            workload_id="wl-bundle",
            format="oci-image",
            entrypoint=["/bin/sh"],
            arguments=["-c", "uptime"],
            env={"PORT": "8080"},
        )
        prep = self.provider.prepare(workload)
        self.assertIsNotNone(prep.temp_dir)
        config_path = os.path.join(prep.temp_dir, "config.json")
        self.assertTrue(os.path.isfile(config_path))

        import json
        with open(config_path, "r", encoding="utf-8") as f:
            spec = json.load(f)

        self.assertEqual(spec.get("ociVersion"), "1.0.2")
        self.assertEqual(spec["process"]["args"], ["/bin/sh", "-c", "uptime"])
        self.assertIn("PORT=8080", spec["process"]["env"])

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)
        self.assertFalse(os.path.exists(config_path))

    @patch("subprocess.run")
    def test_podman_invocation_command_formatting(self, mock_run: MagicMock) -> None:
        """Verifies that podman runtime formats invocation as 'podman run --rm'."""
        mock_run.return_value = MagicMock(returncode=0, stdout=b"OK\n", stderr=b"")
        workload = WorkloadSpec(
            workload_id="wl-podman",
            format="oci-image",
            entrypoint=["alpine:latest", "echo", "hello"],
            working_dir="/app",
            env={"ENV_TEST": "val"},
        )
        prep = self.provider.prepare(workload)
        envelope = {
            "envelope_id": "oce-podman-001",
            "intent": {"action": "container.run"},
            "invariants": ["INV-SEC-008"],
        }
        with patch.object(self.provider, "_detect_runtime_binary", return_value="/usr/bin/podman"):
            receipt = self.provider.execute(prep, envelope)
            self.assertEqual(receipt.exit_code, 0)
            podman_calls = [
                c for c in mock_run.call_args_list if c[0] and c[0][0] and c[0][0][0] == "/usr/bin/podman"
            ]
            self.assertTrue(len(podman_calls) > 0)
            cmd = podman_calls[0][0][0]
            self.assertEqual(cmd[0], "/usr/bin/podman")
            self.assertEqual(cmd[1], "run")
            self.assertEqual(cmd[2], "--rm")
            self.assertIn("-w", cmd)
            self.assertIn("/app", cmd)
            self.assertIn("alpine:latest", cmd)

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)


if __name__ == "__main__":
    unittest.main()
