"""
Storage hygiene, Nix store inspection, and disk reclamation metrics.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from typing import Any, Dict, List, Optional


def calculate_store_size() -> str:
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


def probe_storage_hygiene() -> Dict[str, Any]:
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
                usage_str = parts[1].split("in")[0].strip()
                metrics["journal_usage"] = usage_str
                if usage_str.endswith("G"):
                    metrics["journal_size_mb"] = int(float(usage_str[:-1]) * 1024)
                elif usage_str.endswith("M"):
                    metrics["journal_size_mb"] = int(float(usage_str[:-1]))
                elif usage_str.endswith("K"):
                    metrics["journal_size_mb"] = max(1, int(float(usage_str[:-1]) / 1024))
        except Exception:
            metrics["journal_usage"] = "Standard"

    trash_dir = os.path.expanduser("~/.local/share/Trash")
    if os.path.exists(trash_dir):
        try:
            total_b = sum(os.path.getsize(os.path.join(dirpath, filename))
                          for dirpath, dirnames, filenames in os.walk(trash_dir)
                          for filename in filenames)
            metrics["trash_size_mb"] = total_b // (1024 * 1024)
        except Exception:
            pass

    from .generation import list_generations
    gens = list_generations()
    metrics["generations_count"] = len(gens)

    return metrics

def is_btrfs_path(path: str) -> bool:
    """Checks whether path resides on a Btrfs filesystem."""
    if not shutil.which("stat"):
        return False
    try:
        out = subprocess.check_output(["stat", "-f", "-c", "%T", path], stderr=subprocess.DEVNULL, text=True).strip()
        return out.lower() == "btrfs"
    except Exception:
        return False

def _get_branch_dir(source: str, branch_name: str) -> str:
    parent = os.path.dirname(os.path.abspath(source))
    base = os.path.basename(os.path.abspath(source))
    return os.path.join(parent, f".branch_{base}_{branch_name}")

def create_workspace_branch(source_path: str, branch_name: str) -> str:
    """
    Creates an instant CoW / Reflink workspace branch.
    If on Btrfs, utilizes atomic subvolume snapshotting; otherwise leverages cp --reflink=auto.
    """
    source = os.path.abspath(source_path)
    if not os.path.exists(source):
        raise FileNotFoundError(f"Source workspace path does not exist: {source}")

    branch_dir = _get_branch_dir(source, branch_name)

    if os.path.exists(branch_dir):
        raise FileExistsError(f"Workspace branch already exists: {branch_dir}")

    is_btrfs = is_btrfs_path(source)
    snapshot_method = "reflink_cow"
    if is_btrfs and shutil.which("btrfs"):
        try:
            res = subprocess.run(["btrfs", "subvolume", "snapshot", source, branch_dir],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if res.returncode == 0:
                snapshot_method = "btrfs_snapshot"
        except Exception:
            pass

    if snapshot_method == "reflink_cow":
        subprocess.check_call(["cp", "-a", "--reflink=auto", source, branch_dir])

    return {
        "status": "SUCCESS",
        "branch_name": branch_name,
        "source_path": source,
        "branch_path": branch_dir,
        "method": snapshot_method
    }

def list_workspace_branches(source_path: str) -> list[str]:
    """Lists existing workspace branches for given workspace directory."""
    source = os.path.abspath(source_path)
    parent = os.path.dirname(source)
    base = os.path.basename(source)
    prefix = f".branch_{base}_"
    branches = []
    if os.path.exists(parent):
        for name in os.listdir(parent):
            if name.startswith(prefix) and os.path.isdir(os.path.join(parent, name)):
                branches.append(name[len(prefix):])
    return sorted(branches)

def revert_workspace_branch(source_path: str, branch_name: str) -> bool:
    """Restores source workspace from designated branch snapshot via CoW reflink."""
    source = os.path.abspath(source_path)
    branch_dir = _get_branch_dir(source, branch_name)
    if not os.path.exists(branch_dir):
        raise FileNotFoundError(f"Branch does not exist: {branch_dir}")

    # Reflink overwrite back to source
    subprocess.check_call(["cp", "-a", "--reflink=auto", f"{branch_dir}/.", source])
    return {
        "status": "SUCCESS",
        "branch_name": branch_name,
        "source_path": source
    }


