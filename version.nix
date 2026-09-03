# ==============================================================================
# NEURONIX OS: Single Source of Truth for Versioning & Release Channels
# Referenced by flake.nix, installer, CLI, GUI Center, and packaging derivations.
# ==============================================================================
{
  version = "1.0.1-beta";
  releaseTag = "v1.0.1";
  stateVersion = "24.11";
  channelDevelopment = "nixos-unstable";
  channelStable = "nixos-26.05";
  nixpkgsCommit = "577972710ddbf3f000ae7f184dd26c25264d7be7";
}
