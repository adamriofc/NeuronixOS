# Chapter 9: Platform Security, Cryptography & Supply Chain

## 1. Privilege Escalation & Execution Allowlist

To eliminate command-injection risks when executing privileged system maintenance, the NEURONIX CLI enforces an explicit binary allowlist in `run_privileged`:

* **Permitted System Binaries:** `nixos-rebuild`, `nix-collect-garbage`, `nix-store`, `journalctl`, `fstrim`, `tee`, `mkdir`.
* **Security Guard:** Any command outside this allowlist is rejected immediately with exit code `1`.
* **Input Sanitization:** Package names and stack arguments are strictly filtered against POSIX-safe regex patterns (`^[A-Za-z0-9._+-]+$`) to prevent shell escape sequences.

---

## 2. Platform Cryptography & Measured Boot

### 2.1 Lanzaboote UEFI Secure Boot
NEURONIX supports Lanzaboote for cryptographic verification of the complete boot chain:
* Generates system-specific cryptographic keys (`/etc/secureboot`).
* Signs the unified Linux kernel EFI binary, initrd, and systemd-boot loader.
* Verifies digital signatures against the hardware UEFI PK/KEK/db certificate databases.

### 2.2 TPM2 Device Enrollment & Automated LUKS Decryption
Workstations with TPM2 hardware security chips can securely bind root partition disk encryption keys:
```bash
# Enroll TPM2 PCR 7 (Secure Boot state) to unlock LUKS partition
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2
```

---

## 3. Supply Chain Security & Attestation

Every official release of NEURONIX OS conforms to modern enterprise supply chain standards:

1. **Deterministic SPDX 2.3 SBOM:**  
   The build pipeline generates an official Software Bill of Materials in SPDX 2.3 JSON specification (`dist/neuronix-os-v1.0.3-sbom.spdx.json`), inventorying every upstream package, license, and derivation hash.
2. **SLSA Build Provenance Attestation:**  
   GitHub Actions utilizes OpenID Connect (OIDC) tokens with `id-token: write` and `attestations: write` permissions to cryptographically attest build provenance via GitHub Artifact Attestations (`actions/attest-build-provenance@v2`).
3. **Cryptographic Release Signatures:**  
   The SHA256 checksum database is signed with a dedicated Ed25519 cryptographic release key (`SHA256SUMS.sig`), verifiable via `release_sign.pub`.
