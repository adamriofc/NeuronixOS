# NEURONIX OS Runbook: Boot Recovery and Atomic Rollback

## 1. Architectural Overview

NEURONIX OS decouples operating system state transitions from live filesystem modification by building complete system closures in `/nix/store` and updating atomic generation pointers in `/nix/var/nix/profiles/system`. 

When an upgrade introduces kernel incompatibilities, misconfigured systemd units, or display manager regressions, the system can revert to any prior operational generation instantly without data loss.

## 2. Bootloader Level Recovery (Cold Recovery)

If the active system generation fails to reach user space or panics during kernel initialization:

1. Reboot the workstation and access the systemd-boot menu (press `Space` or `Esc` during UEFI initialization).
2. Use the arrow keys to navigate the generation timeline. Each entry displays generation number, kernel version, and build timestamp:
   ```text
   NEURONIX OS - Generation 42 (2026-09-04 18:22)
   NEURONIX OS - Generation 41 (2026-09-01 10:14) [Select for Rollback]
   NEURONIX OS - Generation 40 (2026-08-25 09:30)
   ```
3. Select the immediate predecessor generation and press `Enter`.
4. The system boots into the selected immutable closure with write access to user subvolumes (`/home`) preserved.

## 3. Active Shell Rollback (Warm Recovery)

When logged into a running shell, users can revert generations using either the NEURONIX CLI or upstream tooling:

```bash
# Automated predecessor rollback via NEURONIX CLI
neuronix undo

# Equivalent upstream declarative invocation
sudo nixos-rebuild switch --rollback
```

To roll back to an explicit historical generation number (for instance, Generation 40):

```bash
# List historical generations
neuronix generations

# Activate specific generation link
sudo /nix/var/nix/profiles/system-40-link/bin/switch-to-configuration switch
```

## 4. Verification and Invariant Confirmation

Verify the active profile pointer after rollback:

```bash
readlink -f /nix/var/nix/profiles/system
neuronix doctor --json | jq .system.generation
```
