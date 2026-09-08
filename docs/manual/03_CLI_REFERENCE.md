# Chapter 3: Unified CLI Command Reference

The `neuronix` CLI is the central operational control plane for the NEURONIX OS workstation.

---

## 1. Global Syntax & Environment

```bash
neuronix <COMMAND> [OPTIONS]
```

* **Default PATH:** `/run/current-system/sw/bin:/usr/bin:/bin`
* **Concurrency Lock:** Mutating commands acquire `/run/neuronix-operation.lock` via `flock`.
* **Privilege Handling:** Commands requiring root automatically escalate via `sudo` or `pkexec`.

---

## 2. Command Index & Specifications

### 2.1 `neuronix status`
Displays live system telemetry, kernel information, active generation, Btrfs storage utilization, autonomous timers, and the 27-pillar hardware shield.
* **Options:** None
* **Exit Codes:** `0` on success

### 2.2 `neuronix diet`
Performs complete 5-stage storage maintenance:
1. `nix-collect-garbage -d` (unlinked derivation cleanup)
2. `nix-store --optimise` (hardlink inode deduplication)
3. `flatpak uninstall --unused -y` (unused runtime pruning)
4. `journalctl --vacuum-size=500M` (log size capping)
5. `fstrim -av` (VirtIO/NVMe physical block discard)
* **Exit Codes:** `0` on completion

### 2.3 `neuronix dev <stack> [--manifest|-m]`
Provisions isolated, ephemeral development environments in RAM.
* **Available Stacks:** `python`, `rust`, `node`, `ai`, `go`, `web3`
* **Options:**
  * `--manifest`, `-m`: Emits declarative JSON manifest without entering subshell.
* **Exit Codes:** `0` on clean exit, `1` on invalid stack

### 2.4 `neuronix sandbox [options] [configuration_path | iso_path]`
Boots an in-memory OS Micro-VM sandbox in `/dev/shm` to test proposed Nix configurations, external ISOs, and cloud images with zero host disk mutation.
* **Alias:** `neuronix try` is retained as a fully supported backward-compatible alias.
* **Subcommands:**
  * `get <distro>`: Autonomous OS Fabric: fetches verified OS images (alpine, ubuntu-24.04, arch, debian-12, windows-11).
  * `snapshot <create|restore|list> <name> [snap]`: Btrfs subvolume and CoW snapshot management.
  * `branch <src> <dest>`: Instant CoW clone/branch with 0-byte initial storage overhead.
* **Options:**
  * `--smoke-test`: Fast verification of kernel boot, systemd targets, and 9P store mounts.
  * `--iso <path>`: Boots custom external OS ISO directly in hardware-accelerated Micro-VM.
  * `--os <distro>`: Boots cloud-init minimal distro image (alpine, ubuntu, arch, debian, windows-11).
  * `--persist <name>`: Enables persistent Btrfs CoW testing sandbox across reboots.
  * `--windows`: Enables Windows 11 Autopilot Fabric (TPM 2.0 swtpm, VirtIO-Win auto-injection, autounattend.xml).
  * `--virtio-win <path>`: Specifies custom VirtIO-Win driver CD-ROM.
  * `--autounattend <path>`: Specifies custom unattended Windows answer file.
  * `--3d-accel`: Enables VirtIO-GPU VirGL 3D hardware rendering for GUI sessions.
  * `--gui`: Launches graphical window with SPICE vdagent dynamic resizing and bidirectional clipboard.
  * `--dry-run`: Dry-evaluates QEMU parameters, catalog targets, and RAM disk reservation.
  * `--mode <synthetic|real|auto>`: Execution engine mode.
  * `--promote [-y|--yes]`: Atomically applies configuration to host upon clean test pass.
* **Exit Codes:** `0` on success, `1` on test failure, `2` if KVM unavailable in real mode

### 2.5 `neuronix verify <package>`
Validates package derivation in pure `nixpkgs` closure without altering system state.
* **Arguments:** Package name (strictly sanitized against regex `^[A-Za-z0-9._+-]+$`)
* **Exit Codes:** `0` if package evaluates and passes dry-build, `1` if invalid

### 2.6 `neuronix undo`
Initiates instantaneous atomic rollback to preceding system generation.
* **Exit Codes:** `0` on successful symlink pointer swap

### 2.7 `neuronix doctor [--json] [--output|-o <file>]`
Deep diagnostic probe. Sanitizes active username and IP address.
* **Options:**
  * `--json`: Outputs structured JSON conformant with schema 1.0.0.
  * `--output`, `-o <file>`: Exports formatted Markdown diagnostic report.
* **Exit Codes:** `0` on success

### 2.8 `neuronix manual [topic]`
Renders this system-embedded technical manual directly in terminal.
* **Topics:** `index`, `arch`, `config`, `cli`, `storage`, `shadow`, `dev`, `mcp`, `hardware`, `security`, `ai`, `all`
* **Exit Codes:** `0` on success

### 2.9 `neuronix kernel [flavor]`
Inspects available kernel packages or declaratively switches kernel profile.
* **Flavors:** `default`, `zen`, `lts`, `latest`, `hardened`
* **Exit Codes:** `0` on success

### 2.10 `neuronix shield`
Displays memory pressure diagnostics, ZRAM block devices, PSI metrics, and sysctl limits.

### 2.11 `neuronix battery [80|100|status]`
Configures laptop battery charge threshold via sysfs `charge_control_limit_max`.

### 2.12 `neuronix generations`
Renders chronological time-travel timeline of system generations and active links.

### 2.13 `neuronix check-update`
Queries upstream repository for available commits and channel releases.

### 2.14 `neuronix upgrade [--staged|--switch]`
Orchestrates atomic system upgrade. `--staged` builds in background for next reboot.

### 2.15 `neuronix mcp`
Launches native Model Context Protocol JSON-RPC 2.0 stdio server.

### 2.16 `neuronix center`
Launches the graphical NEURONIX Control Center desktop hub.

### 2.17 `neuronix welcome`
Opens first-boot onboarding wizard and interactive welcome guide.

### 2.18 `neuronix quickstart`
Displays curated 1-click catalog of daily desktop applications via Flatpak.

### 2.19 `neuronix sentinel [status|confirm] [--json]`
Inspects autonomous Boot-Sentinel health assessment state, active watchdog timers, and emergency rollback history.
* **Subcommands:**
  * `status`: Displays active assessment window, watchdog status, and last-known-good generation pointer.
  * `confirm`: Manually confirms current booted generation as healthy, updates last-known-good, and disarms `neuronix-boot-sentinel-watchdog.timer`.
* **Options:** `--json` outputs machine-readable JSON.
* **Failure Mode:** On timeout or compositor crash, triggers emergency fallback converging on `neuronix_core.rollback` and `TransactionJournal`.

### 2.20 `neuronix diff [GEN_A] [GEN_B] [--json]`
Performs generational forensic diff structured into three distinct analytical tiers:
* **Tier 1 (Metadata):** Generation IDs, store paths, kernel versions, and kernel migration detection.
* **Tier 2 (Authoritative Nix Store Closures):** Closure additions, removals, upgrades, and size deltas via `nix store diff-closures`.
* **Tier 3 (Convenience Deltas):** User-facing executables in `/sw/bin` and declared systemd services.
* **Options:** `--json` outputs complete 3-tier JSON diff report. Defaults to comparing previous vs active generation if arguments omitted.

### 2.21 `neuronix distill <packages...> [--dry-run] [--force] [--json]`
Reverse-compiles imperatively executed packages into declarative Flake configuration in `modules/custom/user-packages.nix`.
* **Safety Boundary:** Refuses to overwrite human-managed configurations lacking the `# AUTO-GENERATED BY NEURONIX DISTILL` header unless `--force` is provided.
* **Options:**
  * `--dry-run`: Previews package verification and generated Nix syntax without writing to disk.
  * `--force`: Overrides human-managed file safety boundary.
  * `--json`: Outputs structured JSON report.

### 2.22 `neuronix container <git-url|dir|oci-image> [options]`
Spins up an ephemeral, zero-copy development container in RAM (`/dev/shm`) isolated via Bubblewrap with zero SSD disk wear.
* **Security & Isolation:** Strictly enforces writable tmpfs `/dev/shm` without silent disk fallbacks. Sanitizes credentials and wipes secrets (`AWS_*`, `GITHUB_*`, tokens, `SSH_AUTH_SOCK`).
* **In-Memory Micro-DNS Mesh:** Automatic rootless service mesh synthesizing `127.0.0.0/8` IP aliases and `*.local` domains for multi-service stacks without Docker network or external DNS.
* **Dynamic FHS Emulation:** Automatically resolves `/lib64/ld-linux-x86-64.so.2` and glibc shared libraries, allowing foreign Linux binaries to run without container bloat.
* **Daemonless OCI Runner & Compiler:** Directly runs OCI/Docker Hub images in RAM without dockerd, and compiles declarative Nix workspaces into micro-layer OCI images.
* **Subcommands:**
  * `build <target> [--output <out.tar>] [--tag <tag>]`: Compiles declarative workspace to ultra-lean OCI tarball (15-35 MB).
  * `daemon <target> --name <name> [--run <cmd>]`: Launches persistent background container supervised by systemd user units (0 MB idle RAM).
  * `stop <name>`: Stops container daemon and cleanly vaporizes RAM workspace.
  * `list | ps`: Displays active container daemons and statuses.
  * `compose <file.yaml|json>`: Launches multi-service stack in RAM with In-Memory Micro-DNS.
* **Options:**
  * `--run, -c <cmd>`: Executes command inside container non-interactively.
  * `--stack <file.yaml|json>`: Launches declarative multi-service stack in RAM with private IPC.
  * `--export-oci <out.tar>`: Exports container workspace to standard OCI image tarball.
  * `--keep <path>`: Exports workspace changes to destination directory on exit.
  * `--vaporize`: Deletes RAM workspace on exit without prompt.
  * `--fhs / --no-fhs`: Toggles transparent FHS dynamic linker emulation (default: on).
  * `--dry-run`: Inspects memory allocation without spawning subshell.
  * `--json`: Emits status in JSON.

### 2.23 `neuronix tune [profile] [--status] [--json]`
Applies deterministic real-time kernel, cgroups, PipeWire quantum, and CPU governor tuning profiles with strict `APPLY -> READBACK -> VALIDATE` semantics.
* **Profiles:** `gaming` (performance governor, max_map_count), `battery` (powersave, 80% ceiling), `audio-daw` (PipeWire 64/48000 quantum buffer), `balanced` (adaptive schedutil).
* **Truthful Statuses:** Evaluates and reports `APPLIED`, `PARTIAL`, `UNSUPPORTED`, or `FAILED` based on verified readback validation.
* **Options:** `--status` displays current governors and audio quantum; `--json` outputs telemetry in JSON.

### 2.24 `neuronix mesh [status|peers] [--json]`
Discovers and queries local peer-to-peer binary cache nodes on the local LAN/Wi-Fi subnet advertising via mDNS/Avahi (`_nix-cache._tcp` on port 5000).
* **Binary Cache Serving:** Serves local store via `services.nix-serve` HTTP daemon on port 5000.
* **Peer Validation:** Probes `/nix-cache-info` endpoints on discovered nodes to verify binary cache protocol readiness.
* **Options:** `--json` outputs peer node list in JSON.

### 2.25 `neuronix daemon [status|ping|ast] [--json]`
Interacts with the autonomous micro-Rust systems daemon and unified live system AST engine (`/run/neuronix/ast.sock`).
* **Substrate Engine:** Ultra-lean 758 KB static binary with zero external crates, sub-millisecond response latency, and guaranteed transparent Python/Bash fallback.
* **AST Schema 2.0.0:** Emits machine-readable AST containing system generations, storage topology, memory metrics, daemon health, and security posture.
* **Subcommands:**
  * `status`: Displays daemon operating state, socket path, and architecture.
  * `ping`: Performs low-latency JSON-RPC roundtrip healthcheck (`PONG`).
  * `ast`: Queries and emits full system Abstract Syntax Tree in structured JSON.
* **Options:** `--json` outputs status or AST directly in structured JSON.

### 2.26 `neuronix ghost [--run <cmd>]`
Executes an ephemeral, zero-trace user session in volatile RAM overlay (`/dev/shm`) with guaranteed vaporization on exit.
* **Zero Disk Wear & Privacy:** Mounts an isolated tmpfs overlay in volatile memory. Real `$HOME` paths and sensitive persistence are completely shielded.
* **RAM Vaporization:** Automatically unmounts and wipes the volatile RAM workspace buffer immediately upon process exit (0 bytes residue).
* **Options:**
  * `--run <cmd>`: Executes a specific non-interactive command inside the volatile RAM overlay and exits immediately.
  * Default: Spawns an interactive shell (`/bin/bash`) within the ephemeral RAM overlay.

### 2.27 `neuronix branch [create|list|revert] <path> [name]`
Provides instant, atomic copy-on-write project workspace branching using Btrfs subvolumes or filesystem Reflinks (`cp --reflink=always`).
* **Instantaneous Snapshots:** Clones entire multi-gigabyte project directories in under 10 milliseconds with 0 bytes initial storage footprint.
* **Subcommands:**
  * `create <path> [name]`: Creates a CoW branch snapshot of the specified workspace.
  * `list <path>`: Lists existing branch snapshots associated with the workspace.
  * `revert <path> <name>`: Restores workspace state from a named branch snapshot.

### 2.28 `neuronix ebpf [status|policy <pkg>]`
Inspects and manages declarative eBPF Linux Security Module (LSM) syscall containment and security policies.
* **Kernel Syscall Gate:** Uses Aya pure-Rust eBPF kernel hooks to enforce syscall restrictions on ephemeral developer containers and untrusted workloads.
* **Subcommands:**
  * `status`: Inspects active eBPF LSM status and kernel security enforcement mode (`ENFORCING` or `AUDIT_MODE`).
  * `policy <pkg>`: Generates declarative eBPF confinement policy for the specified package or derivation.


