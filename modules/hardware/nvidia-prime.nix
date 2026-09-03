{ pkgs, lib, config, ... }:

{
  # Hybrid GPU management (NVIDIA Optimus / PRIME) & hardware video decode
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
      vaapiVdpau
    ];
  };

  # Driver & Utilitas GPU
  environment.systemPackages = with pkgs; [
    nvtopPackages.full
    vulkan-tools
    glxinfo
    libva-utils
  ];
}
