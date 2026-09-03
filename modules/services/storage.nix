{ pkgs, lib, ... }:

{
  # Pilar 3 & 25: Pemeliharaan Filesystem Btrfs & Subvolume Management
  # Layanan balance latar belakang berkala untuk mencegah fragmentasi metadata chunk kosong
  systemd.services.btrfs-balance = {
    description = "NEURONIX Btrfs Metadata Auto-Balance Service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=10 -musage=10 /";
    };
  };

  systemd.timers.btrfs-balance = {
    description = "Timer Bulanan Btrfs Auto-Balance";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      Persistent = true;
    };
  };

  # Pemeliharaan Storage Sadar Hypervisor: fstrim terjadwal
  services.fstrim = {
    enable = lib.mkDefault true;
    interval = "daily";
  };

  # Pilar 23: Driver Native ntfs3 + exFAT + Auto-mount USB Eksternal Windows
  boot.supportedFilesystems = [ "btrfs" "ntfs" "exfat" "ext4" "vfat" ];

  services.udisks2.enable = true;
  services.gvfs.enable = true;

  environment.systemPackages = with pkgs; [
    btrfs-progs
    exfatprogs
    ntfs3g
    dosfstools
  ];
}
