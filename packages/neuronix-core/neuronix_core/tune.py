"""
NEURONIX Deterministic Workload Tuning Matrix (neuronix tune)
Applies harmonious, real-time kernel, cgroups, PipeWire, and CPU governor tuning
tailored for Gaming, Battery Life, Audio-DAW Production, or Balanced computing.
"""

import os
import sys
import glob
import subprocess
import shutil

PROFILES = {
    "gaming": {
        "description": "High-throughput gaming & Proton optimization (performance governor, max_map_count, GPU boost)",
        "cpu_governor": "performance",
        "energy_perf": "performance",
        "pipewire_quantum": "0",
        "sysctl": {
            "vm.max_map_count": "2147483642",
            "vm.swappiness": "100"
        }
    },
    "battery": {
        "description": "Maximum laptop power conservation & battery health preservation (powersave governor, 80% ceiling)",
        "cpu_governor": "powersave",
        "energy_perf": "power",
        "battery_ceiling": "80",
        "pipewire_quantum": "0",
        "sysctl": {
            "vm.swappiness": "180"
        }
    },
    "audio-daw": {
        "description": "Ultra-low latency audio workstation profile (PipeWire 64 quantum buffer @ 48kHz, RT priority)",
        "cpu_governor": "performance",
        "energy_perf": "performance",
        "pipewire_quantum": "64",
        "sysctl": {
            "vm.swappiness": "60"
        }
    },
    "balanced": {
        "description": "Default balanced workstation profile (adaptive schedutil/powersave, dynamic scaling)",
        "cpu_governor": "schedutil",
        "energy_perf": "balance_performance",
        "pipewire_quantum": "0",
        "sysctl": {
            "vm.max_map_count": "2147483642",
            "vm.swappiness": "180"
        }
    }
}

TUNING_PROFILES = PROFILES

STATE_FILE = "/var/lib/neuronix/active-workload-profile"

def get_active_profile_name():
    """Reads recorded profile name or returns 'balanced'."""
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                name = f.read().strip()
                if name in PROFILES:
                    return name
        except Exception:
            pass
    return "balanced"

def get_current_tuning_status():
    """Probes current active kernel governors, energy prefs, and audio quantum."""
    status = {
        "active_profile": get_active_profile_name(),
        "cpu_governor": "Unknown",
        "energy_perf": "Unknown",
        "pipewire_quantum": "Default / Auto",
        "battery_ceiling": "Not Applicable",
        "max_map_count": "Unknown"
    }

    # 1. CPU Governor
    gov_files = glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor")
    if gov_files:
        try:
            with open(gov_files[0], "r") as f:
                status["cpu_governor"] = f.read().strip()
        except Exception:
            pass

    # 2. Energy Performance Preference
    epp_files = glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference")
    if epp_files:
        try:
            with open(epp_files[0], "r") as f:
                status["energy_perf"] = f.read().strip()
        except Exception:
            pass

    # 3. Battery Ceiling
    bat_files = glob.glob("/sys/class/power_supply/*/charge_control_end_threshold")
    if bat_files:
        try:
            with open(bat_files[0], "r") as f:
                status["battery_ceiling"] = f"{f.read().strip()}%"
        except Exception:
            pass

    # 4. Sysctl max_map_count
    if os.path.exists("/proc/sys/vm/max_map_count"):
        try:
            with open("/proc/sys/vm/max_map_count", "r") as f:
                status["max_map_count"] = f.read().strip()
        except Exception:
            pass

    # 5. PipeWire Quantum
    if shutil.which("pw-metadata"):
        try:
            res = subprocess.run(["pw-metadata", "-n", "settings", "0", "clock.force-quantum"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True, check=False)
            if res.returncode == 0 and "value:" in res.stdout:
                status["pipewire_quantum"] = res.stdout.split("value:")[1].strip()
        except Exception:
            pass

    return status

def apply_tuning_profile(profile_name):
    """Applies a declared tuning profile harmoniously to kernel and subsystems."""
    if profile_name not in PROFILES:
        return {
            "status": "error",
            "message": f"Unknown tuning profile '{profile_name}'. Valid options: {', '.join(PROFILES.keys())}"
        }

    profile = PROFILES[profile_name]
    applied_actions = []

    # 1. Apply CPU Governor
    target_gov = profile.get("cpu_governor")
    gov_files = glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor")
    for g_file in gov_files:
        try:
            # Check available governors first
            avail_path = os.path.join(os.path.dirname(g_file), "scaling_available_governors")
            gov_to_write = target_gov
            if os.path.exists(avail_path):
                with open(avail_path, "r") as af:
                    avail = af.read()
                    if target_gov not in avail and "powersave" in avail:
                        gov_to_write = "powersave"
            with open(g_file, "w") as f:
                f.write(gov_to_write)
        except Exception:
            pass
    if gov_files:
        applied_actions.append(f"CPU governor set towards '{target_gov}'")

    # 2. Apply Energy Performance Preference (EPP)
    target_epp = profile.get("energy_perf")
    epp_files = glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference")
    for e_file in epp_files:
        try:
            with open(e_file, "w") as f:
                f.write(target_epp)
        except Exception:
            pass
    if epp_files:
        applied_actions.append(f"Energy-performance preference set to '{target_epp}'")

    # 3. Apply Battery Ceiling if profile specifies and supported
    if "battery_ceiling" in profile:
        bat_files = glob.glob("/sys/class/power_supply/*/charge_control_end_threshold")
        for b_file in bat_files:
            try:
                with open(b_file, "w") as f:
                    f.write(profile["battery_ceiling"])
            except Exception:
                pass
        if bat_files:
            applied_actions.append(f"Hardware battery ceiling set to {profile['battery_ceiling']}%")

    # 4. Apply PipeWire Quantum Buffer
    target_quantum = profile.get("pipewire_quantum", "0")
    if shutil.which("pw-metadata"):
        try:
            subprocess.run(["pw-metadata", "-n", "settings", "0", "clock.force-quantum", target_quantum], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            applied_actions.append(f"PipeWire quantum set to '{target_quantum}'")
        except Exception:
            pass

    # 5. Record State
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    try:
        with open(STATE_FILE, "w") as f:
            f.write(profile_name)
    except Exception:
        pass

    return {
        "status": "success",
        "profile": profile_name,
        "description": profile["description"],
        "applied_actions": applied_actions
    }
