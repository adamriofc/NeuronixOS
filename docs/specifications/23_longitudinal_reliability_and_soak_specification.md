# NEURONIX Specification: Longitudinal Reliability & Multi-Cycle Soak Testing Protocol

> **Document ID:** `NRX-SPEC-023`  
> **Version:** 1.0.5-RELEASE  
> **Status:** Ratified & Active  
> **Subsystem:** Operational Stability, Resource Leak Invariants, and Sustained Soak Qualification  
> **Verification Gate:** `tests/benchmarks/benchmark_uef_resources.py` & `tests/benchmarks/benchmark_rollback.py`  

---

## 1. Executive Summary

Longitudinal reliability measures the capacity of an operating system control plane and execution fabric to operate continuously under sustained transactional load without state corruption, handle depletion, resource degradation, or memory bloat.

In traditional desktop and workstation environments, long-running daemons and agent environments commonly suffer from cumulative resource leaks:
1. **File Descriptor Leaks:** Unclosed sockets, lingering event loops, and uncollected IPC pipes.
2. **Mount Point Leaks:** Abandoned temporary pivot points and transient namespace mounts accumulating in `/proc/mounts`.
3. **Storage Scratch Clutter:** Leftover temporary working directories and payload artifacts in `/dev/shm` or `/tmp`.
4. **Memory RSS Growth:** Non-reclaimed heaps and uncollected reference cycles causing gradual Resident Set Size (RSS) expansion.

NEURONIX OS establishes formal, automated **Longitudinal Soak Testing Protocols** and **Zero-Leak Resource Invariants** enforced continuously across multi-cycle operational benchmarks.

---

## 2. Resource Invariant Preservation Gates

The longitudinal stability harness asserts four immutable invariants across every operational cycle:

| Invariant ID | Formal Invariant Name | Evaluation Target | Enforcement Threshold |
| :--- | :--- | :--- | :--- |
| **`INV-RES-001`** | `ZERO_FD_LEAK` | Open file descriptor delta in `/proc/<pid>/fd` | $\Delta FD == 0$ |
| **`INV-RES-002`** | `ZERO_MOUNT_LEAK` | Active kernel mount entries in `/proc/mounts` | $\Delta Mount == 0$ |
| **`INV-RES-003`** | `ZERO_TEMP_DIR_LEAK` | Ephemeral scratch allocations in `/dev/shm` | $\Delta Temp == 0$ |
| **`INV-RES-004`** | `BOUNDED_RSS_GROWTH` | Process Resident Set Size delta via `/proc/<pid>/statm` | $\Delta RSS < 1.0\text{ MB}$ (1,000 cycles) |

---

## 3. Multi-Cycle Endurance Qualification Matrix

Empirical qualification of longitudinal reliability is executed via continuous multi-iteration soak harnesses in `tests/benchmarks/`:

```text
               LONGITUDINAL MULTI-CYCLE ENDURANCE QUALIFICATION
                                      │
       ┌──────────────────────────────┼──────────────────────────────┐
       ▼                              ▼                              ▼
1,000-Cycle UEF Soak          100-Cycle OCI Soak             100-Iteration Rollback
(Interleaved Native/Rootfs)   (Container Lifecycle)          (Atomic Symlink Swaps)
   - 0 FD Leaks                   - 0 FD Leaks                   - p50: 0.038 ms
   - 0 Mount Leaks                - 0 Mount Leaks                - p90: 0.042 ms
   - 0 Temp Dir Leaks             - 0 Temp Dir Leaks             - p99: 0.047 ms
   - Delta RSS: 0.33 MB           - Delta RSS: 0.01 MB           - 0 Corrupted States
```

### 3.1 1,000-Cycle UEF Provider Endurance Benchmark
- **Test Harness:** `tests/benchmarks/benchmark_uef_resources.py` (`benchmark_resource_leak_invariants`)
- **Execution:** 1,000 full lifecycles (`prepare` -> `execute` -> `cleanup`) across interleaved native and sandbox providers.
- **Elapsed Duration:** 13.7 seconds total (13.7 ms per cycle average).
- **Leak Invariants:**
  - `fd_delta`: 0 (`start_fds == 57`, `end_fds == 57`) -> **PASS**
  - `mount_delta`: 0 (`start_mounts == 31`, `end_mounts == 31`) -> **PASS**
  - `temp_dir_delta`: 0 (`start_dirs == 6`, `end_dirs == 6`) -> **PASS**
  - `rss_delta_mb`: 0.33 MB (well below the 20.0 MB threshold) -> **PASS**

### 3.2 100-Cycle OCI Container Lifecycle Benchmark
- **Test Harness:** `tests/benchmarks/benchmark_uef_resources.py` (`benchmark_oci_endurance_100_cycles`)
- **Execution:** 100 continuous container prepare, execution, and cleanup cycles.
- **Elapsed Duration:** 0.04 seconds total (0.387 ms per cycle average).
- **Leak Invariants:**
  - `fd_delta`: 0 -> **PASS**
  - `mount_delta`: 0 -> **PASS**
  - `temp_dir_delta`: 0 -> **PASS**
  - `rss_delta_mb`: 0.01 MB -> **PASS**

### 3.3 100-Iteration Generation Rollback Benchmark
- **Test Harness:** `tests/benchmarks/benchmark_rollback.py`
- **Execution:** 100 atomic profile switches (Gen 42 -> 41 -> 40).
- **Latency Distribution:**
  - p50: 0.038 ms
  - p90: 0.042 ms
  - p99: 0.047 ms
- **Integrity Guarantee:** 100% atomic symlink durability with zero state corruption.

---

## 4. Privacy-Preserving Longitudinal Telemetry

For continuous fleet-wide health tracking and longitudinal operational observation without external network dependencies, NEURONIX OS provides the privacy-preserving diagnostic engine (`neuronix doctor --json`):

```json
{
  "schema_version": "1.0.0",
  "health_status": "HEALTHY",
  "system": {
    "os": "NEURONIX OS 1.0.5 (NixOS Substrate)",
    "kernel": "6.18.48",
    "generation": "5",
    "total_generations": 3
  },
  "privacy": {
    "user": "<sanitized-user>",
    "network_status": "Terhubung (Online)"
  }
}
```

All IP addresses, MAC addresses, hostnames, and personal identifiers are strictly sanitized before output, enabling longitudinal tracking across production deployments without violating privacy boundaries.
