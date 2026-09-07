{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.services.mesh;
in
{
  options.neuronix.services.mesh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable zero-config local P2P binary cache mesh over mDNS (AirDrop for Nix store).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "TCP port used for local peer-to-peer binary cache sharing.";
    };

    autoDiscover = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically discover and query neighbor NEURONIX nodes on local LAN/Wi-Fi.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Serve local Nix binary cache over HTTP for LAN peer synchronization
    services.nix-serve = {
      enable = true;
      port = cfg.port;
      bindAddress = "0.0.0.0";
    };

    # Ensure mDNS / Avahi is active for zero-config mesh discovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
      extraServiceFiles = {
        nix-cache = ''
          <?xml version="1.0" standalone='no'?>
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">NEURONIX Nix Cache on %h</name>
            <service>
              <type>_nix-cache._tcp</type>
              <port>${toString cfg.port}</port>
            </service>
          </service-group>
        '';
      };
    };

    # Allow mesh traffic across local network
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
