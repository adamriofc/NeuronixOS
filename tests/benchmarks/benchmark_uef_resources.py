"""
Resource Qualification and Zero-Leak Benchmark for UEF Execution Providers.

Measures:
1. Idle Core baseline: RSS footprint, background CPU utilization, and state engine root computation.
2. Provider lifecycle overhead: prepare, execute, and cleanup duration across Native, Rootfs, and OCI.
3. 1,000-cycle endurance qualification: asserts zero file descriptor leaks, zero mount leaks,
   zero leftover temporary directories, and bounded memory growth (< 20 MB).

Strict Invariants Enforced:
- fd_delta == 0
- mount_delta == 0
- temp_dir_delta == 0
- rss_delta_mb < 20.0
"""

from __future__ import annotations

import gc
import glob
import json
import os
import resource
import shutil
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.state import compute_state_root
from neuronix_core.uef.models import WorkloadSpec
from neuronix_core.uef.native_provider import NativeLinuxProvider
from neuronix_core.uef.oci_provider import OciContainerProvider
from neuronix_core.uef.rootfs_provider import RootfsBwrapProvider


def get_current_rss_mb() -> float:
    """Return resident set size of current process in megabytes."""
    try:
        with open("/proc/self/statm", "r", encoding="utf-8") as f:
            resident_pages = int(f.read().split()[1])
            return (resident_pages * os.sysconf("SC_PAGE_SIZE")) / (1024.0 * 1024.0)
    except Exception:
        return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0


def count_open_fds() -> int:
    """Return count of currently open file descriptors for this process."""
    try:
        return len(os.listdir("/proc/self/fd"))
    except Exception:
        return 0


def count_active_mounts() -> int:
    """Return count of active system mounts from /proc/mounts."""
    try:
        with open("/proc/mounts", "r", encoding="utf-8") as f:
            return len(f.readlines())
    except Exception:
        return 0


def count_neuronix_temp_dirs() -> int:
    """Return count of active temporary directories created by UEF providers."""
    return len(glob.glob("/tmp/neuronix-*"))


def benchmark_idle_core_baseline() -> Dict[str, Any]:
    """Measure idle baseline of neuronix_core runtime."""
    gc.collect()
    rss_idle_mb = round(get_current_rss_mb(), 2)

    # Measure CPU consumption during idle window
    usage_start = resource.getrusage(resource.RUSAGE_SELF)
    t0 = time.perf_counter()
    time.sleep(0.05)
    t1 = time.perf_counter()
    usage_end = resource.getrusage(resource.RUSAGE_SELF)

    cpu_time_ms = (
        (usage_end.ru_utime - usage_start.ru_utime)
        + (usage_end.ru_stime - usage_start.ru_stime)
    ) * 1000.0

    # Measure initial state root computation
    t_state_0 = time.perf_counter()
    state_root = compute_state_root()
    t_state_1 = time.perf_counter()
    state_root_time_ms = (t_state_1 - t_state_0) * 1000.0

    return {
        "idle_rss_mb": rss_idle_mb,
        "idle_window_seconds": round(t1 - t0, 4),
        "idle_cpu_time_ms": round(cpu_time_ms, 3),
        "initial_state_root": state_root,
        "initial_state_root_duration_ms": round(state_root_time_ms, 3),
    }


def benchmark_provider_lifecycles() -> Dict[str, Any]:
    """Profile isolated single-cycle lifecycle across all available execution providers."""
    results: Dict[str, Any] = {}

    # 1. NativeLinuxProvider
    native_provider = NativeLinuxProvider()
    wl_native = WorkloadSpec(
        workload_id="bench-native-single",
        format="elf-binary",
        entrypoint=["/bin/true"],
    )
    env_native = {
        "envelope_id": "oce-bench-native-single",
        "intent": {"action": "system.status"},
        "invariants": ["INV-SEC-001"],
    }

    t0 = time.perf_counter()
    prep_native = native_provider.prepare(wl_native)
    t_prep = time.perf_counter()
    receipt_native = native_provider.execute(prep_native, env_native)
    t_exec = time.perf_counter()
    proof_native = native_provider.cleanup(prep_native)
    t_clean = time.perf_counter()

    results["native_linux"] = {
        "prepare_ms": round((t_prep - t0) * 1000.0, 3),
        "execute_ms": round((t_exec - t_prep) * 1000.0, 3),
        "cleanup_ms": round((t_clean - t_exec) * 1000.0, 3),
        "total_ms": round((t_clean - t0) * 1000.0, 3),
        "exit_code": receipt_native.exit_code,
        "cleanup_clean": proof_native.clean,
    }

    # 2. RootfsBwrapProvider
    bwrap_provider = RootfsBwrapProvider()
    if shutil.which("bwrap"):
        wl_bwrap = WorkloadSpec(
            workload_id="bench-bwrap-single",
            format="rootfs-dir",
            entrypoint=["/bin/true"],
            rootfs_path="/",
        )
        env_bwrap = {
            "envelope_id": "oce-bench-bwrap-single",
            "intent": {"action": "system.status"},
            "invariants": ["INV-SEC-005"],
        }
        t0 = time.perf_counter()
        prep_bwrap = bwrap_provider.prepare(wl_bwrap)
        t_prep = time.perf_counter()
        receipt_bwrap = bwrap_provider.execute(prep_bwrap, env_bwrap)
        t_exec = time.perf_counter()
        proof_bwrap = bwrap_provider.cleanup(prep_bwrap)
        t_clean = time.perf_counter()

        results["rootfs_bwrap"] = {
            "prepare_ms": round((t_prep - t0) * 1000.0, 3),
            "execute_ms": round((t_exec - t_prep) * 1000.0, 3),
            "cleanup_ms": round((t_clean - t_exec) * 1000.0, 3),
            "total_ms": round((t_clean - t0) * 1000.0, 3),
            "exit_code": receipt_bwrap.exit_code,
            "cleanup_clean": proof_bwrap.clean,
        }
    else:
        results["rootfs_bwrap"] = {"status": "SKIPPED_BINARY_NOT_FOUND"}

    # 3. OciContainerProvider (Bundle Preparation & Cleanup)
    oci_provider = OciContainerProvider()
    wl_oci = WorkloadSpec(
        workload_id="bench-oci-single",
        format="oci-bundle",
        entrypoint=["/bin/true"],
    )
    t0 = time.perf_counter()
    prep_oci = oci_provider.prepare(wl_oci)
    t_prep = time.perf_counter()
    proof_oci = oci_provider.cleanup(prep_oci)
    t_clean = time.perf_counter()

    results["oci_bundle"] = {
        "prepare_ms": round((t_prep - t0) * 1000.0, 3),
        "cleanup_ms": round((t_clean - t_prep) * 1000.0, 3),
        "total_ms": round((t_clean - t0) * 1000.0, 3),
        "cleanup_clean": proof_oci.clean,
    }

    return results


def benchmark_endurance_1000_cycles(total_cycles: int = 1000) -> Dict[str, Any]:
    """
    Execute 1,000 full execution lifecycles and verify strict zero-leak invariants.
    Alternates between NativeLinuxProvider and RootfsBwrapProvider when bwrap is available.
    """
    native_provider = NativeLinuxProvider()
    bwrap_provider = RootfsBwrapProvider()
    has_bwrap = bool(shutil.which("bwrap"))

    wl_native = WorkloadSpec(
        workload_id="bench-native-cycle",
        format="elf-binary",
        entrypoint=["/bin/true"],
    )
    wl_bwrap = WorkloadSpec(
        workload_id="bench-bwrap-cycle",
        format="rootfs-dir",
        entrypoint=["/bin/true"],
        rootfs_path="/",
    )

    env_native = {
        "envelope_id": "oce-bench-native-endurance",
        "intent": {"action": "system.probe"},
        "invariants": ["INV-SEC-001"],
    }
    env_bwrap = {
        "envelope_id": "oce-bench-bwrap-endurance",
        "intent": {"action": "system.probe"},
        "invariants": ["INV-SEC-005"],
    }

    # Baseline snapshot
    gc.collect()
    start_rss = get_current_rss_mb()
    start_fds = count_open_fds()
    start_mounts = count_active_mounts()
    start_temp_dirs = count_neuronix_temp_dirs()

    t_start = time.perf_counter()
    for i in range(total_cycles):
        if has_bwrap and (i % 2 == 1):
            prep = bwrap_provider.prepare(wl_bwrap)
            receipt = bwrap_provider.execute(prep, env_bwrap)
            proof = bwrap_provider.cleanup(prep)
        else:
            prep = native_provider.prepare(wl_native)
            receipt = native_provider.execute(prep, env_native)
            proof = native_provider.cleanup(prep)

        assert receipt.exit_code == 0, f"Lifecycle {i} failed with exit_code {receipt.exit_code}"
        assert proof.clean, f"Lifecycle {i} cleanup was not clean"

    t_end = time.perf_counter()
    duration_total_s = t_end - t_start

    # Post-execution snapshot
    gc.collect()
    end_rss = get_current_rss_mb()
    end_fds = count_open_fds()
    end_mounts = count_active_mounts()
    end_temp_dirs = count_neuronix_temp_dirs()

    fd_delta = end_fds - start_fds
    mount_delta = end_mounts - start_mounts
    temp_dir_delta = end_temp_dirs - start_temp_dirs
    rss_delta_mb = round(end_rss - start_rss, 2)

    # Verification assertions
    assert fd_delta == 0, f"FD leak detected: delta={fd_delta} (start={start_fds}, end={end_fds})"
    assert mount_delta == 0, f"Mount leak detected: delta={mount_delta} (start={start_mounts}, end={end_mounts})"
    assert temp_dir_delta == 0, f"Temp dir leak detected: delta={temp_dir_delta} (start={start_temp_dirs}, end={end_temp_dirs})"
    assert rss_delta_mb < 20.0, f"Memory leak detected: RSS growth={rss_delta_mb} MB exceeds 20.0 MB threshold"

    return {
        "total_cycles": total_cycles,
        "total_duration_s": round(duration_total_s, 2),
        "mean_cycle_latency_ms": round((duration_total_s / total_cycles) * 1000.0, 3),
        "resource_deltas": {
            "fd_start": start_fds,
            "fd_end": end_fds,
            "fd_delta": fd_delta,
            "mount_start": start_mounts,
            "mount_end": end_mounts,
            "mount_delta": mount_delta,
            "temp_dir_start": start_temp_dirs,
            "temp_dir_end": end_temp_dirs,
            "temp_dir_delta": temp_dir_delta,
            "rss_start_mb": round(start_rss, 2),
            "rss_end_mb": round(end_rss, 2),
            "rss_delta_mb": rss_delta_mb,
        },
        "invariants_passed": {
            "INV-RES-001_ZERO_FD_LEAK": (fd_delta == 0),
            "INV-RES-002_ZERO_MOUNT_LEAK": (mount_delta == 0),
            "INV-RES-003_ZERO_TEMP_DIR_LEAK": (temp_dir_delta == 0),
            "INV-RES-004_BOUNDED_RSS_GROWTH": (rss_delta_mb < 20.0),
        },
    }


def main() -> None:
    print("Executing UEF Resource Qualification & Endurance Benchmark...")

    baseline = benchmark_idle_core_baseline()
    lifecycle = benchmark_provider_lifecycles()
    endurance = benchmark_endurance_1000_cycles(1000)

    report = {
        "benchmark": "UEF Resource Qualification Profile",
        "timestamp_ns": time.time_ns(),
        "idle_core_baseline": baseline,
        "provider_lifecycles": lifecycle,
        "endurance_qualification": endurance,
    }

    print(json.dumps(report, indent=2))
    print("\nAll zero-leak resource invariants verified successfully!")


if __name__ == "__main__":
    main()
