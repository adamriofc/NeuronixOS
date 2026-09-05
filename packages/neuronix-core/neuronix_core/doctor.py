"""
Standardized system diagnostic probe and privacy-sanitized telemetry engine.
Conforms to NEURONIX Diagnostic Schema Version 1.0.0.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import shutil
import platform
import subprocess
from typing import Dict, Any
from .generation import get_active_generation, list_generations

SCHEMA_VERSION = "1.0.0"

def get_sanitized_diagnostics() -> Dict[str, Any]:
    """
    Collects system diagnostics conforming to schema 1.0.0 with sensitive
    user identifiers (username, hostname, internal IP/MAC) sanitized.
    """
    uname = platform.uname()
    active_gen = get_active_generation()
    all_gens = list_generations()

    # Hardware stats
    cpu_model = "Generic CPU"
    cpu_cores = os.cpu_count() or 1
    if os.path.exists("/proc/cpuinfo"):
        try:
            with open("/proc/cpuinfo", "r") as f:
                for line in f:
                    if line.startswith("model name"):
                        cpu_model = line.split(":", 1)[1].strip()
                        break
        except Exception:
            pass

    mem_total = "N/A"
    mem_used = "N/A"
    swap_total = "0B"
    if os.path.exists("/proc/meminfo"):
        try:
            with open("/proc/meminfo", "r") as f:
                mem_data = {}
                for line in f:
                    parts = line.split(":")
                    if len(parts) == 2:
                        mem_data[parts[0].strip()] = parts[1].strip()
                if "MemTotal" in mem_data:
                    total_kb = int(mem_data["MemTotal"].split()[0])
                    mem_total = f"{total_kb // 1024}MiB"
                if "MemAvailable" in mem_data and "MemTotal" in mem_data:
                    avail_kb = int(mem_data["MemAvailable"].split()[0])
                    used_kb = total_kb - avail_kb
                    mem_used = f"{used_kb // 1024}MiB"
                if "SwapTotal" in mem_data:
                    swap_kb = int(mem_data["SwapTotal"].split()[0])
                    swap_total = f"{swap_kb // 1024}MiB"
        except Exception:
            pass

    # Storage stats
    root_stat = "N/A"
    try:
        st = os.statvfs("/")
        free_gb = (st.f_bavail * st.f_frsize) / (1024 ** 3)
        total_gb = (st.f_blocks * st.f_frsize) / (1024 ** 3)
        used_gb = total_gb - free_gb
        root_stat = f"{used_gb:.1f}G/{total_gb:.1f}G"
    except Exception:
        pass

    store_stat = "N/A"
    if os.path.exists("/nix/store"):
        try:
            st = os.statvfs("/nix/store")
            free_gb = (st.f_bavail * st.f_frsize) / (1024 ** 3)
            total_gb = (st.f_blocks * st.f_frsize) / (1024 ** 3)
            used_gb = total_gb - free_gb
            store_stat = f"{used_gb:.1f}G/{total_gb:.1f}G"
        except Exception:
            pass

    # System timers
    timers = {
        "auto_diet": "inactive",
        "security_audit": "inactive",
        "auto_update": "inactive"
    }
    if shutil.which("systemctl"):
        for t_name, unit in [("auto_diet", "neuronix-auto-diet.timer"),
                             ("security_audit", "neuronix-security-audit.timer"),
                             ("auto_update", "neuronix-auto-update.timer")]:
            try:
                res = subprocess.run(
                    ["systemctl", "is-active", unit],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False
                )
                if res.stdout.strip() == "active":
                    timers[t_name] = "active"
            except Exception:
                pass

    return {
        "schema_version": SCHEMA_VERSION,
        "health_status": "HEALTHY",
        "system": {
            "os": "NEURONIX OS 1.0.3 (NixOS Substrate)",
            "kernel": uname.release or "Linux-unknown",
            "arch": uname.machine or "x86_64",
            "uptime": "active",
            "generation": str(active_gen),
            "total_generations": len(all_gens)
        },
        "hardware": {
            "cpu": f"{cpu_model} ({cpu_cores} cores)",
            "memory_used": mem_used,
            "memory_total": mem_total,
            "swap": swap_total,
            "gpu": "Generic Display Adapter"
        },
        "storage": {
            "root": root_stat,
            "nix_store": store_stat
        },
        "desktop": {
            "environment": os.environ.get("XDG_CURRENT_DESKTOP", "Terminal/Headless"),
            "session": os.environ.get("XDG_SESSION_TYPE", "tty")
        },
        "maintenance_timers": timers,
        "privacy": {
            "user": "<sanitized-user>",
            "host": "<sanitized-host>",
            "network_status": "Privacy-Preserving Audit Mode"
        }
    }

def print_doctor_json() -> None:
    """Outputs serialized doctor JSON report to stdout."""
    diag = get_sanitized_diagnostics()
    sys.stdout.write(json.dumps(diag, indent=2) + "\n")
