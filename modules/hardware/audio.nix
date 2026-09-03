{ pkgs, lib, ... }:

{
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

  # Analog audio DAC pop elimination (ALSA Powersave tuning)
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=0
    options snd_hda_intel power_save_controller=N
  '';
}
