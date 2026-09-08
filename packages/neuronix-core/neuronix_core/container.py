"""
NEURONIX Ephemeral Zero-Copy Development Container Engine (neuronix container)
Spins up isolated in-memory development containers on tmpfs/ZRAM (/dev/shm),
featuring Transparent Dynamic FHS Emulation, Daemonless OCI Image Runner,
Multi-Service Stack Orchestration, and Zero-Bloat OCI Export.
"""

import os
import sys
import glob
import json
import time
import shutil
import tarfile
import hashlib
import tempfile
import subprocess
import urllib.parse
import urllib.request

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
    if not target or not isinstance(target, str):
        return False
    if target.startswith("http://") or target.startswith("https://") or target.startswith("git@"):
        return True
    if target.endswith(".git"):
        return True
    return False

def is_oci_url(target):
    """Checks if target is an OCI or Docker image reference."""
    if not target or not isinstance(target, str):
        return False
    if target.startswith("docker://") or target.startswith("oci://"):
        return True
    # Target looks like an image tag and not an existing path or git url
    if not os.path.exists(target) and not is_git_url(target):
        if ":" in target and not target.startswith("-") and not target.startswith("/"):
            return True
    return False

def resolve_fhs_paths():
    """
    Detects dynamic linker and standard shared library directories for FHS compatibility.
    Resolves /lib64/ld-linux-x86-64.so.2 and glibc libraries across host and Nix store.
    """
    fhs = {
        "ld_linux": None,
        "lib_dirs": [],
        "env": {}
    }
    candidates = [
        "/lib64/ld-linux-x86-64.so.2",
        "/usr/lib64/ld-linux-x86-64.so.2",
        "/usr/lib/ld-linux-x86-64.so.2",
        "/run/current-system/sw/lib/ld-linux-x86-64.so.2"
    ]
    glibc_matches = sorted(glob.glob("/nix/store/*-glibc-*/lib/ld-linux-x86-64.so.2"))
    if glibc_matches:
        candidates.extend(glibc_matches)

    for c in candidates:
        if os.path.exists(c):
            fhs["ld_linux"] = os.path.realpath(c)
            break

    for p in ["/usr/lib", "/usr/lib64", "/lib", "/lib64", "/run/current-system/sw/lib"]:
        if os.path.isdir(p) and p not in fhs["lib_dirs"]:
            fhs["lib_dirs"].append(p)

    fhs["env"]["LD_LIBRARY_PATH"] = ":".join(fhs["lib_dirs"])
    if fhs["ld_linux"]:
        fhs["env"]["NIX_LD"] = fhs["ld_linux"]
        fhs["env"]["NIX_LD_LIBRARY_PATH"] = ":".join(fhs["lib_dirs"])
    return fhs

def safe_extract_tar(tar, destination_dir):
    """
    Safely extracts tarfile members, protecting against Tar Slip (directory traversal),
    absolute path injection, device node creation, and suid/sgid privilege escalations.
    """
    os.makedirs(destination_dir, exist_ok=True)
    dest_abs = os.path.realpath(os.path.abspath(destination_dir))
    validated_members = []
    for member in tar.getmembers():
        # Reject absolute paths
        if member.name.startswith("/") or member.name.startswith("\\"):
            raise ValueError(f"Insecure tar member (absolute path): {member.name}")

        # Resolve target destination path
        target_path = os.path.realpath(os.path.abspath(os.path.join(destination_dir, member.name)))
        if not (target_path == dest_abs or target_path.startswith(dest_abs + os.sep)):
            raise ValueError(f"Insecure tar member (path traversal attempt): {member.name}")

        # Check symlinks/hardlinks
        if member.issym() or member.islnk():
            if os.path.isabs(member.linkname):
                clean_link = member.linkname.lstrip("/")
                resolved_link = os.path.realpath(os.path.abspath(os.path.join(destination_dir, clean_link)))
                if not (resolved_link == dest_abs or resolved_link.startswith(dest_abs + os.sep)):
                    raise ValueError(f"Insecure tar symlink escaping rootfs: {member.name} -> {member.linkname}")
            else:
                member_dir = os.path.dirname(target_path)
                resolved_link = os.path.realpath(os.path.abspath(os.path.join(member_dir, member.linkname)))
                if not (resolved_link == dest_abs or resolved_link.startswith(dest_abs + os.sep)):
                    raise ValueError(f"Insecure tar relative symlink escaping rootfs: {member.name} -> {member.linkname}")

        # Reject character/block special devices and FIFOs
        if member.ischr() or member.isblk() or member.isfifo():
            raise ValueError(f"Insecure tar member (device special file or FIFO): {member.name}")

        # Clear setuid and setgid bits
        member.mode = member.mode & ~(0o4000 | 0o2000)
        validated_members.append(member)

    # Perform extraction with standard filter if available; fail hard on any filter violation
    if hasattr(tarfile, "data_filter"):
        try:
            tar.extractall(destination_dir, members=validated_members, filter="data")
            return
        except Exception as err:
            raise ValueError(f"Tar extraction rejected by data filter: {err}") from err

    tar.extractall(destination_dir, members=validated_members)

def pull_and_extract_oci_image(image_ref, destination_dir, allow_synthetic=False):
    """
    Daemonless OCI / Docker Hub layer extractor.
    Downloads and unpacks image layers directly into destination_dir/rootfs in RAM tmpfs.
    Enforces strict failure handling with zero synthetic fallback unless allow_synthetic=True.
    """
    clean_ref = image_ref
    if clean_ref.startswith("docker://"):
        clean_ref = clean_ref[9:]
    elif clean_ref.startswith("oci://"):
        clean_ref = clean_ref[6:]

    repo = clean_ref.split(":")[0] if ":" in clean_ref else clean_ref
    tag = clean_ref.split(":")[1] if ":" in clean_ref else "latest"
    if "/" not in repo:
        repo = f"library/{repo}"

    rootfs_dir = os.path.join(destination_dir, "rootfs")
    os.makedirs(rootfs_dir, exist_ok=True)

    metadata = {
        "image": clean_ref,
        "repo": repo,
        "tag": tag,
        "layers_extracted": 0,
        "daemonless": True,
        "rootfs": rootfs_dir
    }

    try:
        # 1. Acquire Docker Hub anonymous bearer token
        auth_url = f"https://auth.docker.io/token?service=registry.docker.io&scope=repository:{repo}:pull"
        req = urllib.request.Request(auth_url, headers={"User-Agent": "Neuronix-Container/1.0"})
        with urllib.request.urlopen(req, timeout=8) as resp:
            token = json.loads(resp.read().decode("utf-8")).get("token")

        # 2. Query manifest
        man_url = f"https://registry-1.docker.io/v2/{repo}/manifests/{tag}"
        man_req = urllib.request.Request(man_url, headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json",
            "User-Agent": "Neuronix-Container/1.0"
        })
        with urllib.request.urlopen(man_req, timeout=8) as m_resp:
            man_data = json.loads(m_resp.read().decode("utf-8"))

        # Resolve multiarch if manifest list returned
        target_digest = None
        if "manifests" in man_data:
            for item in man_data.get("manifests", []):
                arch = item.get("platform", {}).get("architecture")
                if arch in {"amd64", "x86_64"}:
                    target_digest = item.get("digest")
                    break
            if target_digest:
                sub_url = f"https://registry-1.docker.io/v2/{repo}/manifests/{target_digest}"
                sub_req = urllib.request.Request(sub_url, headers={
                    "Authorization": f"Bearer {token}",
                    "Accept": "application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json",
                    "User-Agent": "Neuronix-Container/1.0"
                })
                with urllib.request.urlopen(sub_req, timeout=8) as s_resp:
                    man_data = json.loads(s_resp.read().decode("utf-8"))

        layers = man_data.get("layers", [])
        if not layers:
            raise ValueError(f"No layers found in manifest for {repo}:{tag}")

        for layer in layers:
            l_digest = layer.get("digest")
            if not l_digest:
                continue
            blob_url = f"https://registry-1.docker.io/v2/{repo}/blobs/{l_digest}"
            blob_req = urllib.request.Request(blob_url, headers={
                "Authorization": f"Bearer {token}",
                "User-Agent": "Neuronix-Container/1.0"
            })
            with urllib.request.urlopen(blob_req, timeout=15) as b_resp:
                layer_tmp = tempfile.NamedTemporaryFile(dir=destination_dir, delete=False)
                shutil.copyfileobj(b_resp, layer_tmp)
                layer_tmp.close()
                try:
                    with tarfile.open(layer_tmp.name, "r:*") as tf:
                        safe_extract_tar(tf, rootfs_dir)
                    metadata["layers_extracted"] += 1
                finally:
                    if os.path.exists(layer_tmp.name):
                        os.unlink(layer_tmp.name)

        return rootfs_dir, metadata, "OCI rootfs successfully extracted in RAM"
    except Exception as e:
        if allow_synthetic:
            # Fallback to synthesizing minimal functional rootfs for hermetic offline test environments
            for d in ["bin", "etc", "usr", "lib", "tmp", "home", "root"]:
                os.makedirs(os.path.join(rootfs_dir, d), exist_ok=True)
            with open(os.path.join(rootfs_dir, "etc", "os-release"), "w") as f:
                f.write(f"NAME=\"NEURONIX OCI ({clean_ref})\"\nID=neuronix-oci\nPRETTY_NAME=\"NEURONIX Daemonless OCI Container\"\n")
            metadata["offline_synthetic"] = True
            metadata["notice"] = f"Initialized ephemeral container rootfs (network resolution notice: {e})"
            return rootfs_dir, metadata, "Offline synthetic rootfs prepared in RAM"
        else:
            shutil.rmtree(rootfs_dir, ignore_errors=True)
            return None, metadata, f"Failed to pull OCI image '{image_ref}': {e}"

def setup_ram_workspace(target, custom_shm_base="/dev/shm", require_ram=True, allow_synthetic=False):
    """Allocates ephemeral RAM workspace and clones/stages target repository or OCI image."""
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

    project_name = "workspace"

    if is_oci_url(target):
        rootfs_dir, meta, msg = pull_and_extract_oci_image(target, workspace_dir, allow_synthetic=allow_synthetic)
        if not rootfs_dir:
            shutil.rmtree(workspace_dir, ignore_errors=True)
            return None, None, msg
        active_dir = rootfs_dir
    elif is_git_url(target):
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
        except Exception as e:
            shutil.rmtree(workspace_dir, ignore_errors=True)
            return None, None, f"Failed to stage target directory in RAM workspace: {e}"
    else:
        active_dir = workspace_dir

    return workspace_dir, active_dir, "Workspace successfully prepared in RAM"

def build_bwrap_command(active_dir, command=None, enable_fhs=True, unshare_net=False, extra_binds=None, extra_env=None):
    """
    Constructs an isolated bubblewrap execution command or fallback subshell command.
    Ensures private PID, UTS, IPC namespaces, dynamic FHS emulation, and optional network unsharing.
    Returns (cmd_tokens, env_dict).
    """
    has_bwrap = shutil.which("bwrap") is not None
    user = os.environ.get("USER", "neuronix")

    # Detect if active_dir is an OCI rootfs (contains /bin or /usr/bin and /etc)
    is_oci_rootfs = (os.path.isdir(os.path.join(active_dir, "bin")) or 
                     os.path.isdir(os.path.join(active_dir, "usr", "bin"))) and \
                    os.path.isdir(os.path.join(active_dir, "etc"))

    if has_bwrap:
        bwrap_cmd = [
            "bwrap",
            "--clearenv",
            "--unshare-pid",
            "--unshare-uts",
            "--unshare-ipc"
        ]
        if unshare_net:
            bwrap_cmd.append("--unshare-net")

        if is_oci_rootfs:
            bwrap_cmd.extend([
                "--bind", active_dir, "/",
                "--dev", "/dev",
                "--proc", "/proc",
                "--tmpfs", "/tmp",
                "--setenv", "HOME", "/root",
                "--setenv", "PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "--chdir", "/"
            ])
        else:
            bwrap_cmd.extend([
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
                "--setenv", "LANG", os.environ.get("LANG", "C.UTF-8")
            ])

            if enable_fhs:
                fhs = resolve_fhs_paths()
                if os.path.isdir("/usr/lib"):
                    bwrap_cmd.extend(["--symlink", "usr/lib", "/lib64"])
                    bwrap_cmd.extend(["--symlink", "usr/lib", "/lib"])
                elif fhs.get("ld_linux") and os.path.exists(fhs["ld_linux"]):
                    bwrap_cmd.extend(["--ro-bind", fhs["ld_linux"], "/lib64/ld-linux-x86-64.so.2"])

                if fhs.get("env", {}).get("LD_LIBRARY_PATH"):
                    bwrap_cmd.extend(["--setenv", "LD_LIBRARY_PATH", fhs["env"]["LD_LIBRARY_PATH"]])
                if fhs.get("env", {}).get("NIX_LD"):
                    bwrap_cmd.extend(["--setenv", "NIX_LD", fhs["env"]["NIX_LD"]])
                    bwrap_cmd.extend(["--setenv", "NIX_LD_LIBRARY_PATH", fhs["env"].get("NIX_LD_LIBRARY_PATH", "")])

        bwrap_cmd.extend([
            "--setenv", "NEURONIX_CONTAINER", "1",
            "--setenv", "NEURONIX_SANDBOX", "1"
        ])

        if not unshare_net and os.path.exists("/etc/resolv.conf"):
            bwrap_cmd.extend(["--ro-bind", "/etc/resolv.conf", "/etc/resolv.conf"])
        if os.path.exists("/etc/ssl"):
            bwrap_cmd.extend(["--ro-bind", "/etc/ssl", "/etc/ssl"])

        # Bind extra files/directories if provided
        if extra_binds:
            for host_src, container_dest, ro in extra_binds:
                if os.path.exists(host_src):
                    flag = "--ro-bind" if ro else "--bind"
                    bwrap_cmd.extend([flag, host_src, container_dest])

        # Apply extra env vars
        if extra_env:
            for k, v in extra_env.items():
                bwrap_cmd.extend(["--setenv", str(k), str(v)])

        if command:
            bwrap_cmd.extend(["bash", "-c", command])
        else:
            bwrap_cmd.extend(["bash"])

        return bwrap_cmd, None
    else:
        sub_env = sanitize_environment()
        sub_env["HOME"] = active_dir
        if enable_fhs:
            fhs = resolve_fhs_paths()
            sub_env.update(fhs.get("env", {}))
        if extra_env:
            sub_env.update(extra_env)
        tokens = ["bash", "-c", command] if command else ["bash"]
        return tokens, sub_env

def run_container_session(active_dir, command=None, env_vars=None, enable_fhs=True, unshare_net=False):
    """Executes a command or launches an interactive shell inside the container with FHS emulation."""
    if not active_dir or not os.path.isdir(active_dir):
        return 1, "Invalid container directory"

    cmd_tokens, sub_env = build_bwrap_command(
        active_dir,
        command=command,
        enable_fhs=enable_fhs,
        unshare_net=unshare_net,
        extra_env=env_vars
    )
    res = subprocess.run(cmd_tokens, cwd=active_dir, env=sub_env, check=False)
    return res.returncode, "Container session closed"

# Backward-compatible alias
run_sandbox_session = run_container_session

def synthesize_micro_dns_hosts(services, scratch_dir):
    """
    Synthesizes an in-memory /etc/hosts mapping service names to loopback aliases.
    Enables zero-root, daemonless inter-service discovery in ephemeral stacks.
    """
    hosts_path = os.path.join(scratch_dir, "hosts")
    lines = [
        "127.0.0.1 localhost",
        "::1 localhost ip6-localhost ip6-loopback"
    ]
    base_octet = 10
    service_ips = {}
    for name in services.keys():
        clean_name = "".join(c for c in name if c.isalnum() or c in "-_")
        ip = f"127.0.0.{base_octet}"
        service_ips[clean_name] = ip
        lines.append(f"{ip} {clean_name}.local {clean_name}")
        base_octet += 1

    with open(hosts_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return hosts_path, service_ips

def run_stack_session(stack_file, custom_shm_base="/dev/shm", timeout_sec=None, allow_secret_env=False):
    """
    Ephemeral Multi-Service Stack Orchestrator (Alternative to docker-compose).
    Runs multi-service declarative definitions in RAM with isolated Bubblewrap containers, Micro-DNS & graceful termination.
    """
    if not os.path.isfile(stack_file):
        return {
            "status": "error",
            "message": f"Stack specification file not found: {stack_file}"
        }

    try:
        with open(stack_file, "r") as f:
            content = f.read()
        
        stack_data = None
        try:
            stack_data = json.loads(content)
        except Exception:
            try:
                import yaml
                stack_data = yaml.safe_load(content)
            except Exception as ye:
                return {
                    "status": "error",
                    "message": f"Failed to parse stack file as JSON or YAML: {ye}"
                }
    except Exception as e:
        return {"status": "error", "message": f"Failed to read stack file: {e}"}

    services = stack_data.get("services", {})
    if not services:
        return {"status": "error", "message": "No services defined in stack file"}

    # Allocate ephemeral stack workspace
    ws_dir, _, msg = setup_ram_workspace(tempfile.gettempdir(), custom_shm_base=custom_shm_base)
    if not ws_dir:
        return {"status": "error", "message": f"Failed to allocate RAM workspace for stack: {msg}"}

    hosts_file, service_ips = synthesize_micro_dns_hosts(services, ws_dir)
    procs = {}
    statuses = {}

    for name, s_cfg in services.items():
        cmd = s_cfg.get("command") or s_cfg.get("run") or f"echo 'Starting service {name}'"
        svc_env = {
            "NEURONIX_STACK_HOSTS": hosts_file,
            "HOSTALIASES": hosts_file
        }
        for svc_name, svc_ip in service_ips.items():
            svc_env[f"SERVICE_{svc_name.upper()}_IP"] = svc_ip
            svc_env[f"SERVICE_{svc_name.upper()}_HOST"] = f"{svc_name}.local"

        if "env" in s_cfg and isinstance(s_cfg["env"], dict):
            for k, v in s_cfg["env"].items():
                k_upper = str(k).upper()
                if not allow_secret_env:
                    if any(pat in k_upper for pat in SENSITIVE_ENV_PATTERNS) or k in SENSITIVE_ENV_EXACT:
                        continue
                svc_env[str(k)] = str(v)
        
        try:
            # Wrap service inside container bubblewrap isolation with Micro-DNS hosts file mounted
            extra_binds = [(hosts_file, "/etc/hosts", True)]
            cmd_tokens, sub_env = build_bwrap_command(
                ws_dir,
                command=cmd,
                extra_binds=extra_binds,
                extra_env=svc_env
            )
            p = subprocess.Popen(cmd_tokens, cwd=ws_dir, env=sub_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            procs[name] = p
            statuses[name] = {"pid": p.pid, "command": cmd, "status": "running", "ip": service_ips.get(name, "127.0.0.1")}
        except Exception as pe:
            statuses[name] = {"status": "failed", "error": str(pe)}

    time.sleep(0.2)
    for name, p in procs.items():
        if p.poll() is not None:
            statuses[name]["status"] = "exited"
            statuses[name]["exit_code"] = p.returncode

    for name, p in procs.items():
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=1)
            except Exception:
                p.kill()

    teardown_container(ws_dir)

    return {
        "status": "success",
        "services_count": len(services),
        "services": statuses,
        "dns_hosts": service_ips,
        "message": "Ephemeral multi-service stack orchestrated with Micro-DNS and vaporized cleanly in RAM"
    }

def build_container_oci(target, output_tar, tag="latest", repo="neuronix-app", entrypoint=None, mode="auto"):
    """
    Declarative Nix-to-OCI Micro-Layer Compiler.
    Compiles target source, Nix closure, or derivation into a standard OCI Image Layout tarball.
    Generates OCI Image Layout (oci-layout, index.json, blobs/sha256/*) and
    Docker archive format (manifest.json, repositories, config.json, layer.tar).
    """
    if not os.path.exists(target):
        return False, f"Target path does not exist: {target}"

    if mode not in {"auto", "nix", "source"}:
        return False, f"Invalid build mode '{mode}': must be 'auto', 'nix', or 'source'"

    src_dir = target if os.path.isdir(target) else os.path.dirname(os.path.abspath(target))
    
    # Check if target is a Nix flake or derivation
    is_nix = os.path.isfile(os.path.join(src_dir, "flake.nix")) or \
             os.path.isfile(os.path.join(src_dir, "default.nix")) or \
             target.startswith("/nix/store/")

    if mode == "nix" and not is_nix:
        return False, f"Target '{target}' is not a Nix project (flake.nix or default.nix missing) but mode='nix' was requested"

    nix_store_paths = []
    if mode == "nix" or (mode == "auto" and is_nix):
        if not shutil.which("nix"):
            if mode == "nix":
                return False, "Nix binary 'nix' not found in PATH; cannot resolve Nix closure"
        else:
            try:
                eval_target = target if target.startswith("/nix/store/") else src_dir
                res = subprocess.run(
                    ["nix", "path-info", "-r", eval_target],
                    capture_output=True, text=True, timeout=15, check=False
                )
                if res.returncode == 0:
                    nix_store_paths = [p.strip() for p in res.stdout.strip().splitlines() if p.strip().startswith("/nix/store/")]
                elif mode == "nix":
                    err_msg = res.stderr.strip() or f"exit code {res.returncode}"
                    return False, f"Nix closure evaluation failed for '{eval_target}': {err_msg}"
            except Exception as err:
                if mode == "nix":
                    return False, f"Nix closure evaluation error: {err}"

    if not entrypoint:
        if nix_store_paths:
            entrypoint = ["/bin/sh"]
        elif os.path.isfile(os.path.join(src_dir, "flake.nix")):
            entrypoint = ["/bin/sh"]
        elif os.path.isfile(os.path.join(src_dir, "main.py")):
            entrypoint = ["python3", "main.py"]
        elif os.path.isfile(os.path.join(src_dir, "index.js")):
            entrypoint = ["node", "index.js"]
        elif os.path.isfile(os.path.join(src_dir, "main.go")):
            entrypoint = ["./main"]
        else:
            entrypoint = ["/bin/sh"]

    out_dir = os.path.dirname(os.path.abspath(output_tar))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with tempfile.TemporaryDirectory(dir="/dev/shm" if os.path.isdir("/dev/shm") else None) as td:
        layer_tar = os.path.join(td, "layer.tar")
        hasher = hashlib.sha256()

        with tarfile.open(layer_tar, "w") as tar:
            if mode != "nix" or not nix_store_paths:
                for item in sorted(os.listdir(src_dir)):
                    if item in {".git", ".direnv", "dist", ".cache", "__pycache__"}:
                        continue
                    p = os.path.join(src_dir, item)
                    tar.add(p, arcname=os.path.join("app", item) if not item.startswith("bin") else item)

            for sp in nix_store_paths:
                if os.path.exists(sp):
                    tar.add(sp, arcname=sp.lstrip("/"))

        with open(layer_tar, "rb") as f:
            while chunk := f.read(65536):
                hasher.update(chunk)
        layer_sha = hasher.hexdigest()
        layer_size = os.path.getsize(layer_tar)

        # 1. OCI Image Config Blob
        config_data = {
            "architecture": "amd64",
            "os": "linux",
            "rootfs": {
                "type": "layers",
                "diff_ids": [f"sha256:{layer_sha}"]
            },
            "config": {
                "Env": [
                    "PATH=/app/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                    "NEURONIX_OCI_IMAGE=1"
                ],
                "WorkingDir": "/app",
                "Entrypoint": entrypoint
            }
        }
        config_bytes = json.dumps(config_data, indent=2).encode("utf-8")
        config_sha = hashlib.sha256(config_bytes).hexdigest()

        # 2. OCI Image Manifest Blob
        manifest_obj = {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "config": {
                "mediaType": "application/vnd.oci.image.config.v1+json",
                "digest": f"sha256:{config_sha}",
                "size": len(config_bytes)
            },
            "layers": [
                {
                    "mediaType": "application/vnd.oci.image.layer.v1.tar",
                    "digest": f"sha256:{layer_sha}",
                    "size": layer_size
                }
            ],
            "annotations": {
                "org.opencontainers.image.ref.name": f"{repo}:{tag}"
            }
        }
        manifest_bytes = json.dumps(manifest_obj, indent=2).encode("utf-8")
        manifest_sha = hashlib.sha256(manifest_bytes).hexdigest()

        # 3. Create OCI Content-Addressable Blob Storage
        blobs_dir = os.path.join(td, "blobs", "sha256")
        os.makedirs(blobs_dir, exist_ok=True)

        blob_config = os.path.join(blobs_dir, config_sha)
        with open(blob_config, "wb") as f:
            f.write(config_bytes)

        blob_layer = os.path.join(blobs_dir, layer_sha)
        shutil.copyfile(layer_tar, blob_layer)

        blob_manifest = os.path.join(blobs_dir, manifest_sha)
        with open(blob_manifest, "wb") as f:
            f.write(manifest_bytes)

        # 4. Standard OCI Layout Descriptor Files
        oci_layout_file = os.path.join(td, "oci-layout")
        with open(oci_layout_file, "w") as f:
            json.dump({"imageLayoutVersion": "1.0.0"}, f)

        index_data = {
            "schemaVersion": 2,
            "manifests": [
                {
                    "mediaType": "application/vnd.oci.image.manifest.v1+json",
                    "digest": f"sha256:{manifest_sha}",
                    "size": len(manifest_bytes),
                    "annotations": {
                        "org.opencontainers.image.ref.name": f"{repo}:{tag}"
                    }
                }
            ]
        }
        index_file = os.path.join(td, "index.json")
        with open(index_file, "w") as f:
            json.dump(index_data, f, indent=2)

        # 5. Docker Archive Format Compatibility Files (for docker load / podman load)
        docker_manifest_data = [{
            "Config": f"{config_sha}.json",
            "RepoTags": [f"{repo}:{tag}"],
            "Layers": ["layer.tar"]
        }]
        docker_manifest_file = os.path.join(td, "manifest.json")
        with open(docker_manifest_file, "wb") as f:
            f.write(json.dumps(docker_manifest_data, indent=2).encode("utf-8"))

        repositories_data = {repo: {tag: config_sha}}
        repo_file = os.path.join(td, "repositories")
        with open(repo_file, "wb") as f:
            f.write(json.dumps(repositories_data, indent=2).encode("utf-8"))

        config_file = os.path.join(td, f"{config_sha}.json")
        with open(config_file, "wb") as f:
            f.write(config_bytes)

        # 6. Assemble Full Dual-Format Archive
        with tarfile.open(output_tar, "w") as out:
            # OCI Image Layout structure
            out.add(oci_layout_file, arcname="oci-layout")
            out.add(index_file, arcname="index.json")
            out.add(blob_config, arcname=f"blobs/sha256/{config_sha}")
            out.add(blob_layer, arcname=f"blobs/sha256/{layer_sha}")
            out.add(blob_manifest, arcname=f"blobs/sha256/{manifest_sha}")
            # Docker legacy archive structure
            out.add(docker_manifest_file, arcname="manifest.json")
            out.add(repo_file, arcname="repositories")
            out.add(config_file, arcname=f"{config_sha}.json")
            out.add(layer_tar, arcname="layer.tar")

    return True, f"Declarative micro-OCI image compiled to {output_tar} ({repo}:{tag})"

CONTAINER_RUNTIME_DIR = os.path.expanduser("~/.local/share/neuronix/containers")

def daemonize_container_session(target, name, command=None, custom_shm_base="/dev/shm", enable_fhs=True, unshare_net=False):
    """
    Spawns an isolated container session as a background daemon without Docker daemon.
    Supervised via systemd-run --user when available, or detached process supervisor.
    Ensures background execution runs inside container bubblewrap isolation.
    """
    if not name or not isinstance(name, str):
        return False, "Container daemon name must be specified"
    clean_name = "".join(c for c in name if c.isalnum() or c in "-_")
    runtime_dir = os.path.join(CONTAINER_RUNTIME_DIR, clean_name)
    os.makedirs(runtime_dir, exist_ok=True)
    pid_file = os.path.join(runtime_dir, "pid")

    if os.path.exists(pid_file):
        try:
            with open(pid_file) as f:
                old_pid = int(f.read().strip())
            os.kill(old_pid, 0)
            return False, f"Container daemon '{clean_name}' is already running (PID: {old_pid})"
        except (OSError, ValueError):
            try:
                os.unlink(pid_file)
            except OSError:
                pass

    ws_dir, act_dir, msg = setup_ram_workspace(target, custom_shm_base=custom_shm_base)
    if not ws_dir:
        return False, f"Failed to allocate workspace: {msg}"

    exec_cmd = command if command else "while true; do sleep 3600; done"
    cmd_tokens, sub_env = build_bwrap_command(
        act_dir,
        command=exec_cmd,
        enable_fhs=enable_fhs,
        unshare_net=unshare_net,
        extra_env={"NEURONIX_CONTAINER_DAEMON": clean_name}
    )

    if shutil.which("systemd-run") and os.environ.get("XDG_RUNTIME_DIR"):
        unit_name = f"neuronix-container-{clean_name}.service"
        sys_cmd = [
            "systemd-run", "--user",
            f"--unit={unit_name}",
            "--description=NEURONIX Ephemeral Container Daemon",
            "--remain-after-exit=no",
            f"--working-directory={act_dir}"
        ] + cmd_tokens
        try:
            res = subprocess.run(sys_cmd, capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                with open(pid_file, "w") as f:
                    f.write("SYSTEMD_USER\n")
                with open(os.path.join(runtime_dir, "ws_dir"), "w") as f:
                    f.write(ws_dir + "\n")
                return True, f"Container daemon '{clean_name}' launched successfully via systemd user unit {unit_name}"
        except Exception:
            pass

    log_file = open(os.path.join(runtime_dir, "daemon.log"), "w")
    proc = subprocess.Popen(
        cmd_tokens,
        cwd=act_dir,
        env=sub_env,
        stdout=log_file,
        stderr=log_file,
        start_new_session=True
    )
    with open(pid_file, "w") as f:
        f.write(str(proc.pid) + "\n")
    with open(os.path.join(runtime_dir, "ws_dir"), "w") as f:
        f.write(ws_dir + "\n")

    return True, f"Container daemon '{clean_name}' running in background (PID: {proc.pid}, RAM: {ws_dir})"

def stop_container_daemon(name):
    """Stops a background container daemon and vaporizes its RAM workspace."""
    clean_name = "".join(c for c in name if c.isalnum() or c in "-_")
    runtime_dir = os.path.join(CONTAINER_RUNTIME_DIR, clean_name)
    pid_file = os.path.join(runtime_dir, "pid")
    ws_file = os.path.join(runtime_dir, "ws_dir")

    if not os.path.exists(pid_file):
        return False, f"Container daemon '{clean_name}' is not running"

    with open(pid_file) as f:
        val = f.read().strip()

    if val == "SYSTEMD_USER":
        unit_name = f"neuronix-container-{clean_name}.service"
        subprocess.run(["systemctl", "--user", "stop", unit_name], capture_output=True)
    else:
        try:
            pid = int(val)
            os.kill(pid, 15)
            time.sleep(0.2)
            os.kill(pid, 9)
        except OSError:
            pass

    if os.path.exists(ws_file):
        with open(ws_file) as f:
            ws_dir = f.read().strip()
        teardown_container(ws_dir)

    shutil.rmtree(runtime_dir, ignore_errors=True)
    return True, f"Container daemon '{clean_name}' stopped and workspace vaporized cleanly"

def list_container_daemons():
    """Lists active container daemons."""
    if not os.path.isdir(CONTAINER_RUNTIME_DIR):
        return []
    daemons = []
    for d in sorted(os.listdir(CONTAINER_RUNTIME_DIR)):
        r_dir = os.path.join(CONTAINER_RUNTIME_DIR, d)
        pid_file = os.path.join(r_dir, "pid")
        if os.path.isfile(pid_file):
            with open(pid_file) as f:
                val = f.read().strip()
            status = "running"
            if val != "SYSTEMD_USER":
                try:
                    os.kill(int(val), 0)
                except OSError:
                    status = "dead"
            daemons.append({"name": d, "target_type": val, "status": status})
    return daemons

def export_container_oci(source_dir, output_tar, tag="latest", repo="neuronix-app"):
    """
    Zero-Bloat OCI Exporter.
    Compiles workspace directory into an OCI/Docker compliant image tarball ready for docker load.
    """
    if not os.path.isdir(source_dir):
        return False, f"Source directory does not exist: {source_dir}"

    out_dir = os.path.dirname(os.path.abspath(output_tar))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with tempfile.TemporaryDirectory(dir="/dev/shm" if os.path.isdir("/dev/shm") else None) as td:
        layer_tar = os.path.join(td, "layer.tar")
        hasher = hashlib.sha256()
        with tarfile.open(layer_tar, "w") as tar:
            for item in sorted(os.listdir(source_dir)):
                p = os.path.join(source_dir, item)
                tar.add(p, arcname=item)

        with open(layer_tar, "rb") as f:
            while chunk := f.read(65536):
                hasher.update(chunk)
        layer_sha = hasher.hexdigest()

        layer_size = os.path.getsize(layer_tar)

        # 1. OCI Image Config
        config_data = {
            "architecture": "amd64",
            "os": "linux",
            "rootfs": {
                "type": "layers",
                "diff_ids": [f"sha256:{layer_sha}"]
            },
            "config": {
                "Env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
                "WorkingDir": "/workspace"
            }
        }
        config_bytes = json.dumps(config_data, indent=2).encode("utf-8")
        config_sha = hashlib.sha256(config_bytes).hexdigest()

        # 2. OCI Image Manifest
        manifest_obj = {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "config": {
                "mediaType": "application/vnd.oci.image.config.v1+json",
                "digest": f"sha256:{config_sha}",
                "size": len(config_bytes)
            },
            "layers": [
                {
                    "mediaType": "application/vnd.oci.image.layer.v1.tar",
                    "digest": f"sha256:{layer_sha}",
                    "size": layer_size
                }
            ],
            "annotations": {
                "org.opencontainers.image.ref.name": f"{repo}:{tag}"
            }
        }
        manifest_bytes = json.dumps(manifest_obj, indent=2).encode("utf-8")
        manifest_sha = hashlib.sha256(manifest_bytes).hexdigest()

        # 3. Content-Addressable Blobs
        blobs_dir = os.path.join(td, "blobs", "sha256")
        os.makedirs(blobs_dir, exist_ok=True)

        blob_config = os.path.join(blobs_dir, config_sha)
        with open(blob_config, "wb") as f:
            f.write(config_bytes)

        blob_layer = os.path.join(blobs_dir, layer_sha)
        shutil.copyfile(layer_tar, blob_layer)

        blob_manifest = os.path.join(blobs_dir, manifest_sha)
        with open(blob_manifest, "wb") as f:
            f.write(manifest_bytes)

        # 4. Standard OCI Layout Descriptor Files
        oci_layout_file = os.path.join(td, "oci-layout")
        with open(oci_layout_file, "w") as f:
            json.dump({"imageLayoutVersion": "1.0.0"}, f)

        index_data = {
            "schemaVersion": 2,
            "manifests": [
                {
                    "mediaType": "application/vnd.oci.image.manifest.v1+json",
                    "digest": f"sha256:{manifest_sha}",
                    "size": len(manifest_bytes),
                    "annotations": {
                        "org.opencontainers.image.ref.name": f"{repo}:{tag}"
                    }
                }
            ]
        }
        index_file = os.path.join(td, "index.json")
        with open(index_file, "w") as f:
            json.dump(index_data, f, indent=2)

        # 5. Docker Archive Compatibility Files
        docker_manifest_data = [{
            "Config": f"{config_sha}.json",
            "RepoTags": [f"{repo}:{tag}"],
            "Layers": ["layer.tar"]
        }]
        docker_manifest_file = os.path.join(td, "manifest.json")
        with open(docker_manifest_file, "wb") as f:
            f.write(json.dumps(docker_manifest_data, indent=2).encode("utf-8"))

        repositories_data = {
            repo: {
                tag: config_sha
            }
        }
        repo_file = os.path.join(td, "repositories")
        with open(repo_file, "wb") as f:
            f.write(json.dumps(repositories_data, indent=2).encode("utf-8"))

        config_file = os.path.join(td, f"{config_sha}.json")
        with open(config_file, "wb") as f:
            f.write(config_bytes)

        with tarfile.open(output_tar, "w") as out:
            # OCI structure
            out.add(oci_layout_file, arcname="oci-layout")
            out.add(index_file, arcname="index.json")
            out.add(blob_config, arcname=f"blobs/sha256/{config_sha}")
            out.add(blob_layer, arcname=f"blobs/sha256/{layer_sha}")
            out.add(blob_manifest, arcname=f"blobs/sha256/{manifest_sha}")
            # Docker legacy structure
            out.add(docker_manifest_file, arcname="manifest.json")
            out.add(repo_file, arcname="repositories")
            out.add(config_file, arcname=f"{config_sha}.json")
            out.add(layer_tar, arcname="layer.tar")

    return True, f"OCI image tarball successfully compiled to {output_tar}"

def teardown_container(workspace_dir, export_path=None):
    """Cleans up in-memory workspace and optionally exports changes."""
    if not workspace_dir or not os.path.exists(workspace_dir):
        return True, "No workspace to clean"

    if export_path:
        os.makedirs(export_path, exist_ok=True)
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
