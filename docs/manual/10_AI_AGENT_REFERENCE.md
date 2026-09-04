# Chapter 10: AI Copilot System Directive & Semantic Reference

**Audience:** Autonomous AI Agents (OpenCode, Claude Desktop, Antigravity, Cursor, Zed, Ollama)  
**Context:** NEURONIX OS Execution Environment  
**Protocol:** Model Context Protocol (MCP) JSON-RPC 2.0  

---

## 1. Core Operating Principles for AI Agents

When assisting users or administering NEURONIX OS, autonomous AI models MUST observe these fundamental architectural rules:

1. **NEVER attempt imperative mutations in system paths:**  
   Paths under `/nix/store`, `/run/current-system`, and `/usr` are strictly immutable. Do NOT execute `apt`, `yum`, `pacman`, or attempt to write directly into binary directories.
2. **ALWAYS use declarative NixOS modules for persistent changes:**  
   To install applications permanently or reconfigure system services, modify `/etc/nixos/configuration.nix` using valid `neuronix.*` options, then execute `nixos-rebuild switch`.
3. **USE `neuronix try` for risk-free experimentation:**  
   Before recommending or applying radical system alterations, test the candidate Flake inside the in-memory Shadow Micro-VM (`neuronix try`).
4. **RECOMMEND atomic rollback if errors occur:**  
   If a newly activated generation causes display or networking issues, invoke `neuronix undo` to restore the previous generation instantaneously.
5. **RESPECT the user data boundary:**  
   User projects and files reside under `/home`. Never store system binaries or scratch state outside of `/tmp` or `/dev/shm`.

---

## 2. Fast MCP Tool Dispatch Matrix

When connected via Model Context Protocol, prioritize calling these dedicated tools rather than executing raw bash scripts:

| AI Objective | Recommended MCP Tool Call | Payload Example |
| :--- | :--- | :--- |
| Query system health & kernel | `neuronix_status` | `{}` |
| Dry-run test a candidate Flake | `neuronix_shadow_eval` | `{"config_path": "/tmp/test-flake"}` |
| Prove package derivation exists | `neuronix_verify` | `{"package": "ripgrep"}` |
| Revert broken configuration | `neuronix_undo` | `{"dry_run": false}` |
| Free disk space & discard blocks | `neuronix_diet` | `{"dry_run": false}` |
| Read technical manual chapters | `neuronix_manual` | `{"topic": "storage"}` |
| Collect sanitized debug diagnostics | `neuronix_doctor` | `{}` |

---

## 3. Canonical System Paths Reference

* `/etc/nixos/configuration.nix`: Main declarative system configuration.
* `/etc/nixos/flake.nix`: Root flake declaration for the active workstation.
* `/etc/neuronix/release.json`: Machine-readable rilis manifest and build provenance.
* `/etc/neuronix/manual/`: Offline system manual corpus (Markdown format).
* `/run/current-system/sw/bin/neuronix`: Primary CLI orchestrator binary.
* `/run/neuronix-operation.lock`: Exclusive flock mutex file for system mutations.
* `/dev/shm`: RAM disk for ephemeral Shadow VM execution.
* `/nix/var/nix/profiles/system`: Symlink tracking the currently active system generation.
