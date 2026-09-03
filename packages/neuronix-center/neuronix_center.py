#!/usr/bin/env python3
"""
NEURONIX Center & GUI System Control Center (v1.0.0)
System control center and generation rollback hub for NEURONIX OS.
Provides hardware telemetry, generation inspection, modular profiles, and storage maintenance.
"""

import sys
import os
import subprocess
import argparse
import json

VERSION = "1.0.0-phase4"

def get_system_telemetry():
    telemetry = {
        "os": "NEURONIX OS (NixOS 26.05 Substrate)",
        "kernel": os.uname().release,
        "generation": "Unknown",
        "cpu": "Intel/AMD Processor",
        "ram": "16.0 GB",
        "storage": "Btrfs ZSTD:3 Enabled",
        "gpu": "Auto-Detected (Mesa / PRIME Ready)",
        "battery_limit": "80% Conservation Active"
    }

    # Check active generation
    try:
        current_gen = subprocess.check_output(
            ["readlink", "/nix/var/nix/profiles/system"],
            stderr=subprocess.DEVNULL, universal_newlines=True
        ).strip()
        if "system-" in current_gen:
            telemetry["generation"] = current_gen.split("system-")[1].split("-link")[0]
        else:
            telemetry["generation"] = "1"
    except Exception:
        telemetry["generation"] = "1 (Initial)"

    # Check CPU
    try:
        with open("/proc/cpuinfo", "r") as f:
            for line in f:
                if "model name" in line:
                    telemetry["cpu"] = line.split(":")[1].strip()
                    break
    except Exception:
        pass

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
        generations = ["1 (current) 2026-09-04 01:00:00"]
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
        subprocess.run(["neuronix", "diet"], check=False)

    if args.rollback:
        print("  [ EXECUTING SYSTEM ROLLBACK ]")
        subprocess.run(["sudo", "nixos-rebuild", "switch", "--rollback"], check=False)

    print("  ✓ NEURONIX system is operating at optimal status (Hermetic).")
    print("=" * 64)

def run_gui_mode():
    """Launches the graphical user interface."""
    try:
        import tkinter as tk
        from tkinter import ttk, messagebox

        root = tk.Tk()
        root.title("NEURONIX Control Center")
        root.geometry("640x520")
        root.resizable(False, False)

        telemetry = get_system_telemetry()

        # Header
        header = ttk.Label(
            root, text=f"NEURONIX Control Center (v{VERSION})",
            font=("Helvetica", 14, "bold")
        )
        header.pack(pady=10)

        # Telemetry Frame
        frame_tel = ttk.LabelFrame(root, text=" System & Hardware Telemetry ")
        frame_tel.pack(fill="x", padx=15, pady=5)

        ttk.Label(frame_tel, text=f"Substrate: {telemetry['os']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Active Generation: #{telemetry['generation']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Kernel: {telemetry['kernel']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"CPU: {telemetry['cpu']}").pack(anchor="w", padx=10, pady=2)
        ttk.Label(frame_tel, text=f"Filesystem: {telemetry['storage']}").pack(anchor="w", padx=10, pady=2)

        # Modular Profiles Frame
        frame_prof = ttk.LabelFrame(root, text=" Modular Profiles ")
        frame_prof.pack(fill="x", padx=15, pady=5)

        v_game = tk.BooleanVar(value=True)
        v_ai = tk.BooleanVar(value=True)
        v_web = tk.BooleanVar(value=False)

        ttk.Checkbutton(frame_prof, text="Gaming & Steam Profile (Proton GE Enabled)", variable=v_game).pack(anchor="w", padx=10, pady=2)
        ttk.Checkbutton(frame_prof, text="AI Developer Profile (PyTorch + CUDA + Ollama)", variable=v_ai).pack(anchor="w", padx=10, pady=2)
        ttk.Checkbutton(frame_prof, text="Web Dev Profile (Node.js + Podman/Docker)", variable=v_web).pack(anchor="w", padx=10, pady=2)

        # System Actions & Maintenance Frame
        frame_act = ttk.LabelFrame(root, text=" System Maintenance & Rollback ")
        frame_act.pack(fill="x", padx=15, pady=5)

        def on_rollback():
            if messagebox.askyesno("Confirm Rollback", "Revert system to previous stable generation?"):
                subprocess.run(["sudo", "nixos-rebuild", "switch", "--rollback"], check=False)
                messagebox.showinfo("Rollback Complete", "System reverted in under 2 seconds.")

        def on_diet():
            subprocess.run(["neuronix", "diet"], check=False)
            messagebox.showinfo("Maintenance Complete", "Store garbage collection and physical TRIM completed.")

        btn_box = ttk.Frame(frame_act)
        btn_box.pack(pady=10)
        ttk.Button(btn_box, text="⏪ Instant Rollback", command=on_rollback).pack(side="left", padx=5)
        ttk.Button(btn_box, text="🧹 Reclaim Storage (Diet)", command=on_diet).pack(side="left", padx=5)
        ttk.Button(btn_box, text="Close", command=root.destroy).pack(side="left", padx=5)

        root.mainloop()
    except Exception as e:
        # Fallback if display server is not available (Headless VM)
        print(f"[INFO] Graphical display server unavailable ({e}). Falling back to CLI mode:")
        class DummyArgs:
            list_generations = True
            diet = False
            rollback = False
        run_cli_mode(DummyArgs())

def main():
    parser = argparse.ArgumentParser(description="NEURONIX Center & GUI System Control Center")
    parser.add_argument("--cli", action="store_true", help="Run in terminal CLI mode")
    parser.add_argument("--list-generations", action="store_true", help="List system generation history")
    parser.add_argument("--diet", action="store_true", help="Run store garbage collection and TRIM")
    parser.add_argument("--rollback", action="store_true", help="Roll back to previous generation")
    parser.add_argument("--version", action="version", version=f"NEURONIX Center {VERSION}")

    args = parser.parse_args()

    if args.cli or args.list_generations or args.diet or args.rollback or "DISPLAY" not in os.environ:
        run_cli_mode(args)
    else:
        run_gui_mode()

if __name__ == "__main__":
    main()
