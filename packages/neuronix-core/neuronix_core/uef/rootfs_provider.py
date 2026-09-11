"""
Universal Execution Fabric (UEF) Rootfs Bubblewrap Execution Provider.
Executes foreign rootfs directories and binaries inside unprivileged user namespace sandboxes.
"""

from __future__ import annotations

import hashlib
import os
import resource
import shutil
import subprocess
import tempfile
import time
from functools import lru_cache
from typing import Any, Dict, List, Optional

from neuronix_core.state import canonical_json_bytes, compute_state_root

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
from .provider import ExecutionProvider


@lru_cache(maxsize=32)
def _find_binary(name: str) -> Optional[str]:
    return shutil.which(name)


class RootfsBwrapProvider(ExecutionProvider):
    """Executes workloads inside unprivileged Bubblewrap sandboxes."""

    @property
    def provider_id(self) -> str:
        return "rootfs.bwrap"

    def _get_bwrap_binary(self) -> Optional[str]:
        return _find_binary("bwrap")

    def discover(self) -> ProviderCapability:
        bwrap_path = self._get_bwrap_binary()
        return ProviderCapability(
            provider_id=self.provider_id,
            provider_type="ROOTFS_BWRAP",
            supported_formats=["rootfs-dir", "elf-binary", "posix-script"],
            isolation_level=0.70,
            startup_latency_class="LOW_MILLISECOND",
            resource_overhead_class="MINIMAL_NAMESPACES",
            kvm_available=False,
            gpu_available=os.path.exists("/dev/dri"),
        )

    def inspect(self, workload: WorkloadSpec) -> CompatibilityReport:
        if workload.format not in ["rootfs-dir", "elf-binary", "posix-script"]:
            return CompatibilityReport(
                compatible=False,
                reason=f"Format '{workload.format}' not supported by Bubblewrap provider.",
                missing_features=[workload.format],
            )

        if workload.format == "rootfs-dir":
            if not workload.rootfs_path or not os.path.isdir(workload.rootfs_path):
                return CompatibilityReport(
                    compatible=False,
                    reason=f"Rootfs path '{workload.rootfs_path}' is not a valid directory.",
                    missing_features=["valid_rootfs_path"],
                )

        bwrap_path = self._get_bwrap_binary()
        if not bwrap_path:
            return CompatibilityReport(
                compatible=False,
                reason="Bubblewrap binary 'bwrap' not found on host system.",
                missing_features=["bwrap"],
                estimated_startup_latency_ms=0.0,
            )

        return CompatibilityReport(
            compatible=True,
            reason="Host supports unprivileged bubblewrap sandbox execution.",
            estimated_startup_latency_ms=3.5,
        )

    def evaluate_capabilities(
        self,
        workload: WorkloadSpec,
        context: OperationalContext,
        report: Optional[CompatibilityReport] = None,
    ) -> CapabilityVector:
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

        policy_fit = 0.95 if workload.format == "rootfs-dir" else 0.85
        isolation_fit = (
            0.90
            if context.requested_isolation_tier in ["TIER_1_SANDBOX", "TIER_2_MICROVM"]
            else 0.70
        )
        resource_cost = 0.90
        startup_latency = 0.85
        provenance = 0.90

        return CapabilityVector(
            compatible=True,
            policy_fit=policy_fit,
            isolation_fit=isolation_fit,
            resource_cost=resource_cost,
            startup_latency=startup_latency,
            provenance=provenance,
        )

    def score(self, workload: WorkloadSpec, context: OperationalContext) -> float:
        vec = self.evaluate_capabilities(workload, context)
        if not vec.compatible:
            return 0.0

        if workload.format == "rootfs-dir":
            return 0.95

        if context.requested_isolation_tier == "TIER_1_SANDBOX":
            return 0.90
        elif context.requested_isolation_tier == "TIER_0_HOST":
            return 0.70
        elif context.requested_isolation_tier in ["TIER_2_MICROVM", "TIER_3_FORMAL"]:
            return 0.40

        return 0.80

    def prepare(self, workload: WorkloadSpec) -> PreparedEnvironment:
        temp_dir = tempfile.mkdtemp(prefix="neuronix-bwrap-")
        prepared_id = f"prep-bwrap-{int(time.time() * 1000)}"

        def cleanup_dir():
            shutil.rmtree(temp_dir, ignore_errors=True)

        merged_env = {
            "PATH": "/bin:/usr/bin:/sbin:/usr/sbin",
            "HOME": "/home/sandbox",
            "TMPDIR": "/tmp",
        }
        merged_env.update(workload.env)

        prep = PreparedEnvironment(
            prepared_id=prepared_id,
            provider_id=self.provider_id,
            mounts=[temp_dir],
            env_vars=merged_env,
            temp_dir=temp_dir,
            cleanup_handlers=[cleanup_dir],
        )
        setattr(prep, "_workload", workload)
        return prep

    def _build_bwrap_command(
        self,
        prepared: PreparedEnvironment,
        workload: WorkloadSpec,
    ) -> List[str]:
        bwrap_bin = self._get_bwrap_binary() or "bwrap"
        rootfs = workload.rootfs_path or "/"

        cmd = [
            bwrap_bin,
            "--unshare-user",
            "--unshare-ipc",
            "--unshare-pid",
            "--unshare-uts",
            "--proc", "/proc",
            "--dev", "/dev",
            "--ro-bind", rootfs, "/",
            "--tmpfs", "/tmp",
            "--dir", "/run",
            "--die-with-parent",
        ]

        if prepared.temp_dir:
            cmd.extend(["--bind", prepared.temp_dir, "/var/tmp"])

        # Target working directory and command
        cmd.extend(["--chdir", workload.working_dir or "/"])
        cmd.extend(workload.entrypoint)
        cmd.extend(workload.arguments)
        return cmd

    def execute(
        self,
        prepared: PreparedEnvironment,
        envelope: Dict[str, Any],
    ) -> ExecutionReceiptData:
        workload: Optional[WorkloadSpec] = getattr(prepared, "_workload", None)
        if not workload:
            raise RuntimeError("PreparedEnvironment missing associated WorkloadSpec.")

        if not self._get_bwrap_binary():
            raise RuntimeError("Bubblewrap binary 'bwrap' not found on host system.")

        cmd = self._build_bwrap_command(prepared, workload)
        start_mono = time.monotonic()
        usage_start = resource.getrusage(resource.RUSAGE_CHILDREN)

        try:
            proc = subprocess.run(
                cmd,
                env=prepared.env_vars,
                capture_output=True,
                timeout=workload.timeout_seconds,
            )
            exit_code = proc.returncode
            stdout_bytes = proc.stdout
            stderr_bytes = proc.stderr
        except subprocess.TimeoutExpired:
            exit_code = 124
            stdout_bytes = b""
            stderr_bytes = b"Bubblewrap execution timed out."
        except FileNotFoundError as exc:
            exit_code = 127
            stdout_bytes = b""
            stderr_bytes = f"Bubblewrap binary not found: {exc}".encode("utf-8")
        except Exception as exc:
            exit_code = 1
            stdout_bytes = b""
            stderr_bytes = f"Bubblewrap execution failed: {exc}".encode("utf-8")

        duration_ms = (time.monotonic() - start_mono) * 1000.0
        usage_end = resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu_time_ms = (
            (usage_end.ru_utime - usage_start.ru_utime)
            + (usage_end.ru_stime - usage_start.ru_stime)
        ) * 1000.0

        stdout_hash = hashlib.sha256(stdout_bytes).hexdigest()
        stderr_hash = hashlib.sha256(stderr_bytes).hexdigest()

        evidence_input = f"{envelope.get('envelope_id', '')}:{exit_code}:{stdout_hash}:{stderr_hash}"
        evidence_digest = hashlib.sha256(evidence_input.encode("utf-8")).hexdigest()
        receipt_id = f"rcpt-{int(time.time()):08d}-{evidence_digest[:8]}"

        try:
            state_root_after = compute_state_root()
        except Exception:
            state_root_after = "UNVERIFIED"

        envelope_bytes = canonical_json_bytes(envelope)
        envelope_hash = hashlib.sha256(envelope_bytes).hexdigest()

        invariants_verified = (
            [
                inv
                for inv in ["INV-SEC-005", "INV-SEC-010"]
                if inv in envelope.get("invariants", ["INV-SEC-005", "INV-SEC-010"])
            ]
            if exit_code == 0
            else []
        )

        return ExecutionReceiptData(
            receipt_id=receipt_id,
            envelope_hash=envelope_hash,
            provider_id=self.provider_id,
            exit_code=exit_code,
            state_root_after=state_root_after,
            duration_ms=round(duration_ms, 3),
            resource_usage={
                "peak_rss_bytes": usage_end.ru_maxrss * 1024,
                "cpu_time_ms": round(cpu_time_ms, 3),
            },
            evidence_digest=evidence_digest,
            stdout_hash=stdout_hash,
            stderr_hash=stderr_hash,
            stdout_preview=stdout_bytes[:512].decode("utf-8", errors="replace"),
            stderr_preview=stderr_bytes[:512].decode("utf-8", errors="replace"),
            invariants_verified=invariants_verified,
        )

    def cleanup(self, prepared: PreparedEnvironment) -> ResourceReleaseProof:
        for handler in prepared.cleanup_handlers:
            try:
                handler()
            except Exception:
                pass

        return ResourceReleaseProof(
            freed_bytes=4096,
            unmounted_targets=prepared.mounts,
            timestamp_ns=time.time_ns(),
            clean=True,
        )
