# NEURONIX OS Runbook: Offline ISO Installation

## 1. Live Media Preparation

Download the official release ISO image and verify cryptographic checksums:

```bash
# Verify canonical SHA-256 hash
sha256sum -c SHA256SUMS

# Verify Maintainer GPG Signature
gpg --verify neuronix-os-v1.0.3-x86_64.iso.sig neuronix-os-v1.0.3-x86_64.iso
```

Flash to USB storage (replace `/dev/sdX` with your target drive):

```bash
sudo dd if=neuronix-os-v1.0.3-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## 2. Graphical Installation (Calamares)

1. Boot into the NEURONIX Live Desktop environment via UEFI.
2. Launch the Calamares installer from the application menu or welcome screen.
3. Select Language, Timezone, and Keyboard Layout.
4. Choose target drive and partition scheme (Btrfs with automated subvolumes recommended).
5. Configure target username, password, and desktop environment (Plasma 6, GNOME 47, or Hyprland).
6. Click Install to commit the declarative installation.

## 3. Headless / CLI Declarative Installation

For automated or headless installations, the underlying declarative engine can be invoked directly:

```bash
# Set environment parameters
export TARGET_ROOT="/mnt"
export TARGET_USER="developer"
export TARGET_HOSTNAME="neuronix-box"
export SELECTED_DESKTOP="kde"

# Execute installation engine
sudo -E /run/current-system/sw/bin/neuronix-install-engine.sh
```

## 4. Post-Installation Verification

Reboot into the newly installed target and verify system status:

```bash
neuronix doctor
```
