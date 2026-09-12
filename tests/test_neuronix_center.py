#!/usr/bin/env python3
"""
Unit tests for NEURONIX Center (neuronix_center.py).
Validates Design Token System, responsive architecture, non-blocking telemetry,
terminal emulator resolution, concurrency guards, and quiet status indicators.
"""

import sys
import os
import unittest
from unittest.mock import patch, MagicMock
import types

# Ensure neuronix-center is importable
repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
center_pkg = os.path.join(repo_root, "packages/neuronix-center")
if center_pkg not in sys.path:
    sys.path.insert(0, center_pkg)

import neuronix_center


class TestNeuronixCenterTokens(unittest.TestCase):
    def test_spacing_tokens(self):
        self.assertEqual(neuronix_center.SPACE_XS, 4)
        self.assertEqual(neuronix_center.SPACE_SM, 8)
        self.assertEqual(neuronix_center.SPACE_MD, 12)
        self.assertEqual(neuronix_center.SPACE_LG, 16)
        self.assertEqual(neuronix_center.SPACE_XL, 24)
        self.assertEqual(neuronix_center.SPACE_2XL, 32)

    def test_palettes_completeness(self):
        required_keys = [
            "bg_app", "bg_header", "bg_card", "bg_card_alt", "bg_card_hover",
            "fg_primary", "fg_secondary", "fg_muted", "border", "border_subtle",
            "btn_bg", "btn_hover", "btn_active", "accent", "accent_hover",
            "status_healthy", "status_working", "status_attention", "status_error"
        ]
        for key in required_keys:
            self.assertIn(key, neuronix_center.DARK_PALETTE)
            self.assertIn(key, neuronix_center.LIGHT_PALETTE)
            self.assertTrue(neuronix_center.DARK_PALETTE[key].startswith("#"))
            self.assertTrue(neuronix_center.LIGHT_PALETTE[key].startswith("#"))


class TestNeuronixCenterHelpers(unittest.TestCase):
    def test_clean_display_text(self):
        self.assertEqual(neuronix_center.clean_display_text(None), "Unknown")
        self.assertEqual(neuronix_center.clean_display_text(""), "Unknown")
        self.assertEqual(neuronix_center.clean_display_text("short"), "short")
        self.assertEqual(neuronix_center.clean_display_text("A" * 40, max_len=10), "AAAAAAA...")
        self.assertEqual(neuronix_center.clean_display_text("Test", max_len=2), "Test")

    def test_format_cpu_display(self):
        self.assertEqual(neuronix_center.format_cpu_display(None), "Unknown Processor")
        amd_raw = "AMD Ryzen 7 5800HS with Radeon Graphics Processor"
        self.assertEqual(neuronix_center.format_cpu_display(amd_raw), "AMD Ryzen 7 5800HS")
        intel_raw = "Intel(R) Core(TM) i7-10700K CPU @ 3.80GHz"
        self.assertIn("Intel Core i7-10700K", neuronix_center.format_cpu_display(intel_raw))

    def test_format_gpu_display(self):
        self.assertEqual(neuronix_center.format_gpu_display(None), "Not Detected")
        self.assertEqual(neuronix_center.format_gpu_display("Cezanne [Radeon Vega Series / Radeon Vega Mobile Series]"), "AMD Radeon Vega (Cezanne)")
        nvidia_raw = "NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile / Max-Q]"
        formatted_nvidia = neuronix_center.format_gpu_display(nvidia_raw)
        self.assertNotIn("NVIDIA Corporation", formatted_nvidia)
        self.assertTrue(len(formatted_nvidia) <= 32)

    def test_detect_system_dark_mode(self):
        with patch.dict(os.environ, {"GTK_THEME": "Adwaita:dark"}):
            self.assertTrue(neuronix_center.detect_system_dark_mode())
        with patch.dict(os.environ, {"GTK_THEME": "Adwaita:light"}):
            self.assertFalse(neuronix_center.detect_system_dark_mode())


class TestNeuronixCenterTelemetry(unittest.TestCase):
    def test_get_system_telemetry(self):
        tel = neuronix_center.get_system_telemetry()
        expected_keys = ["os", "kernel", "generation", "cpu", "ram", "storage", "gpu", "battery_limit"]
        for k in expected_keys:
            self.assertIn(k, tel)

    def test_list_generations(self):
        gens = neuronix_center.list_generations()
        self.assertIsInstance(gens, list)
        self.assertTrue(len(gens) > 0)

    def test_get_passport_summary(self):
        ps = neuronix_center.get_passport_summary()
        self.assertIn("state_root", ps)
        self.assertIn("trust_status", ps)
        self.assertIn("verified_assertions", ps)
        self.assertIn("total_assertions", ps)
        self.assertIn("evidence_digest", ps)
        self.assertEqual(ps["total_assertions"], 1384)


class TestNeuronixCenterTerminalLauncher(unittest.TestCase):
    @patch("subprocess.Popen")
    @patch("shutil.which")
    def test_alacritty_requires_e_flag(self, mock_which, mock_popen):
        mock_which.side_effect = lambda cmd: cmd == "alacritty"
        neuronix_center.launch_in_terminal(["ls", "-la"])
        mock_popen.assert_called_once()
        args, kwargs = mock_popen.call_args
        cmd_sent = args[0]
        self.assertEqual(cmd_sent[0], "alacritty")
        self.assertEqual(cmd_sent[1], "-e")
        self.assertEqual(cmd_sent[2], "bash")
        self.assertEqual(cmd_sent[3], "-c")

    @patch("subprocess.Popen")
    @patch("shutil.which")
    def test_konsole_requires_e_flag(self, mock_which, mock_popen):
        mock_which.side_effect = lambda cmd: cmd == "konsole"
        neuronix_center.launch_in_terminal(["ls", "-la"])
        mock_popen.assert_called_once()
        args, kwargs = mock_popen.call_args
        cmd_sent = args[0]
        self.assertEqual(cmd_sent[0], "konsole")
        self.assertEqual(cmd_sent[1], "-e")

    @patch("subprocess.Popen")
    @patch("shutil.which")
    def test_gnome_terminal_double_dash(self, mock_which, mock_popen):
        mock_which.side_effect = lambda cmd: cmd == "gnome-terminal"
        neuronix_center.launch_in_terminal(["ls", "-la"])
        mock_popen.assert_called_once()
        args, kwargs = mock_popen.call_args
        cmd_sent = args[0]
        self.assertEqual(cmd_sent[0], "gnome-terminal")
        self.assertEqual(cmd_sent[1], "--")

    @patch("subprocess.Popen")
    @patch("shutil.which")
    def test_xterm_separate_argv(self, mock_which, mock_popen):
        mock_which.side_effect = lambda cmd: cmd == "xterm"
        neuronix_center.launch_in_terminal(["ls", "-la"])
        mock_popen.assert_called_once()
        args, kwargs = mock_popen.call_args
        cmd_sent = args[0]
        self.assertEqual(cmd_sent[0], "xterm")
        self.assertEqual(cmd_sent[1], "-e")
        self.assertEqual(cmd_sent[2], "bash")
        self.assertEqual(cmd_sent[3], "-c")

    @patch("subprocess.Popen")
    @patch("shutil.which")
    def test_terminal_fallback_non_silent(self, mock_which, mock_popen):
        mock_which.return_value = None
        with patch.dict(os.environ, {}, clear=True):
            with patch("sys.stderr.write") as mock_stderr:
                neuronix_center.launch_in_terminal(["echo", "hello"])
                mock_stderr.assert_called()
                err_text = "".join(call[0][0] for call in mock_stderr.call_args_list)
                self.assertIn("Terminal Emulator Unavailable", err_text)
                mock_popen.assert_called_once()


class TestNeuronixCenterGUI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Determine if Tkinter can be initialized
        cls.gui_available = False
        try:
            import tkinter as tk
            root = tk.Tk()
            root.destroy()
            cls.gui_available = True
        except Exception:
            cls.gui_available = False

    def test_gui_instantiation_and_structure(self):
        if not self.gui_available:
            self.skipTest("Tkinter display server unavailable in current execution context")

        import tkinter as tk
        root = tk.Tk()
        try:
            app = neuronix_center.NeuronixControlCenterApp(root)
            self.assertEqual(root.title(), "Conductor")
            self.assertTrue(root.resizable()[0])
            self.assertTrue(root.resizable()[1])

            # Verify 4 progressive disclosure tabs
            tabs = [app.notebook.tab(i, "text") for i in range(app.notebook.index("end"))]
            self.assertEqual(tabs, ["Overview", "System", "Developer", "Advanced"])

            # Verify Status States
            app.set_status("healthy", "Test Healthy")
            self.assertEqual(app.status_text.cget("text"), "Test Healthy")
            app.set_status("working", "Test Working")
            self.assertEqual(app.status_text.cget("text"), "Test Working")
            app.set_status("attention", "Test Attention")
            self.assertEqual(app.status_text.cget("text"), "Test Attention")
            app.set_status("error", "Test Error")
            self.assertEqual(app.status_text.cget("text"), "Test Error")

            # Verify Busy Concurrency Guard
            app._set_busy(True)
            self.assertTrue(app.is_busy)
            self.assertEqual(str(app.btn_upgrade.cget("state")), "disabled")
            app._set_busy(False)
            self.assertFalse(app.is_busy)
            self.assertEqual(str(app.btn_upgrade.cget("state")), "normal")

            # Verify Treeview configuration
            self.assertIn("entry", app.gen_tree["columns"])
        finally:
            root.destroy()


class TestNeuronixCenterCLI(unittest.TestCase):
    def test_run_cli_mode_basic(self):
        args = types.SimpleNamespace(
            list_generations=False,
            diet=False,
            opencode=False,
            rollback=False,
            upgrade=False,
            check_update=False,
            doctor=False,
            welcome=False,
            quickstart=False,
        )
        with patch("sys.stdout.write"):
            neuronix_center.run_cli_mode(args)


if __name__ == "__main__":
    unittest.main()
