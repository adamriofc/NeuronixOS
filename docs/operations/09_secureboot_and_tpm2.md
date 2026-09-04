# NEURONIX OS Runbook: Secure Boot and TPM2 Hardware Integration

## 1. Architecture Overview

NEURONIX OS provides declarative modules for Unified Extensible Firmware Interface (UEFI) Secure Boot signing via **Lanzaboote** and hardware disk encryption key enrollment using **TPM2** (Trusted Platform Module 2.0).

## 2. Lanzaboote Secure Boot Configuration

To enable cryptographic signing of kernel images and initrd closures:

1. In `/etc/nixos/configuration.nix`, enable the Secure Boot module:
   ```nix
   neuronix.hardware.secureBoot = {
     enable = true;
     pkiPath = "/etc/secureboot";
   };
   ```
2. Generate private signing keys if not already present:
   ```bash
   sudo sbctl create-keys
   sudo sbctl enroll-keys --microsoft
   ```
3. Rebuild the system to sign the new generation:
   ```bash
   sudo nixos-rebuild switch
   ```
4. Verify Secure Boot signing state:
   ```bash
   sbctl status
   ```

## 3. TPM2 Automatic LUKS Volume Unlocking

For systems equipped with a physical or virtual TPM 2.0 chip, root partitions can be enrolled to unlock automatically without entering passphrases at boot:

```bash
# Enroll TPM2 to LUKS volume
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7 /dev/nvme0n1p3
```
