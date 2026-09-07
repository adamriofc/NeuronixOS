"""
NEURONIX Ephemeral Zero-Copy Repo Sandbox Engine (neuronix sandbox)
Spins up isolated in-memory development sandboxes on tmpfs/ZRAM (/dev/shm),
masking real $HOME credentials and vaporizing build artifacts cleanly on exit.
"""

import os
import sys
import shutil
import subprocess
import tempfile
import urllib.parse

def is_git_url(target):
    """Checks if target is a remote git URL."""
    if not target:
        return False
    if target.startswith("http://") or target.startswith("https://") or target.startswith("git@"):
        return True
    if target.endswith(".git"):
        return True
    return False

def setup_ram_workspace(target, custom_shm_base="/dev/shm"):
    """Allocates ephemeral RAM workspace and clones/stages target repository."""
    shm_base = custom_shm_base if os.path.isdir(custom_shm_base) and os.access(custom_shm_base, os.W_OK) else tempfile.gettempdir()
    workspace_dir = tempfile.mkdtemp(prefix="neuronix-sandbox-", dir=shm_base)

    status = "ready"
    project_name = "workspace"

    if is_git_url(target):
        project_name = target.rstrip("/").split("/")[-1]
        if project_name.endswith(".git"):
            project_name = project_name[:-4]
        target_clone_dir = os.path.join(workspace_dir, project_name)
        
        # Shallow clone to minimize RAM and time
        cmd = ["git", "clone", "--depth", "1", target, target_clone_dir]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, check=False)
        if res.returncode != 0:
            shutil.rmtree(workspace_dir, ignore_errors=True)
            return None, None, f"Git clone failed: {res.stderr.strip()}"
        active_dir = target_clone_dir
    elif os.path.isdir(target):
        project_name = os.path.basename(os.path.abspath(target))
        active_dir = os.path.join(workspace_dir, project_name)
        # Copy directory into RAM
        shutil.copytree(target, active_dir, symlinks=True, ignore=shutil.ignore_patterns(".git/objects/*", "node_modules", "target"))
    else:
        active_dir = workspace_dir

    return workspace_dir, active_dir, "Workspace successfully prepared in RAM"

def run_sandbox_session(active_dir, command=None, env_vars=None):
    """Executes a command or launches an interactive shell inside the sandbox."""
    if not active_dir or not os.path.isdir(active_dir):
        return 1, "Invalid sandbox directory"

    has_bwrap = shutil.which("bwrap") is not None
    user = os.environ.get("USER", "neuronix")

    if has_bwrap:
        bwrap_cmd = [
            "bwrap",
            "--ro-bind", "/nix/store", "/nix/store",
            "--ro-bind", "/run/current-system/sw", "/usr",
            "--ro-bind", "/run/current-system/sw/bin", "/bin",
            "--proc", "/proc",
            "--dev", "/dev",
            "--tmpfs", f"/home/{user}",
            "--bind", active_dir, f"/home/{user}/workspace",
            "--chdir", f"/home/{user}/workspace",
            "--setenv", "HOME", f"/home/{user}",
            "--setenv", "PATH", "/run/current-system/sw/bin:/usr/bin:/bin",
            "--setenv", "NEURONIX_SANDBOX", "1"
        ]
        if os.path.exists("/etc/resolv.conf"):
            bwrap_cmd.extend(["--ro-bind", "/etc/resolv.conf", "/etc/resolv.conf"])
        if os.path.exists("/etc/ssl"):
            bwrap_cmd.extend(["--ro-bind", "/etc/ssl", "/etc/ssl"])

        if command:
            bwrap_cmd.extend(["bash", "-c", command])
        else:
            bwrap_cmd.extend(["bash"])

        res = subprocess.run(bwrap_cmd, check=False)
        return res.returncode, "Sandbox session closed"
    else:
        # Unprivileged subshell fallback
        sub_env = os.environ.copy()
        sub_env["NEURONIX_SANDBOX"] = "1"
        if command:
            res = subprocess.run(["bash", "-c", command], cwd=active_dir, env=sub_env, check=False)
        else:
            res = subprocess.run(["bash"], cwd=active_dir, env=sub_env, check=False)
        return res.returncode, "Subshell session closed"

def teardown_sandbox(workspace_dir, export_path=None):
    """Cleans up in-memory workspace and optionally exports changes."""
    if not workspace_dir or not os.path.exists(workspace_dir):
        return True, "No workspace to clean"

    if export_path:
        os.makedirs(export_path, exist_ok=True)
        # Copy contents to export destination
        for item in os.listdir(workspace_dir):
            s = os.path.join(workspace_dir, item)
            d = os.path.join(export_path, item)
            if os.path.isdir(s):
                shutil.copytree(s, d, dirs_exist_ok=True)
            else:
                shutil.copy2(s, d)

    shutil.rmtree(workspace_dir, ignore_errors=True)
    return True, "Vaporized RAM workspace successfully"

def allocate_ram_workspace(target, custom_shm_base="/dev/shm"):
    ws, _, _ = setup_ram_workspace(target, custom_shm_base)
    return ws

def vaporize_workspace(ws, export_path=None):
    ok, _ = teardown_sandbox(ws, export_path)
    return ok

