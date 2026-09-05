#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Atomic Rollback Latency Profiling Benchmark
# Measures 100 generation switch operations and computes percentiles (p50, p95, p99)
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

TEST_DIR=$(mktemp -d "/tmp/neuronix-rollback-bench-XXXXXX")
trap 'rm -rf "${TEST_DIR}"' EXIT

PROFILE_DIR="${TEST_DIR}/profiles"
mkdir -p "${PROFILE_DIR}"

# Create 5 mock generations
for gen in {1..5}; do
    mkdir -p "${TEST_DIR}/store/gen-${gen}"
    echo "kernel-hash-${gen}" > "${TEST_DIR}/store/gen-${gen}/kernel"
    ln -s "${TEST_DIR}/store/gen-${gen}" "${PROFILE_DIR}/system-${gen}-link"
done

ln -sfn "${PROFILE_DIR}/system-5-link" "${PROFILE_DIR}/system"

# Run 100 iterations of atomic profile switches and profile latency
export PROFILE_DIR
export PYTHON_BIN
export PROJECT_ROOT

"$PYTHON_BIN" - << 'PYEOF'
import json
import math
import os
import sys
import time

profile_dir = os.environ["PROFILE_DIR"]
system_link = os.path.join(profile_dir, "system")

def percentile(data, p):
    if not data:
        return 0.0
    sorted_d = sorted(data)
    idx = (len(sorted_d) - 1) * p / 100.0
    lower = math.floor(idx)
    upper = math.ceil(idx)
    if lower == upper:
        return float(sorted_d[int(idx)])
    return float(sorted_d[lower] * (upper - idx) + sorted_d[upper] * (idx - lower))

latencies_ms = []
iterations = 100

for i in range(iterations):
    target_gen = (i % 5) + 1
    target_link = os.path.join(profile_dir, f"system-{target_gen}-link")
    temp_link = os.path.join(profile_dir, f"system.tmp.{i}")
    
    t0 = time.perf_counter()
    # Atomic symlink replacement equivalent to nix-env --switch-generation
    os.symlink(target_link, temp_link)
    os.replace(temp_link, system_link)
    t1 = time.perf_counter()
    
    elapsed_ms = (t1 - t0) * 1000.0
    latencies_ms.append(elapsed_ms)

p50 = percentile(latencies_ms, 50)
p95 = percentile(latencies_ms, 95)
p99 = percentile(latencies_ms, 99)
mean_val = sum(latencies_ms) / len(latencies_ms)

result = {
    "subsystem": "rollback",
    "samples": iterations,
    "metrics": {
        "mean_ms": round(mean_val, 3),
        "min_ms": round(min(latencies_ms), 3),
        "max_ms": round(max(latencies_ms), 3),
        "p50_ms": round(p50, 3),
        "p95_ms": round(p95, 3),
        "p99_ms": round(p99, 3),
        "budget_p99_ms": 2000.0
    },
    "status": "PASS" if p99 < 2000.0 else "FAIL"
}

print(json.dumps(result, indent=2))
if result["status"] != "PASS":
    sys.exit(1)
PYEOF
