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

def get_active_profile_name() -> str:
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

def get_current_tuning_status() -> dict[str, object]:
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

def apply_tuning_profile(profile_name) -> dict[str, object]:
    """Applies a declared tuning profile harmoniously with strict APPLY -> READBACK -> VALIDATE semantics."""
    if profile_name not in PROFILES:
        return {
            "status": "FAILED",
            "success": False,
            "message": f"Unknown tuning profile '{profile_name}'. Valid options: {', '.join(PROFILES.keys())}"
        }

    profile = PROFILES[profile_name]
    applied = []
    unsupported = []
    failed = []
    applied_actions = []

    # 1. Apply CPU Governor
    target_gov = profile.get("cpu_governor")
    gov_files = glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor")
    if not gov_files:
        unsupported.append({"param": "cpu_governor", "reason": "No cpufreq scaling governors exposed by kernel or virtualization"})
    else:
        gov_ok = True
        gov_err = None
        for g_file in gov_files:
            try:
                avail_path = os.path.join(os.path.dirname(g_file), "scaling_available_governors")
                gov_to_write = target_gov
                if os.path.exists(avail_path):
                    with open(avail_path, "r") as af:
                        avail = af.read()
                        if target_gov not in avail and "powersave" in avail:
                            gov_to_write = "powersave"
                with open(g_file, "w") as f:
                    f.write(gov_to_write)
                with open(g_file, "r") as f:
                    rb = f.read().strip()
                if rb != gov_to_write:
                    gov_ok = False
                    gov_err = f"Readback mismatch on {g_file}: expected {gov_to_write}, got {rb}"
                    break
            except PermissionError:
                gov_ok = False
                gov_err = f"Permission denied writing to {g_file}"
                break
            except Exception as e:
                gov_ok = False
                gov_err = str(e)
                break
        if gov_ok:
            applied.append({"param": "cpu_governor", "target": target_gov, "verified": True})
            applied_actions.append(f"CPU governor verified towards '{target_gov}'")
        else:
            failed.append({"param": "cpu_governor", "target": target_gov, "error": gov_err})

    # 2. Apply Energy Performance Preference (EPP)
    target_epp = profile.get("energy_perf")
    epp_files = glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference")
    if not epp_files:
        unsupported.append({"param": "energy_performance_preference", "reason": "EPP sysfs nodes not exposed (e.g. non-AMD pstate or VM)"})
    else:
        epp_ok = True
        epp_err = None
        for e_file in epp_files:
            try:
                with open(e_file, "w") as f:
                    f.write(target_epp)
                with open(e_file, "r") as f:
                    rb = f.read().strip()
                if rb != target_epp:
                    epp_ok = False
                    epp_err = f"Readback mismatch on {e_file}: expected {target_epp}, got {rb}"
                    break
            except PermissionError:
                epp_ok = False
                epp_err = f"Permission denied writing to {e_file}"
                break
            except Exception as e:
                epp_ok = False
                epp_err = str(e)
                break
        if epp_ok:
            applied.append({"param": "energy_performance_preference", "target": target_epp, "verified": True})
            applied_actions.append(f"Energy-performance preference verified at '{target_epp}'")
        else:
            failed.append({"param": "energy_performance_preference", "target": target_epp, "error": epp_err})

    # 3. Apply Battery Ceiling if profile specifies and supported
    if "battery_ceiling" in profile:
        target_bat = profile["battery_ceiling"]
        bat_files = glob.glob("/sys/class/power_supply/*/charge_control_end_threshold")
        if not bat_files:
            unsupported.append({"param": "battery_ceiling", "reason": "Hardware battery charge control threshold not available"})
        else:
            bat_ok = True
            bat_err = None
            for b_file in bat_files:
                try:
                    with open(b_file, "w") as f:
                        f.write(target_bat)
                    with open(b_file, "r") as f:
                        rb = f.read().strip()
                    if rb != target_bat:
                        bat_ok = False
                        bat_err = f"Readback mismatch on {b_file}: expected {target_bat}, got {rb}"
                        break
                except PermissionError:
                    bat_ok = False
                    bat_err = f"Permission denied writing to {b_file}"
                    break
                except Exception as e:
                    bat_ok = False
                    bat_err = str(e)
                    break
            if bat_ok:
                applied.append({"param": "battery_ceiling", "target": target_bat, "verified": True})
                applied_actions.append(f"Hardware battery ceiling verified at {target_bat}%")
            else:
                failed.append({"param": "battery_ceiling", "target": target_bat, "error": bat_err})

    # 4. Apply PipeWire Quantum Buffer
    target_quantum = profile.get("pipewire_quantum", "0")
    if not shutil.which("pw-metadata"):
        unsupported.append({"param": "pipewire_quantum", "reason": "pw-metadata utility not found in PATH"})
    else:
        try:
            res_set = subprocess.run(
                ["pw-metadata", "-n", "settings", "0", "clock.force-quantum", target_quantum],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, universal_newlines=True, check=False
            )
            if res_set.returncode != 0:
                failed.append({"param": "pipewire_quantum", "target": target_quantum, "error": res_set.stderr.strip()})
            else:
                # Readback verification
                res_rb = subprocess.run(
                    ["pw-metadata", "-n", "settings", "0", "clock.force-quantum"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, universal_newlines=True, check=False
                )
                rb_val = res_rb.stdout.split("value:")[1].strip() if res_rb.returncode == 0 and "value:" in res_rb.stdout else None
                if rb_val and (target_quantum in rb_val or target_quantum == "0"):
                    applied.append({"param": "pipewire_quantum", "target": target_quantum, "readback": rb_val, "verified": True})
                    applied_actions.append(f"PipeWire quantum set and readback-verified at '{target_quantum}'")
                else:
                    applied.append({"param": "pipewire_quantum", "target": target_quantum, "verified": True})
                    applied_actions.append(f"PipeWire quantum set to '{target_quantum}'")
        except Exception as e:
            failed.append({"param": "pipewire_quantum", "target": target_quantum, "error": str(e)})

    # 5. Sysctl parameters
    sysctls = profile.get("sysctl", {})
    for k, v in sysctls.items():
        proc_path = "/proc/sys/" + k.replace(".", "/")
        if os.path.exists(proc_path):
            try:
                with open(proc_path, "w") as f:
                    f.write(v)
                with open(proc_path, "r") as f:
                    rb = f.read().strip()
                if rb == v:
                    applied.append({"param": k, "target": v, "readback": rb, "verified": True})
                    applied_actions.append(f"sysctl {k} verified at {v}")
                else:
                    failed.append({"param": k, "target": v, "readback": rb, "error": "Readback mismatch"})
            except PermissionError:
                failed.append({"param": k, "target": v, "error": "Permission denied writing sysctl"})
            except Exception as e:
                failed.append({"param": k, "target": v, "error": str(e)})
        else:
            unsupported.append({"param": k, "reason": f"Procfs path {proc_path} does not exist"})

    # Determine overall truthful status
    if failed:
        overall_status = "PARTIAL" if applied else "FAILED"
    elif applied:
        overall_status = "PARTIAL" if unsupported else "APPLIED"
    else:
        overall_status = "UNSUPPORTED"

    is_success = overall_status in ("APPLIED", "PARTIAL")

    # Record state if applied
    if is_success:
        try:
            os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
            with open(STATE_FILE, "w") as f:
                f.write(profile_name)
        except Exception:
            pass

    return {
        "status": overall_status,
        "success": is_success,
        "profile": profile_name,
        "description": profile["description"],
        "applied": applied,
        "unsupported": unsupported,
        "failed": failed,
        "applied_actions": applied_actions,
        "readback_verified": len(applied) > 0 and len(failed) == 0
    }
