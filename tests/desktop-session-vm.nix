# Graphical integration of the canonical module, separate from ISO qualification.
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "neuronix-desktop-session";
  enableOCR = true;
  nodes = let
    common = { ... }: {
      imports = [ ../modules/desktop/neuronix.nix ];
      neuronix.desktop.enable = true;
      networking.networkmanager.enable = true;
      users.users.alice = {
        isNormalUser = true;
        uid = 1000;
        password = "test-password";
        extraGroups = [ "video" "audio" "networkmanager" ];
      };
      environment.systemPackages = [ pkgs.jq ];
      environment.variables = {
        WLR_RENDERER = "pixman";
        SWAYSOCK = "/run/user/1000/neuronix-sway.sock";
      };
      virtualisation.memorySize = 2048;
      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      system.stateVersion = "24.11";
    };
  in {
    live = { ... }: {
      imports = [ common ];
      neuronix.desktop.live = { enable = true; user = "alice"; };
    };
    installed = { ... }: { imports = [ common ]; };
  };
  testScript = ''
    import shlex
    from test_driver.machine import QemuMachine

    def as_user(command: str) -> str:
        return "su - alice -c " + shlex.quote(
            "export XDG_RUNTIME_DIR=/run/user/1000; "
            "export SWAYSOCK=/run/user/1000/neuronix-sway.sock; " + command
        )

    def graphical_ready(machine: QemuMachine) -> None:
        machine.wait_for_file("/run/user/1000/neuronix-sway.sock")
        machine.wait_until_succeeds(as_user(
            "swaymsg -t get_tree | jq -e '.. | objects | select(.app_id? == \"neuronix-conductor\")'"
        ))
        machine.succeed(as_user("systemctl --user is-active neuronix-panel.service"))
        machine.succeed(as_user("systemctl --user is-active conductor.socket"))
        machine.succeed(as_user("systemctl --user show-environment | grep XDG_CURRENT_DESKTOP=Neuronix:sway"))
        machine.fail("pgrep -x gnome-shell")
        machine.fail("pgrep -x plasmashell")
        machine.fail("pgrep -x calamares")
        machine.succeed(as_user("swaymsg exec neuronix-center"))
        machine.wait_until_succeeds(as_user(
            "swaymsg -t get_tree | jq -e '.. | objects | select(.name? == \"NEURONIX Center\")'"
        ))

    live.start()
    live.wait_for_unit("greetd.service")
    graphical_ready(live)
    live.succeed("command -v neuronix-install")
    live.screenshot("live-neuronix")
    live.succeed(as_user("swaymsg exit"))
    live.wait_until_fails(as_user("systemctl --user is-active neuronix-panel.service"))
    live.shutdown()

    installed.start()
    installed.wait_for_unit("greetd.service")
    installed.fail("pgrep -x sway")
    installed.fail("command -v neuronix-install")
    installed.wait_for_text("Welcome to NeuronixOS")
    installed.send_chars("alice\n")
    installed.wait_for_text("Password")
    installed.send_chars("test-password\n")
    graphical_ready(installed)
    installed.screenshot("installed-neuronix")
    installed.succeed(as_user("swaymsg exit"))
    installed.wait_until_fails(as_user("systemctl --user is-active neuronix-panel.service"))
    installed.wait_for_text("Welcome to NeuronixOS")
    installed.shutdown()
  '';
}
