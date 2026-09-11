"""
Empirical Latency and Overhead Benchmark for UEF and Coherence Engine.
Measures:
1. Dynamic Provider Resolver scoring time (microseconds).
2. Native host execution overhead.
3. Coherence Engine envelope evaluation time.
Outputs structured JSON report with deterministic percentiles.
"""

from __future__ import annotations

import json
import statistics
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.osl.coherence import CoherenceEngine
from neuronix_core.uef.models import OperationalContext, WorkloadSpec
from neuronix_core.uef.resolver import create_default_resolver


def benchmark_resolver(iterations: int = 1000) -> Dict[str, Any]:
    """Measure dynamic resolver resolution time across iterations."""
    resolver = create_default_resolver()
    workload = WorkloadSpec(
        workload_id="bench-wl",
        format="elf-binary",
        entrypoint=["/bin/echo"],
    )
    context = OperationalContext(requested_isolation_tier="TIER_0_HOST")

    latencies_us: List[float] = []
    for _ in range(iterations):
        t0 = time.perf_counter_ns()
        provider, score, _ = resolver.resolve(workload, context)
        t1 = time.perf_counter_ns()
        latencies_us.append((t1 - t0) / 1000.0)

    return {
        "iterations": iterations,
        "min_us": round(min(latencies_us), 2),
        "mean_us": round(statistics.mean(latencies_us), 2),
        "median_us": round(statistics.median(latencies_us), 2),
        "p99_us": round(statistics.quantiles(latencies_us, n=100)[98], 2),
        "max_us": round(max(latencies_us), 2),
    }


def benchmark_coherence(iterations: int = 1000) -> Dict[str, Any]:
    """Measure CoherenceEngine envelope evaluation time."""
    engine = CoherenceEngine()
    envelope = {
        "envelope_id": "oce-bench-01",
        "intent": {
            "action": "system.status",
            "category": "READ",
            "description": "Benchmark probe",
            "target_resource_uri": "neuronix://system/status",
        },
        "actor": {
            "principal_id": "bench-actor",
            "principal_type": "HUMAN_OPERATOR",
            "session_nonce": "nonce-bench",
        },
        "authority": {"tier": "FULL_OPERATOR"},
        "environment": {"target_substrate": "NIXOS_HOST", "isolation_tier": "TIER_0_HOST"},
        "preconditions": {"required_state_root": "0" * 64},
        "expected_effects": {"declared_diff": "", "destructive": False},
        "invariants": ["INV-SEC-001"],
        "evidence": {"input_digest": "0" * 64},
        "outcome": {"status": "PENDING_EVALUATION"},
    }

    latencies_us: List[float] = []
    for _ in range(iterations):
        t0 = time.perf_counter_ns()
        verdict = engine.evaluate_envelope(envelope, current_state_root="0" * 64)
        t1 = time.perf_counter_ns()
        latencies_us.append((t1 - t0) / 1000.0)

    return {
        "iterations": iterations,
        "min_us": round(min(latencies_us), 2),
        "mean_us": round(statistics.mean(latencies_us), 2),
        "median_us": round(statistics.median(latencies_us), 2),
        "p99_us": round(statistics.quantiles(latencies_us, n=100)[98], 2),
        "max_us": round(max(latencies_us), 2),
    }


def main() -> None:
    print("Executing UEF & Coherence Engine Micro-Benchmarks...")
    resolver_results = benchmark_resolver(1000)
    coherence_results = benchmark_coherence(1000)

    report = {
        "benchmark": "UEF & Coherence Engine Latency Profile",
        "timestamp_ns": time.time_ns(),
        "resolver_scoring_latencies": resolver_results,
        "coherence_evaluation_latencies": coherence_results,
    }

    print(json.dumps(report, indent=2))
    assert resolver_results["median_us"] < 500.0, "Resolver scoring must be sub-millisecond"
    assert coherence_results["median_us"] < 200.0, "Coherence evaluation must be sub-millisecond"
    print("\nBenchmark verification passed successfully!")


if __name__ == "__main__":
    main()
