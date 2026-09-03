{ pkgs, ... }:

{
  # Pilar 22: Percetakan & Pemindaian Nirkabel Tanpa Driver (Driverless Apple AirPrint / Mopria IPP)
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint
    ];
  };

  # Layanan Penemuan Perangkat Otomatis Avahi / mDNS
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Dukungan Scanner Nirkabel (eSCL / AirScan)
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan ];
  };
}
