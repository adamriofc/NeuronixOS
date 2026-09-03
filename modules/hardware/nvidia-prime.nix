{ pkgs, lib, config, ... }:

{
  # Pilar 7 & 20: Manajemen GPU Hibrida (NVIDIA Optimus / AMD PRIME) & Hardware Video Decoding
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
