"""
System generation inspection and historical lineage management.
"""

import os
import glob
import subprocess
from datetime import datetime

SYSTEM_PROFILE = os.environ.get("NEURONIX_SYSTEM_PROFILE", "/nix/var/nix/profiles/system")

def get_system_profile():
    return os.environ.get("NEURONIX_SYSTEM_PROFILE", SYSTEM_PROFILE)

def parse_generation_number(path):
    """Extracts numeric generation ID from profile symlink string."""
    basename = os.path.basename(path)
    if basename.startswith("system-") and basename.endswith("-link"):
        try:
            return int(basename.split("system-")[1].split("-link")[0])
        except ValueError:
            return None
    return None

def get_active_generation():
    """Returns the current active system generation number as a string."""
    prof = get_system_profile()
    if os.path.exists(prof):
        try:
            target = os.readlink(prof)
            if "system-" in target:
                num = target.split("system-")[1].split("-link")[0]
                return num
        except Exception:
            pass
    return "1"

def list_generations():
    """
    Returns a sorted list of dictionaries representing system generations:
    [{ 'generation': int, 'date': str, 'active': bool, 'path': str }]
    """
    generations = []
    active = get_active_generation()
    prof = get_system_profile()
    profile_dir = os.path.dirname(prof)

    if not os.path.exists(profile_dir):
        return [{
            "generation": 1,
            "date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "active": True,
            "path": prof
        }]

    links = glob.glob(f"{prof}-*-link")
    now_ts = datetime.now().timestamp()
    for link in links:
        gen_num = parse_generation_number(link)
        if gen_num is not None:
            age_days = 0.0
            try:
                mtime = os.path.getmtime(link)
                dt_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
                age_days = round(max(0.0, (now_ts - mtime) / 86400.0), 2)
            except Exception:
                dt_str = "Unknown"
            
            is_active = (str(gen_num) == str(active))
            generations.append({
                "generation": gen_num,
                "date": dt_str,
                "active": is_active,
                "path": link,
                "age_days": age_days,
                "gc_eligible": (not is_active and age_days >= 14.0)
            })

    generations.sort(key=lambda x: x["generation"])
    if not generations:
        generations.append({
            "generation": int(active) if active.isdigit() else 1,
            "date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "active": True,
            "path": prof,
            "age_days": 0.0,
            "gc_eligible": False
        })

    return generations
