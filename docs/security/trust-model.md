# NEURONIX Security Trust Model & Privilege Hierarchy

## 1. Overview

NEURONIX OS operates on a declarative privilege separation model designed to balance developer usability with strict operating system integrity. This document formally outlines the security boundaries, trust domains, and access rights across users, groups, daemons, and package substituters.

---

## 2. Privilege Domain Hierarchy

The system enforces six distinct privilege levels:

```text
+-------------------------------------------------------------------------+
| [LEVEL 0: ROOT (UID 0)]                                                |
| Complete kernel and hardware authority. Manages activation scripts.     |
+-----------------------------------+-------------------------------------+
                                    |
+-----------------------------------+-------------------------------------+
| [LEVEL 1: WHEEL GROUP & TRUSTED-USERS]                                 |
| Full sudo escalation and administrative access to the Nix Daemon socket.|
+-----------------------------------+-------------------------------------+
                                    |
+-----------------------------------+-------------------------------------+
| [LEVEL 2: POLKIT AUTHORIZED ACTIONS]                                   |
| Graphical authentication prompts for specific system management tasks. |
+-----------------------------------+-------------------------------------+
                                    |
+-----------------------------------+-------------------------------------+
| [LEVEL 3: UNPRIVILEGED USER (UID >= 1000)]                             |
| Standard interactive desktop session. Restricted to $HOME.             |
+-----------------------------------+-------------------------------------+
                                    |
+-----------------------------------+-------------------------------------+
| [LEVEL 4: NIX BUILD SANDBOX (nixbld1..nixbld32)]                       |
| Hermetic, isolated user namespaces with no network or root filesystem. |
+-----------------------------------+-------------------------------------+
                                    |
+-----------------------------------+-------------------------------------+
| [LEVEL 5: FLATPAK APPLICATION SANDBOX]                                 |
| Bubblewrap isolation for user applications via XDG Desktop Portals.   |
+-------------------------------------------------------------------------+
```

---

## 3. The `trusted-users` Domain in NixOS

In `modules/core/default.nix`, NEURONIX declares:
```nix
nix.settings.trusted-users = [ "root" ];
```

### Implications and Rationale (SEC-TRUST-001)
1. **Nix Daemon Socket Hardening:** Only `root` is permitted as a trusted user. Ordinary users in the `wheel` group cannot instruct the multi-user `nix-daemon` to register arbitrary binary substituters or override core security settings without explicit root authentication.
2. **Elimination of Privilege Escalation:** While members of the `wheel` group can execute commands with `sudo`, decoupling `wheel` from `trusted-users` ensures the Nix daemon does not grant ambient root-equivalent authority to user shells or background agent processes.
3. **Security Boundary:** All non-root users are untrusted. They can build existing derivations and install packages from declared caches, but cannot inject untrusted binary paths into `/nix/store`. Store immutability protects package paths from ordinary in-place mutation.

---

## 4. Privilege Matrix by Actor

| Actor / Entity | System Modifications | Nix Store Writes | Hardware & Kernel Access | Network Namespace |
| :--- | :--- | :--- | :--- | :--- |
| **root (UID 0)** | Full authority | Via daemon / direct | Unrestricted | Host network |
| **@wheel Member** | Via `sudo` or `polkit` | Allowed (trusted) | Via kernel modules (`sudo`) | Host network |
| **Standard User** | Disallowed | Unprivileged builds only | Device nodes (audio, video) | Host network |
| **Nix Build User (`nixbld*`)** | Isolated to build dir | Output written to store | Completely restricted | Isolated (disabled during build) |
| **Flatpak Container** | Disallowed | Read-only runtime access | Wayland socket, PipeWire | Mediated via Portals |

---

## 5. Binary Substituter Verification & Signatures

All binary packages fetched by NEURONIX must satisfy cryptographic signature verification:
- **Default Substituter:** `https://cache.nixos.org`
- **Public Key:** `cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=`
- **Policy:** Unsigned binaries from unknown substituters are rejected automatically by the Nix daemon unless an administrative user explicitly approves the substituter and imports its cryptographic public key.

---

## 6. Sudo and Polkit Policies

- **CLI Escalation:** Administrative commands (e.g. `nixos-rebuild switch`, systemd unit management) require standard `sudo` authentication.
- **Desktop Escalation:** Graphical administrative actions in NEURONIX Center utilize Polkit (`polkit-gnome` or `polkit-kde-agent`) to display secure authentication dialogs, ensuring password input is never piped through unverified shell processes.
