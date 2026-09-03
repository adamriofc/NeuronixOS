{ lib, ... }:

{
  # Active Memory Pressure Shield (ZRAM ZSTD + systemd-oomd)
  # Menggandakan kapasitas RAM efektif, mengeliminasi swap thrashing, freeze, dan random hard-reboot.

  # 1. ZRAM Swap Terkompresi ZSTD di Memori RAM
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100; # Menggunakan hingga 100% RAM sebagai swap pool terkompresi (~2x-3x rasio)
    priority = 100;
  };

  # 2. Daemon Pemantau Tekanan Memori systemd-oomd berbasis PSI (Pressure Stall Information)
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
    extraConfig = {
      DefaultMemoryPressureDurationSec = "10s";
    };
  };

  # Kernel Virtual Memory tuning for modern ZRAM
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;          # Proaktif mengompresi memori pasif ke ZRAM
    "vm.watermark_boost_factor" = 0; # Mencegah lonjakan kswapd agresif
    "vm.watermark_scale_factor" = 125;
    "vm.page-cluster" = 0;           # Bacaan halaman 4KB instan di ZRAM
    "vm.vfs_cache_pressure" = 50;    # Mempertahankan dentry cache agar UI desktop tetap mulus
  };
}
