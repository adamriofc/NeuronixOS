# NEURONIX OS Runbook: Active Memory Pressure Shield & ZRAM

## 1. Subsystem Architecture

To prevent complete workstation freezes during intensive compilation or large language model inference, NEURONIX implements a dual-layer memory shield:
1. **Dynamic Compressed RAM (`zram-generator`):** Creates an in-memory swap device utilizing the high-speed `zstd` compression algorithm. ZRAM expands effective available memory capacity by approximately 1.5x to 2.0x.
2. **Userspace OOM Daemon (`systemd-oomd`):** Continuously monitors kernel Pressure Stall Information (PSI). When memory pressure exceeds defined latency thresholds, it selectively terminates misbehaving runaway processes before kernel freeze occurs.

## 2. Inspecting Memory and PSI Diagnostics

Inspect real-time memory metrics, swap allocation, and PSI pressure:

```bash
neuronix shield
```

Check active ZRAM block device status:

```bash
zramctl
```

Inspect systemd-oomd status:

```bash
systemctl status systemd-oomd
```

## 3. Kernel Virtual Memory Tuning

NEURONIX configures optimized virtual memory parameters:
- `vm.max_map_count = 2147483642`: Required for heavy memory mapping (Steam Proton, LLM memory allocators).
- `vm.swappiness = 180`: Actively prioritizes moving idle anonymous pages into compressed ZRAM.
