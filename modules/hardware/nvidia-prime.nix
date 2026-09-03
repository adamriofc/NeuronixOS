{ pkgs, lib, config, ... }:

# ==============================================================================
# NEURONIX OS: Hybrid GPU & NVIDIA PRIME Render Offload Subsystem
# Provides hardware-accelerated graphics, VA-API/NVDEC, and dynamic dGPU power gating.
#
# Status: IMPLEMENTED (Requires host-specific PCI bus IDs for discrete GPU)
# ==============================================================================
{
  options = {
    neuronix.hardware.nvidia = {
      enable = lib.mkEnableOption "NVIDIA proprietary drivers and PRIME offload";
      intelBusId = lib.mkOption {
        type = lib.types.str;
        default = "PCI:0:2:0";
        description = "PCI Bus ID for integrated Intel GPU.";
      };
      nvidiaBusId = lib.mkOption {
        type = lib.types.str;
        default = "PCI:1:0:0";
        description = "PCI Bus ID for discrete NVIDIA GPU.";
      };
    };
  };

  config = lib.mkMerge [
    {
      # Accelerated hardware graphics stack (Mesa + 32-bit gaming runtimes)
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          intel-media-driver
          libva-vdpau-driver
          vaapiVdpau
        ];
      };

      # Driver inspection and diagnostic utilities
      environment.systemPackages = with pkgs; [
        nvtopPackages.full
        vulkan-tools
        glxinfo
        libva-utils
        pciutils
      ];
    }

    (lib.mkIf config.neuronix.hardware.nvidia.enable {
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        powerManagement.finegrained = true;
        open = false; # Proprietary production driver for broad GPU support
        nvidiaSettings = true;

        prime = {
          offload = {
            enable = true;
            enableOffloadCmd = true;
          };
          intelBusId = config.neuronix.hardware.nvidia.intelBusId;
          nvidiaBusId = config.neuronix.hardware.nvidia.nvidiaBusId;
        };
      };
    })
  ];
}
