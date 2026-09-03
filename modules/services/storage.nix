{ pkgs, lib, ... }:

{
  # Btrfs filesystem maintenance and subvolume topology
  # Periodic background balance service to prevent metadata chunk fragmentation
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

  # Native ntfs3 + exFAT drivers and removable media automounting
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
