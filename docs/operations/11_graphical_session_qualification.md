# NEURONIX OS Runbook: Graphical Session Qualification

## 1. Scope and Evidence Rules

Qualify the exact image through **live boot -> install -> authenticated reboot -> update -> rollback**, retaining the canonical Neuronix session throughout. This runbook defines a procedure; it is not a report that these stages have passed.

Record the Git revision, working-tree changes, ISO SHA-256, Nix build log, VM launch configuration, and timestamps. Keep source checks, successful builds, VM graphical observations, and physical hardware observations separate. Mark any unexecuted stage **UNVERIFIED**. The existing `test_real_os_install_boot.sh` prerequisite and contract result is insufficient evidence of graphical ISO boot.

Store images, virtual disks, logs, screenshots, temporary files, and build caches on the designated development drive. A `nix build --out-link` location does not move the Nix store: use a builder whose store and temporary storage are on the approved volume, or the candidate build workflow on GitHub Actions. Do not install Neuronix onto the development host or its disks during qualification.

The `Neuronix graphical session` workflow also runs `tests/qualify_iso.py` on a separate disposable runner. It boots the exact candidate ISO with OVMF/KVM, records screenshots, operates Calamares, removes the ISO, authenticates the installed user, and exercises generation update and rollback. Its `evidence.json` marks only stages actually completed. A root control channel is started through the guest terminal for inspection; the production image has no test backdoor. A failed run is not qualification, and module VM results alone do not replace this ISO gate.

Calamares passes its actual mounted target, username, hostname, locale, timezone and keyboard selection to the engine. Passwords remain in Calamares' users job, which runs inside the target after `nixos-install`; the generated account is locked until that job completes. Direct engine callers must supply a password hash or password for real installations. Plaintext passwords are never written into the generated Nix configuration.

## 2. Build and VM Preparation

1. Run the relevant source/session contract tests and installer generation tests; save their real outputs.
2. On the approved builder, build `.#packages.x86_64-linux.iso`. Save the complete result and its checksum. A parse/evaluation result alone does not complete this build gate.
3. Create a disposable virtual disk of at least 30 GiB and launch the resulting ISO in a UEFI QEMU/KVM VM with at least 4 GiB RAM and a graphical display. Keep the writable UEFI variable image with the virtual disk on the development drive. Attach only the virtual target disk and ISO, never host block devices.
4. Record QEMU arguments, firmware paths, display/GPU model, memory, CPU count, and accelerator. If KVM is unavailable, record the actual accelerator; do not label a software-emulated boot as a hardware-accelerated result.

## 3. Observe the Live Session

The VM must reach the Neuronix session through greetd auto-login as `nixos`. Conductor must be visibly open in a foot window. Record a screenshot that includes the panel and Conductor, plus the output of these commands from `Mod+Return` inside the guest:

```bash
id -un
printf '%s\n' "$XDG_CURRENT_DESKTOP" "$XDG_SESSION_TYPE"
swaymsg -t get_version
swaymsg -t get_tree
systemctl status greetd --no-pager
systemctl --user status conductor.socket --no-pager
pgrep -a -f 'sway|foot|conductor|gnome-shell|plasmashell|calamares'
```

Verify all of the following:

- The desktop identity names Neuronix and the session type is Wayland; Sway owns the compositor session.
- GNOME Shell and Plasma Shell are absent from the canonical session.
- The terminal accepts normal input, Unicode, backspace, and full-screen terminal applications. Test resizing and closing/reopening Conductor with `Mod+Shift+c`.
- `Mod+c` opens Center; `Mod+Space` opens the launcher; notifications and an application file chooser work. Check display scaling and the configured keyboard layout.
- Calamares is not launched automatically. The live panel Install action and `Mod+i` launch it on demand. Closing the installer leaves the session usable.

A screenshot of an application launched manually on another desktop does not satisfy this gate.

## 4. Install in the VM

1. Open Calamares using the live Install action. Select only the VM's disposable target disk.
2. Configure a new user, its password, locale, and keyboard. Install with the default Neuronix profile.
3. Before reboot, retain the installation log and generated `/etc/nixos` configuration from the mounted target. Confirm it imports the canonical Neuronix desktop module and does not enable live auto-login or live installer actions.
4. Shut down the VM, detach the ISO, and boot the installed virtual disk using its recorded firmware and display configuration. Keep a snapshot of the completed installation for repeatable testing.

## 5. Authenticate and Check the Installed Session

The VM must require the configured user's authentication at greetd. Log in, capture the same session observations as in section 3, and check:

- The same Neuronix panel, Conductor entry point, Center, launcher, and terminal work after first boot.
- The Install action is absent, `Mod+i` does not launch installation, and the live account does not auto-login.
- `Mod+Shift+l` locks the session; an incorrect password fails and the correct installed password unlocks it.
- `Mod+Shift+e` returns to authentication. Logging in again opens a usable session without duplicate panel or notification processes.
- `neuronix status` and `neuronix doctor` operate, and Conductor can reach its runtime. Closing its foot window must leave the session and independent runtime clients usable.

## 6. Update and Roll Back Without Losing Identity

Perform these mutations only inside the disposable installed guest:

1. Record the initial system generation and configuration. Ensure this baseline already uses the canonical Neuronix profile.
2. Add a harmless test marker to the guest's declarative configuration, for example `environment.etc."neuronix/qualification-marker".text = "session-check";`.
3. Build and activate the next generation using the installed flake and its actual host name. Save the build/switch result; verify the marker exists, then log out and back in or reboot.
4. Capture session evidence again and verify the same identity, authentication, shortcuts, and Conductor entry point.
5. Roll back to the recorded baseline using `neuronix undo`. Reboot and verify the selected generation, the marker's absence, and the same session observations.
6. Restore the configuration source to the baseline after the test. Runtime generation rollback does not automatically revert edits made to configuration files.

If an activation or graphical login fails, save guest journal output and the failing generation. Recover using the previous generation and record the failed stage; do not discard it as a successful rollback qualification.

## 7. Qualification Record

Attach evidence to each row rather than inferring later stages from an earlier PASS:

| Stage | Required evidence | Initial status |
| :--- | :--- | :--- |
| Source/session contract | Actual test output and revision | UNVERIFIED |
| ISO build | Successful build log and ISO checksum | UNVERIFIED |
| Live graphical VM boot | Screenshot, session/compositor output, launch configuration | UNVERIFIED |
| Installation | Calamares result and generated target configuration | UNVERIFIED |
| Installed reboot/authentication | Login, lock/unlock, identity and shortcut observations | UNVERIFIED |
| Update and rollback | Generation IDs, marker result, post-reboot session evidence | UNVERIFIED |
| Physical hardware | Hardware inventory, display/input tests, boot evidence | UNVERIFIED |

Record physical GPU, display, scaling, keyboard, suspend/resume, and network observations separately. VM success does not establish physical hardware qualification.
