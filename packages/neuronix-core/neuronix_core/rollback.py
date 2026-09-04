"""
Atomic generation rollback handler and safety invariant engine.
"""

import os
import subprocess
import shutil
from .generation import list_generations, get_active_generation

def simulate_rollback(target_generation=None):
    """
    Validates whether an atomic rollback is valid and deterministically safe.
    Returns (is_valid, message, target_gen_number).
    """
    history = list_generations()
    if not history:
        return False, "No system generations found in Nix profile registry.", None

    active_str = get_active_generation()
    active_num = int(active_str) if active_str.isdigit() else 1

    if target_generation is not None:
        target_num = int(target_generation)
        match = [g for g in history if g["generation"] == target_num]
        if not match:
            return False, f"Target generation {target_num} does not exist in history.", None
        if target_num == active_num:
            return False, f"Generation {target_num} is already the active generation.", None
        return True, f"Verified target generation {target_num} available for switch.", target_num

    # Default: rollback to immediate predecessor
    predecessors = [g for g in history if g["generation"] < active_num]
    if not predecessors:
        return False, f"Current generation ({active_num}) has no preceding generation to roll back to.", None

    target = predecessors[-1]["generation"]
    return True, f"Valid rollback target identified: generation {target}.", target

def execute_rollback(target_generation=None, dry_run=False):
    """
    Executes atomic system rollback to predecessor or explicit generation target.
    Returns (success: bool, return_code: int, output: str).
    """
    is_valid, msg, target_num = simulate_rollback(target_generation)
    if not is_valid:
        return False, 1, msg

    if dry_run:
        return True, 0, f"[DRY-RUN] Rollback to generation {target_num} validated safely."

    cmd = []
    if os.geteuid() != 0 and shutil.which("sudo"):
        cmd.append("sudo")

    if target_generation is None:
        cmd.extend(["nixos-rebuild", "switch", "--rollback"])
    else:
        target_bin = f"/nix/var/nix/profiles/system-{target_num}-link/bin/switch-to-configuration"
        if os.path.exists(target_bin):
            cmd.extend([target_bin, "switch"])
        else:
            cmd.extend(["nix-env", "--profile", "/nix/var/nix/profiles/system", "--switch-generation", str(target_num)])

    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        return (proc.returncode == 0), proc.returncode, proc.stdout + proc.stderr
    except Exception as e:
        return False, 1, str(e)
