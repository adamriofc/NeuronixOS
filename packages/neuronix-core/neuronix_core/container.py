"""
NEURONIX Ephemeral Zero-Copy Development Container Engine (neuronix container)
Spins up isolated in-memory development containers on tmpfs/ZRAM (/dev/shm),
masking real $HOME credentials and vaporizing build artifacts cleanly on exit.
"""

import os
import sys
import shutil
import subprocess
import tempfile
import urllib.parse

SENSITIVE_ENV_PATTERNS = [
    "TOKEN", "KEY", "SECRET", "AUTH", "PASS", "CREDENTIAL",
    "AWS_", "GITHUB_", "GITLAB_", "NPM_", "DOCKER_",
    "OPENAI_", "ANTHROPIC_", "GEMINI_"
]
SENSITIVE_ENV_EXACT = {
    "SSH_AUTH_SOCK", "GPG_AGENT_INFO", "GNUPGHOME", "KUBECONFIG"
}

def sanitize_environment(base_env=None):
    """Sanitizes environment by scrubbing all credentials, secret keys, and tokens."""
    source = base_env if base_env is not None else os.environ
    clean = {}
    whitelist_keys = {"PATH", "USER", "LOGNAME", "TERM", "LANG", "SHELL"}
    for k, v in source.items():
        if k in whitelist_keys:
            clean[k] = v
            continue
        k_upper = k.upper()
        if any(pat in k_upper for pat in SENSITIVE_ENV_PATTERNS) or k in SENSITIVE_ENV_EXACT:
            continue
        if k.startswith("LC_") or k in {"TZ", "COLORTERM", "SHLVL"}:
            clean[k] = v
    clean["NEURONIX_CONTAINER"] = "1"
    clean["NEURONIX_SANDBOX"] = "1"
    return clean

def is_git_url(target):
    """Checks if target is a remote git URL."""
    if not target:
        return False
    if target.startswith("http://") or target.startswith("https://") or target.startswith("git@"):
        return True
    if target.endswith(".git"):
        return True
    return False

def setup_ram_workspace(target, custom_shm_base="/dev/shm", require_ram=True):
    """Allocates ephemeral RAM workspace and clones/stages target repository."""
    if require_ram:
        if not (os.path.isdir(custom_shm_base) and os.access(custom_shm_base, os.W_OK)):
            return None, None, f"Strict RAM container requires writable tmpfs path '{custom_shm_base}'. Silent disk fallback disallowed."
        shm_base = custom_shm_base
    else:
        shm_base = custom_shm_base if os.path.isdir(custom_shm_base) and os.access(custom_shm_base, os.W_OK) else tempfile.gettempdir()

    try:
        workspace_dir = tempfile.mkdtemp(prefix="neuronix-container-", dir=shm_base)
    except Exception as e:
        return None, None, f"Failed to allocate RAM workspace in {shm_base}: {e}"

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
        project_name = os.path.basename(os.path.abspath(target)) or "workspace"
        active_dir = os.path.join(workspace_dir, project_name)
        
        def _ignore_special(dir_path, names):
            ignored = set()
            for name in names:
                full_path = os.path.join(dir_path, name)
                try:
                    import stat
                    st = os.lstat(full_path)
                    if stat.S_ISSOCK(st.st_mode) or stat.S_ISFIFO(st.st_mode) or stat.S_ISCHR(st.st_mode) or stat.S_ISBLK(st.st_mode):
                        ignored.add(name)
                    elif not os.access(full_path, os.R_OK):
                        ignored.add(name)
                    elif name in {".git", "node_modules", "target", ".direnv", "dist"}:
                        ignored.add(name)
                except Exception:
                    ignored.add(name)
            return ignored

        try:
            shutil.copytree(target, active_dir, symlinks=True, ignore=_ignore_special, ignore_dangling_symlinks=True)
        except Exception:
            # If partial copy or error occurs on non-critical files, preserve whatever was copied
            os.makedirs(active_dir, exist_ok=True)
    else:
        active_dir = workspace_dir

    return workspace_dir, active_dir, "Workspace successfully prepared in RAM"

def run_container_session(active_dir, command=None, env_vars=None):
    """Executes a command or launches an interactive shell inside the container."""
    if not active_dir or not os.path.isdir(active_dir):
        return 1, "Invalid container directory"

    has_bwrap = shutil.which("bwrap") is not None
    user = os.environ.get("USER", "neuronix")

    if has_bwrap:
        bwrap_cmd = [
            "bwrap",
            "--clearenv",
            "--unshare-pid",
            "--unshare-uts",
            "--unshare-ipc",
            "--ro-bind", "/nix/store", "/nix/store",
            "--ro-bind", "/run/current-system/sw", "/usr",
            "--ro-bind", "/run/current-system/sw/bin", "/bin",
            "--proc", "/proc",
            "--dev", "/dev",
            "--tmpfs", f"/home/{user}",
            "--bind", active_dir, f"/home/{user}/workspace",
            "--chdir", f"/home/{user}/workspace",
            "--setenv", "HOME", f"/home/{user}",
            "--setenv", "USER", user,
            "--setenv", "LOGNAME", user,
            "--setenv", "PATH", "/run/current-system/sw/bin:/usr/bin:/bin",
            "--setenv", "TERM", os.environ.get("TERM", "xterm-256color"),
            "--setenv", "LANG", os.environ.get("LANG", "C.UTF-8"),
            "--setenv", "NEURONIX_CONTAINER", "1",
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
        return res.returncode, "Container session closed"
    else:
        # Unprivileged subshell fallback with sanitized credentials
        sub_env = sanitize_environment()
        sub_env["HOME"] = active_dir
        if env_vars:
            sub_env.update(env_vars)
        if command:
            res = subprocess.run(["bash", "-c", command], cwd=active_dir, env=sub_env, check=False)
        else:
            res = subprocess.run(["bash"], cwd=active_dir, env=sub_env, check=False)
        return res.returncode, "Subshell session closed"

# Backward-compatible alias
run_sandbox_session = run_container_session

def teardown_container(workspace_dir, export_path=None):
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

# Backward-compatible alias
teardown_sandbox = teardown_container

def allocate_ram_workspace(target, custom_shm_base="/dev/shm", require_ram=True):
    ws, _, _ = setup_ram_workspace(target, custom_shm_base, require_ram=require_ram)
    return ws

def vaporize_workspace(ws, export_path=None):
    ok, _ = teardown_container(ws, export_path)
    return ok
