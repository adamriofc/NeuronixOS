{ pkgs, lib, config ? {}, ... }:

{
  options = {
    neuronix.audio.antiPop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable ALSA HDA power saving to eliminate DAC audio popping on susceptible desktop DACs";
    };
  };

  config = {
    # Modern PipeWire & WirePlumber audio subsystem (low-latency + HD duplex Bluetooth)
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;

      wireplumber = {
        enable = true;
        extraConfig = {
          "10-bluetooth-codecs" = {
            "monitor.bluez.properties" = {
              # Mengaktifkan codec Bluetooth HD modern
              "bluez5.enable-sbc-xq" = true;
              "bluez5.enable-msbc" = true;
              "bluez5.enable-hw-volume" = true;
              "bluez5.codecs" = [ "ldac" "aptx_hd" "aptx" "aac" "sbc" "lc3plus" ];
            };
          };
        };
      };
    };

    # Analog audio DAC pop elimination (ALSA Powersave tuning when antiPop is active)
    boot.extraModprobeConfig = lib.mkIf (config.neuronix.audio.antiPop or false) ''
      options snd_hda_intel power_save=0
      options snd_hda_intel power_save_controller=N
    '';
  };
}
