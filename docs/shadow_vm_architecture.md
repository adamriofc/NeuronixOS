# NEURONIX Shadow Micro-VM Architecture Specification

**Component ID:** `NRX-SPEC-003`  
**Subsystem:** Transient In-Memory QEMU Micro-Hypervisor Harness  
**Substrate Version:** 1.0.4  

---

## 1. Abstract

Mutating configuration files on bare-metal systems creates unquantified availability risks. While NixOS provides generation-based rollback, a faulty kernel driver, display server regression, or broken systemd service can render the machine unbootable, forcing manual GRUB recovery.

The **NEURONIX In-Memory OS Sandbox (`neuronix sandbox`, alias `neuronix try`)** isolates evaluation by constructing a transient clone of the proposed system state entirely inside volatile memory (`/dev/shm`). The host store (`/nix/store`) is mapped into the virtual guest via a 9P transport mount, achieving instantaneous boot latency (under 3 seconds) with zero duplicate disk allocation.

---

## 2. Memory Topology & Ephemeral Scratch Space

Traditional `nixos-rebuild build-vm` invocations write a persistent `.qcow2` overlay file directly to the invoking working directory. On developer workstations, this introduces filesystem clutter, disk I/O bottlenecks, and host storage inflation.

`neuronix sandbox` enforces an in-memory disk topology:

Scratch Path: `/dev/shm/neuronix_shadow_<pid>`

```text
Host Memory (RAM)
┌──────────────────────────────────────────────────────────────┐
│ /dev/shm (tmpfs)                                             │
│  └─ neuronix_shadow_XXXXXX/                                  │
│      ├─ nixos.qcow2        <-- Ephemeral copy-on-write delta │
│      └─ qemu.pid           <-- Tracked process supervisor    │
└──────────────────────────────┬───────────────────────────────┘
                               │ 9P File System (Read-Only)
┌──────────────────────────────▼───────────────────────────────┐
│ Host Physical Storage                                        │
│  └─ /nix/store/ (Immutable Closure Store)                    │
└──────────────────────────────────────────────────────────────┘
```

Upon VM termination, a POSIX exit trap (`EXIT INT TERM HUP`) unconditionally issues `rm -rf` on the scratch path, guaranteeing **zero disk leakage**.

---

## 3. Execution Lifecycle & State Machine

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> ParseArguments: neuronix sandbox [flags]
    ParseArguments --> VerifyKVM: Probe /dev/kvm
    VerifyKVM --> AllocateRAM: Mount scratch in /dev/shm
    AllocateRAM --> BuildRunner: Evaluate derivation (9P closure)
    BuildRunner --> RunSimulation: Boot transient QEMU instance
    
    state RunSimulation {
        [*] --> HeadlessMode
        [*] --> GUIMode
        HeadlessMode --> AutomatedSmokeTest: --smoke-test
        GUIMode --> InteractiveSession
    }
    
    AutomatedSmokeTest --> VerifySystemd: Check is-system-running
    VerifySystemd --> SimulationSuccess: Clean (code 0)
    VerifySystemd --> SimulationFailed: Degraded / Error
    
    SimulationSuccess --> HostPromotion: --promote enabled
    HostPromotion --> AtomicSwitch: nixos-rebuild switch
    AtomicSwitch --> Cleanup
    
    SimulationFailed --> Rejection: Abort host modification
    Rejection --> Cleanup
    
    InteractiveSession --> Cleanup: User exits VM
    Cleanup --> [*]: Wipe /dev/shm scratch
```

---

## 4. Execution Modes & CLI Reference

### 4.1 Automated Smoke Test (`--smoke-test`)
Boots the Micro-VM non-interactively in headless mode, verifies that the systemd target reaches operational equilibrium, and halts the guest:

```bash
neuronix sandbox --smoke-test
```

### 4.2 One-Click Host Promotion (`--promote`)
Guarantees that a configuration is applied to the host operating system only after passing verification inside the Shadow Micro-VM:

```bash
neuronix sandbox --smoke-test --promote /etc/nixos/configuration.nix
```

If the smoke test encounters a kernel panic, failing unit, or dependency cycle, promotion is blocked immediately.

### 4.3 Interactive GUI Session (`--gui`)
Spawns the Micro-VM with a virtual Spice/GTK display for interactive testing of desktop environments (Wayland/Hyprland/GNOME):

```bash
neuronix sandbox --gui
```

### 4.4 Autonomous OS Fabric (`get`)
Provides automated catalog retrieval, SHA-256 validation, and bootstrapping for external Linux distributions and Windows:

```bash
neuronix sandbox get alpine
neuronix sandbox get ubuntu-24.04
neuronix sandbox get arch
neuronix sandbox get debian-12
neuronix sandbox get windows-11
```

### 4.5 Windows 11 Autopilot Fabric
Automates zero-touch Windows 11 deployment with full hardware virtualization:
- **In-Memory TPM 2.0:** Emulates a dedicated TPM 2.0 chip via `swtpm socket` in volatile memory (`/dev/shm`).
- **Zero-Touch Answer File:** Generates `autounattend.xml` configuring language, default admin credentials, bypassing network checks (`OOBE\BYPASSNRO`), and applying registry bypasses (`BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck`, `BypassCPUCheck`).
- **VirtIO-Win Acceleration:** Mounts VirtIO paravirtualized storage drivers automatically.

### 4.6 Sub-Millisecond Btrfs CoW Snapshots & Branching
Enables instant, 0-byte initial overhead snapshotting and multi-branch VM experimentation:

```bash
# Instant snapshot creation and restore
neuronix sandbox snapshot create test-box checkpoint-1
neuronix sandbox snapshot restore test-box checkpoint-1
neuronix sandbox snapshot list test-box

# Instant zero-byte CoW VM branching
neuronix sandbox branch base-vm feature-experiment
```

### 4.7 SPICE Dynamic Viewport & Seamless Clipboard Bus
Integrates the QEMU SPICE `vdagent` protocol channel (`-chardev qemu-vdagent,id=ch1,clipboard=on,mouse=on`), allowing the guest display to dynamically adapt to host window resizing without distortion, along with bidirectional host-to-guest copy-paste.

---

## 5. Security & Isolation Guarantees

1. **Host Store Immutability:** The 9P mount exports `/nix/store` as read-only. Any attempt by a compromised or buggy daemon inside the guest to modify store paths is denied at the VFS layer (`EROFS: Read-only file system`).
2. **Crash Containment:** Kernel panics, OOM conditions, and fork-bombs triggered inside the Micro-VM cannot escape the QEMU process boundary.
3. **Hardware Acceleration:** Uses `/dev/kvm` hardware virtualization extensions (VT-x / AMD-V) when available for near-native execution performance.
