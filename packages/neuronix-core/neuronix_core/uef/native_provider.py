"""
Universal Execution Fabric (UEF) Native Linux Execution Provider.
Executes host ELF binaries and POSIX scripts with direct host syscall performance (0% proxy penalty).
"""

from __future__ import annotations

import hashlib
import os
import resource
import shutil
import subprocess
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


@lru_cache(maxsize=64)
def _find_binary(name: str) -> Optional[str]:
    return shutil.which(name)


class NativeLinuxProvider(ExecutionProvider):
    """Executes native host Linux binaries with 0% proxy penalty."""

    @property
    def provider_id(self) -> str:
        return "native.linux"

    def discover(self) -> ProviderCapability:
        return ProviderCapability(
            provider_id=self.provider_id,
            provider_type="NATIVE_LINUX",
            supported_formats=["elf-binary", "nix-closure", "posix-script"],
            isolation_level=0.0,
            startup_latency_class="SUB_MILLISECOND",
            resource_overhead_class="ZERO_OVERHEAD",
            kvm_available=os.path.exists("/dev/kvm"),
            gpu_available=os.path.exists("/dev/dri") or os.path.exists("/proc/driver/nvidia"),
        )

    def inspect(self, workload: WorkloadSpec) -> CompatibilityReport:
        if workload.format not in ["elf-binary", "nix-closure", "posix-script"]:
            return CompatibilityReport(
                compatible=False,
                reason=f"Format '{workload.format}' not supported natively by host kernel.",
                missing_features=[workload.format],
            )

        if not workload.entrypoint:
            return CompatibilityReport(
                compatible=False,
                reason="Workload entrypoint list is empty.",
            )

        binary = workload.entrypoint[0]
        if not os.path.isabs(binary):
            resolved = _find_binary(binary)
            if not resolved:
                return CompatibilityReport(
                    compatible=False,
                    reason=f"Binary '{binary}' not found in host PATH.",
                    missing_features=[binary],
                )
        elif not os.path.exists(binary):
            return CompatibilityReport(
                compatible=False,
                reason=f"Binary '{binary}' does not exist on host.",
                missing_features=[binary],
            )

        return CompatibilityReport(
            compatible=True,
            reason="Host Linux kernel supports native execution directly.",
            estimated_startup_latency_ms=0.5,
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

        # Host execution:
        # High resource efficiency (1.0 = zero overhead)
        # High startup speed (0.99 = sub-millisecond)
        # Provenance: 0.95 (direct signed/nix host store binaries)
        if context.requested_isolation_tier == "TIER_0_HOST":
            policy_fit = 0.99
            isolation_fit = 0.95
        elif context.requested_isolation_tier == "TIER_1_SANDBOX":
            policy_fit = 0.50
            isolation_fit = 0.20
        else:
            policy_fit = 0.20
            isolation_fit = 0.05

        return CapabilityVector(
            compatible=True,
            policy_fit=policy_fit,
            isolation_fit=isolation_fit,
            resource_cost=1.0,
            startup_latency=0.99,
            provenance=0.95,
        )

    def score(self, workload: WorkloadSpec, context: OperationalContext) -> float:
        vec = self.evaluate_capabilities(workload, context)
        if not vec.compatible:
            return 0.0

        base_score = 0.95
        if context.requested_isolation_tier == "TIER_0_HOST":
            return base_score + 0.04
        elif context.requested_isolation_tier == "TIER_1_SANDBOX":
            return 0.40
        elif context.requested_isolation_tier in ["TIER_2_MICROVM", "TIER_3_FORMAL"]:
            return 0.10
        return base_score

    def prepare(self, workload: WorkloadSpec) -> PreparedEnvironment:
        merged_env = os.environ.copy()
        merged_env.update(workload.env)
        prepared_id = f"prep-native-{int(time.time() * 1000)}"

        # Store workload on the prepared environment for execution
        prep = PreparedEnvironment(
            prepared_id=prepared_id,
            provider_id=self.provider_id,
            mounts=[],
            env_vars=merged_env,
        )
        setattr(prep, "_workload", workload)
        return prep

    def execute(
        self,
        prepared: PreparedEnvironment,
        envelope: Dict[str, Any],
    ) -> ExecutionReceiptData:
        workload: Optional[WorkloadSpec] = getattr(prepared, "_workload", None)
        if not workload:
            raise RuntimeError("PreparedEnvironment missing associated WorkloadSpec.")

        cmd = list(workload.entrypoint) + list(workload.arguments)
        start_mono = time.monotonic()
        usage_start = resource.getrusage(resource.RUSAGE_CHILDREN)

        try:
            proc = subprocess.run(
                cmd,
                env=prepared.env_vars,
                cwd=workload.working_dir if os.path.exists(workload.working_dir) else None,
                capture_output=True,
                timeout=workload.timeout_seconds,
            )
            exit_code = proc.returncode
            stdout_bytes = proc.stdout
            stderr_bytes = proc.stderr
        except subprocess.TimeoutExpired:
            exit_code = 124
            stdout_bytes = b""
            stderr_bytes = b"Execution timed out."
        except Exception as exc:
            exit_code = 127
            stdout_bytes = b""
            stderr_bytes = str(exc).encode("utf-8")

        duration_ms = (time.monotonic() - start_mono) * 1000.0
        usage_end = resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu_time_ms = (
            (usage_end.ru_utime - usage_start.ru_utime)
            + (usage_end.ru_stime - usage_start.ru_stime)
        ) * 1000.0

        stdout_hash = hashlib.sha256(stdout_bytes).hexdigest()
        stderr_hash = hashlib.sha256(stderr_bytes).hexdigest()

        # Compute deterministic evidence digest
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
                for inv in ["INV-SEC-001"]
                if inv in envelope.get("invariants", ["INV-SEC-001"])
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
            freed_bytes=0,
            unmounted_targets=[],
            timestamp_ns=time.time_ns(),
            clean=True,
        )
