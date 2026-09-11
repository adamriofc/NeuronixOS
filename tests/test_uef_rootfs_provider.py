"""
Unit tests for RootfsBwrapProvider (UEF Bubblewrap Isolated Rootfs Provider).
Validates unprivileged namespace capability discovery, command line construction,
isolation policy enforcement, and volatile resource reclamation.
"""

from __future__ import annotations

import os
import shutil
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.uef.models import OperationalContext, WorkloadSpec
from neuronix_core.uef.rootfs_provider import RootfsBwrapProvider


class TestUefRootfsProvider(unittest.TestCase):
    def setUp(self) -> None:
        self.provider = RootfsBwrapProvider()

    def test_provider_discovery(self) -> None:
        """RootfsBwrapProvider discovers bubblewrap capability and declares isolation."""
        cap = self.provider.discover()
        self.assertEqual(cap.provider_id, "rootfs.bwrap")
        self.assertEqual(cap.provider_type, "ROOTFS_BWRAP")
        self.assertIn("rootfs-dir", cap.supported_formats)
        self.assertGreaterEqual(cap.isolation_level, 0.6)
        self.assertEqual(cap.resource_overhead_class, "MINIMAL_NAMESPACES")

    def test_inspect_rootfs_dir_format(self) -> None:
        """Inspect accepts rootfs-dir format when directory exists."""
        workload = WorkloadSpec(
            workload_id="wl-rootfs",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",  # host root as test fixture
        )
        report = self.provider.inspect(workload)
        self.assertTrue(report.compatible)

    def test_dynamic_scoring_prioritizes_sandbox_and_rootfs(self) -> None:
        """Scoring gives high score for rootfs format and sandbox tier."""
        workload_rootfs = WorkloadSpec(
            workload_id="wl-rootfs",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",
        )
        ctx_sandbox = OperationalContext(requested_isolation_tier="TIER_1_SANDBOX")
        score = self.provider.score(workload_rootfs, ctx_sandbox)
        self.assertGreaterEqual(score, 0.85)

    def test_bwrap_argument_construction(self) -> None:
        """Verifies that bwrap command includes essential isolation flags."""
        workload = WorkloadSpec(
            workload_id="wl-secure",
            format="elf-binary",
            entrypoint=["/bin/echo"],
            arguments=["isolated"],
        )
        prep = self.provider.prepare(workload)
        bwrap_cmd = self.provider._build_bwrap_command(prep, workload)

        # Essential unprivileged isolation flags
        self.assertIn("--unshare-user", bwrap_cmd)
        self.assertIn("--unshare-ipc", bwrap_cmd)
        self.assertIn("--unshare-pid", bwrap_cmd)
        self.assertIn("--proc", bwrap_cmd)
        self.assertIn("--dev", bwrap_cmd)

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)

    @patch("subprocess.run")
    def test_mocked_execution_receipt(self, mock_run: MagicMock) -> None:
        """Verifies receipt generation from executed bwrap process."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout=b"ROOTFS_EXEC_SUCCESS\n",
            stderr=b"",
        )
        workload = WorkloadSpec(
            workload_id="wl-test",
            format="rootfs-dir",
            entrypoint=["/bin/sh", "-c", "echo ROOTFS_EXEC_SUCCESS"],
            rootfs_path="/",
        )
        prep = self.provider.prepare(workload)
        envelope = {
            "envelope_id": "oce-rootfs-001",
            "intent": {"action": "test.rootfs_exec"},
        }

        receipt = self.provider.execute(prep, envelope)
        self.assertEqual(receipt.exit_code, 0)
        self.assertEqual(receipt.provider_id, "rootfs.bwrap")
        self.assertIn("ROOTFS_EXEC_SUCCESS", receipt.stdout_preview)
        self.assertIn("INV-SEC-005", receipt.invariants_verified)

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)

    def test_missing_bwrap_inspect_fails_closed(self) -> None:
        """Missing bwrap binary must report compatible=False (fail-closed)."""
        workload = WorkloadSpec(
            workload_id="wl-rootfs",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",
        )
        with patch.object(self.provider, "_get_bwrap_binary", return_value=None):
            report = self.provider.inspect(workload)
            self.assertFalse(report.compatible)
            self.assertIn("bwrap", report.missing_features)
            self.assertEqual(self.provider.score(workload, OperationalContext()), 0.0)

    @patch("subprocess.run")
    def test_execution_failure_fails_closed_no_synthetic_success(
        self, mock_run: MagicMock
    ) -> None:
        """Execution errors must yield non-zero exit code and never synthetic success."""
        mock_run.side_effect = Exception("bwrap namespace creation failed")
        workload = WorkloadSpec(
            workload_id="wl-fail",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",
        )
        prep = self.provider.prepare(workload)
        envelope = {
            "envelope_id": "oce-fail-001",
            "intent": {"action": "test.fail"},
        }
        with patch.object(self.provider, "_get_bwrap_binary", return_value="/usr/bin/bwrap"):
            receipt = self.provider.execute(prep, envelope)
            self.assertNotEqual(receipt.exit_code, 0)
            self.assertNotIn("ROOTFS_EXEC_SUCCESS", receipt.stdout_preview)
            self.assertIn("bwrap namespace creation failed", receipt.stderr_preview)
            self.assertEqual(receipt.invariants_verified, [])

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)

    def test_real_bwrap_integration_execution(self) -> None:
        """Integration test: verifies real unprivileged bwrap container execution on host."""
        if not shutil.which("bwrap"):
            self.skipTest("Bubblewrap ('bwrap') is not available on this host.")

        workload = WorkloadSpec(
            workload_id="wl-real-bwrap",
            format="rootfs-dir",
            entrypoint=["/bin/echo"],
            arguments=["REAL_BWRAP_EXECUTION_VERIFIED"],
            rootfs_path="/",
        )
        prep = self.provider.prepare(workload)
        envelope = {
            "envelope_id": "oce-real-bwrap-001",
            "intent": {"action": "system.probe_bwrap"},
            "invariants": ["INV-SEC-005"],
        }
        receipt = self.provider.execute(prep, envelope)
        self.assertEqual(receipt.exit_code, 0)
        self.assertIn("REAL_BWRAP_EXECUTION_VERIFIED", receipt.stdout_preview)
        self.assertEqual(len(receipt.envelope_hash), 64)
        self.assertEqual(len(receipt.state_root_after), 64)
        self.assertIn("INV-SEC-005", receipt.invariants_verified)

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)


if __name__ == "__main__":
    unittest.main()
