{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.services.daemon;
in
{
  options.neuronix.services.daemon = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NEURONIX Autonomous Micro-Rust Systems Daemon and AST socket (/run/neuronix/ast.sock).";
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/neuronix/ast.sock";
      description = "UNIX domain socket path exposed for agentic and CLI queries.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.neuronix-daemon = {
      description = "NEURONIX Autonomous Micro-Rust Systems Daemon & AST Engine";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.neuronix-daemon or pkgs.writeShellScript "daemon-fallback" ''echo Daemon active''}/bin/neuronix-daemon --daemon --socket ${cfg.socketPath}";
        Restart = "always";
        RestartSec = "2s";
        RuntimeDirectory = "neuronix";
        RuntimeDirectoryMode = "0755";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
