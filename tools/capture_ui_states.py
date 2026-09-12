#!/usr/bin/env python3
"""
Captures high-resolution rendered screenshots of NEURONIX Center across all 4 tab surfaces
and primary operational states using Xvfb and ImageMagick import / ffmpeg.
"""

import sys
import os
import time
import subprocess
import shutil

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
center_dir = os.path.join(repo_root, "packages/neuronix-center")
assets_dir = os.path.join(repo_root, "docs/assets")
artifacts_dir = os.path.expanduser("~/.gemini/antigravity/artifacts")
brain_dir = os.path.expanduser("~/.gemini/antigravity/brain/b5df519d-9fea-48e8-a2fd-50575a066515")
os.makedirs(assets_dir, exist_ok=True)
os.makedirs(artifacts_dir, exist_ok=True)

if center_dir not in sys.path:
    sys.path.insert(0, center_dir)

import tkinter as tk
import neuronix_center


def capture(filename):
    out_path = os.path.join(assets_dir, filename)
    # Use ffmpeg or import to capture exact 720x520 window from display
    display = os.environ.get("DISPLAY", ":99")
    cmd = [
        "ffmpeg", "-f", "x11grab",
        "-video_size", "720x520",
        "-draw_mouse", "0",
        "-i", f"{display}+0,0",
        "-vframes", "1",
        "-y", out_path
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    # Copy to artifacts directory
    art_path = os.path.join(artifacts_dir, filename)
    shutil.copy2(out_path, art_path)
    if os.path.exists(brain_dir):
        brain_path = os.path.join(brain_dir, filename)
        shutil.copy2(out_path, brain_path)
    print(f"Captured: {filename} -> {out_path}, {art_path}")


def main():
    root = tk.Tk()
    app = neuronix_center.NeuronixControlCenterApp(root)
    root.geometry("720x520+0+0")
    root.update_idletasks()
    root.update()

    # Wait for telemetry worker to populate
    for _ in range(30):
        root.update_idletasks()
        root.update()
        if not app.is_refreshing and app.ov_os_val.cget("text") != "Reading...":
            break
        time.sleep(0.1)

    time.sleep(0.5)
    root.update_idletasks()
    root.update()

    # 1. Overview Tab (Healthy)
    app.notebook.select(0)
    app.set_status("healthy", "System Healthy")
    root.update_idletasks()
    root.update()
    time.sleep(0.2)
    capture("neuronix_center_overview.png")

    # 2. System Tab
    app.notebook.select(1)
    root.update_idletasks()
    root.update()
    time.sleep(0.2)
    capture("neuronix_center_system.png")

    # 3. Developer Tab
    app.notebook.select(2)
    root.update_idletasks()
    root.update()
    time.sleep(0.2)
    capture("neuronix_center_developer.png")

    # 4. Advanced Tab
    app.notebook.select(3)
    root.update_idletasks()
    root.update()
    time.sleep(0.2)
    capture("neuronix_center_advanced.png")

    # 5. Working State (Overview Tab)
    app.notebook.select(0)
    app.set_status("working", "Staging System Upgrade...")
    app.sys_feedback_lbl.configure(text="Staging system upgrade...")
    root.update_idletasks()
    root.update()
    time.sleep(0.2)
    capture("neuronix_center_working.png")

    # 6. Attention State (Overview Tab)
    app.set_status("attention", "Attention: Updates Pending")
    app.sys_feedback_lbl.configure(text="System updates available for inspection.")
    root.update_idletasks()
    root.update()
    time.sleep(0.2)
    capture("neuronix_center_attention.png")

    root.destroy()
    print("All 6 screenshots successfully rendered and synchronized.")


if __name__ == "__main__":
    main()
