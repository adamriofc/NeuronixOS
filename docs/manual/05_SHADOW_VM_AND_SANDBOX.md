# Chapter 5: In-Memory OS Sandbox and Developer Containers

## 1. Zero Blast Radius Principle

Before applying changes to a production workstation, administrators and AI agents need an environment to test new configurations without mutating host disks. 

The NEURONIX **In-Memory OS Sandbox (Shadow Micro-VM)** (`neuronix sandbox`, alias `neuronix try`) creates an ephemeral virtual machine residing entirely in the Linux RAM disk (`/dev/shm`):

* **Host Isolation:** The guest operates inside a hardware-virtualized QEMU sandbox.
* **Store Sharing via 9P:** The host immutable `/nix/store` is passed to the guest read-only using the 9P virtio filesystem, achieving sub-second boot times without cloning gigabytes of data.
* **Transient Discard:** Upon VM termination, all memory allocated in `/dev/shm` is instantly wiped. The host workstation remains completely untouched.

---

## 2. Modes of Operation

The OS Sandbox runner (`src/shadow_vm.sh`) provides three execution modes:

```bash
# Auto Mode (Default): Uses real KVM if available, falls back to synthetic smoke test
neuronix sandbox --mode auto

# Real Mode: Strictly enforces hardware virtualization via /dev/kvm
# Returns exit code 2 if KVM is unavailable
neuronix sandbox --mode real

# Synthetic Mode: Fast deterministic simulation for CI and headless environments
neuronix sandbox --mode synthetic

# Backward-compatible alias
neuronix try --mode auto
```

---

## 3. Four-Stage Guest Verification Oracle

The OS Sandbox oracle validates four mandatory boot milestones before declaring success:

1. `kernel_seen`: Linux kernel decompression and console output initialization.
2. `systemd_seen`: systemd PID 1 target orchestration.
3. `ninep_seen`: Successful 9P virtio mount of `/nix/store`.
4. `guest_ready_seen`: Complete readiness signal emitted by guest target units.

---

## 4. Advanced Micro-VM Capabilities

In addition to testing local NixOS configurations, the OS Sandbox supports universal hypervisor tasks:

* **Universal Direct ISO Booting:** Boot custom operating system ISO images directly with KVM hardware acceleration:
  ```bash
  neuronix sandbox --iso /path/to/installer.iso --gui --3d-accel
  ```
* **Dual-Mode Btrfs CoW Persistence:** While sandboxes default to 100% ephemeral RAM, `--persist <name>` creates a lightweight Btrfs copy-on-write subvolume overlay with 0-byte initial storage overhead:
  ```bash
  neuronix sandbox --os alpine --persist test-lab
  ```
* **VirtIO-GPU 3D Acceleration:** Utilizing host DRI render nodes (`/dev/dri/renderD128`), VirGL provides 60+ FPS accelerated rendering inside GUI VM sessions.
* **Safe Configuration Promotion:** Verify candidate flakes in memory and atomically apply to host with `--promote`:
  ```bash
  neuronix sandbox /path/to/flake.nix --smoke-test --promote -y
  ```

---

## 5. Ephemeral Zero-Copy Development Container (neuronix container)

While `neuronix sandbox` isolates entire system configurations via QEMU, `neuronix container` isolates application development, repositories, and foreign codebases via lightweight Linux kernel namespaces:

* **RAM Workspace (/dev/shm):** Repositories clone or copy directly into tmpfs/ZRAM in memory, eliminating SSD write wear during high-volume build cycles.
* **Transparent Dynamic FHS Emulation:** Automatically resolves dynamic linkers (`/lib64/ld-linux-x86-64.so.2`) and standard glibc libraries, enabling foreign pre-compiled binaries (Go, Rust, Node, Python C-extensions) to execute out of the box.
* **Daemonless OCI Image Runner:** Pulls and extracts Docker Hub and OCI container images directly into RAM tmpfs without requiring `dockerd` or root privileges.
* **Multi-Service Stack Orchestration:** Declaratively launches multi-service stacks (`--stack stack.yaml`) in RAM with isolated networking and automatic vaporization.
* **Zero-Bloat OCI Export:** Compiles container workspaces into standard OCI/Docker image tarballs with `--export-oci`.
* **Bubblewrap Containerization:** Mounts `/nix/store` read-only, masks host `$HOME` credentials (`.ssh`, `.aws`, `.gnupg`) with an isolated tmpfs, and cleans up completely upon exit.

```bash
# Clone foreign git repository into isolated RAM container with FHS emulation
neuronix container https://github.com/example/untrusted-tool.git

# Run Docker Hub image directly in RAM without Docker daemon
neuronix container oci://alpine:latest --run "cat /etc/os-release"

# Orchestrate ephemeral multi-service stack in RAM in milliseconds
neuronix container --stack neuronix-stack.yaml

# Export workspace changes into standard OCI image tarball
neuronix container /path/to/project --export-oci my-app.tar
```
