{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.services.conductor;
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
      default = pkgs.conductor or (pkgs.writeShellScriptBin "conductor" "echo 'Conductor package placeholder'");
      description = "The Conductor native Rust operating surface package.";
    };

    runtimePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.conductor-runtime or (pkgs.writeShellScriptBin "conductor-runtime" "echo 'Conductor runtime placeholder'");
      description = "The Conductor zero-idle capability runtime and control broker package.";
    };

    mcpPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.conductor-mcp or (pkgs.writeShellScriptBin "conductor-mcp" "echo 'Conductor MCP package placeholder'");
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
