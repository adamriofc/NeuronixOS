# Evaluate the real flake outputs against an already fetched, pinned nixpkgs tree.
# Nothing is built, and the runner uses a read-only dummy store.
{ nixpkgsSource, generatedRoot ? null }:
let
  # Keep outPath a string: a Nix path would try copying nixpkgs into the store.
  source = toString nixpkgsSource;
  nixpkgs = (import (source + "/flake.nix")).outputs {
    self = { outPath = source; };
  } // { outPath = source; };
  flake = (import ../flake.nix).outputs {
    self = flake;
    inherit nixpkgs;
    # Desktop outputs do not use the generators input. Fail if that changes.
    nixos-generators = throw "desktop session evaluation unexpectedly requires nixos-generators";
  };
  lib = nixpkgs.lib;
  generated = (import (generatedRoot + "/etc/nixos/flake.nix")).outputs {
    self = generated;
    inherit nixpkgs;
  };
  targets = {
    neuronix-iso = { system = "x86_64-linux"; live = true; };
    neuronix-desktop = { system = "x86_64-linux"; live = false; };
    neuronix-desktop-aarch64 = { system = "aarch64-linux"; live = false; };
  } // lib.optionalAttrs (generatedRoot != null) {
    generated = { system = "x86_64-linux"; live = false; };
  };
  evaluate = name: expected:
    let
      evaluated = if name == "generated" then generated.nixosConfigurations.neuronix-test
        else flake.nixosConfigurations.${name};
      cfg = evaluated.config;
      get = path: fallback: lib.attrByPath path fallback cfg;
      packages = map lib.getName cfg.environment.systemPackages;
      session = get [ "services" "greetd" "settings" ] { };
      initial = session.initial_session or { };
      defaultSession = session.default_session or { };
      userServices = cfg.systemd.user.services;
      check = description: passed: { inherit description passed; };
      checks = [
        (check "NixOS assertions satisfied" (lib.all (entry: entry.assertion) cfg.assertions))
        (check "target architecture" (evaluated.pkgs.stdenv.hostPlatform.system == expected.system))
        (check "canonical desktop enabled" (get [ "neuronix" "desktop" "enable" ] false))
        (check "live mode matches target" (get [ "neuronix" "desktop" "live" "enable" ] false == expected.live))
        (check "live autologin opt-in by default" (lib.attrByPath [ "neuronix" "desktop" "live" "enable" "default" ] null evaluated.options == false))
        (check "greetd enabled" cfg.services.greetd.enable)
        (check "Sway enabled" cfg.programs.sway.enable)
        (check "XWayland enabled" cfg.programs.sway.xwayland.enable)
        (check "GNOME disabled" (!cfg.services.desktopManager.gnome.enable))
        (check "GDM disabled" (!cfg.services.displayManager.gdm.enable))
        (check "Plasma disabled" (!cfg.services.desktopManager.plasma6.enable))
        (check "Xorg server disabled" (!cfg.services.xserver.enable))
        (check "Hyprland disabled" (!cfg.programs.hyprland.enable))
        (check "greeter launches canonical session" (lib.hasInfix "neuronix-session" (defaultSession.command or "")))
        (check "greeter runs as its own account" ((defaultSession.user or "") == "greeter"))
        (check "greetd PAM authentication present" (builtins.hasAttr "greetd" cfg.security.pam.services))
        (check "autologin limited to live mode" (builtins.hasAttr "initial_session" session == expected.live))
        (check "live autologin uses configured account and session" (!expected.live || (
          (initial.user or null) == get [ "neuronix" "desktop" "live" "user" ] null
          && lib.hasInfix "neuronix-session" (initial.command or "")
        )))
        (check "display-manager autologin disabled" (!cfg.services.displayManager.autoLogin.enable))
        (check "Conductor runtime enabled" cfg.neuronix.services.conductor.enable)
        (check "Conductor private socket path" (get [ "systemd" "user" "sockets" "conductor" "socketConfig" "ListenStream" ] "" == "%t/conductor.sock"))
        (check "Conductor socket enabled" (builtins.elem "sockets.target" (get [ "systemd" "user" "sockets" "conductor" "wantedBy" ] [ ])))
        (check "Conductor socket permissions" (get [ "systemd" "user" "sockets" "conductor" "socketConfig" "SocketMode" ] "" == "0600"))
        (check "Conductor runtime service present" (builtins.hasAttr "conductor" userServices))
        (check "Conductor surface follows desktop target" (builtins.elem "neuronix-session.target" (get [ "systemd" "user" "services" "neuronix-conductor-surface" "wantedBy" ] [ ])))
        (check "canonical session target present" (builtins.hasAttr "neuronix-session" cfg.systemd.user.targets))
        (check "Center included in system packages" (builtins.elem "neuronix-center" packages))
        (check "CLI included in system packages" (builtins.elem "neuronix-cli" packages))
        (check "Conductor included in system packages" (builtins.elem "conductor" packages))
        (check "Conductor runtime included in system packages" (builtins.elem cfg.neuronix.services.conductor.runtimePackage cfg.environment.systemPackages))
        (check "Calamares only in live system" (builtins.elem "calamares" packages == expected.live))
        (check "Calamares user autostart absent" (!lib.any (service: lib.hasInfix "calamares" service) (builtins.attrNames userServices)))
        (check "Calamares XDG autostart absent" (!lib.any (entry: lib.hasInfix "autostart" entry && lib.hasInfix "calamares" entry) (builtins.attrNames cfg.environment.etc)))
        (check "Calamares autostart package absent" (!lib.any (package: lib.hasInfix "calamares" package && lib.hasInfix "autostart" package) packages))
        (check "panel installer action limited to live" (builtins.hasAttr "custom/install" (builtins.fromJSON (builtins.unsafeDiscardStringContext cfg.environment.etc."neuronix/waybar/config.json".text)) == expected.live))
        (check "session identity preserved" ((builtins.fromJSON cfg.environment.etc."neuronix/session.json".text).session == "neuronix"))
        (check "distribution identity preserved" (cfg.system.nixos.distroId == "neuronixos" && cfg.system.nixos.distroName == "NeuronixOS"))
        (check "installer authorization limited to live" (lib.hasInfix "io.calamares.calamares.pkexec.run" cfg.security.polkit.extraConfig == expected.live))
      ];
    in {
      inherit checks;
      # Force the derivation graph as well as selected options: catches missing
      # sources, package names, systemd units and module assertion failures.
      toplevel = cfg.system.build.toplevel.drvPath;
      failures = map (check: check.description) (builtins.filter (check: !check.passed) checks);
    };
  results = lib.mapAttrs evaluate targets;
in {
  inherit results;
  total = lib.foldl' (sum: result: sum + builtins.length result.checks) 0 (builtins.attrValues results);
  passed = lib.all (result: result.failures == [ ]) (builtins.attrValues results);
}
