"""
Truthful hardware and operating system telemetry probe.
Extracts metrics directly from sysfs, procfs, and profile symlinks.
"""

import os
import subprocess
import shutil

def get_cpu_info():
    """Extracts CPU model name from /proc/cpuinfo."""
    if os.path.exists("/proc/cpuinfo"):
        try:
            with open("/proc/cpuinfo", "r") as f:
                for line in f:
                    if "model name" in line:
                        return line.split(":")[1].strip()
        except Exception:
            pass
    return "Unknown Processor"

def get_ram_info():
    """Extracts total and available memory from /proc/meminfo."""
    total_mb = 0
    avail_mb = 0
    if os.path.exists("/proc/meminfo"):
        try:
            with open("/proc/meminfo", "r") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        total_mb = int(line.split()[1]) // 1024
                    elif line.startswith("MemAvailable:"):
                        avail_mb = int(line.split()[1]) // 1024
            used_mb = max(0, total_mb - avail_mb)
            return f"{used_mb} MB / {total_mb} MB"
        except Exception:
            pass
    return "Unknown RAM"

def get_storage_info():
    """Calculates disk usage for root mount point."""
    try:
        st = os.statvfs("/")
        total_gb = (st.f_blocks * st.f_frsize) / (1024 ** 3)
        avail_gb = (st.f_bavail * st.f_frsize) / (1024 ** 3)
        used_gb = total_gb - avail_gb
        return f"{used_gb:.1f} GB / {total_gb:.1f} GB"
    except Exception:
        return "Unknown Filesystem"

def get_gpu_info():
    """Detects primary display controller via lspci or sysfs."""
    if shutil.which("lspci"):
        try:
            out = subprocess.check_output(["lspci"], stderr=subprocess.DEVNULL, universal_newlines=True)
            for line in out.splitlines():
                if "VGA compatible controller" in line or "3D controller" in line:
                    parts = line.split("controller:")
                    if len(parts) > 1:
                        return parts[1].strip()
        except Exception:
            pass
    return "Integrated / Standard Display"

def get_battery_info():
    """Probes battery charging status and health from /sys/class/power_supply."""
    base = "/sys/class/power_supply"
    if os.path.isdir(base):
        for entry in os.listdir(base):
            if entry.startswith("BAT"):
                cap_file = os.path.join(base, entry, "capacity")
                status_file = os.path.join(base, entry, "status")
                if os.path.exists(cap_file):
                    try:
                        with open(cap_file, "r") as f:
                            cap = f.read().strip()
                        status = "Discharging"
                        if os.path.exists(status_file):
                            with open(status_file, "r") as sf:
                                status = sf.read().strip()
                        return f"{cap}% ({status})"
                    except Exception:
                        pass
    return "AC Power / Bare-Metal"

def get_battery_limit():
    """Probes battery charge control ceiling if supported by kernel sysfs."""
    import glob
    battery_limit_paths = glob.glob("/sys/class/power_supply/*/charge_control_end_threshold") + \
                          glob.glob("/sys/class/power_supply/*/charge_control_limit_max") + \
                          glob.glob("/sys/class/power_supply/*/charge_stop_threshold")
    if battery_limit_paths:
        try:
            with open(battery_limit_paths[0], "r") as f:
                val = f.read().strip()
                return f"{val}% Active Hardware Ceiling"
        except Exception:
            return "Supported (Unset)"
    return "Not Supported (AC / Bare-Metal)"

def get_system_telemetry():
    """Probes complete truthful system runtime telemetry."""
    from .generation import get_active_generation
    return {
        "os": "NEURONIX OS (Declarative NixOS Substrate)",
        "kernel": os.uname().release if hasattr(os, "uname") else "Linux",
        "generation": get_active_generation(),
        "cpu": get_cpu_info(),
        "ram": get_ram_info(),
        "storage": get_storage_info(),
        "gpu": get_gpu_info(),
        "battery": get_battery_info(),
        "battery_limit": get_battery_limit()
    }
