{ pkgs, lib, ... }:

{
  # Pilar 18: Subsistem Audio Modern PipeWire & WirePlumber (Latensi Rendah + HD Duplex Bluetooth)
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

  # Pilar 24: Eliminasi Bunyi Letupan Audio "Pop" pada Headphone Kabel 3.5mm (ALSA Powersave)
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=0
    options snd_hda_intel power_save_controller=N
  '';
}
