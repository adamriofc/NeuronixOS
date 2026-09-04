---
name: Hardware Qualification Report
about: Submit qualification data for a tested hardware model
title: '[HW-QUAL]: '
labels: ['hardware']
assignees: ''
---

### Device Specification
- **Vendor / Model:**
- **CPU Architecture:**
- **Primary GPU:**
- **Secondary GPU (if dual):**
- **Wi-Fi / Bluetooth Chipset:**
- **Audio Codec:**

### Qualification Results
- [ ] Calamares Live ISO boot successful
- [ ] Btrfs subvolumes and systemd-boot initialized
- [ ] PipeWire audio playback and duplex capture functional
- [ ] Wi-Fi and Bluetooth functional
- [ ] S3 / modern standby suspend and resume functional
- [ ] Graphical desktop compositor (Wayland) functional without tearing

### Telemetry Payload
Attach the output of `neuronix doctor --json` below:
```json
(paste doctor JSON here)
```
