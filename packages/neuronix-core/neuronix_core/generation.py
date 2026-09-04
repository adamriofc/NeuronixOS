"""
System generation inspection and historical lineage management.
"""

import os
import glob
import subprocess
from datetime import datetime

SYSTEM_PROFILE = "/nix/var/nix/profiles/system"

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
    if os.path.exists(SYSTEM_PROFILE):
        try:
            target = os.readlink(SYSTEM_PROFILE)
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
    profile_dir = os.path.dirname(SYSTEM_PROFILE)

    if not os.path.exists(profile_dir):
        return [{
            "generation": 1,
            "date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "active": True,
            "path": SYSTEM_PROFILE
        }]

    links = glob.glob(f"{SYSTEM_PROFILE}-*-link")
    for link in links:
        gen_num = parse_generation_number(link)
        if gen_num is not None:
            try:
                mtime = os.path.getmtime(link)
                dt_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                dt_str = "Unknown"
            generations.append({
                "generation": gen_num,
                "date": dt_str,
                "active": (str(gen_num) == str(active)),
                "path": link
            })

    generations.sort(key=lambda x: x["generation"])
    if not generations:
        generations.append({
            "generation": int(active) if active.isdigit() else 1,
            "date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "active": True,
            "path": SYSTEM_PROFILE
        })

    return generations
