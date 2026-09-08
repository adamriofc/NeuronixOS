# ==============================================================================
# NEURONIX OS: Canonical Platform Module Suite
# Guarantees complete module composition parity between ISO, installed hosts,
# and declarative target configurations.
# ==============================================================================
{ ... }:

{
  imports = [
    ./core
    ./hardware/boot.nix
    ./hardware/firmware.nix
    ./hardware/audio.nix
    ./hardware/power.nix
    ./hardware/cpu.nix
    ./services/memory-shield.nix
    ./services/storage.nix
    ./services/flatpak.nix
    ./services/network.nix
    ./services/desktop-tweaks.nix
    ./services/printing.nix
    ./services/security.nix
    ./services/opencode.nix
    ./services/update.nix
    ./hardware/tuning.nix
    ./services/mesh.nix
  ];
}
