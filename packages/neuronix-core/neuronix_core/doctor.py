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
import socket
import urllib.request
from typing import Dict, Any, Optional
from .generation import get_active_generation, list_generations

SCHEMA_VERSION = "1.0.0"

class HealthStatus:
    PASS = "PASS"
    WARN = "WARN"
    FAIL = "FAIL"
    UNKNOWN = "UNKNOWN"
    UNSUPPORTED = "UNSUPPORTED"

def check_connectivity(timeout: float = 2.0) -> Dict[str, Any]:
    """
    Evaluates 3-stage network connectivity:
    1. Layer 2/3 Link default route
    2. Layer 7 DNS resolution (cache.nixos.org)
    3. Layer 7 HTTPS TLS handshake (https://cache.nixos.org)
    """
    has_link = False
    dns_ok = False
    https_ok = False
    diag_detail = ""

    # 1. Link route check
    try:
        with open("/proc/net/route", "r") as f:
            for line in f.readlines()[1:]:
                fields = line.strip().split()
                if len(fields) >= 2 and fields[1] == "00000000":
                    has_link = True
                    break
    except Exception:
        has_link = True  # Fallback if /proc/net/route is restricted

    # 2. DNS check
    try:
        dns_res = socket.getaddrinfo("cache.nixos.org", 443, socket.AF_UNSPEC, socket.SOCK_STREAM)
        if dns_res:
            dns_ok = True
    except Exception as e:
        diag_detail = f"DNS resolution failed: {e}"

    # 3. HTTPS check
    if dns_ok:
        try:
            req = urllib.request.Request(
                "https://cache.nixos.org",
                headers={"User-Agent": "NEURONIX-Doctor-Probe"}
            )
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                if resp.status in (200, 301, 302):
                    https_ok = True
        except Exception as e:
            diag_detail = f"HTTPS handshake failed: {e}"

    if has_link and dns_ok and https_ok:
        status = HealthStatus.PASS
        summary = "Full Internet & Nix Cache Egress Verified"
    elif has_link and dns_ok and not https_ok:
        status = HealthStatus.WARN
        summary = f"DNS operational, but HTTPS egress restricted ({diag_detail})"
    elif has_link and not dns_ok:
        status = HealthStatus.FAIL
        summary = f"Default route active, but DNS resolution failed ({diag_detail})"
    else:
        status = HealthStatus.FAIL
        summary = "No default network route detected (offline)"

    return {
        "status": status,
        "summary": summary,
        "details": {
            "link_route": has_link,
            "dns_resolution": dns_ok,
            "https_egress": https_ok
        }
    }

def get_sanitized_diagnostics(share_mode: bool = False) -> Dict[str, Any]:
    """
    Collects system diagnostics conforming to schema 1.0.0 with sensitive
    user identifiers (username, hostname, internal IP/MAC) sanitized.
    When share_mode is True, aggressively strips all environmental IDs and private paths.
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
    root_free_gb = 100.0
    try:
        st = os.statvfs("/")
        root_free_gb = (st.f_bavail * st.f_frsize) / (1024 ** 3)
        total_gb = (st.f_blocks * st.f_frsize) / (1024 ** 3)
        used_gb = total_gb - root_free_gb
        root_stat = f"{used_gb:.1f}G/{total_gb:.1f}G"
    except Exception:
        pass

    store_stat = "N/A"
    store_free_gb = 100.0
    if os.path.exists("/nix/store"):
        try:
            st = os.statvfs("/nix/store")
            store_free_gb = (st.f_bavail * st.f_frsize) / (1024 ** 3)
            total_gb = (st.f_blocks * st.f_frsize) / (1024 ** 3)
            used_gb = total_gb - store_free_gb
            store_stat = f"{used_gb:.1f}G/{total_gb:.1f}G"
        except Exception:
            pass

    # Subsystem: Storage evaluation
    if root_free_gb < 1.0 or store_free_gb < 1.0:
        storage_status = HealthStatus.FAIL
        storage_summary = "Critical storage shortage (under 1.0 GiB remaining)"
    elif root_free_gb < 3.0 or store_free_gb < 3.0:
        storage_status = HealthStatus.WARN
        storage_summary = "Low storage headroom (under 3.0 GiB remaining)"
    else:
        storage_status = HealthStatus.PASS
        storage_summary = "Ample storage headroom available"

    # Subsystem: Kernel
    kernel_status = HealthStatus.PASS if uname.release else HealthStatus.UNKNOWN

    # Subsystem: Generation
    if active_gen is not None and str(active_gen).isdigit():
        generation_status = HealthStatus.PASS
    else:
        generation_status = HealthStatus.FAIL

    # Subsystem: Network
    net_eval = check_connectivity()
    network_status = net_eval["status"]

    # Subsystem: Battery
    battery_status = HealthStatus.UNSUPPORTED
    base_batt = "/sys/class/power_supply"
    if os.path.exists(base_batt):
        bats = [b for b in os.listdir(base_batt) if b.startswith("BAT")]
        if bats:
            battery_status = HealthStatus.WARN
            for b in bats:
                b_path = os.path.join(base_batt, b)
                for node in ["charge_control_end_threshold", "charge_control_limit_max", "charge_stop_threshold"]:
                    if os.path.exists(os.path.join(b_path, node)):
                        battery_status = HealthStatus.PASS
                        break

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

    timer_status = HealthStatus.PASS if any(v == "active" for v in timers.values()) else HealthStatus.WARN

    # Subsystem evaluations map
    evaluations = {
        "storage": {"status": storage_status, "summary": storage_summary},
        "kernel": {"status": kernel_status, "summary": f"Kernel {uname.release}"},
        "generation": {"status": generation_status, "summary": f"Active Gen #{active_gen}"},
        "network": {"status": network_status, "summary": net_eval["summary"]},
        "battery": {"status": battery_status, "summary": "Battery charge threshold interface"},
        "timers": {"status": timer_status, "summary": "Maintenance timers"}
    }

    # Aggregate overall health
    statuses = [v["status"] for v in evaluations.values()]
    if HealthStatus.FAIL in statuses:
        overall_health = "UNHEALTHY"
        overall_code = HealthStatus.FAIL
    elif HealthStatus.WARN in statuses:
        overall_health = "DEGRADED"
        overall_code = HealthStatus.WARN
    else:
        overall_health = "HEALTHY"
        overall_code = HealthStatus.PASS

    return {
        "schema_version": SCHEMA_VERSION,
        "health_status": overall_health,
        "health_code": overall_code,
        "subsystems": evaluations,
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
            "environment": "<redacted>" if share_mode else os.environ.get("XDG_CURRENT_DESKTOP", "Terminal/Headless"),
            "session": "<redacted>" if share_mode else os.environ.get("XDG_SESSION_TYPE", "tty")
        },
        "maintenance_timers": timers,
        "privacy": {
            "user": "<sanitized-user>",
            "host": "<sanitized-host>",
            "network_status": "Privacy-Preserving Audit Mode" if share_mode else net_eval["summary"],
            "share_mode": share_mode
        }
    }

def print_doctor_json(share_mode: bool = False) -> None:
    """Outputs serialized doctor JSON report to stdout."""
    diag = get_sanitized_diagnostics(share_mode=share_mode)
    sys.stdout.write(json.dumps(diag, indent=2) + "\n")
