"""
Atomic generation rollback handler and safety invariant engine.
Enforces mutual exclusion, transaction journaling, and postcondition verification.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import subprocess
import shutil
from typing import Tuple, Optional
from .generation import list_generations, get_active_generation, get_system_profile
from .lock import OperationLock, ConcurrentOperationError
from .journal import TransactionJournal, TransactionState

def simulate_rollback(target_generation: Optional[int] = None) -> Tuple[bool, str, Optional[int]]:
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

def execute_rollback(target_generation: Optional[int] = None, dry_run: bool = False) -> Tuple[bool, int, str]:
    """
    Executes atomic system rollback to predecessor or explicit generation target.
    Enforces exclusive lock, journals the transaction, and verifies postconditions.
    Returns (success: bool, return_code: int, output: str).
    """
    is_valid, msg, target_num = simulate_rollback(target_generation)
    if not is_valid:
        return False, 1, msg

    active_str = get_active_generation()
    active_num = int(active_str) if active_str.isdigit() else 1

    if dry_run:
        return True, 0, f"[DRY-RUN] Rollback from generation {active_num} to {target_num} validated safely."

    # Acquire exclusive operation lock
    try:
        lock = OperationLock("rollback")
        lock.acquire()
    except ConcurrentOperationError as e:
        return False, 126, str(e)

    # Initialize transaction journal
    journal = TransactionJournal()
    tx_id = journal.start_transaction("rollback", {
        "previous_generation": active_num,
        "target_generation": target_num
    })

    try:
        journal.update_transaction(tx_id, TransactionState.APPLYING)

        cmd = []
        if os.geteuid() != 0 and shutil.which("sudo") and not os.environ.get("NEURONIX_NO_SUDO"):
            cmd.append("sudo")

        if target_generation is None:
            cmd.extend(["nixos-rebuild", "switch", "--rollback"])
        else:
            prof = get_system_profile()
            target_bin = f"{prof}-{target_num}-link/bin/switch-to-configuration"
            if os.path.exists(target_bin):
                cmd.extend([target_bin, "switch"])
            else:
                cmd.extend(["nix-env", "--profile", prof, "--switch-generation", str(target_num)])

        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        raw_output = proc.stdout + proc.stderr

        if proc.returncode != 0:
            journal.abort_transaction(tx_id, f"Process execution failed with exit code {proc.returncode}: {raw_output}")
            return False, proc.returncode, raw_output

        # Postcondition verification
        new_active = get_active_generation()
        if new_active == str(target_num):
            journal.commit_transaction(tx_id, {"final_generation": int(new_active)})
            return True, 0, f"SUCCESS: Rolled back successfully to generation {new_active}.\n{raw_output}"
        else:
            err_msg = (
                f"POSTCONDITION FAILED: Expected active generation {target_num}, "
                f"but active generation is {new_active}."
            )
            journal.abort_transaction(tx_id, err_msg)
            return False, 1, f"{err_msg}\n{raw_output}"

    except Exception as ex:
        journal.abort_transaction(tx_id, str(ex))
        return False, 1, f"Unhandled exception during rollback: {ex}"
    finally:
        lock.release()
