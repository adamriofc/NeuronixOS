"""
Unit tests for OciContainerProvider (UEF OCI Container Standard Runtime Provider).
Validates Mode A (high-level image -> podman/docker) and Mode B (low-level bundle -> crun/runc),
dynamic scoring prioritization, fail-closed contracts, and ephemeral container lifecycle cleanup.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.uef.models import OperationalContext, WorkloadSpec
from neuronix_core.uef.oci_provider import (
    OciContainerProvider,
    STANDARD_CONTAINER_SYSCALL_ALLOWLIST,
    RESTRICTED_PRIVILEGED_SYSCALLS,
    generate_standard_seccomp_profile,
    validate_seccomp_profile,
    evaluate_syscall_policy,
)


class TestUefOciProvider(unittest.TestCase):
    def setUp(self) -> None:
        self.provider = OciContainerProvider()

    def test_provider_discovery(self) -> None:
        """OciContainerProvider discovers OCI container capabilities."""
        cap = self.provider.discover()
        self.assertEqual(cap.provider_id, "oci.crun")
        self.assertEqual(cap.provider_type, "OCI_CONTAINER")
        self.assertGreaterEqual(cap.isolation_level, 0.80)
        self.assertEqual(cap.resource_overhead_class, "MODERATE_CONTAINER")

    def test_inspect_oci_image_format(self) -> None:
        """Inspect accepts oci-image format when high-level runtime is present."""
        workload = WorkloadSpec(
            workload_id="wl-oci",
            format="oci-image",
            entrypoint=["alpine:latest", "sh", "-c", "echo hello"],
        )
        with patch.object(self.provider, "_detect_high_level_runtime", return_value="/usr/bin/podman"):
            report = self.provider.inspect(workload)
            self.assertTrue(report.compatible)
            self.assertIn("Mode A", report.reason)
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

    def test_mode_a_oci_image_without_high_level_runtime_fails_closed(self) -> None:
        """OCI image format strictly requires podman/docker; crun/runc alone cannot execute it."""
        workload = WorkloadSpec(
            workload_id="wl-oci-nohigh",
            format="oci-image",
            entrypoint=["alpine:latest"],
        )
        with patch.object(self.provider, "_detect_high_level_runtime", return_value=None):
            with patch.object(self.provider, "_detect_low_level_runtime", return_value="/usr/bin/runc"):
                report = self.provider.inspect(workload)
                self.assertFalse(report.compatible)
                self.assertIn("podman", report.missing_features)
                self.assertEqual(self.provider.score(workload, OperationalContext()), 0.0)

    def test_mode_b_rootfs_dir_without_valid_path_fails_closed(self) -> None:
        """Mode B requires a valid populated rootfs directory."""
        workload = WorkloadSpec(
            workload_id="wl-rootfs-invalid",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/nonexistent/rootfs/path/dir",
        )
        report = self.provider.inspect(workload)
        self.assertFalse(report.compatible)
        self.assertIn("valid_rootfs_path", report.missing_features)

    def test_scoring_prioritizes_oci_images(self) -> None:
        """Scoring rates oci-image format highest for container provider."""
        workload_oci = WorkloadSpec(
            workload_id="wl-oci",
            format="oci-image",
            entrypoint=["debian:stable-slim"],
        )
        ctx = OperationalContext(requested_isolation_tier="TIER_1_SANDBOX")
        with patch.object(self.provider, "_detect_high_level_runtime", return_value="/usr/bin/podman"):
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
        with patch.object(self.provider, "_detect_runtime_for_workload", return_value="/usr/bin/podman"):
            receipt = self.provider.execute(prep, envelope)
            self.assertEqual(receipt.exit_code, 0)
            self.assertEqual(receipt.provider_id, "oci.crun")
            self.assertIn("INV-SEC-008", receipt.invariants_verified)

        proof = self.provider.cleanup(prep)
        self.assertTrue(proof.clean)

    def test_missing_runtime_inspect_fails_closed(self) -> None:
        """Missing all OCI runtime binaries must report compatible=False (fail-closed)."""
        workload = WorkloadSpec(
            workload_id="wl-oci",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",
        )
        with patch.object(self.provider, "_detect_low_level_runtime", return_value=None):
            with patch.object(self.provider, "_detect_high_level_runtime", return_value=None):
                report = self.provider.inspect(workload)
                self.assertFalse(report.compatible)
                self.assertIn("crun", report.missing_features)
                self.assertIn("runc", report.missing_features)
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
        with patch.object(self.provider, "_detect_runtime_for_workload", return_value="/usr/bin/podman"):
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
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            arguments=["-c", "uptime"],
            rootfs_path="/",
            env={"PORT": "8080"},
        )
        prep = self.provider.prepare(workload)
        self.assertIsNotNone(prep.temp_dir)
        config_path = os.path.join(prep.temp_dir, "config.json")
        self.assertTrue(os.path.isfile(config_path))

        with open(config_path, "r", encoding="utf-8") as f:
            spec = json.load(f)

        self.assertEqual(spec.get("ociVersion"), "1.0.2")
        self.assertEqual(spec["process"]["args"], ["/bin/sh", "-c", "uptime"])
        self.assertIn("PORT=8080", spec["process"]["env"])
        self.assertEqual(spec["root"]["path"], "/")

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
        with patch.object(self.provider, "_detect_runtime_for_workload", return_value="/usr/bin/podman"):
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

    def test_mode_b_rootfs_dir_without_low_level_runtime_fails_closed(self) -> None:
        """Mode B (rootfs-dir) strictly requires low-level runtime (crun/runc); podman alone is rejected."""
        workload = WorkloadSpec(
            workload_id="wl-rootfs-nohigh",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",
        )
        with patch.object(self.provider, "_detect_high_level_runtime", return_value="/usr/bin/podman"):
            with patch.object(self.provider, "_detect_low_level_runtime", return_value=None):
                report = self.provider.inspect(workload)
                self.assertFalse(report.compatible)
                self.assertIn("crun", report.missing_features)
                self.assertIn("runc", report.missing_features)
                self.assertEqual(self.provider.score(workload, OperationalContext()), 0.0)

    def test_mode_b_oci_bundle_without_low_level_runtime_fails_closed(self) -> None:
        """Mode B (oci-bundle) strictly requires low-level runtime (crun/runc); docker alone is rejected."""
        workload = WorkloadSpec(
            workload_id="wl-bundle-nohigh",
            format="oci-bundle",
            entrypoint=["/bin/sh"],
            bundle_path="/tmp/fake-bundle",
        )
        with patch.object(self.provider, "_detect_high_level_runtime", return_value="/usr/bin/docker"):
            with patch.object(self.provider, "_detect_low_level_runtime", return_value=None):
                report = self.provider.inspect(workload)
                self.assertFalse(report.compatible)
                self.assertIn("crun", report.missing_features)
                self.assertEqual(self.provider.score(workload, OperationalContext()), 0.0)

    def test_mode_b_rootfs_dir_with_crun_accepts(self) -> None:
        """Mode B accepts rootfs-dir when crun/runc and valid rootfs are present."""
        workload = WorkloadSpec(
            workload_id="wl-rootfs-ok",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",
        )
        with patch.object(self.provider, "_detect_low_level_runtime", return_value="/usr/bin/crun"):
            with patch.object(self.provider, "_detect_high_level_runtime", return_value=None):
                report = self.provider.inspect(workload)
                self.assertTrue(report.compatible)
                self.assertIn("Mode B", report.reason)
                self.assertIn("crun", report.reason)

    def test_mode_b_oci_bundle_with_crun_and_valid_bundle_accepts(self) -> None:
        """Mode B accepts oci-bundle when crun and valid bundle directory with config.json exist."""
        import tempfile
        temp_bundle = tempfile.mkdtemp(prefix="test-oci-bundle-")
        try:
            rootfs_dir = os.path.join(temp_bundle, "rootfs")
            os.makedirs(rootfs_dir, exist_ok=True)
            cfg_path = os.path.join(temp_bundle, "config.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump({"ociVersion": "1.0.2", "root": {"path": "rootfs"}}, f)

            workload = WorkloadSpec(
                workload_id="wl-bundle-ok",
                format="oci-bundle",
                entrypoint=["/bin/sh"],
                bundle_path=temp_bundle,
            )
            with patch.object(self.provider, "_detect_low_level_runtime", return_value="/usr/bin/crun"):
                with patch.object(self.provider, "_detect_high_level_runtime", return_value=None):
                    report = self.provider.inspect(workload)
                    self.assertTrue(report.compatible)
                    self.assertIn("Mode B", report.reason)
        finally:
            shutil.rmtree(temp_bundle, ignore_errors=True)

    def test_mode_b_oci_bundle_missing_config_json_fails_closed(self) -> None:
        """Mode B rejects oci-bundle if config.json is absent in bundle directory."""
        import tempfile
        temp_bundle = tempfile.mkdtemp(prefix="test-oci-bundle-nocfg-")
        try:
            rootfs_dir = os.path.join(temp_bundle, "rootfs")
            os.makedirs(rootfs_dir, exist_ok=True)
            workload = WorkloadSpec(
                workload_id="wl-bundle-nocfg",
                format="oci-bundle",
                entrypoint=["/bin/sh"],
                bundle_path=temp_bundle,
            )
            with patch.object(self.provider, "_detect_low_level_runtime", return_value="/usr/bin/crun"):
                report = self.provider.inspect(workload)
                self.assertFalse(report.compatible)
                self.assertIn("oci_config_json", report.missing_features)
        finally:
            shutil.rmtree(temp_bundle, ignore_errors=True)

    def test_mode_b_oci_bundle_missing_rootfs_dir_fails_closed(self) -> None:
        """Mode B rejects oci-bundle if rootfs directory referenced in config.json is missing."""
        import tempfile
        temp_bundle = tempfile.mkdtemp(prefix="test-oci-bundle-noroot-")
        try:
            cfg_path = os.path.join(temp_bundle, "config.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump({"ociVersion": "1.0.2", "root": {"path": "rootfs"}}, f)

            workload = WorkloadSpec(
                workload_id="wl-bundle-noroot",
                format="oci-bundle",
                entrypoint=["/bin/sh"],
                bundle_path=temp_bundle,
            )
            with patch.object(self.provider, "_detect_low_level_runtime", return_value="/usr/bin/crun"):
                report = self.provider.inspect(workload)
                self.assertFalse(report.compatible)
                self.assertIn("valid_rootfs_dir", report.missing_features)
        finally:
            shutil.rmtree(temp_bundle, ignore_errors=True)

    def test_execute_enforces_strict_runtime_orthogonality(self) -> None:
        """Execute strictly raises RuntimeError if an incompatible engine is invoked on mismatched format."""
        # 1. High-level runtime on Mode B format
        workload_b = WorkloadSpec(
            workload_id="wl-mismatch-b",
            format="rootfs-dir",
            entrypoint=["/bin/sh"],
            rootfs_path="/",
        )
        prep_b = self.provider.prepare(workload_b)
        setattr(prep_b, "_runtime", "/usr/bin/podman")
        with self.assertRaises(RuntimeError) as cm_b:
            self.provider.execute(prep_b, {"envelope_id": "env-b"})
        self.assertIn("Mode A (oci-image) is strictly required", str(cm_b.exception))
        self.provider.cleanup(prep_b)

        # 2. Low-level runtime on Mode A format
        workload_a = WorkloadSpec(
            workload_id="wl-mismatch-a",
            format="oci-image",
            entrypoint=["alpine:latest"],
        )
        prep_a = self.provider.prepare(workload_a)
        setattr(prep_a, "_runtime", "/usr/bin/crun")
        with self.assertRaises(RuntimeError) as cm_a:
            self.provider.execute(prep_a, {"envelope_id": "env-a"})
        self.assertIn("Mode B (rootfs-dir or oci-bundle) is strictly required", str(cm_a.exception))
        self.provider.cleanup(prep_a)

    def test_discover_reflects_runtime_presence_orthogonally(self) -> None:
        """Discover lists only supported formats based on orthogonal runtime availability."""
        with patch.object(self.provider, "_detect_high_level_runtime", return_value="/usr/bin/podman"):
            with patch.object(self.provider, "_detect_low_level_runtime", return_value=None):
                cap = self.provider.discover()
                self.assertIn("oci-image", cap.supported_formats)
                self.assertNotIn("rootfs-dir", cap.supported_formats)
                self.assertNotIn("oci-bundle", cap.supported_formats)

        with patch.object(self.provider, "_detect_high_level_runtime", return_value=None):
            with patch.object(self.provider, "_detect_low_level_runtime", return_value="/usr/bin/crun"):
                cap = self.provider.discover()
                self.assertNotIn("oci-image", cap.supported_formats)
                self.assertIn("rootfs-dir", cap.supported_formats)
                self.assertIn("oci-bundle", cap.supported_formats)

    def test_real_oci_runtime_discovery_and_integration(self) -> None:
        """Integration check: validates detection of real host OCI container runtimes (runc and/or podman)."""
        has_runc = bool(shutil.which("runc"))
        has_podman = bool(shutil.which("podman"))
        if not (has_runc or has_podman):
            self.skipTest("Neither runc nor podman is available on host.")

        if has_runc:
            # Real Mode B inspection with host rootfs
            workload_b = WorkloadSpec(
                workload_id="wl-real-oci-test-b",
                format="rootfs-dir",
                entrypoint=["/bin/true"],
                rootfs_path="/",
            )
            report_b = self.provider.inspect(workload_b)
            self.assertTrue(report_b.compatible)
            self.assertIn("Mode B", report_b.reason)

            prep = self.provider.prepare(workload_b)
            config_path = os.path.join(prep.temp_dir, "config.json")
            self.assertTrue(os.path.exists(config_path))
            proof = self.provider.cleanup(prep)
            self.assertTrue(proof.clean)

        if has_podman:
            # Real Mode A inspection with container image
            workload_a = WorkloadSpec(
                workload_id="wl-real-oci-test-a",
                format="oci-image",
                entrypoint=["alpine:latest", "/bin/true"],
            )
            report_a = self.provider.inspect(workload_a)
            self.assertTrue(report_a.compatible)
            self.assertIn("Mode A", report_a.reason)

    def test_discover_no_runtime_returns_empty_supported_formats(self) -> None:
        """When neither high-level nor low-level runtime is present, discover returns empty supported_formats."""
        with patch.object(self.provider, "_detect_high_level_runtime", return_value=None), \
             patch.object(self.provider, "_detect_low_level_runtime", return_value=None):
            cap = self.provider.discover()
            self.assertEqual(cap.supported_formats, [])
            self.assertEqual(cap.isolation_level, 0.0)
            self.assertEqual(cap.startup_latency_class, "UNAVAILABLE")
            self.assertEqual(cap.resource_overhead_class, "NONE")

    def test_resolver_rejects_oci_when_no_runtimes_detected(self) -> None:
        """When no runtimes are installed, resolver assigns 0.0 score and inspect fails closed."""
        with patch.object(self.provider, "_detect_high_level_runtime", return_value=None), \
             patch.object(self.provider, "_detect_low_level_runtime", return_value=None):
            workload = WorkloadSpec(
                workload_id="wl-img-noruntime",
                format="oci-image",
                entrypoint=["alpine:latest", "sh"],
            )
            report = self.provider.inspect(workload)
            self.assertFalse(report.compatible)
            self.assertIn("podman", report.missing_features)

            ctx = OperationalContext(
                requested_isolation_tier="TIER_1_SANDBOX",
                network_allowed=False,
            )
            score = self.provider.score(workload, ctx)
            self.assertEqual(score, 0.0)

    def test_oci_image_provenance_classification(self) -> None:
        """Validates distinction between digest-pinned images and mutable tags."""
        self.assertEqual(
            OciContainerProvider.classify_image_provenance("alpine@sha256:abcd1234ef567890"),
            "PROVENANCE_STRONG",
        )
        self.assertEqual(
            OciContainerProvider.classify_image_provenance("alpine:latest"),
            "PROVENANCE_NORMAL",
        )

        # In evaluate_capabilities, pinned digest yields 1.0 provenance
        workload_pinned = WorkloadSpec(
            workload_id="wl-pinned",
            format="oci-image",
            entrypoint=["alpine@sha256:1234567890abcdef", "sh"],
        )
        with patch.object(self.provider, "_detect_high_level_runtime", return_value="/usr/bin/podman"):
            vec = self.provider.evaluate_capabilities(
                workload_pinned,
                OperationalContext("TIER_1_SANDBOX", False, False),
            )
            self.assertEqual(vec.provenance, 1.0)

    def test_untrusted_workload_oci_config_hardening(self) -> None:
        """Verifies generated config.json contains hardened security profile."""
        workload = WorkloadSpec(
            workload_id="wl-untrusted-bundle",
            format="rootfs-dir",
            entrypoint=["/bin/sh", "-c", "whoami"],
            rootfs_path="/",
        )
        with patch.object(self.provider, "_detect_low_level_runtime", return_value="/usr/bin/crun"):
            prep = self.provider.prepare(workload)
            config_path = os.path.join(prep.temp_dir, "config.json")
            self.assertTrue(os.path.exists(config_path))
            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)

            # Security invariants
            self.assertTrue(cfg["process"]["noNewPrivileges"])
            self.assertIn("capabilities", cfg["process"])
            self.assertNotIn("CAP_SYS_ADMIN", cfg["process"]["capabilities"]["bounding"])
            self.assertTrue(cfg["root"]["readonly"])
            ns_types = [ns["type"] for ns in cfg["linux"]["namespaces"]]
            self.assertIn("user", ns_types)
            self.assertIn("network", ns_types)
            self.assertEqual(cfg["linux"]["seccomp"]["defaultAction"], "SCMP_ACT_ERRNO")
            self.assertGreater(len(cfg["linux"]["seccomp"]["syscalls"]), 0)
            allowed_names = set(cfg["linux"]["seccomp"]["syscalls"][0]["names"])
            self.assertIn("read", allowed_names)
            self.assertIn("write", allowed_names)
            self.assertIn("execve", allowed_names)
            self.assertNotIn("reboot", allowed_names)
            self.assertNotIn("kexec_load", allowed_names)
            self.assertNotIn("bpf", allowed_names)
            self.assertIn("resources", cfg["linux"])
            self.assertGreater(cfg["linux"]["resources"]["memory"]["limit"], 0)
            self.assertGreater(cfg["linux"]["resources"]["pids"]["limit"], 0)

            self.provider.cleanup(prep)

    def test_seccomp_profile_architecture_aware_allowlist(self) -> None:
        """Verifies seccomp profile is architecture-aware and allows userspace while blocking privileged operations."""
        profile = generate_standard_seccomp_profile()
        self.assertEqual(profile["defaultAction"], "SCMP_ACT_ERRNO")
        self.assertIn("SCMP_ARCH_X86_64", profile["architectures"])
        self.assertIn("SCMP_ARCH_AARCH64", profile["architectures"])
        self.assertGreater(len(profile["syscalls"]), 0)

        rule = profile["syscalls"][0]
        self.assertEqual(rule["action"], "SCMP_ACT_ALLOW")
        names = set(rule["names"])

        # Userspace essentials must be allowed
        for sc in ["read", "write", "openat", "close", "mmap", "clone", "execve", "exit_group"]:
            self.assertIn(sc, names)

        # Dangerous/privileged operations must NOT be in allowlist (denied by defaultAction)
        for sc in RESTRICTED_PRIVILEGED_SYSCALLS:
            self.assertNotIn(sc, names)

    def test_seccomp_empty_allowlist_regression_assertion(self) -> None:
        """Regression invariant: default-deny with empty syscall allowlist is strictly prohibited."""
        empty_profile = {
            "defaultAction": "SCMP_ACT_ERRNO",
            "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
            "syscalls": [],
        }
        self.assertFalse(validate_seccomp_profile(empty_profile))

        # Missing architecture also fails closed
        missing_arch = {
            "defaultAction": "SCMP_ACT_ERRNO",
            "architectures": ["SCMP_ARCH_X86_64"],
            "syscalls": [{"names": ["read"], "action": "SCMP_ACT_ALLOW"}],
        }
        self.assertFalse(validate_seccomp_profile(missing_arch))

        # Empty rule list fails closed
        empty_rule_names = {
            "defaultAction": "SCMP_ACT_ERRNO",
            "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
            "syscalls": [{"names": [], "action": "SCMP_ACT_ALLOW"}],
        }
        self.assertFalse(validate_seccomp_profile(empty_rule_names))

        # Valid standard profile passes
        valid_profile = generate_standard_seccomp_profile()
        self.assertTrue(validate_seccomp_profile(valid_profile))

    def test_seccomp_malformed_input_resilience_and_fail_closed(self) -> None:
        """Verifies validate_seccomp_profile and evaluate_syscall_policy fail closed on malformed structures."""
        # Non-dict inputs must return False without crashing
        self.assertFalse(validate_seccomp_profile(None))
        self.assertFalse(validate_seccomp_profile("string_not_dict"))
        self.assertFalse(validate_seccomp_profile([1, 2, 3]))

        # Malformed architectures container type
        self.assertFalse(validate_seccomp_profile({
            "defaultAction": "SCMP_ACT_ERRNO",
            "architectures": 12345,
            "syscalls": [{"names": ["read"], "action": "SCMP_ACT_ALLOW"}],
        }))

        # Malformed syscall entry (string instead of dict)
        self.assertFalse(validate_seccomp_profile({
            "defaultAction": "SCMP_ACT_ERRNO",
            "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
            "syscalls": ["malformed_string_entry"],
        }))

        # Malformed names (None instead of list)
        self.assertFalse(validate_seccomp_profile({
            "defaultAction": "SCMP_ACT_ERRNO",
            "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_AARCH64"],
            "syscalls": [{"names": None, "action": "SCMP_ACT_ALLOW"}],
        }))

        # Policy evaluation resilience against invalid inputs
        self.assertEqual(evaluate_syscall_policy("", {}), "SCMP_ACT_ERRNO")
        self.assertEqual(evaluate_syscall_policy("read", None), "SCMP_ACT_ALLOW")
        self.assertEqual(evaluate_syscall_policy("read", {"defaultAction": "SCMP_ACT_ERRNO", "syscalls": [{"names": None}]}), "SCMP_ACT_ERRNO")

    def test_seccomp_custom_base_and_essential_syscalls_coverage(self) -> None:
        """Verifies custom base allowlists and confirms essential modern container syscalls are present."""
        # Empty base syscalls with defaultAction SCMP_ACT_ERRNO must raise ValueError
        with self.assertRaises(ValueError):
            generate_standard_seccomp_profile(default_action="SCMP_ACT_ERRNO", base_syscalls=[])

        with self.assertRaises(ValueError):
            generate_standard_seccomp_profile(default_action="SCMP_ACT_KILL", base_syscalls=[])

        # Essential modern userspace syscalls must be covered in default profile
        profile = generate_standard_seccomp_profile()
        allowed = set(profile["syscalls"][0]["names"])
        for essential in [
            "statfs", "fstatfs", "statfs64", "fstatfs64",
            "sync", "syncfs", "fadvise64", "close_range",
            "rseq", "getgroups", "setgroups", "getpgid", "setpgid",
            "getsid", "setsid", "getpgrp", "setpgrp",
            "capget", "capset", "inotify_init", "inotify_init1",
            "inotify_add_watch", "inotify_rm_watch",
        ]:
            self.assertIn(essential, allowed, f"Essential syscall '{essential}' must be present in standard container allowlist")

    @patch("subprocess.run")
    def test_seccomp_operational_workload_lifecycle(self, mock_run: MagicMock) -> None:
        """
        Operational test proving:
        1. Normal container workload with allowed syscalls succeeds and outputs verified receipt.
        2. Restricted syscalls are blocked by seccomp policy (SCMP_ACT_ERRNO).
        3. Workload resources are cleanly released with valid ResourceReleaseProof.
        """
        # 1. Policy resolution assertions
        self.assertEqual(evaluate_syscall_policy("read"), "SCMP_ACT_ALLOW")
        self.assertEqual(evaluate_syscall_policy("write"), "SCMP_ACT_ALLOW")
        self.assertEqual(evaluate_syscall_policy("execve"), "SCMP_ACT_ALLOW")
        self.assertEqual(evaluate_syscall_policy("reboot"), "SCMP_ACT_ERRNO")
        self.assertEqual(evaluate_syscall_policy("kexec_load"), "SCMP_ACT_ERRNO")
        self.assertEqual(evaluate_syscall_policy("bpf"), "SCMP_ACT_ERRNO")

        workload = WorkloadSpec(
            workload_id="wl-seccomp-operational",
            format="rootfs-dir",
            entrypoint=["/bin/sh", "-c", "echo seccomp-active"],
            rootfs_path="/",
        )

        with patch.object(self.provider, "_detect_low_level_runtime", return_value="/usr/bin/crun"):
            prep = self.provider.prepare(workload)
            config_path = os.path.join(prep.temp_dir, "config.json")
            self.assertTrue(os.path.exists(config_path))
            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            self.assertTrue(validate_seccomp_profile(cfg["linux"]["seccomp"]))

            # Normal shell execution succeeds
            mock_run.return_value = subprocess.CompletedProcess(
                args=["/usr/bin/crun", "run", "-b", prep.temp_dir, "nrx-123456"],
                returncode=0,
                stdout=b"seccomp-active\n",
                stderr=b"",
            )
            receipt = self.provider.execute(prep, {})
            self.assertEqual(receipt.exit_code, 0)
            self.assertEqual(receipt.provider_id, "oci.crun")
            self.assertIn("seccomp-active", receipt.stdout_preview)
            self.assertTrue(len(receipt.evidence_digest) > 0)

            # Restricted syscall blocked (e.g. reboot / kexec_load triggers EPERM)
            mock_run.return_value = subprocess.CompletedProcess(
                args=["/usr/bin/crun", "run", "-b", prep.temp_dir, "nrx-123456"],
                returncode=1,
                stdout=b"",
                stderr=b"Operation not permitted (seccomp SCMP_ACT_ERRNO blocked syscall)\n",
            )
            failed_receipt = self.provider.execute(prep, {})
            self.assertEqual(failed_receipt.exit_code, 1)
            self.assertIn("Operation not permitted", failed_receipt.stderr_preview)

            # Cleanup proof is verified clean
            proof = self.provider.cleanup(prep)
            self.assertTrue(proof.clean)
            self.assertFalse(os.path.exists(prep.temp_dir))


if __name__ == "__main__":
    unittest.main()
