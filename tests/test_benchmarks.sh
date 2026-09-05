#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Performance Benchmark & Latency Profiling Harness
# Executes modular industrial performance benchmarks:
#   1. Boot Stage Latency (Firmware, Kernel, Systemd, Desktop p50/p95/p99)
#   2. Memory Footprint, ZRAM & PSI Pressure Budget
#   3. Storage Subsystem & Btrfs ZSTD:3 Compression Efficiency
#   4. Multi-Hop Atomic Rollback Latency (100 Iterations p50/p95/p99)
# Produces machine-readable evidence: dist/benchmark_results.json
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
BENCH_JSON="${DIST_DIR}/benchmark_results.json"
BENCHMARKS_DIR="${PROJECT_ROOT}/tests/benchmarks"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

mkdir -p "${DIST_DIR}"

PASSED=0
FAILED=0

# Colors
if [[ -t 1 ]]; then
    GREEN="\033[32m"
    RED="\033[31m"
    CYAN="\033[36m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    GREEN=""
    RED=""
    CYAN=""
    BOLD=""
    RESET=""
fi

echo -e "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║         NEURONIX OS INDUSTRIAL PERFORMANCE BENCHMARK GATE         ║${RESET}"
echo -e "${BOLD}${CYAN}║    Boot, Memory/PSI, Btrfs ZSTD:3 & 100-Iteration Rollback        ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

# 1. Boot Stage Latency Benchmark
BOOT_OUT=$(bash "${BENCHMARKS_DIR}/boot_benchmark.sh" 2>/dev/null || echo '{"status":"FAIL"}')
BOOT_STATUS=$("$PYTHON_BIN" -c "import json; print(json.loads('''$BOOT_OUT''').get('status', 'FAIL'))" 2>/dev/null || echo "FAIL")
BOOT_P99=$("$PYTHON_BIN" -c "import json; print(json.loads('''$BOOT_OUT''').get('metrics', {}).get('p99_ms', 0))" 2>/dev/null || echo "0")
echo -ne "  [BENCHMARK] Boot stage latency budget (p99: ${BOOT_P99}ms < 10000ms) ... "
if [[ "$BOOT_STATUS" == "PASS" ]]; then
    echo -e "${GREEN}PASS${RESET}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${RESET}"
    ((FAILED++))
fi

# 2. Memory Footprint & ZRAM/PSI Benchmark
MEM_OUT=$(bash "${BENCHMARKS_DIR}/memory_benchmark.sh" 2>/dev/null || echo '{"status":"FAIL"}')
MEM_STATUS=$("$PYTHON_BIN" -c "import json; print(json.loads('''$MEM_OUT''').get('status', 'FAIL'))" 2>/dev/null || echo "FAIL")
MEM_USED=$("$PYTHON_BIN" -c "import json; print(json.loads('''$MEM_OUT''').get('metrics', {}).get('mem_used_mb', 0))" 2>/dev/null || echo "0")
echo -ne "  [BENCHMARK] Runtime memory & PSI pressure budget (${MEM_USED} MB used) ... "
if [[ "$MEM_STATUS" == "PASS" ]]; then
    echo -e "${GREEN}PASS${RESET}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${RESET}"
    ((FAILED++))
fi

# 3. Storage Subsystem & Btrfs ZSTD:3 Benchmark
STORAGE_OUT=$(bash "${BENCHMARKS_DIR}/storage_benchmark.sh" 2>/dev/null || echo '{"status":"FAIL"}')
STORAGE_STATUS=$("$PYTHON_BIN" -c "import json; print(json.loads('''$STORAGE_OUT''').get('status', 'FAIL'))" 2>/dev/null || echo "FAIL")
SAVINGS_PCT=$("$PYTHON_BIN" -c "import json; print(json.loads('''$STORAGE_OUT''').get('savings_percentage', 0))" 2>/dev/null || echo "0")
echo -ne "  [BENCHMARK] Btrfs ZSTD:3 store compression budget (${SAVINGS_PCT}% savings) ... "
if [[ "$STORAGE_STATUS" == "PASS" ]]; then
    echo -e "${GREEN}PASS${RESET}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${RESET}"
    ((FAILED++))
fi

# 4. Multi-Hop Atomic Rollback Benchmark (100 Iterations)
ROLLBACK_OUT=$(bash "${BENCHMARKS_DIR}/rollback_benchmark.sh" 2>/dev/null || echo '{"status":"FAIL"}')
ROLLBACK_STATUS=$("$PYTHON_BIN" -c "import json; print(json.loads('''$ROLLBACK_OUT''').get('status', 'FAIL'))" 2>/dev/null || echo "FAIL")
ROLLBACK_P99=$("$PYTHON_BIN" -c "import json; print(json.loads('''$ROLLBACK_OUT''').get('metrics', {}).get('p99_ms', 0))" 2>/dev/null || echo "0")
echo -ne "  [BENCHMARK] Atomic generation rollback budget (100 runs, p99: ${ROLLBACK_P99}ms < 2000ms) ... "
if [[ "$ROLLBACK_STATUS" == "PASS" ]]; then
    echo -e "${GREEN}PASS${RESET}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${RESET}"
    ((FAILED++))
fi

# Emit aggregated benchmark results JSON
"$PYTHON_BIN" - << PYEOF
import json
from datetime import datetime, timezone

boot_data = json.loads('''$BOOT_OUT''')
mem_data = json.loads('''$MEM_OUT''')
storage_data = json.loads('''$STORAGE_OUT''')
rollback_data = json.loads('''$ROLLBACK_OUT''')

report = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": "PASSED" if $FAILED == 0 else "FAILED",
    "summary": {
        "total_benchmarks": 4,
        "passed": $PASSED,
        "failed": $FAILED
    },
    "subsystems": {
        "boot": boot_data,
        "memory": mem_data,
        "storage": storage_data,
        "rollback": rollback_data
    }
}

with open("${BENCH_JSON}", "w") as f:
    json.dump(report, f, indent=2)
PYEOF

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Benchmark Metrics   : $((PASSED + FAILED))"
echo -e "  Passed Latency Checks     : ${PASSED}"
echo -e "  Failed Latency Checks     : ${FAILED}"
echo -e "  Benchmark Artifact File   : ${BENCH_JSON}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ ALL INDUSTRIAL PERFORMANCE BUDGETS SATISFIED 100%${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ BENCHMARK PERFORMANCE BUDGET REGRESSION DETECTED${RESET}\n"
    exit 1
fi
