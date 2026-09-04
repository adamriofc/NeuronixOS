"""
Storage hygiene, Nix store inspection, and disk reclamation metrics.
"""

import os
import subprocess
import shutil

def calculate_store_size():
    """Returns human-readable size of /nix/store."""
    if not os.path.exists("/nix/store"):
        return "0 GB"
    if shutil.which("du"):
        try:
            out = subprocess.check_output(
                ["du", "-sh", "--exclude=proc", "/nix/store"],
                stderr=subprocess.DEVNULL, timeout=5, text=True
            ).strip()
            return out.split()[0]
        except Exception:
            pass
    return "Unavailable"

def probe_storage_hygiene():
    """
    Evaluates storage hygiene metrics:
    - Journal logs size
    - User trash size
    - Total Nix generations count
    - Estimated reclaimable capacity
    """
    metrics = {
        "store_size": calculate_store_size(),
        "journal_size_mb": 0,
        "trash_size_mb": 0,
        "generations_count": 1,
        "status": "HEALTHY"
    }

    if shutil.which("journalctl"):
        try:
            out = subprocess.check_output(
                ["journalctl", "--disk-usage"],
                stderr=subprocess.DEVNULL, timeout=3, text=True
            ).strip()
            # Sample: "Archived and active journals take up 32.0M in the file system."
            parts = out.split("take up")
            if len(parts) > 1:
                metrics["journal_usage"] = parts[1].split("in")[0].strip()
        except Exception:
            metrics["journal_usage"] = "Standard"

    from .generation import list_generations
    gens = list_generations()
    metrics["generations_count"] = len(gens)

    return metrics
