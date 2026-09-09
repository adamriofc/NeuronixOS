# NEURONIX OS Runbook: Active Memory Pressure Shield & Hierarchical ZRAM

## 1. Subsystem Architecture

To prevent workstation freezes during intensive compilation, container builds, or local LLM inference, NEURONIX implements an intelligent four-tier hierarchical memory architecture:

1. **Tier 1: Dynamic In-Memory ZRAM Swap (`priority = 32767`):**
   Allocates an in-RAM compressed block device using the high-speed `zstd` algorithm, dynamically scaled to 100% of host physical RAM capacity. With `priority = 32767` (the maximum Linux kernel swapon priority), all memory paging requests are strictly routed to RAM-speed compressed memory first.
2. **Tier 2: In-Kernel Zswap Deactivation (`zswap.enabled = 0`):**
   Explicitly disables in-kernel zswap via boot parameters. When using ZRAM, active zswap causes double-compression (pages compressed by zswap before being compressed again by ZRAM), wasting CPU cycles and inflating page fault latency. Disabling zswap ensures single-pass, high-efficiency ZSTD compression.
3. **Tier 3: Zero-Wear Secondary Storage Swap & Hibernation Protection:**
   Secondary swap partitions (or swapfiles in the dedicated `@swap` subvolume with `nodatacow,noatime`) are assigned low priorities (e.g., -2). Physical storage remains at 0 bytes used during normal workloads, eliminating write-wear on SSDs (especially QLC/TLC media). Full hibernation capability (`resume=UUID=...`) remains intact because the kernel writes directly to physical storage during `systemctl hibernate`.
4. **Tier 4: Userspace OOM Guardian (`systemd-oomd` / `earlyoom`):**
   Continuously monitors Pressure Stall Information (PSI) at `/proc/pressure/memory`. If aggregate memory pressure stalls exceed safety thresholds, the daemon terminates rogue memory-leak processes before the kernel freezes.

## 2. Inspecting Memory & PSI Diagnostics

Inspect real-time memory metrics, swap allocation, zswap status, and PSI pressure:

```bash
# Human-readable diagnostic dashboard
neuronix shield

# Structured JSON telemetry for automated monitoring
neuronix shield --json
```

Check active ZRAM block device status directly:

```bash
zramctl
```

Inspect swap priority hierarchy and storage protection:

```bash
swapon --show
```

Verify in-kernel zswap deactivation:

```bash
cat /sys/module/zswap/parameters/enabled  # Outputs 'N'
```

Inspect OOM daemon status:

```bash
systemctl status systemd-oomd
```

## 3. Kernel Virtual Memory Tuning

NEURONIX configures optimized virtual memory parameters in `modules/services/memory-shield.nix`:
- `vm.swappiness = 180`: Proactively moves cold, idle anonymous memory pages into compressed ZRAM, preserving uncompressed physical RAM for active applications and file cache.
- `vm.page-cluster = 0`: Reads and writes single 4KB pages to ZRAM, eliminating multi-page readahead latency in RAM.
- `vm.vfs_cache_pressure = 50`: Retains directory and inode caches longer to maintain desktop responsiveness and reduce filesystem I/O stalls.
- `vm.watermark_scale_factor = 125`: Ensures early, gentle page reclamation without sudden I/O pauses.
- `vm.watermark_boost_factor = 0`: Eliminates kswapd thrashing loops under sudden burst allocations.
- `vm.max_map_count = 2147483642`: Sets virtual memory map areas to 2^31 - 6 (the standard ceiling used by Steam Proton, DXVK, and large-scale AI/LLM runtimes).
