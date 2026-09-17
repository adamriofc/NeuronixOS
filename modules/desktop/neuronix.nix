{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.desktop;
  center = pkgs.callPackage ../../packages/neuronix-center { };
  cli = pkgs.callPackage ../../packages/neuronix-cli { };
  conductor = config.neuronix.services.conductor.package;
  terminal = "${pkgs.foot}/bin/foot --config=/etc/neuronix/foot.ini";
  conductorCommand = "${terminal} --app-id=neuronix-conductor --title=Conductor ${conductor}/bin/conductor --interactive";

  # Import the compositor environment before any graphical user service starts.
  sessionReady = pkgs.writeShellScript "neuronix-session-ready" ''
    set -eu
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
    ${pkgs.systemd}/bin/systemctl --user start neuronix-session.target
  '';
  session = pkgs.writeShellScriptBin "neuronix-session" ''
    # greetd/PAM supplies the systemd user bus. Keep it for app/socket activation.
    export XDG_CURRENT_DESKTOP=Neuronix:sway
    export XDG_SESSION_DESKTOP=neuronix
    export XDG_SESSION_TYPE=wayland
    export TERMINAL=foot
    cleanup() {
      ${pkgs.systemd}/bin/systemctl --user stop neuronix-session.target
      ${pkgs.systemd}/bin/systemctl --user unset-environment DISPLAY WAYLAND_DISPLAY SWAYSOCK
    }
    trap cleanup EXIT
    ${config.programs.sway.package}/bin/sway --config /etc/neuronix/sway.conf "$@"
  '';
  sessionEntry = pkgs.runCommand "neuronix-session-entry" {
    passthru.providedSessions = [ "neuronix" ];
  } ''
    mkdir -p $out/share/wayland-sessions
    cat > $out/share/wayland-sessions/neuronix.desktop <<EOF
    [Desktop Entry]
    Name=Neuronix
    Comment=NeuronixOS operating surface
    Exec=${session}/bin/neuronix-session
    Type=Application
    DesktopNames=Neuronix;sway;
    EOF
  '';
  install = pkgs.writeShellScriptBin "neuronix-install" ''
    exec /run/wrappers/bin/pkexec ${pkgs.calamares}/bin/calamares --config /etc/calamares/settings.conf
  '';
  conductorEntry = pkgs.makeDesktopItem {
    name = "neuronix-conductor";
    desktopName = "Conductor";
    comment = "Neuronix operating surface";
    exec = conductorCommand;
    icon = "utilities-terminal";
    categories = [ "System" ];
  };
  installEntry = pkgs.makeDesktopItem {
    name = "neuronix-install";
    desktopName = "Install NeuronixOS";
    exec = "${install}/bin/neuronix-install";
    icon = "system-software-install";
    categories = [ "System" ];
  };
  graphicalService = description: command: {
    inherit description;
    partOf = [ "neuronix-session.target" ];
    after = [ "graphical-session-pre.target" ];
    wantedBy = [ "neuronix-session.target" ];
    serviceConfig = {
      ExecStart = command;
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
in
{
  imports = [ ../services/conductor.nix ../services/desktop-tweaks.nix ];

  options.neuronix.desktop = {
    enable = lib.mkEnableOption "the canonical Neuronix graphical session";
    live = {
      enable = lib.mkEnableOption "live-media autologin and installation actions";
      user = lib.mkOption {
        type = lib.types.str;
        default = "nixos";
        description = "Existing live-media account used for the initial session.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(config.services.desktopManager.gnome.enable
          || config.services.desktopManager.plasma6.enable
          || config.services.displayManager.gdm.enable
          || config.services.displayManager.sddm.enable
          || config.services.xserver.enable
          || config.programs.hyprland.enable);
        message = "The Neuronix session owns the desktop. Disable neuronix.desktop.enable before selecting an alternative desktop profile.";
      }
      {
        assertion = config.neuronix.services.conductor.enable;
        message = "The Neuronix session requires its Conductor runtime.";
      }
    ];

    programs.sway = {
      enable = true;
      xwayland.enable = true; # The existing Tkinter Center uses X11.
      wrapperFeatures.gtk = true;
      extraPackages = [ ];
      extraSessionCommands = ''
        export XDG_CURRENT_DESKTOP=Neuronix:sway
        export XDG_SESSION_DESKTOP=neuronix
        export XDG_SESSION_TYPE=wayland
        export TERMINAL=foot
      '';
    };
    services.greetd = {
      enable = true;
      useTextGreeter = true;
      settings = {
        default_session = {
          user = "greeter";
          command = "${pkgs.tuigreet}/bin/tuigreet --time --greeting 'Welcome to NeuronixOS' --cmd ${session}/bin/neuronix-session";
        };
      } // lib.optionalAttrs cfg.live.enable {
        initial_session = {
          user = cfg.live.user;
          command = "${session}/bin/neuronix-session";
        };
      };
    };
    services.displayManager.sessionPackages = [ sessionEntry ];
    # Session services below own startup; avoid duplicate legacy welcome windows.
    services.xserver.desktopManager.runXdgAutostartIfNone = false;
    security.polkit.enable = true;
    # The passwordless live account can launch only this installer action;
    # installed sessions retain the normal administrator authentication policy.
    security.polkit.extraConfig = lib.mkIf cfg.live.enable ''
      polkit.addRule(function(action, subject) {
        if (action.id === "io.calamares.calamares.pkexec.run" &&
            subject.local && subject.active &&
            subject.user === ${builtins.toJSON cfg.live.user}) {
          return polkit.Result.YES;
        }
      });
    '';
    security.pam.services.swaylock = { };
    fonts.fontconfig.enable = true;
    environment.sessionVariables.TERMINAL = "foot";
    environment.systemPackages = [
      center cli session conductorEntry pkgs.foot pkgs.wofi pkgs.waybar
      pkgs.mako pkgs.swaybg pkgs.swaylock pkgs.swayidle pkgs.brightnessctl
      pkgs.pulseaudio pkgs.networkmanagerapplet pkgs.lxqt.lxqt-policykit
    ] ++ lib.optionals cfg.live.enable [ install installEntry ];

    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.Neuronix = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
        "org.freedesktop.impl.portal.Inhibit" = [ "none" ];
      };
    };

    environment.etc."neuronix/session.json".text = builtins.toJSON {
      session = "neuronix";
      compositor = "sway";
      substrate = "nixos";
      live = cfg.live.enable;
    };
    environment.etc."neuronix/sway.conf".text = ''
      set $mod Mod4
      font pango:Inter 10
      default_border pixel 2
      default_floating_border pixel 2
      floating_modifier $mod normal
      focus_follows_mouse no
      gaps inner 8
      client.focused #7aa2f7 #1a1b26 #c0caf5 #7aa2f7 #7aa2f7
      client.unfocused #24283b #1a1b26 #a9b1d6 #24283b #24283b
      input type:touchpad tap enabled
      # Keep the installer's minimum-size wizard usable beside Conductor.
      for_window [class="(?i)calamares"] floating enable
      for_window [app_id="(?i).*calamares.*"] floating enable
      input * {
        xkb_layout ${config.services.xserver.xkb.layout}
        xkb_variant "${config.services.xserver.xkb.variant}"
        xkb_options "${config.services.xserver.xkb.options}"
      }
      output * bg /etc/neuronix/artwork/wallpaper.svg fill
      exec ${sessionReady}

      bindsym $mod+Return exec ${terminal}
      bindsym $mod+space exec ${pkgs.wofi}/bin/wofi --show drun
      bindsym $mod+c exec ${center}/bin/neuronix-center
      bindsym $mod+Shift+c exec ${conductorCommand}
      bindsym $mod+Shift+q kill
      bindsym $mod+Shift+r reload
      bindsym $mod+Shift+e exec ${pkgs.sway}/bin/swaynag -t warning -m 'End the Neuronix session?' -B 'Log out' '${pkgs.sway}/bin/swaymsg exit'
      bindsym $mod+f fullscreen toggle
      bindsym $mod+Shift+space floating toggle
      bindsym $mod+Left focus left
      bindsym $mod+Right focus right
      bindsym $mod+Up focus up
      bindsym $mod+Down focus down
      bindsym $mod+1 workspace number 1
      bindsym $mod+2 workspace number 2
      bindsym $mod+3 workspace number 3
      bindsym $mod+4 workspace number 4
      bindsym $mod+Shift+1 move container to workspace number 1
      bindsym $mod+Shift+2 move container to workspace number 2
      bindsym $mod+Shift+3 move container to workspace number 3
      bindsym $mod+Shift+4 move container to workspace number 4
      bindsym XF86AudioRaiseVolume exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%
      bindsym XF86AudioLowerVolume exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%
      bindsym XF86AudioMute exec ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle
      bindsym XF86MonBrightnessUp exec ${pkgs.brightnessctl}/bin/brightnessctl set +5%
      bindsym XF86MonBrightnessDown exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
    '' + lib.optionalString cfg.live.enable ''
      bindsym $mod+i exec ${install}/bin/neuronix-install
    '' + lib.optionalString (!cfg.live.enable) ''
      bindsym $mod+Shift+l exec ${pkgs.swaylock}/bin/swaylock -f -c 1a1b26
    '';

    environment.etc."neuronix/waybar/config.json".text = builtins.toJSON ({
      layer = "top";
      position = "top";
      height = 36;
      "modules-left" = [ "custom/neuronix" "sway/workspaces" ];
      "modules-center" = [ "custom/conductor" "custom/center" "custom/terminal" ]
        ++ lib.optional cfg.live.enable "custom/install";
      "modules-right" = [ "network" "pulseaudio" "battery" "clock" "tray" ];
      "custom/neuronix" = { format = "NEURONIX"; "on-click" = "${pkgs.wofi}/bin/wofi --show drun"; tooltip = false; };
      "custom/conductor" = { format = "Conductor"; "on-click" = conductorCommand; tooltip = false; };
      "custom/center" = { format = "System"; "on-click" = "${center}/bin/neuronix-center"; tooltip = false; };
      "custom/terminal" = { format = "Terminal"; "on-click" = terminal; tooltip = false; };
      network = { "format-wifi" = "{essid}"; "format-ethernet" = "Connected"; "format-disconnected" = "Offline"; "on-click" = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor"; };
      pulseaudio = { format = "Volume {volume}%"; "format-muted" = "Muted"; "on-click" = "${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle"; };
      battery = { format = "Battery {capacity}%"; };
      clock = { format = "{:%a %H:%M}"; };
    } // lib.optionalAttrs cfg.live.enable {
      "custom/install" = { format = "Install NeuronixOS"; "on-click" = "${install}/bin/neuronix-install"; tooltip = false; };
    });
    environment.etc."neuronix/waybar/style.css".source = ./neuronix-waybar.css;
    environment.etc."neuronix/foot.ini".text = ''
      [main]
      font=JetBrains Mono:size=11
      pad=12x12
      [colors]
      background=1a1b26
      foreground=c0caf5
    '';

    systemd.user.targets.neuronix-session = {
      description = "Neuronix graphical session";
      bindsTo = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
    };
    systemd.user.services = {
      neuronix-conductor-surface = graphicalService "Conductor operating surface"
        "${terminal} --app-id=neuronix-conductor --title=Conductor ${conductor}/bin/conductor --interactive";
      neuronix-panel = graphicalService "Neuronix panel"
        "${pkgs.waybar}/bin/waybar --config /etc/neuronix/waybar/config.json --style /etc/neuronix/waybar/style.css";
      neuronix-notifications = graphicalService "Neuronix notifications" "${pkgs.mako}/bin/mako";
      neuronix-polkit-agent = graphicalService "Neuronix authentication agent" "${pkgs.lxqt.lxqt-policykit}/bin/lxqt-policykit-agent";
      neuronix-network = graphicalService "Neuronix network indicator" "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
      neuronix-input-method = lib.mkIf (config.i18n.inputMethod.enable && config.i18n.inputMethod.type == "fcitx5")
        (graphicalService "Neuronix input method" "${config.i18n.inputMethod.package}/bin/fcitx5");
      neuronix-idle = lib.mkIf (!cfg.live.enable) (graphicalService "Neuronix screen locking"
        "${pkgs.swayidle}/bin/swayidle -w timeout 600 '${pkgs.swaylock}/bin/swaylock -f -c 1a1b26' before-sleep '${pkgs.swaylock}/bin/swaylock -f -c 1a1b26'");
    };
  };
}
