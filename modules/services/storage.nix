{ pkgs, lib, ... }:

{
  # Btrfs filesystem maintenance and subvolume topology
  # Background balance service with filesystem detection to prevent unnecessary wear
  systemd.services.btrfs-balance = {
    description = "NEURONIX Btrfs Metadata Auto-Balance Service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "neuronix-btrfs-balance" ''
        # Verify root filesystem is Btrfs before executing maintenance
        if ${pkgs.util-linux}/bin/findmnt -n -o FSTYPE / 2>/dev/null | grep -q "btrfs"; then
          ${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=10 -musage=10 /
        fi
      '';
    };
  };

  systemd.timers.btrfs-balance = {
    description = "Monthly Btrfs Auto-Balance Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      Persistent = true;
    };
  };

  # Hypervisor-Aware Storage Maintenance: Scheduled fstrim
  services.fstrim = {
    enable = lib.mkDefault true;
    interval = "daily";
  };

  # Autonomous Storage Diet: Scheduled Garbage Collection & Store Deduplication
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    options = lib.mkDefault "--delete-older-than 14d";
  };

  nix.optimise = {
    automatic = lib.mkDefault true;
    dates = [ "weekly" ];
  };

  # Dynamic Storage Guard (Prevents out-of-disk conditions during compilation/evaluation)
  nix.settings = {
    min-free = lib.mkDefault 1073741824; # 1 GiB Emergency trigger
    max-free = lib.mkDefault 3221225472; # 3 GiB Target headroom
  };

  # Systemd Journal Log Retention Ceiling & Autonomous Vacuuming
  # Enforces systemd log file ceiling to protect root storage (/var/log/journal)
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    SystemMaxFileSize=50M
    MaxRetentionSec=1month
    RuntimeMaxUse=100M
  '';

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
