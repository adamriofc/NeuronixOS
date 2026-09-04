# ==============================================================================
# NEURONIX OS: Single Source of Truth for Versioning & Release Channels
# Referenced by flake.nix, installer, CLI, GUI Center, and packaging derivations.
# ==============================================================================
{
  version = "1.0.3";
  releaseTag = "v1.0.3";
  stateVersion = "24.11";
  channelDevelopment = "nixos-unstable";
  channelStable = "nixos-26.05";
  isRelease = true;
  nixpkgsCommit = "3ed67ec0a4d3c7ab4ae1f04f8ee8df07bfa506a2";
  primarySystem = "x86_64-linux";
  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  supportedTiers = {
    x86_64-linux = {
      tier = 1;
      isoSupported = true;
      packagesSupported = true;
      status = "FULL_STACK";
    };
    aarch64-linux = {
      tier = 2;
      isoSupported = false;
      packagesSupported = true;
      status = "TOOLING_ONLY";
    };
  };
}
