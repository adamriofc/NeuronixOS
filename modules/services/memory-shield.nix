{ lib, ... }:

{
  # Active Memory Pressure Shield (ZRAM ZSTD + systemd-oomd)
  # Doubles effective RAM capacity, eliminating swap thrashing, system freezes, and random kernel panics.

  # 1. ZSTD Compressed In-Memory ZRAM Swap Pool
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100; # Allocate up to 100% RAM as compressed swap pool (~2x-3x ratio)
    priority = 100;
  };

  # 2. Pressure Stall Information (PSI) based systemd-oomd memory pressure daemon
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    settings.OOM = {
      DefaultMemoryPressureDurationSec = "10s";
    };
  };

  # Kernel Virtual Memory tuning for modern ZRAM
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;          # Proactively compress cold memory pages into ZRAM
    "vm.watermark_boost_factor" = 0; # Prevent aggressive kswapd thrashing
    "vm.watermark_scale_factor" = 125;
    "vm.page-cluster" = 0;           # Single 4KB page read/write for ZRAM latency optimization
    "vm.vfs_cache_pressure" = 50;    # Retain directory and inode cache for smooth UI responsiveness
  };
}
