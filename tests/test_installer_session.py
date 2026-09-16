"""Exercise the generated production desktop and its self-contained payload."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
INSTALLER = PROJECT_ROOT / "installer/scripts/neuronix-install-engine.sh"


class InstallerSessionTests(unittest.TestCase):
    def setUp(self):
        # Keep every generated file on the same drive as the checkout. In
        # particular, do not let the legacy installer mutate its /tmp alias.
        self.workspace = tempfile.TemporaryDirectory(
            prefix=".installer-session-test-", dir=PROJECT_ROOT
        )
        self.addCleanup(self.workspace.cleanup)
        self.scratch = Path(self.workspace.name)
        self.target = self.scratch / "target"
        self.guard = self.scratch / "guard.bash"
        self.guard.write_text(
            """guard_paths() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      /tmp/*|/etc/*|/) echo "TEST BLOCKED host write: $arg" >&2; return 73 ;;
    esac
  done
}
rm() { guard_paths "$@" && command rm "$@"; }
ln() { guard_paths "$@" && command ln "$@"; }
mkdir() { guard_paths "$@" && command mkdir "$@"; }
nixos-install() { echo 'TEST BLOCKED real install' >&2; return 74; }
nixos-generate-config() { echo 'TEST BLOCKED hardware generation' >&2; return 74; }
"""
        )

    def run_installer(self, *, script=INSTALLER, **overrides):
        env = os.environ.copy()
        env.pop("SELECTED_DESKTOP", None)
        env.update(
            DRY_RUN="1",
            TARGET_ROOT=str(self.target),
            TARGET_USER="alice",
            TARGET_HOSTNAME="neuronix-test",
            TARGET_ARCH="x86_64",
            TARGET_PASSWORD="test-only-password",
            NEURONIX_DUAL_BOOT_WINDOWS="1",
            NEURONIX_COMMIT="test-fixture",
            BASH_ENV=str(self.guard),
            TMPDIR=str(self.scratch),
        )
        env.update(overrides)
        return subprocess.run(
            ["bash", str(script)], env=env, cwd=PROJECT_ROOT,
            text=True, capture_output=True, timeout=60,
        )

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("TEST BLOCKED", result.stdout + result.stderr)

    def test_default_generates_canonical_authenticated_session(self):
        self.assert_success(self.run_installer())
        config_dir = self.target / "etc/nixos"
        flake = (config_dir / "flake.nix").read_text()
        config = (config_dir / "configuration.nix").read_text()
        self.assertIn("./modules/desktop/neuronix.nix", flake)
        self.assertIn("neuronix.desktop.enable = true;", config)
        self.assertIn("users.users.alice", config)
        for incompatible in (
            "services.desktopManager.gnome.enable",
            "services.desktopManager.plasma6.enable",
            "programs.hyprland.enable",
            "initial_session", "autoLogin", "live.enable = true",
            '"$TARGET_USER"',
        ):
            with self.subTest(incompatible=incompatible):
                self.assertNotIn(incompatible, config)

    def test_release_identity_matches_session(self):
        self.assert_success(self.run_installer(SELECTED_DESKTOP="neuronix"))
        manifest = json.loads((self.target / "etc/neuronix/release.json").read_text())
        self.assertEqual(manifest["desktop_environment"], "neuronix")
        self.assertEqual(manifest["desktop_session"], "neuronix")
        self.assertEqual(manifest["desktop_compositor"], "sway")
        self.assertEqual(manifest["substrate"], "nixos")

    def test_payload_contains_local_dependencies(self):
        self.assert_success(self.run_installer())
        config_dir = self.target / "etc/nixos"
        # These are consumed by the canonical platform, artwork and CLI modules;
        # generating syntactically valid Nix alone does not prove they exist.
        for relative in (
            "modules/platform.nix", "modules/desktop/neuronix.nix",
            "packages/neuronix-cli/default.nix",
            "packages/neuronix-center/default.nix",
            "packages/conductor-runtime/default.nix",
            "artwork/wallpapers/neuronix-cyber-neural-dark.svg",
            "artwork/branding/neuronix-logo.png",
            "docs/manual/00_INDEX.md", "src/neuronix", "bin/neuronix",
            "data/skills/system.status.json", "version.nix",
        ):
            with self.subTest(path=relative):
                self.assertTrue((config_dir / relative).is_file(), relative)
        self.assertEqual(
            (config_dir / "bin/neuronix").resolve(), config_dir / "src/neuronix"
        )

    def test_legacy_and_unknown_desktops_are_rejected_before_writes(self):
        for desktop in ("kde", "gnome", "hyprland", "unknown"):
            with self.subTest(desktop=desktop):
                target = self.scratch / desktop
                result = self.run_installer(
                    SELECTED_DESKTOP=desktop, TARGET_ROOT=str(target)
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid SELECTED_DESKTOP", result.stderr)
                self.assertFalse(target.exists())

    def test_running_system_root_and_relative_targets_are_rejected(self):
        root_alias = self.scratch / "running-system"
        root_alias.symlink_to("/", target_is_directory=True)
        for target in ("/", "relative-target", str(root_alias)):
            with self.subTest(target=target):
                result = self.run_installer(TARGET_ROOT=target)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("TARGET_ROOT must be", result.stderr)
                self.assertNotIn("TEST BLOCKED", result.stderr)

    def test_explicit_dry_run_is_contained_and_preserves_existing_files(self):
        self.target.mkdir()
        marker = self.target / "keep-existing-data.txt"
        marker.write_text("unchanged")
        self.assert_success(self.run_installer())
        self.assertEqual(marker.read_text(), "unchanged")

    def test_incomplete_payload_fails_before_generating_target_configuration(self):
        fixture_script = self.scratch / "source/installer/scripts/install.sh"
        fixture_script.parent.mkdir(parents=True)
        shutil.copyfile(INSTALLER, fixture_script)
        result = self.run_installer(script=fixture_script)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing installer payload", result.stderr)
        self.assertFalse((self.target / "etc/nixos/configuration.nix").exists())


if __name__ == "__main__":
    unittest.main()
