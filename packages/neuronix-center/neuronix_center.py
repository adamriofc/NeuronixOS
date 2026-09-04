#!/usr/bin/env python3
"""
NEURONIX Center & GUI System Control Center
Truthful system telemetry, modular developer environments, and atomic rollback hub.
All telemetry is probed directly from Linux kernel sysfs, /proc, and Nix profiles.
"""

import sys
import os
import time
import subprocess
import argparse
import glob

VERSION = "1.0.3"
try:
    _vfile = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../version.nix")
    if os.path.exists(_vfile):
        with open(_vfile, "r") as _f:
            for _line in _f:
                if "version =" in _line:
                    VERSION = _line.split('"')[1]
                    break
except Exception:
    pass

def get_neuronix_cmd():
    import shutil
    if shutil.which("neuronix"):
        return ["neuronix"]
    repo_bin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../src/neuronix")
    if os.path.exists(repo_bin):
        return ["bash", repo_bin]
    return ["neuronix"]

def get_system_telemetry():
    """Probes runtime system telemetry truthfully without hardcoded mock values."""
    telemetry = {
        "os": "NEURONIX OS (Declarative NixOS Substrate)",
        "kernel": os.uname().release,
        "generation": "Unknown",
        "cpu": "Unknown Processor",
        "ram": "Unknown",
        "storage": "Unknown Filesystem",
        "gpu": "Not Detected",
        "battery_limit": "Not Supported (AC / Bare-Metal)"
    }

    # 1. Probing Active NixOS Generation
    try:
        current_gen = subprocess.check_output(
            ["readlink", "/nix/var/nix/profiles/system"],
            stderr=subprocess.DEVNULL, universal_newlines=True
        ).strip()
        if "system-" in current_gen:
            telemetry["generation"] = current_gen.split("system-")[1].split("-link")[0]
        else:
            telemetry["generation"] = "Unknown"
    except Exception:
        telemetry["generation"] = "Unknown"

    # 2. Probing Real Physical CPU
    try:
        with open("/proc/cpuinfo", "r") as f:
            for line in f:
                if "model name" in line:
                    telemetry["cpu"] = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass

    # 3. Probing Real Physical RAM from /proc/meminfo
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    parts = line.split()
                    kb = int(parts[1])
                    gib = kb / (1024 * 1024)
                    telemetry["ram"] = f"{gib:.1f} GiB Total"
                    break
    except Exception:
        telemetry["ram"] = "Unknown"

    # 4. Probing Real Root Filesystem and Mount Options
    try:
        out = subprocess.check_output(
            ["findmnt", "-n", "-o", "FSTYPE,OPTIONS", "/"],
            stderr=subprocess.DEVNULL, universal_newlines=True
        ).strip()
        if out:
            parts = out.split(None, 1)
            fstype = parts[0].upper()
            opts = parts[1] if len(parts) > 1 else ""
            if "compress=zstd" in opts:
                telemetry["storage"] = f"{fstype} (ZSTD Compression Active)"
            else:
                telemetry["storage"] = f"{fstype} ({opts.split(',')[0] if opts else 'standard'})"
    except Exception:
        # Fallback to /proc/mounts
        try:
            with open("/proc/mounts", "r") as f:
                for line in f:
                    fields = line.split()
                    if len(fields) >= 3 and fields[1] == "/":
                        telemetry["storage"] = f"{fields[2].upper()} (Mounted /)"
                        break
        except Exception:
            telemetry["storage"] = "Unknown Filesystem"

    # 5. Probing Real GPU / Display Controller
    try:
        lspci_out = subprocess.check_output(
            ["lspci"], stderr=subprocess.DEVNULL, universal_newlines=True
        )
        for line in lspci_out.splitlines():
            if "VGA compatible controller" in line or "3D controller" in line:
                gpu_desc = line.split(":", 2)[-1].strip()
                telemetry["gpu"] = gpu_desc
                break
    except Exception:
        # Fallback check sysfs DRM
        drm_cards = glob.glob("/sys/class/drm/card*")
        if drm_cards:
            telemetry["gpu"] = "Kernel DRM Display Controller Active"
        else:
            telemetry["gpu"] = "Not Detected"

    # 6. Probing Real Battery Charge Threshold
    battery_limit_paths = glob.glob("/sys/class/power_supply/*/charge_control_limit_max") + \
                          glob.glob("/sys/class/power_supply/*/charge_control_end_threshold")
    if battery_limit_paths:
        try:
            with open(battery_limit_paths[0], "r") as f:
                val = f.read().strip()
                telemetry["battery_limit"] = f"{val}% Active Hardware Ceiling"
        except Exception:
            telemetry["battery_limit"] = "Supported (Unset)"
    else:
        telemetry["battery_limit"] = "Not Supported (AC / Bare-Metal)"

    return telemetry

def list_generations():
    """Returns the list of system generations."""
    generations = []
    try:
        out = subprocess.check_output(
            ["nix-env", "--list-generations", "-p", "/nix/var/nix/profiles/system"],
            stderr=subprocess.DEVNULL, universal_newlines=True
        )
        for line in out.strip().split("\n"):
            if line:
                generations.append(line.strip())
    except Exception:
        pass
    if not generations:
        generations = ["Generation data unavailable (no active profile links found)"]
    return generations

def run_cli_mode(args):
    """Executes NEURONIX Center in CLI / headless mode."""
    telemetry = get_system_telemetry()
    print("=" * 64)
    print(f"  NEURONIX CONTROL CENTER & SYSTEM HUB (v{VERSION})")
    print("=" * 64)
    print(f"  ● Operating System : {telemetry['os']}")
    print(f"  ● Kernel Version   : {telemetry['kernel']}")
    print(f"  ● Active Generation: #{telemetry['generation']}")
    print(f"  ● Processor (CPU)  : {telemetry['cpu']}")
    print(f"  ● Physical Memory  : {telemetry['ram']}")
    print(f"  ● Display Adapter  : {telemetry['gpu']}")
    print(f"  ● Storage Format   : {telemetry['storage']}")
    print(f"  ● Battery Limit    : {telemetry['battery_limit']}")
    print("-" * 64)

    if args.list_generations:
        print("  [ SYSTEM GENERATION TIMELINE ]")
        for gen in list_generations():
            print(f"    {gen}")
        print("-" * 64)

    if args.diet:
        print("  [ RUNNING STORAGE MAINTENANCE (DIET) ]")
        res = subprocess.run(get_neuronix_cmd() + ["diet"], check=False)
        if res.returncode != 0:
            print(f"  ✗ Storage maintenance exited with code {res.returncode}.")

    if getattr(args, 'upgrade', False):
        print("  [ RUNNING STAGED SYSTEM UPGRADE ]")
        res = subprocess.run(get_neuronix_cmd() + ["upgrade", "--staged"], check=False)
        if res.returncode != 0:
            print(f"  ✗ System upgrade exited with code {res.returncode}.")

    if getattr(args, 'check_update', False):
        print("  [ CHECKING FOR UPSTREAM SYSTEM UPDATES ]")
        res = subprocess.run(get_neuronix_cmd() + ["check-update"], check=False)
        if res.returncode != 0:
            print(f"  ✗ Update check exited with code {res.returncode}.")

    if getattr(args, 'doctor', False):
        print("  [ RUNNING SYSTEM DOCTOR & DIAGNOSTICS ]")
        res = subprocess.run(get_neuronix_cmd() + ["doctor"], check=False)
        if res.returncode != 0:
            print(f"  ✗ System doctor exited with code {res.returncode}.")

    if getattr(args, 'welcome', False):
        print("  [ LAUNCHING ONBOARDING WELCOME EXPERIENCE ]")
        res = subprocess.run(get_neuronix_cmd() + ["welcome", "--cli"], check=False)
        if res.returncode != 0:
            print(f"  ✗ Welcome experience exited with code {res.returncode}.")

    if getattr(args, 'quickstart', False):
        print("  [ LAUNCHING QUICKSTART APP HUB ]")
        res = subprocess.run(get_neuronix_cmd() + ["quickstart", "list"], check=False)
        if res.returncode != 0:
            print(f"  ✗ Quickstart catalog exited with code {res.returncode}.")

    if args.opencode:
        print("  [ LAUNCHING OPENCODE AI SYSTEM COPILOT ]")
        try:
            res = subprocess.run(["opencode", "status"], check=False)
            if res.returncode != 0:
                print(f"  ✗ OpenCode status exited with code {res.returncode}.")
        except FileNotFoundError:
            print("  [INFO] OpenCode binary not found in PATH. Ensure neuronix.services.opencode.enable = true.")

    if args.rollback:
        print("  [ EXECUTING SYSTEM ROLLBACK ]")
        start_t = time.monotonic()
        res = subprocess.run(["sudo", "nixos-rebuild", "switch", "--rollback"], check=False)
        elapsed = time.monotonic() - start_t
        if res.returncode == 0:
            print(f"  ✓ System successfully reverted to previous generation in {elapsed:.2f}s.")
        else:
            print(f"  ✗ Rollback command exited with code {res.returncode}.")

    print("  ● Telemetry stream: Live Linux kernel sysfs, /proc, and Nix profile state.")
    print("=" * 64)

def run_gui_mode():
    """Launches the graphical user interface."""
    try:
        import tkinter as tk
        from tkinter import ttk, messagebox

        root = tk.Tk()
        root.title("NEURONIX Control Center")
        root.geometry("680x560")
        root.resizable(False, False)

        telemetry = get_system_telemetry()

        # Header
        header = ttk.Label(
            root, text=f"NEURONIX Control Center (v{VERSION})",
            font=("Helvetica", 14, "bold")
        )
        header.pack(pady=10)

        # Telemetry Frame
        frame_tel = ttk.LabelFrame(root, text=" Live Hardware & Kernel Telemetry ")
        frame_tel.pack(fill="x", padx=15, pady=5)

        ttk.Label(frame_tel, text=f"Operating System : {telemetry['os']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Kernel Version   : {telemetry['kernel']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Active Generation: #{telemetry['generation']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Processor (CPU)  : {telemetry['cpu']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Physical Memory  : {telemetry['ram']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Display Adapter  : {telemetry['gpu']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Root Filesystem  : {telemetry['storage']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Battery Ceiling  : {telemetry['battery_limit']}").pack(anchor="w", padx=10, pady=2)

        # Modular Profiles Frame
        frame_prof = ttk.LabelFrame(root, text=" Developer Substrate & AI Copilot ")
        frame_prof.pack(fill="x", padx=15, pady=5)

        ttk.Label(frame_prof, text="Launch isolated hermetic developer environments or OpenCode AI Copilot:").pack(anchor="w", padx=10, pady=2)

        dev_box = ttk.Frame(frame_prof)
        dev_box.pack(pady=5, padx=10, fill="x")

        def launch_stack(stack_name):
            subprocess.Popen(["x-terminal-emulator", "-e", f"neuronix dev {stack_name}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def launch_opencode():
            subprocess.Popen(["x-terminal-emulator", "-e", "opencode interactive"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        ttk.Button(dev_box, text="OpenCode AI", command=launch_opencode).pack(side="left", padx=4)
        ttk.Button(dev_box, text="Python (uv)", command=lambda: launch_stack("python")).pack(side="left", padx=4)
        ttk.Button(dev_box, text="Rust (cargo)", command=lambda: launch_stack("rust")).pack(side="left", padx=4)
        ttk.Button(dev_box, text="Node (pnpm)", command=lambda: launch_stack("node")).pack(side="left", padx=4)
        ttk.Button(dev_box, text="AI (PyTorch)", command=lambda: launch_stack("ai")).pack(side="left", padx=4)

        # System Actions & Maintenance Frame
        frame_act = ttk.LabelFrame(root, text=" System Maintenance & Atomic Rollback ")
        frame_act.pack(fill="x", padx=15, pady=5)

        def on_upgrade():
            if messagebox.askyesno("Confirm System Upgrade", "Prepare and stage system upgrade for next reboot (zero session disruption)?"):
                start_t = time.monotonic()
                res = subprocess.run(["neuronix", "upgrade", "--staged"], check=False)
                elapsed = time.monotonic() - start_t
                if res.returncode == 0:
                    messagebox.showinfo("Upgrade Staged", f"System upgrade staged successfully in {elapsed:.2f} seconds.\nNew generation will activate on next reboot.")
                else:
                    messagebox.showerror("Upgrade Failed", f"Upgrade operation exited with code {res.returncode}.")

        def on_rollback():
            if messagebox.askyesno("Confirm Rollback", "Revert system to previous stable NixOS generation?"):
                start_t = time.monotonic()
                res = subprocess.run(["sudo", "nixos-rebuild", "switch", "--rollback"], check=False)
                elapsed = time.monotonic() - start_t
                if res.returncode == 0:
                    messagebox.showinfo("Rollback Complete", f"System reverted successfully in {elapsed:.2f} seconds.")
                else:
                    messagebox.showerror("Rollback Failed", f"Rollback exited with code {res.returncode}.")

        def on_diet():
            start_t = time.monotonic()
            res = subprocess.run(["neuronix", "diet"], check=False)
            elapsed = time.monotonic() - start_t
            if res.returncode == 0:
                messagebox.showinfo("Diet Complete", f"Storage reclaimed successfully in {elapsed:.2f} seconds.")
            else:
                messagebox.showerror("Diet Failed", f"Diet operation exited with code {res.returncode}.")

        def on_doctor():
            subprocess.Popen(["x-terminal-emulator", "-e", "neuronix doctor"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def on_quickstart():
            subprocess.Popen(["x-terminal-emulator", "-e", "neuronix quickstart list"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        btn_box = ttk.Frame(frame_act)
        btn_box.pack(pady=5, padx=10, fill="x")

        ttk.Button(btn_box, text="🔄 System Upgrade", command=on_upgrade).pack(side="left", padx=4)
        ttk.Button(btn_box, text="↩ Rollback", command=on_rollback).pack(side="left", padx=4)
        ttk.Button(btn_box, text="🧹 Diet", command=on_diet).pack(side="left", padx=4)
        ttk.Button(btn_box, text="🩺 Doctor", command=on_doctor).pack(side="left", padx=4)
        ttk.Button(btn_box, text="📦 Quickstart", command=on_quickstart).pack(side="left", padx=4)
        ttk.Button(btn_box, text="Close", command=root.destroy).pack(side="left", padx=4)

        root.mainloop()
    except Exception as e:
        # Fallback if display server is not available (Headless VM)
        print(f"[INFO] Graphical display server unavailable ({e}). Falling back to CLI mode:")
        class DummyArgs:
            list_generations = True
            diet = False
            opencode = False
            rollback = False
            upgrade = False
            check_update = False
            doctor = False
            welcome = False
            quickstart = False
        run_cli_mode(DummyArgs())

def main():
    parser = argparse.ArgumentParser(description="NEURONIX Center & GUI System Control Center")
    parser.add_argument("--cli", action="store_true", help="Run in terminal CLI mode")
    parser.add_argument("--list-generations", action="store_true", help="List system generation history")
    parser.add_argument("--diet", action="store_true", help="Run store garbage collection and TRIM")
    parser.add_argument("--opencode", action="store_true", help="Launch or check OpenCode AI System Assistant")
    parser.add_argument("--rollback", action="store_true", help="Roll back to previous generation")
    parser.add_argument("--upgrade", action="store_true", help="Perform staged system upgrade")
    parser.add_argument("--check-update", action="store_true", help="Check for available upstream updates")
    parser.add_argument("--doctor", action="store_true", help="Run deep diagnostic and issue reporting tool")
    parser.add_argument("--welcome", action="store_true", help="Launch interactive first-boot onboarding guide")
    parser.add_argument("--quickstart", action="store_true", help="Explore curated daily apps catalog (Flatpak)")
    parser.add_argument("--version", action="version", version=f"NEURONIX Center {VERSION}")

    args = parser.parse_args()

    if args.cli or args.list_generations or args.diet or args.opencode or args.rollback or args.upgrade or args.check_update or args.doctor or args.welcome or args.quickstart or "DISPLAY" not in os.environ:
        run_cli_mode(args)
    else:
        run_gui_mode()

if __name__ == "__main__":
    main()
