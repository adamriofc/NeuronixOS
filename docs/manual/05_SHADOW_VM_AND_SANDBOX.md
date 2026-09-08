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

## 4. Advanced Micro-VM Sandbox Capabilities

In addition to testing local NixOS configurations, the OS Sandbox outclasses Quickemu and traditional virtual machines with cutting-edge hypervisor automation:

* **Autonomous OS Fabric (Image Auto-Fetcher):** Automatically discovers and downloads verified OS and cloud-init images with SHA-256 integrity validation into local cache (`~/.cache/neuronix/images`):
  ```bash
  # View available operating system catalog
  neuronix sandbox get list

  # Fetch verified Ubuntu 24.04 LTS Noble Numbat image
  neuronix sandbox get ubuntu-24.04

  # Fetch ultra-lean Alpine Linux 3.20 Virt image (60 MB)
  neuronix sandbox get alpine
  ```
* **Windows 11 Autopilot Fabric:** Automated zero-touch Windows 11 installation and runtime orchestration without registry friction or manual intervention:
  * **TPM 2.0 In-Memory Emulation:** Automatically provisions an ephemeral `swtpm` TPM 2.0 socket in `/dev/shm` and bridges it via `-chardev socket -tpmdev emulator -device tpm-tis`.
  * **VirtIO-Win Driver Auto-Injection:** Detects and mounts `virtio-win.iso` as a secondary CD-ROM for instant network and storage controller acceleration.
  * **Bypass Answer File (autounattend.xml):** Generates and injects a zero-touch answer file that bypasses TPM, SecureBoot, RAM, Storage, and Microsoft account requirements, provisioning a local Administrator user automatically.
  ```bash
  # Launch Windows 11 with full Autopilot acceleration
  neuronix sandbox --iso /path/to/Win11.iso --windows --gui --3d-accel
  ```
* **Btrfs Subvolume Time-Travel Snapshots:** While sandboxes default to 100% ephemeral RAM, persistent sandboxes (`--persist <name>`) leverage sub-millisecond Btrfs subvolumes and copy-on-write snapshot trees:
  ```bash
  # Take instant atomic snapshot of persistent sandbox
  neuronix sandbox snapshot create my-lab before-upgrade

  # List existing snapshots for sandbox
  neuronix sandbox snapshot list my-lab

  # Restore snapshot state atomically
  neuronix sandbox snapshot restore my-lab before-upgrade
  ```
* **Instant Zero-Byte CoW Branching:** Clone an existing testing sandbox into an independent branch in under 1 millisecond with 0 bytes initial storage overhead:
  ```bash
  # Branch test-lab into experiment-branch instantly via CoW
  neuronix sandbox branch test-lab experiment-branch
  ```
* **Dynamic Viewport and Seamless Clipboard Bus:** Integrates QEMU SPICE `vdagent` channel (`com.redhat.spice.0`) for bidirectional host-guest clipboard sharing and dynamic guest resolution auto-resizing as the host GUI window resizes.
* **VirtIO-GPU 3D Acceleration:** Utilizing host DRI render nodes (`/dev/dri/renderD128`), VirGL provides 60+ FPS accelerated OpenGL/Vulkan rendering inside GUI VM sessions.
* **Safe Configuration Promotion:** Verify candidate flakes in memory and atomically apply to host with `--promote`:
  ```bash
  neuronix sandbox /path/to/flake.nix --smoke-test --promote -y
  ```

---

## 5. Ephemeral Zero-Copy Development Container (neuronix container)

While `neuronix sandbox` isolates entire operating system virtual machines via QEMU, `neuronix container` isolates application development, multi-service stacks, and foreign codebases via lightweight Linux kernel namespaces with 0 MB idle daemon overhead:

* **RAM Workspace (/dev/shm):** Repositories clone or copy directly into tmpfs/ZRAM in memory, eliminating SSD write wear during high-volume build cycles.
* **Transparent Dynamic FHS Emulation:** Automatically resolves dynamic linkers (`/lib64/ld-linux-x86-64.so.2`) and standard glibc libraries, enabling foreign pre-compiled binaries (Go, Rust, Node, Python C-extensions) to execute out of the box.
* **In-Memory Micro-DNS and Service Mesh:** Stack sessions automatically assign deterministic static IP aliases in `127.0.0.0/8` and synthesize local domain resolution (`*.local`) and environment bindings without requiring root privileges, bridge interfaces, or external DNS daemons:
  ```yaml
  # neuronix-stack.yaml
  services:
    web:
      command: "python3 -m http.server 8080"
    db:
      command: "redis-server --port 6379"
  ```
  ```bash
  # Launch multi-service stack with micro-DNS resolution
  neuronix container compose neuronix-stack.yaml
  # web container can resolve 'db.local' or connect via SERVICE_DB_IP!
  ```
* **Declarative Nix-to-OCI Micro-Layer Compiler:** Directly compiles a Nix flake or local directory into a production-ready OCI image tarball (15 to 35 MB) without requiring Docker daemon, Podman, or root access:
  ```bash
  # Compile ultra-lean OCI image from declarative workspace
  neuronix container build /path/to/project --output my-service.tar --tag v1.0.0
  ```
* **Transient Systemd User Quadlet Engine:** Spawns long-running or background container services supervised by systemd user units with 0 MB idle memory overhead:
  ```bash
  # Launch background service daemon in RAM
  neuronix container daemon /path/to/project --name api-worker --run "npm start"

  # Inspect active container daemons
  neuronix container list

  # Stop daemon and cleanly vaporize RAM workspace
  neuronix container stop api-worker
  ```
* **Daemonless OCI Image Runner:** Pulls and extracts Docker Hub and OCI container images directly into RAM tmpfs without requiring `dockerd` or root privileges:
  ```bash
  neuronix container oci://alpine:latest --run "cat /etc/os-release"
  ```
* **Zero-Bloat OCI Export:** Compiles container workspaces into standard OCI/Docker image tarballs with `--export-oci`.
* **Bubblewrap Containerization:** Mounts `/nix/store` read-only, masks host `$HOME` credentials (`.ssh`, `.aws`, `.gnupg`) with an isolated tmpfs, and cleans up completely upon exit with 0 bytes leftover residue.
