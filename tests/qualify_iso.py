#!/usr/bin/env python3
"""Boot the actual ISO and install it into a disposable UEFI QEMU disk.

Run on a dedicated builder with QEMU/KVM, OVMF, Pillow and Tesseract. The
unmodified ISO boots from its own firmware entry. A test-only root control
channel is started through the graphical terminal after observing the desktop;
it is not built into the image. Only regular files are attached as VM disks.
"""

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import shlex
import shutil
import socket
import subprocess
import time
import uuid

from PIL import Image


PASSWORD = "Neuronix-Test-2468"
USERNAME = "alice"


class VM:
    def __init__(self, iso, output):
        self.iso = iso.resolve(strict=True)
        if not self.iso.is_file():
            raise ValueError("The ISO must be a regular file")
        self.output = output.resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        self.disk = self.output / "target.qcow2"
        self.share = self.output / "share"
        self.share.mkdir()
        self.proc = None
        self.qmp = None
        self.control = None
        self.qmp_file = None
        self.boot_number = 0
        self.records = {"iso": str(iso), "stages": {}}
        digest = hashlib.sha256()
        with self.iso.open("rb") as handle:
            for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
                digest.update(block)
        self.records["iso_sha256"] = digest.hexdigest()
        self.code = Path("/usr/share/OVMF/OVMF_CODE_4M.fd")
        self.variables = self.output / "OVMF_VARS.fd"
        shutil.copyfile("/usr/share/OVMF/OVMF_VARS_4M.fd", self.variables)
        subprocess.run(["qemu-img", "create", "-f", "qcow2", str(self.disk), "36G"], check=True)
        self.share.joinpath("control.sh").write_text(
            "#!/bin/sh\nset -eu\n"
            "systemd-run --unit=neuronix-qualification-control --collect "
            "/bin/sh -c 'export PATH=/run/current-system/sw/bin:/run/wrappers/bin; "
            "exec bash </dev/virtio-ports/neuronix.test "
            ">/dev/virtio-ports/neuronix.test 2>&1'\n"
        )
        self.save()

    def save(self):
        self.output.joinpath("evidence.json").write_text(json.dumps(self.records, indent=2) + "\n")

    def stage(self, name):
        print(f"PASS {name}", flush=True)
        self.records["stages"][name] = {"status": "PASS", "time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        self.save()

    def start(self, live=False):
        self.boot_number += 1
        qmp_path = self.output / "qmp.sock"
        control_path = self.output / "control.sock"
        qmp_path.unlink(missing_ok=True)
        control_path.unlink(missing_ok=True)
        args = [
            "qemu-system-x86_64", "-enable-kvm", "-cpu", "host", "-smp", "2", "-m", "4096",
            "-drive", f"if=pflash,format=raw,readonly=on,file={self.code}",
            "-drive", f"if=pflash,format=raw,file={self.variables}",
            "-drive", f"file={self.disk},format=qcow2,if=virtio",
            "-device", "virtio-vga", "-display", "none",
            "-device", "qemu-xhci", "-device", "usb-tablet",
            "-nic", "user,model=virtio-net-pci",
            "-qmp", f"unix:{qmp_path},server=on,wait=off",
            "-chardev", f"socket,id=control,path={control_path},server=on,wait=off",
            "-device", "virtio-serial-pci",
            "-device", "virtserialport,chardev=control,name=neuronix.test",
            "-virtfs", f"local,path={self.share},mount_tag=qa,security_model=none,readonly=on",
            "-serial", f"file:{self.output}/serial-{self.boot_number}.log",
        ]
        if live:
            args += ["-cdrom", str(self.iso), "-boot", "order=d"]
        else:
            args += ["-boot", "order=c"]
        self.records[f"qemu_boot_{self.boot_number}"] = args
        self.save()
        self.proc = subprocess.Popen(args, stdout=self.output.joinpath(f"qemu-{self.boot_number}.log").open("wb"), stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 30
        while not qmp_path.exists():
            if self.proc.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("QEMU did not create its monitor socket")
            time.sleep(0.1)
        self.qmp = socket.socket(socket.AF_UNIX)
        self.qmp.connect(str(qmp_path))
        self.qmp_file = self.qmp.makefile("rwb", buffering=0)
        self.qmp_file.readline()
        self.command("qmp_capabilities")
        self.control = socket.socket(socket.AF_UNIX)
        self.control.connect(str(control_path))

    def command(self, name, **arguments):
        self.qmp_file.write(json.dumps({"execute": name, "arguments": arguments}).encode() + b"\n")
        while True:
            raw = self.qmp_file.readline()
            if not raw:
                raise RuntimeError("QEMU monitor disconnected")
            response = json.loads(raw)
            if "error" in response:
                raise RuntimeError(str(response))
            if "return" in response:
                return response["return"]

    def key(self, keys):
        self.command("send-key", keys=[{"type": "qcode", "data": key} for key in keys.split("+")], **{"hold-time": 30})
        time.sleep(0.055)

    def type(self, text):
        basic = {" ": "spc", "\n": "ret", "\t": "tab", "-": "minus", "=": "equal", "/": "slash", ".": "dot", ",": "comma", ";": "semicolon", "'": "apostrophe", "[": "bracket_left", "]": "bracket_right", "\\": "backslash", "`": "grave_accent"}
        shifted = {"_": "minus", "+": "equal", ":": "semicolon", '"': "apostrophe", "<": "comma", ">": "dot", "?": "slash", "|": "backslash", "~": "grave_accent", "{": "bracket_left", "}": "bracket_right"}
        shifted.update(dict(zip("!@#$%^&*()", "1234567890")))
        for char in text:
            if char.isascii() and char.isalnum():
                self.key(("shift+" if char.isupper() else "") + char.lower())
            elif char in basic:
                self.key(basic[char])
            elif char in shifted:
                self.key("shift+" + shifted[char])
            else:
                raise ValueError(f"Unsupported virtual keyboard character {char!r}")

    def screenshot(self, name="current"):
        ppm = self.output / "current.ppm"
        self.command("screendump", filename=str(ppm))
        png = self.output / f"{name}.png"
        with Image.open(ppm) as image:
            image.save(png)
        return png

    def words(self):
        path = self.screenshot()
        result = subprocess.run(["tesseract", str(path), "stdout", "--psm", "11", "tsv"], capture_output=True, text=True, check=True)
        return [row for row in csv.DictReader(io.StringIO(result.stdout), delimiter="\t") if row["text"].strip()]

    def find(self, phrase, timeout=120):
        deadline = time.monotonic() + timeout
        # Console font OCR commonly reads the O in NeuronixOS as zero.
        terms = phrase.lower().replace("0", "o").split()
        while True:
            words = self.words()
            text = " ".join(word["text"] for word in words)
            self.output.joinpath("current-ocr.txt").write_text(text)
            for index in range(len(words) - len(terms) + 1):
                group = words[index:index + len(terms)]
                normalized = [re.sub(r"[^\w-]", "", word["text"]).lower().replace("0", "o") for word in group]
                if normalized == terms:
                    return group
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Display did not contain {phrase!r}: {text}")
            time.sleep(2)

    def click(self, phrase, timeout=120, dy=0):
        group = self.find(phrase, timeout)
        x = int(group[0]["left"]) + int(group[0]["width"]) // 2
        y = int(group[0]["top"]) + int(group[0]["height"]) // 2 + dy
        with Image.open(self.output / "current.png") as image:
            width, height = image.size
        self.command("input-send-event", events=[
            {"type": "abs", "data": {"axis": "x", "value": round(x * 32767 / width)}},
            {"type": "abs", "data": {"axis": "y", "value": round(y * 32767 / height)}},
            {"type": "btn", "data": {"button": "left", "down": True}},
        ])
        self.command("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
        time.sleep(0.6)

    def bootstrap(self, live=False):
        self.key("meta_l+ret")
        time.sleep(1)
        self.type("sudo mkdir -p /mnt/qa && sudo mount -t 9p -o trans=virtio qa /mnt/qa && sudo bash /mnt/qa/control.sh\n")
        if not live:
            time.sleep(1)
            self.type(PASSWORD + "\n")
        self.run("id -u", timeout=45)
        # Close only the temporary terminal, leaving Conductor visible.
        self.type("exit\n")

    def run(self, command, timeout=120, check=True):
        marker = "__NEURONIX_" + uuid.uuid4().hex
        line = f"bash -e -o pipefail -c {shlex.quote(command)}; printf '\\n{marker}:%s\\n' $?\n"
        self.control.sendall(line.encode())
        deadline = time.monotonic() + timeout
        data = b""
        self.control.settimeout(1)
        with self.output.joinpath("guest-commands.log").open("a") as log:
            log.write(f"\n$ {command}\n")
            while time.monotonic() < deadline:
                try:
                    chunk = self.control.recv(65536)
                except socket.timeout:
                    continue
                if not chunk:
                    raise RuntimeError("Guest control channel disconnected")
                log.write(chunk.decode(errors="replace"))
                log.flush()
                data += chunk
                match = re.search(rb"\n" + marker.encode() + rb":(\d+)\r?\n", data)
                if match:
                    code = int(match[1])
                    output = data[:match.start()].decode(errors="replace")
                    if check and code:
                        raise RuntimeError(f"Guest command failed ({code}): {command}\n{output[-6000:]}")
                    return code, output
        raise TimeoutError(f"Guest command timed out: {command}")

    def user(self, command, live=False):
        user = "nixos" if live else USERNAME
        return self.run(
            f"uid=$(id -u {user}); sock=$(find /run/user/$uid -maxdepth 1 -name 'sway-ipc*.sock' -print -quit); "
            f"test -n \"$sock\"; su - {user} -c " + shlex.quote(
                "export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                "export SWAYSOCK=$(find $XDG_RUNTIME_DIR -maxdepth 1 -name 'sway-ipc*.sock' -print -quit); " + command
            )
        )

    def desktop(self, name, live=False):
        self.user("swaymsg -t get_tree | jq -e '.. | objects | select(.app_id? == \"neuronix-conductor\")'", live)
        self.user("systemctl --user is-active neuronix-panel.service conductor.socket", live)
        self.user("conductor --status | grep -F 'Runtime is online and responsive'", live)
        self.user("systemctl --user show-environment | grep 'XDG_CURRENT_DESKTOP=Neuronix:sway'", live)
        self.run("grep '^ID=neuronixos$' /etc/os-release && ! pgrep -x gnome-shell && ! pgrep -x plasmashell")
        self.screenshot(name)
        self.stage(name)

    def shutdown(self):
        self.run("systemctl poweroff --no-block")
        self.proc.wait(timeout=90)
        self.close()

    def close(self):
        for handle in (self.control, self.qmp_file, self.qmp):
            if handle:
                handle.close()
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()


def qualify(vm):
    vm.start(live=True)
    vm.find("Conductor", timeout=240)
    vm.screenshot("iso-first-desktop")
    vm.bootstrap(live=True)
    vm.run("test -d /sys/firmware/efi; ! pgrep -x calamares")
    vm.desktop("iso-live-session", live=True)
    vm.key("meta_l+i")
    vm.find("Next", timeout=90)
    vm.screenshot("installer-welcome")
    vm.stage("installer-launch")
    vm.click("Next")
    vm.find("Location")
    vm.screenshot("installer-location")
    vm.click("Next")
    vm.find("Keyboard")
    vm.screenshot("installer-keyboard")
    vm.click("Next")
    vm.click("Erase disk")
    vm.screenshot("installer-partition")
    vm.click("Next")
    vm.find("Users")
    vm.screenshot("installer-users-empty")
    vm.click("What is your name", dy=28)
    vm.type("Alice Test\t")
    vm.key("ctrl+a")
    vm.type(USERNAME + "\t")
    vm.key("ctrl+a")
    vm.type("neuronix-test\t" + PASSWORD + "\t" + PASSWORD)
    vm.screenshot("installer-users")
    vm.click("Next")
    vm.screenshot("installer-summary")
    vm.click("Install")
    vm.click("Install now")
    vm.find("All done", timeout=3600)
    vm.screenshot("installer-completed")
    vm.run("lsblk -f; findmnt")
    vm.stage("calamares-installation")
    vm.shutdown()

    vm.start()
    vm.find("Welcome to NeuronixOS", timeout=240)
    vm.screenshot("installed-authentication")
    vm.type(USERNAME + "\n")
    vm.find("Password")
    vm.type(PASSWORD + "\n")
    vm.find("Conductor")
    vm.bootstrap()
    vm.run("! command -v neuronix-install && test -f /etc/nixos/modules/desktop/neuronix.nix")
    vm.desktop("installed-session")
    vm.key("meta_l+shift+l")
    vm.run("sleep 1; pgrep -x swaylock")
    vm.screenshot("installed-lock")
    vm.type("wrong-password\n")
    vm.run("sleep 3; pgrep -x swaylock")
    vm.type(PASSWORD + "\n")
    vm.run("sleep 3; ! pgrep -x swaylock")
    vm.stage("password-lock-unlock")
    vm.run("neuronix status; neuronix doctor", timeout=180)
    _, baseline = vm.run("readlink /nix/var/nix/profiles/system")
    vm.records["baseline_generation"] = baseline.strip()
    vm.run("cp /etc/nixos/configuration.nix /etc/nixos/configuration.nix.qualification-baseline; "
           "sed -i '/system.stateVersion/i\\  environment.etc.\"neuronix/qualification-marker\".text = \"session-check\";' /etc/nixos/configuration.nix; "
           "nixos-rebuild switch --flake /etc/nixos#neuronix-test", timeout=1800)
    vm.run("test \"$(cat /etc/neuronix/qualification-marker)\" = session-check")
    vm.shutdown()
    vm.start()
    vm.find("Welcome to NeuronixOS", timeout=240)
    vm.type(USERNAME + "\n")
    vm.find("Password")
    vm.type(PASSWORD + "\n")
    vm.find("Conductor")
    vm.bootstrap()
    vm.run("test \"$(cat /etc/neuronix/qualification-marker)\" = session-check")
    vm.desktop("updated-session")
    vm.run("neuronix undo", timeout=300)
    vm.run("test ! -e /etc/neuronix/qualification-marker; "
           "mv /etc/nixos/configuration.nix.qualification-baseline /etc/nixos/configuration.nix")
    _, rolled_back = vm.run("readlink /nix/var/nix/profiles/system")
    if rolled_back.strip() != baseline.strip():
        raise AssertionError("Rollback did not select the baseline generation")
    vm.records["rollback_generation"] = rolled_back.strip()
    vm.stage("generation-update-and-rollback")
    vm.shutdown()
    vm.start()
    vm.find("Welcome to NeuronixOS", timeout=240)
    vm.type(USERNAME + "\n")
    vm.find("Password")
    vm.type(PASSWORD + "\n")
    vm.find("Conductor")
    vm.bootstrap()
    vm.run("test ! -e /etc/neuronix/qualification-marker")
    vm.desktop("rollback-reboot-session")
    vm.shutdown()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iso", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    vm = VM(args.iso, args.output)
    try:
        qualify(vm)
    except Exception as error:
        vm.records["failure"] = str(error)
        vm.save()
        if vm.proc and vm.proc.poll() is None:
            vm.screenshot("failure")
        raise
    finally:
        vm.close()


if __name__ == "__main__":
    main()
