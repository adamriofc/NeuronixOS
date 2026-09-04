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

### 2.4 `neuronix try [options]`
Boots an in-memory Shadow Micro-VM in `/dev/shm` to test proposed Nix configurations.
* **Options:**
  * `--smoke-test`: Quick verification of kernel boot and store mounts.
  * `--dry-run`: Dry-evaluates QEMU parameters and RAM disk allocation.
  * `--mode <synthetic|real|auto>`: Execution engine mode.
  * `--promote [-y|--yes]`: Applies configuration to host upon clean test pass.
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
