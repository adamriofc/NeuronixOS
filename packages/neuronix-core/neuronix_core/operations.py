"""
Privileged operation allow-list execution engine for NEURONIX OS.
Enforces strict capability boundaries and prevents arbitrary command injection.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import json
import shutil
import subprocess

APPROVED_PRIVILEGED_OPERATIONS = {
    "rollback": {
        "description": "Execute atomic system generation rollback",
        "requires_args": False,
        "max_args": 1
    },
    "gc": {
        "description": "Trigger Nix store garbage collection",
        "requires_args": False,
        "max_args": 1
    },
    "trim": {
        "description": "Execute storage fstrim discard",
        "requires_args": False,
        "max_args": 0
    },
    "battery": {
        "description": "Apply hardware battery health charge ceiling",
        "requires_args": False,
        "max_args": 1
    },
    "ca-install": {
        "description": "Install content-addressed enterprise root certificate",
        "requires_args": True,
        "max_args": 1
    },
    "upgrade": {
        "description": "Execute transactional atomic system upgrade or switch",
        "requires_args": False,
        "max_args": 2
    }
}

def is_operation_permitted(operation_id: str) -> bool:
    """Checks whether an operation ID is registered in the privileged allow-list."""
    return operation_id in APPROVED_PRIVILEGED_OPERATIONS

def execute_privileged_operation(operation_id: str, *args):
    """
    Executes an approved privileged operation through dedicated handlers.
    Strictly rejects arbitrary shell execution or unregistered operations.
    Returns (success: bool, return_code: int, output: str).
    """
    if not is_operation_permitted(operation_id):
        return False, 126, f"Permission Denied: Operation '{operation_id}' is not in the privileged allow-list."

    op_spec = APPROVED_PRIVILEGED_OPERATIONS[operation_id]
    if op_spec["requires_args"] and not args:
        return False, 1, f"Validation Error: Operation '{operation_id}' requires arguments."
    if len(args) > op_spec["max_args"]:
        return False, 1, f"Validation Error: Operation '{operation_id}' accepts at most {op_spec['max_args']} arguments."

    # Validate argument characters (reject command injection metacharacters)
    for arg in args:
        if not isinstance(arg, str):
            arg = str(arg)
        for bad_char in [";", "&", "|", "`", "$", "\n", "\r"]:
            if bad_char in arg:
                return False, 1, f"Security Violation: Prohibited metacharacter '{bad_char}' detected in argument."

    # Route to safe deterministic handlers
    if operation_id == "rollback":
        from .rollback import execute_rollback
        target = args[0] if args else None
        return execute_rollback(target_generation=target)

    elif operation_id == "gc":
        cmd = ["nix-collect-garbage"]
        if args and args[0] == "--delete-old":
            cmd.append("--delete-old")
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
            return (res.returncode == 0), res.returncode, res.stdout + res.stderr
        except Exception as e:
            return False, 1, str(e)

    elif operation_id == "trim":
        cmd = ["fstrim", "-av"]
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
            return (res.returncode == 0), res.returncode, res.stdout + res.stderr
        except Exception as e:
            return False, 1, str(e)

    elif operation_id == "battery":
        limit = int(args[0]) if args and args[0].isdigit() else 80
        if limit < 40 or limit > 100:
            return False, 1, "Validation Error: Battery limit must be between 40 and 100%."
        # Read/write sysfs directly without shell expansion
        applied = False
        unsupported = True
        base_dir = "/sys/class/power_supply"
        if os.path.exists(base_dir):
            for entry in os.listdir(base_dir):
                if entry.startswith("BAT"):
                    bat_path = os.path.join(base_dir, entry)
                    for node in ["charge_control_end_threshold", "charge_control_limit_max", "charge_stop_threshold"]:
                        target_file = os.path.join(bat_path, node)
                        if os.path.exists(target_file):
                            unsupported = False
                            try:
                                with open(target_file, "w") as f:
                                    f.write(f"{limit}\n")
                                with open(target_file, "r") as f:
                                    actual = f.read().strip()
                                if actual == str(limit):
                                    applied = True
                            except PermissionError:
                                return False, 13, f"Permission Denied: Unable to write to {target_file} (root required)."
                            except Exception as e:
                                return False, 1, f"I/O Error: {e}"
        if unsupported:
            return True, 0, "UNSUPPORTED: No compatible hardware battery control interface detected."
        if applied:
            return True, 0, f"APPLIED: Battery charge threshold verified at {limit}%."
        return False, 1, "FAILED: Failed to verify battery charge threshold after write."

    elif operation_id == "ca-install":
        cert_path = args[0]
        if not os.path.exists(cert_path):
            return False, 1, f"File Not Found: Certificate at '{cert_path}' does not exist."
        # Invoke verified ca installation handler
        from .ca import enroll_certificate
        return enroll_certificate(cert_path)

    elif operation_id == "upgrade":
        from .update import apply_system_update
        flake_uri = None
        dry_run = False
        for a in args:
            if a == "--dry-run":
                dry_run = True
            elif not a.startswith("-"):
                flake_uri = a
        ok, code, res = apply_system_update(flake_uri=flake_uri, dry_run=dry_run)
        return ok, code, json.dumps(res, indent=2)

    return False, 1, f"Unhandled operation: {operation_id}"
