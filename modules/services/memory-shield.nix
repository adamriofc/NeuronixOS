{ lib, ... }:

{
  # Active Memory Pressure Shield (ZRAM ZSTD + systemd-oomd)
  # Doubles effective RAM capacity, eliminating swap thrashing, system freezes, and random kernel panics.

  # 1. ZSTD Compressed In-Memory ZRAM Swap Pool
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100; # Dynamically allocates up to 100% of host RAM as compressed swap pool (~2x-3x ratio)
    priority = 32767;   # Linux maximum swapon priority (0x7fff) ensuring ZRAM is strictly saturated first
  };

  # 2. Kernel Parameters: Disable in-kernel zswap to eliminate double-compression CPU overhead
  boot.kernelParams = [
    "zswap.enabled=0"
  ];

  # 3. Pressure Stall Information (PSI) based systemd-oomd memory pressure daemon
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
