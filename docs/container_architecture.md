# NEURONIX Zero-Copy Ephemeral Container Architecture Specification

**Component ID:** `NRX-SPEC-004`  
**Subsystem:** Ephemeral RAM Container Runtime, Micro-DNS Mesh, and OCI Engine  
**Substrate Version:** 1.0.5  

---

## 1. Abstract

Modern containerization workflows (Docker, Podman) introduce daemon bloat, root privileges, overlay storage degradation, and cumbersome bridge networking. On developer workstations, evaluating untrusted repositories, compiling pre-packaged binaries, or running multi-service stacks does not require persistent disk layers or background root processes.

The **NEURONIX Ephemeral Container Engine (`neuronix container`)** provides a zero-root, daemonless container environment running strictly in volatile memory (`/dev/shm`) with transparent dynamic FHS compatibility, in-memory micro-DNS service mesh, declarative Nix-to-OCI compilation, and transient systemd user quadlet services.

---

## 2. Memory Topology & Ephemeral RAM Backing

`neuronix container` eliminates physical storage wear by binding workspace trees directly into Linux tmpfs:

Scratch Path: `/dev/shm/neuronix_container_<pid>`

```text
Host Volatile Memory (RAM)
┌──────────────────────────────────────────────────────────────┐
│ /dev/shm (tmpfs, require_ram=True)                           │
│  └─ neuronix_container_XXXXXX/                               │
│      ├─ workspace/          <-- Isolated git/project files   │
│      ├─ rootfs/             <-- OCI layer or FHS rootfs      │
│      ├─ hosts               <-- Synthesized Micro-DNS table  │
│      └─ container.pid       <-- Bubblewrap supervisor        │
└──────────────────────────────┬───────────────────────────────┘
                               │ Read-Only Bind Mount
┌──────────────────────────────▼───────────────────────────────┐
│ Host Physical Nix Store                                      │
│  └─ /nix/store/ (Immutable System Derivations)               │
└──────────────────────────────────────────────────────────────┘
```

On container exit, `/dev/shm` scratch directories vaporize automatically, leaving zero orphaned layers or disk artifacts.

---

## 3. Core Architectural Subsystems

### 3.1 Dynamic Transparent FHS Emulation
Non-Nix pre-compiled binaries (Go, Rust, Node, Python wheels) expect standard POSIX paths (`/lib64/ld-linux-x86-64.so.2`, `/usr/lib`, `/bin/bash`). `neuronix container` dynamically provisions `nix-ld` within the bubblewrap namespace, allowing arbitrary ELF binaries to execute without wrapping or base image bloat.

### 3.2 In-Memory Micro-DNS & Service Mesh
For multi-service architectures (`--stack <file.yaml>`), `neuronix container` assigns unique loopback aliases (`127.0.0.10+`) to each service. It generates an ephemeral `/etc/hosts` mapping each service name to its IP and injects `HOSTALIASES`. Services communicate seamlessly via `<service>.local` without requiring root privileges, Docker daemon bridges, or external DNS daemons.

### 3.3 Declarative Nix-to-OCI Compiler (`build`)
The `neuronix container build` engine directly translates local workspaces or Nix Flakes into standardized OCI image tarballs without requiring Docker or Podman:
- Generates compliant OCI Image Manifest specification.
- Assembles layer tarballs with deterministic timestamps (epoch 1970-01-01) and SHA-256 diff_ids.
- Outputs single-file tarballs ready for `docker load` or registry publication.

### 3.4 Transient Systemd User Quadlet Engine (`daemon`)
Long-running background services are managed via systemd user transient units (`systemd-run --user`):
- `neuronix container daemon <target> --name <name>`
- `neuronix container list`
- `neuronix container stop <name>`
- `neuronix container compose <stack.yaml>`

All background containers execute strictly within the user session, without root daemons or system-wide systemd unit pollution.

---

## 4. CLI Syntax & Usage Reference

```bash
# Launch isolated ephemeral RAM container from remote Git repository
neuronix container https://github.com/astral-sh/uv

# Run Docker Hub container image directly in RAM without Docker daemon
neuronix container oci://alpine:latest --run "cat /etc/os-release"

# Build standalone OCI image tarball declaratively
neuronix container build ./my-app --output app.tar --tag v1.0.0

# Run rootless container in background as a transient systemd user service
neuronix container daemon oci://nginx:alpine --name web-server
neuronix container list
neuronix container stop web-server

# Orchestrate multi-service stack with micro-DNS mesh
neuronix container --stack neuronix-stack.yaml
```

---

## 5. Security & Isolation Invariants

1. **Rootless Namespace Sandboxing:** Bubblewrap unshares PID, UTS, and IPC namespaces (`--clearenv`, `--unshare-pid`, `--unshare-uts`, `--unshare-ipc`).
2. **Credential Sanitization:** Strips environment variables containing API tokens, SSH keys, or cloud credentials (`AWS_*`, `GITHUB_*`, `*_TOKEN`, `*_KEY`, `SSH_AUTH_SOCK`).
3. **Store Protection:** Mounts `/nix/store` as strictly read-only.
4. **RAM Purity:** Refuses silent disk fallback when RAM isolation is requested (`require_ram=True`).
