{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.services.conductor;
  # Resolve locally so this module also works in installer-generated flakes,
  # which have no repository `self.packages` or specialArgs.self.
  corePkg = pkgs.python3.pkgs.callPackage ../../packages/neuronix-core { };
  conductorPkg = pkgs.callPackage ../../packages/conductor { };
  runtimePkg = pkgs.python3.pkgs.callPackage ../../packages/conductor-runtime {
    neuronix-core = corePkg;
  };
  mcpPkg = pkgs.python3.pkgs.callPackage ../../packages/conductor-mcp {
    neuronix-core = corePkg;
    conductor-runtime = runtimePkg;
  };
in
{
  options.neuronix.services.conductor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NEURONIX Conductor Native Operating Surface and Socket-Activated Capability Runtime.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = conductorPkg;
      description = "The Conductor native Rust operating surface package.";
    };

    runtimePackage = lib.mkOption {
      type = lib.types.package;
      default = runtimePkg;
      description = "The Conductor zero-idle capability runtime and control broker package.";
    };

    mcpPackage = lib.mkOption {
      type = lib.types.package;
      default = mcpPkg;
      description = "The Conductor MCP 2026-07-28 universal agent adapter package.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      cfg.runtimePackage
      cfg.mcpPackage
    ];

    systemd.user.sockets.conductor = {
      description = "NEURONIX Conductor Capability Runtime Activation Socket";
      documentation = [ "https://github.com/adamriofc/NeuronixOS" ];
      partOf = [ "conductor.service" ];
      wantedBy = [ "sockets.target" ];

      socketConfig = {
        ListenStream = "%t/conductor.sock";
        SocketMode = "0600";
        RemoveOnStop = true;
        Service = "conductor.service";
      };
    };

    systemd.user.services.conductor = {
      description = "NEURONIX Conductor Capability Runtime Broker";
      documentation = [ "https://github.com/adamriofc/NeuronixOS" ];
      requires = [ "conductor.socket" ];
      after = [ "conductor.socket" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.runtimePackage}/bin/conductor-runtime";
        Restart = "on-failure";
        RestartSec = "2s";
        TimeoutStopSec = "5s";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
      };
    };
  };
}
