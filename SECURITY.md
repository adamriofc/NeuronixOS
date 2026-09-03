# Security Policy

## Supported Versions

NEURONIX OS follows the active upstream NixOS channel lifecycle. Security updates and CVE mitigations are delivered through upstream nixpkgs and distribution modules.

| Version | Supported | Maintenance Phase |
| :--- | :---: | :--- |
| 0.4.x (Beta) | Yes | Active Security, Testing, & Subsystem Hardening |
| 0.3.x (Alpha) | Yes | Transition & Bug Fixes |
| < 0.3.0 | No | End of Life (Superseded) |

## Reporting a Vulnerability

The NEURONIX security team takes vulnerabilities seriously. If you discover a security flaw or vulnerability within NEURONIX OS (including installer generator scripts, system modules, or CLI utilities), please report it responsibly.

### Disclosure Guidelines
- **Do not open a public issue.** Please report security issues privately via GitHub Security Advisories at https://github.com/adamriofc/neuronix/security/advisories/new.
- Alternatively, report directly by email to: `adamriofc@protonmail.com` with the subject tag `[SECURITY: NEURONIX]`.
- Please provide:
  - Description of the vulnerability and its potential impact.
  - Minimal reproducible steps or proof-of-concept (PoC).
  - Target component (e.g., installer engine, PAM/PolKit configuration, memory shield, micro-VM isolation).
- We will acknowledge receipt within 48 hours and coordinate a patch and CVE disclosure timeline.

## Security Architecture & Threat Model

NEURONIX implements defensive engineering across its operational layers:

### 1. Immutable Store Protection
The entire package hierarchy (`/nix/store`) is mounted read-only at the kernel level. Package paths are derived from cryptographic SHA-256 hashes of their dependency closures. Direct binary tampering or unauthorized in-place library replacement is mathematically rejected by the filesystem architecture.

### 2. Privilege Separation & User Namespaces
- Administrative actions require explicit authentication via PolKit or wheel-restricted sudo.
- Non-root CLI operations (`neuronix run`, `neuronix dev`) execute inside unprivileged Linux user namespaces without requiring raw root access.

### 3. Isolated Sandbox Execution
The `neuronix try` simulation framework runs untrusted or candidate system configurations inside an ephemeral QEMU micro-VM in RAM (`/dev/shm`). Host storage access is strictly restricted to read-only 9P filesystem mounts of `/nix/store`.

### 4. Processor & Kernel Hardening
- Automatic CPU microcode updates are enabled by default for Intel and AMD platforms to mitigate transient execution flaws (Spectre, Meltdown, Zenbleed).
- Secure Boot integration is supported via signed `shim` bootloaders utilizing `lanzaboote`.
