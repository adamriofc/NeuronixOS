# ADR-009B: Next-Generation Ephemeral Container and Autonomous Hypervisor Architecture

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Developer workstations traditionally rely on heavyweight container runtimes (Docker, Podman) and virtualization managers (Quickemu, VirtualBox). These runtimes present severe limitations on high-security and deterministic systems:
1. **Daemon Bloat & Root Coupling:** Docker requires background root daemons (`dockerd`), container bridges, and iptables mutations that introduce host security vulnerabilities and consume hundreds of megabytes of idle memory.
2. **Storage Pollution & Slow Cleanup:** Traditional container and VM testing accumulates gigabytes of orphaned layers and disk overlays, fragmenting storage and degrading NVMe lifespan.
3. **Complex Multi-OS Bootstrapping:** Provisioning guest operating systems (such as Windows 11) requires tedious manual ISO downloading, virtual TPM configuration, driver slipstreaming, and bypass registry hacks.
4. **Fragile VM Snapshotting:** Traditional hypervisors rely on slow copy operations or complex qcow2 chain snapshots prone to corruption during crash recovery.

## Architectural Decision
NEURONIX establishes two complementary, hyper-advanced workstation engines:

### 1. `neuronix container` (Replacing Docker and Podman)
- **In-Memory Micro-DNS & Service Mesh:** Allocates deterministic loopback aliases (`127.0.0.10+`) and synthesizes an ephemeral `/etc/hosts` mapped via `HOSTALIASES`, providing rootless `*.local` service discovery without external DNS servers or Docker bridges.
- **Declarative Nix-to-OCI Compiler:** Compiles workspace directories or Nix Flakes directly into standard OCI tarball images (`neuronix container build`) without requiring Dockerfile definitions or Docker daemons.
- **Transient Systemd User Quadlet Engine:** Orchestrates rootless background containers and multi-service stacks natively via systemd user units (`neuronix container daemon`, `stop`, `list`, `compose`).
- **Dynamic Transparent FHS:** Integrates `nix-ld` dynamically so foreign ELF binaries run directly in memory without containerization overhead.

### 2. `neuronix sandbox` (Replacing Quickemu and Traditional Hypervisors)
- **Autonomous OS Fabric:** Automates retrieval, SHA-256 validation, and instantiation of Alpine, Ubuntu 24.04, Arch, Debian 12, and Windows 11.
- **Windows 11 Autopilot Fabric:** Embeds an ephemeral RAM `swtpm` TPM 2.0 socket, auto-injects VirtIO storage drivers, and writes a zero-touch `autounattend.xml` answer file with automatic LabConfig registry bypasses.
- **Sub-Millisecond Btrfs CoW Snapshot Trees:** Leverages native Btrfs subvolume snapshots (`create`, `restore`, `branch`) for instant, 0-byte initial overhead branching with automatic QCOW2 fallback.
- **Dynamic Viewport & Clipboard Bus:** Provides SPICE `vdagent` auto-resizing display synchronization and bidirectional clipboard sharing.

## Consequences
- **Positive:** Zero root privileges required; 0-byte disk leakage with volatile RAM backing (`/dev/shm`); instantaneous sub-millisecond branching; out-of-the-box Windows 11 and Linux guest automation; seamless interoperability with standard OCI ecosystems.
- **Trade-off:** RAM-backed execution requires sufficient host physical memory (minimum 4 GiB recommended for containers, 8 GiB for multi-OS VM sandboxes).
