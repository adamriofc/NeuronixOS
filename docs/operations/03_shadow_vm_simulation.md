# NEURONIX OS Runbook: Shadow Micro-VM Simulation

## 1. Safety Rationale

Modifying core operating system configurations carries risks of unbootable setups or missing critical services. The NEURONIX Shadow Micro-VM engine (`neuronix try`) spins up an ephemeral, in-memory QEMU sandbox backed by `/dev/shm` to evaluate configurations before committing them to the host.

## 2. Modes of Operation

The Shadow Micro-VM engine provides three execution modes:
- `--mode real`: Builds a real NixOS QEMU VM runner (`nixos-rebuild build-vm`) and boots it in RAM. Exits with code 2 if KVM or rebuild toolchains are unavailable.
- `--mode synthetic`: Uses an in-memory synthetic runner harness for CI and low-resource environments to validate lifecycle state transitions and telemetry markers.
- `--mode auto`: Attempts real derivation build first; falls back to synthetic mode if compilation is restricted.

## 3. Operational Invocations

### Automated Smoke Testing
Boot the candidate system, verify guest readiness gates, and terminate automatically:

```bash
neuronix try --smoke-test --headless
```

### Candidate File Testing with Atomic Promotion
Simulate a custom configuration file, verify health, and atomically promote to the host upon success:

```bash
neuronix try --smoke-test --promote --yes /etc/nixos/configuration.nix
```

## 4. Verification Gates and Telemetry Markers

During simulation, the runner verifies four mandatory guest readiness gates:
1. `kernel`: Linux kernel boot and initialization marker.
2. `systemd`: Basic system target reached (`basic.target`).
3. `ninep_mount`: Read-only host `/nix/store` 9P mount verification.
4. `guest_ready`: Presence of `/run/neuronix-guest-ready` milestone.

Telemetry results are written to `dist/shadow_vm_report.json`.
