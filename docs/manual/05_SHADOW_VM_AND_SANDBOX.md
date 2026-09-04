# Chapter 5: In-Memory Shadow Micro-VM Simulation

## 1. Zero Blast Radius Principle

Before applying changes to a production workstation, administrators and AI agents need an environment to test new configurations without mutating host disks. 

The NEURONIX **Shadow Micro-VM** (`neuronix try`) creates an ephemeral virtual machine residing entirely in the Linux RAM disk (`/dev/shm`):

* **Host Isolation:** The guest operates inside a hardware-virtualized QEMU sandbox.
* **Store Sharing via 9P:** The host immutable `/nix/store` is passed to the guest read-only using the 9P virtio filesystem, achieving sub-second boot times without cloning gigabytes of data.
* **Transient Discard:** Upon VM termination, all memory allocated in `/dev/shm` is instantly wiped. The host workstation remains completely untouched.

---

## 2. Modes of Operation

The Shadow VM runner (`src/shadow_vm.sh`) provides three execution modes:

```bash
# Auto Mode (Default): Uses real KVM if available, falls back to synthetic smoke test
neuronix try --mode auto

# Real Mode: Strictly enforces hardware virtualization via /dev/kvm
# Returns exit code 2 if KVM is unavailable
neuronix try --mode real

# Synthetic Mode: Fast deterministic simulation for CI and headless environments
neuronix try --mode synthetic
```

---

## 3. Four-Stage Guest Verification Oracle

The Shadow VM oracle validates four mandatory boot milestones before declaring success:

1. `kernel_seen`: Linux kernel decompression and console output initialization.
2. `systemd_seen`: systemd PID 1 target orchestration.
3. `ninep_seen`: Successful 9P virtio mount of `/nix/store`.
4. `guest_ready_seen`: Complete readiness signal emitted by guest target units.

---

## 4. Testing & Safe Configuration Promotion

Test a candidate Nix flake before promoting it to the live host:

```bash
# Test configuration in memory
neuronix try /path/to/experimental/flake.nix

# Test and promote automatically if all verification gates pass
neuronix try /path/to/experimental/flake.nix --promote -y
```
