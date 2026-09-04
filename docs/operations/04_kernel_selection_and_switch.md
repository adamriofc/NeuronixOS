# NEURONIX OS Runbook: Kernel Selection and Switching

## 1. Supported Kernel Flavors

NEURONIX OS provides five curated upstream Linux kernel flavors:
- `zen` (Default): Tuned for desktop gaming, audio interactivity, and responsive workstation multitasking (Zen kernel patchset).
- `default`: Canonical upstream LTS kernel curated by Nixpkgs.
- `lts`: Pinned long-term maintenance kernel for mission-critical stability.
- `latest`: Bleeding-edge upstream stable kernel with latest hardware drivers.
- `hardened`: Enhanced security kernel with lockdown and exploit mitigations.

## 2. Querying Kernel Status

Inspect currently running and configured kernel profiles:

```bash
neuronix kernel status
```

List all available flavors and specifications:

```bash
neuronix kernel list
```

## 3. Staged Kernel Switching Workflow

To switch the system kernel flavor safely without interrupting current workloads:

1. Select the target flavor:
   ```bash
   neuronix kernel set latest
   ```
2. Build and stage the new kernel generation for the subsequent boot:
   ```bash
   neuronix upgrade --staged
   ```
3. Reboot to activate the new kernel:
   ```bash
   systemctl reboot
   ```
4. If a regression occurs, boot into the previous kernel via systemd-boot or execute `neuronix undo`.
