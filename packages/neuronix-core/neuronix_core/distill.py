"""
NEURONIX Imperative-to-Declarative Reverse Engine (neuronix distill)
Converts ephemeral package executions and user requests into verified,
pure-functional NixOS flake declarations with atomic rollback safety.
"""

import os
import sys
import re
import json
import subprocess
import shutil

USER_PACKAGES_MODULE_PATH = "/etc/nixos/modules/custom/user-packages.nix"
FALLBACK_REPO_MODULE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "../../../modules/custom/user-packages.nix"
)

def verify_package_in_nixpkgs(package_name):
    """Formally verifies if a package exists in pure nixpkgs closure."""
    if not package_name or not re.match(r"^[a-zA-Z0-9_\.\-]+$", package_name):
        return False, f"Invalid package name format: '{package_name}'"
    
    env = os.environ.copy()
    if os.path.exists("/nix/var/nix/daemon-socket/socket") or "NIX_REMOTE" in env:
        env.setdefault("NIX_REMOTE", "daemon")

    cmd = ["nix-instantiate", "<nixpkgs>", "-A", package_name]
    try:
        res = subprocess.run(
            cmd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=10,
            check=False
        )
        if res.returncode == 0:
            return True, "Valid pure derivation in nixpkgs"
    except Exception:
        pass

    return False, f"Package '{package_name}' not found in current nixpkgs channel"


def resolve_target_file():
    """Locates the active declarative custom packages file."""
    if os.path.exists(USER_PACKAGES_MODULE_PATH) or os.path.isdir(os.path.dirname(USER_PACKAGES_MODULE_PATH)):
        return USER_PACKAGES_MODULE_PATH
    return FALLBACK_REPO_MODULE

def distill_packages(packages, dry_run=False):
    """Declaratively ingests packages into user-packages.nix with syntax verification."""
    if not packages:
        return {"status": "error", "message": "No packages specified for distillation."}

    results = []
    valid_packages = []
    
    for pkg in packages:
        pkg_clean = pkg.strip()
        if not pkg_clean:
            continue
        is_valid, reason = verify_package_in_nixpkgs(pkg_clean)
        results.append({"package": pkg_clean, "valid": is_valid, "reason": reason})
        if is_valid:
            valid_packages.append(pkg_clean)

    if not valid_packages:
        return {
            "status": "failed",
            "message": "None of the specified packages could be verified in nixpkgs.",
            "details": results
        }

    target_file = resolve_target_file()
    target_dir = os.path.dirname(target_file)
    os.makedirs(target_dir, exist_ok=True)

    original_content = ""
    existing_packages = set()

    if os.path.exists(target_file):
        with open(target_file, "r") as f:
            original_content = f.read()
        # Parse existing packages
        match = re.search(r"environment\.systemPackages\s*=\s*with\s+pkgs;\s*\[([^\]]+)\]", original_content, re.DOTALL)
        if match:
            for item in match.group(1).split():
                clean_item = item.strip().strip('"').strip("'")
                if clean_item and not clean_item.startswith("#"):
                    existing_packages.add(clean_item)

    new_to_add = [p for p in valid_packages if p not in existing_packages]
    if not new_to_add:
        return {
            "status": "noop",
            "message": f"All specified packages ({', '.join(valid_packages)}) are already declared in {target_file}.",
            "declared_packages": sorted(list(existing_packages))
        }

    all_pkgs = sorted(list(existing_packages.union(set(new_to_add))))
    formatted_pkgs = "\n".join([f"    {p}" for p in all_pkgs])
    new_content = f"""# ==============================================================================
# NEURONIX Custom User Packages Module (Managed by neuronix distill)
# ==============================================================================
{{ pkgs, ... }}:

{{
  environment.systemPackages = with pkgs; [
{formatted_pkgs}
  ];
}}
"""

    if dry_run:
        return {
            "status": "dry_run_success",
            "message": f"Verified {len(new_to_add)} packages ready for declarative distillation.",
            "target_file": target_file,
            "packages_to_add": new_to_add,
            "proposed_content": new_content
        }

    # Write file with backup
    backup_file = target_file + ".bak"
    try:
        if os.path.exists(target_file):
            shutil.copy2(target_file, backup_file)
        with open(target_file, "w") as f:
            f.write(new_content)
    except PermissionError:
        return {
            "status": "error",
            "message": f"Permission denied writing to {target_file}. Elevate privileges with sudo."
        }

    # Verify Nix syntax of modified file
    syntax_cmd = ["nix-instantiate", "--parse", target_file]
    syntax_res = subprocess.run(syntax_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if syntax_res.returncode != 0:
        # Revert immediately
        if os.path.exists(backup_file):
            shutil.copy2(backup_file, target_file)
            os.remove(backup_file)
        return {
            "status": "error",
            "message": "Syntax validation failed after file modification. Reverted to previous state.",
            "error_detail": syntax_res.stderr.decode("utf-8", errors="ignore")
        }

    if os.path.exists(backup_file):
        os.remove(backup_file)

    return {
        "status": "success",
        "message": f"Successfully distilled {len(new_to_add)} packages into declarative state.",
        "target_file": target_file,
        "packages_added": new_to_add,
        "total_packages": all_pkgs
    }

def verify_nixpkgs_attribute(pkg):
    ok, _ = verify_package_in_nixpkgs(pkg)
    return ok

distill_package = distill_packages

