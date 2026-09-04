# NEURONIX OS Runbook: Storage Diet and TRIM Optimization

## 1. Subsystem Architecture

The NEURONIX storage architecture manages disk consumption through five synchronized reclamation phases:
1. **Cryptographic Garbage Collection (`nix-collect-garbage -d`):** Purges unreferenced package derivations and orphaned build closures.
2. **Hardlink Inode Deduplication (`nix-store --optimise`):** Merges identical binary files and libraries across distinct packages into single inode references.
3. **Flatpak Runtime Pruning (`flatpak uninstall --unused`):** Removes orphaned runtime runtimes and SDK dependencies.
4. **Journal Ceiling Enforcement (`journalctl --vacuum-size=500M`):** Restricts archived systemd system journals to a 500 MiB boundary.
5. **Storage Controller TRIM Passthrough (`fstrim -av`):** Emits SCSI and NVMe deallocate directives to underlying physical SSD blocks or host VM disks.

## 2. Interactive Storage Diet Execution

To execute an on-demand full storage reclamation cycle:

```bash
# Execute 5-phase diet pipeline
neuronix diet
```

## 3. Autonomous Scheduled Maintenance

NEURONIX configures autonomous maintenance via systemd timers:
- `nix-gc.timer`: Evaluates generation retention policies weekly (`--delete-older-than 14d`).
- `fstrim.timer`: Issues storage TRIM requests weekly across all mounted Btrfs and EXT4 partitions.

Inspect maintenance timer health:

```bash
systemctl list-timers | grep -E 'nix-gc|fstrim'
```

## 4. Troubleshooting Disk Pressure Emergencies

When `/nix/store` approaches 100% capacity and prevents builds:

```bash
# Force aggressive collection of all non-active closures
sudo nix-collect-garbage -d

# Optimize store hardlinks immediately
sudo nix-store --optimise

# Issue physical block discard
sudo fstrim -av
```
