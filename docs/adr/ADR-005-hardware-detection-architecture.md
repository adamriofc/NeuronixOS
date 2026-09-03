# ADR-005: Hybrid Hardware Detection and Battery Longevity Architecture

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Linux desktop installations frequently encounter hardware compatibility challenges out-of-the-box:
1. Missing proprietary wireless firmware causing no Wi-Fi availability during initial setup.
2. Hybrid GPU laptops (Intel/AMD + NVIDIA) causing battery drain or display freezing.
3. Modern laptops remaining plugged into AC power continuously, causing premature battery degradation.

## Architectural Decision
NEURONIX deploys an integrated declarative hardware compatibility matrix:
1. **Full Offline Firmware:** Bundles redistributable firmware blobs (`hardware.enableAllFirmware = true`) within the installer image.
2. **NVIDIA PRIME Dynamic Offload:** Pre-configures PRIME Render Offload to keep the discrete GPU powered down until explicitly requested by high-performance applications.
3. **Battery Longevity Protection:** Configures an autonomous battery threshold daemon setting sysfs `charge_control_limit_max = 80` to prolong lithium-ion battery lifespan during stationary AC usage.

## Consequences
- **Positive:** Out-of-the-box Wi-Fi and Bluetooth connectivity; power efficiency on hybrid GPU laptops; extended hardware lifespan.
- **Trade-off:** Battery maximum capacity is capped at 80% while stationary, toggleable to 100% via `neuronix battery 100`.
