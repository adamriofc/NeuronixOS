"""
System update engine for NEURONIX OS.
Enforces transactional updates, concurrency locks, postcondition health checks,
and automated rollback on regression.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import json
import subprocess
import shutil
from typing import Dict, Any, Tuple, Optional
from .generation import get_active_generation
from .lock import OperationLock, ConcurrentOperationError
from .journal import TransactionJournal, TransactionState
from .rollback import execute_rollback

class ReleaseMetadataError(RuntimeError):
    """Raised when release metadata or pinned revision cannot be determined."""
    pass

def get_repo_root() -> str:
    """Finds repository root containing flake.nix by ascending from current module."""
    curr = os.path.dirname(os.path.abspath(__file__))
    while curr and curr != "/":
        if os.path.exists(os.path.join(curr, "flake.nix")):
            return curr
        curr = os.path.dirname(curr)
    return os.environ.get("NEURONIX_REPO_ROOT", "/etc/nixos")

def get_pinned_nixpkgs_commit(repo_root=None, strict: bool = False) -> Optional[str]:
    """Retrieves locked nixpkgs commit from flake.lock or version.nix."""
    if repo_root is None:
        repo_root = get_repo_root()

    flake_lock = os.path.join(repo_root, "flake.lock")
    if os.path.exists(flake_lock):
        try:
            with open(flake_lock, "r", encoding="utf-8") as f:
                data = json.load(f)
                nodes = data.get("nodes", {})
                nixpkgs = nodes.get("nixpkgs", {})
                locked = nixpkgs.get("locked", {})
                rev = locked.get("rev")
                if rev:
                    return rev
        except Exception:
            pass

    version_nix = os.path.join(repo_root, "version.nix")
    if os.path.exists(version_nix):
        try:
            with open(version_nix, "r", encoding="utf-8") as f:
                for line in f:
                    if "nixpkgsCommit" in line:
                        return line.split('"')[1]
        except Exception:
            pass

    if strict:
        raise ReleaseMetadataError(
            f"Unable to resolve pinned nixpkgs commit from {repo_root}: missing or invalid flake.lock and version.nix."
        )
    return None

# Canonical alias preserving existing API contracts
get_pinned_commit = get_pinned_nixpkgs_commit

def get_local_release_metadata(repo_root=None) -> Dict[str, Any]:
    """Resolves local distribution release metadata from version.nix and release.json."""
    if repo_root is None:
        repo_root = get_repo_root()

    meta = {
        "version": "1.0.3",
        "release_tag": "v1.0.3",
        "state_version": "24.11",
        "channel": "nixos-26.05",
        "nixpkgs_commit": None,
        "release_commit": None
    }

    # Extract declarative metadata from version.nix
    version_nix = os.path.join(repo_root, "version.nix")
    if os.path.exists(version_nix):
        try:
            with open(version_nix, "r", encoding="utf-8") as f:
                for line in f:
                    if "version =" in line:
                        meta["version"] = line.split('"')[1]
                    elif "releaseTag =" in line:
                        meta["release_tag"] = line.split('"')[1]
                    elif "stateVersion =" in line:
                        meta["state_version"] = line.split('"')[1]
                    elif "channelStable =" in line:
                        meta["channel"] = line.split('"')[1]
                    elif "nixpkgsCommit =" in line:
                        meta["nixpkgs_commit"] = line.split('"')[1]
        except Exception:
            pass

    # Extract release commit from release manifest if present
    for candidate in [
        os.path.join(repo_root, "dist/release.json"),
        "/etc/neuronix/release.json"
    ]:
        if os.path.exists(candidate):
            try:
                with open(candidate, "r", encoding="utf-8") as f:
                    rdata = json.load(f)
                    c = rdata.get("commit")
                    if c:
                        meta["release_commit"] = c
                        break
            except Exception:
                pass

    return meta

def get_local_release_commit(repo_root=None) -> Optional[str]:
    """
    Resolves current local NEURONIX OS release commit hash.
    Prioritizes active git checkout commit; falls back to static release manifest.
    Never returns nixpkgs commit to eliminate cross-domain semantic confusion.
    """
    if repo_root is None:
        repo_root = get_repo_root()

    # 1. Inspect git workspace
    if shutil.which("git"):
        try:
            res = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass

    # 2. Inspect declarative release manifest
    meta = get_local_release_metadata(repo_root)
    if meta.get("release_commit"):
        return meta["release_commit"]

    return None

def get_upstream_release_commit(repo_root=None, timeout: float = 3.0) -> Tuple[Optional[str], Optional[str]]:
    """
    Probes remote NEURONIX OS upstream repository for latest release commit.
    Returns (remote_commit_hash, error_message).
    """
    if repo_root is None:
        repo_root = get_repo_root()

    remote_commit = None
    probe_error = None

    # Try git ls-remote if inside git repository
    if shutil.which("git"):
        try:
            res = subprocess.run(
                ["git", "ls-remote", "origin", "HEAD"],
                cwd=repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout,
                check=False
            )
            if res.returncode == 0 and res.stdout.strip():
                remote_commit = res.stdout.strip().split()[0]
        except Exception as e:
            probe_error = str(e)

    # Fallback to GitHub API probe
    if not remote_commit:
        try:
            import urllib.request
            req = urllib.request.Request(
                "https://api.github.com/repos/adamriofc/NeuronixOS/commits/main",
                headers={"User-Agent": "NEURONIX-Update-Engine"}
            )
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                remote_commit = data.get("sha")
        except Exception as e:
            if not probe_error:
                probe_error = str(e)

    return remote_commit, probe_error

def check_upstream_update(repo_root=None, timeout: float = 3.0) -> Dict[str, Any]:
    """
    Checks whether local system tracks latest upstream NEURONIX OS release.
    Strictly separates NEURONIX OS release commits from Nixpkgs revisions.
    Returns standardized status dictionary with zero cross-domain SHA comparison.
    """
    if repo_root is None:
        repo_root = get_repo_root()

    meta = get_local_release_metadata(repo_root)
    local_commit = get_local_release_commit(repo_root)
    pinned_nixpkgs = get_pinned_nixpkgs_commit(repo_root)

    if local_commit is None and pinned_nixpkgs is None:
        return {
            "status": "METADATA_UNAVAILABLE",
            "error": "Neither local release commit nor locked nixpkgs commit could be resolved.",
            "local_commit": None,
            "pinned_nixpkgs_commit": None,
            "channel": meta.get("channel", "nixos-26.05"),
            "release_tag": meta.get("release_tag", "v1.0.3")
        }

    remote_commit, probe_error = get_upstream_release_commit(repo_root, timeout=timeout)

    if not remote_commit:
        return {
            "status": "UNKNOWN",
            "error": f"Upstream check unreachable: {probe_error or 'Connection timed out'}",
            "local_commit": local_commit,
            "pinned_nixpkgs_commit": pinned_nixpkgs,
            "channel": meta.get("channel", "nixos-26.05"),
            "release_tag": meta.get("release_tag", "v1.0.3")
        }

    # Strict domain comparison: NEURONIX OS local commit vs NEURONIX OS remote commit
    is_up_to_date = False
    if local_commit:
        is_up_to_date = (local_commit == remote_commit)
    else:
        # If running on bare installed host without git or commit metadata,
        # consider version tag comparison
        is_up_to_date = False

    status = "UP_TO_DATE" if is_up_to_date else "UPDATE_AVAILABLE"
    return {
        "status": status,
        "local_commit": local_commit,
        "upstream_commit": remote_commit,
        "pinned_nixpkgs_commit": pinned_nixpkgs,
        "channel": meta.get("channel", "nixos-26.05"),
        "release_tag": meta.get("release_tag", "v1.0.3")
    }

def apply_system_update(
    flake_uri: Optional[str] = None,
    dry_run: bool = False,
    auto_rollback: bool = True
) -> Tuple[bool, int, Dict[str, Any]]:
    """
    Executes a transactional system update with strict 6-stage lifecycle:
    CHECK -> ACQUIRE LOCK -> JOURNAL -> BUILD/SWITCH -> HEALTH CHECK -> COMMIT (or ROLLBACK).
    Returns (success: bool, return_code: int, result_dict: dict).
    """
    repo_root = get_repo_root()
    flake_target = flake_uri or repo_root

    current_gen = get_active_generation()
    if current_gen is None or not str(current_gen).isdigit():
        return False, 1, {
            "stage": "PRECHECK",
            "error": "Active system generation could not be determined. Profile symlink is missing or invalid."
        }
    prev_gen_num = int(current_gen)

    if dry_run:
        cmd = ["nixos-rebuild", "dry-build", "--flake", flake_target]
        try:
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
            output = proc.stdout + proc.stderr
            return (proc.returncode == 0), proc.returncode, {
                "stage": "DRY_RUN",
                "output": output,
                "current_generation": prev_gen_num
            }
        except Exception as e:
            return False, 1, {"stage": "DRY_RUN", "error": str(e)}

    # Acquire exclusive concurrency lock
    try:
        lock = OperationLock("system_update")
        lock.acquire()
    except ConcurrentOperationError as e:
        return False, 126, {"stage": "LOCK_ACQUISITION", "error": str(e)}

    journal = TransactionJournal()
    tx_id = journal.start_transaction("system_update", {
        "previous_generation": prev_gen_num,
        "flake_target": flake_target
    })

    try:
        # Stage: APPLYING
        journal.update_transaction(tx_id, TransactionState.APPLYING)

        cmd = []
        if os.geteuid() != 0 and shutil.which("sudo"):
            cmd.append("sudo")
        cmd.extend(["nixos-rebuild", "switch", "--flake", flake_target])

        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        output = proc.stdout + proc.stderr

        if proc.returncode != 0:
            journal.abort_transaction(tx_id, f"nixos-rebuild failed with code {proc.returncode}: {output}")
            return False, proc.returncode, {
                "stage": "SWITCH",
                "error": output,
                "generation": prev_gen_num
            }

        # Stage: HEALTH CHECK
        new_gen = get_active_generation()
        new_gen_num = None
        health_passed = True
        health_error = None

        if new_gen is None or not str(new_gen).isdigit():
            health_passed = False
            health_error = "POSTCONDITION FAILED: Active system generation could not be determined post-switch."
        else:
            new_gen_num = int(new_gen)
            if new_gen_num <= prev_gen_num:
                health_passed = False
                health_error = f"Active generation did not advance (was {prev_gen_num}, now {new_gen_num})"

        # Probe systemd health if available
        if health_passed:
            systemctl_bin = shutil.which("systemctl")
            if systemctl_bin:
                try:
                    sc = subprocess.run(
                        [systemctl_bin, "is-system-running"],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=5.0,
                        check=False
                    )
                    state = sc.stdout.strip()
                    if state in ("degraded", "maintenance"):
                        health_passed = False
                        health_error = f"Systemd health probe FAILED: state is '{state}'"
                    elif sc.returncode != 0 and state not in ("running", "starting"):
                        health_passed = False
                        health_error = f"Systemd health probe UNKNOWN/FAILED: state '{state}', code {sc.returncode}"
                except subprocess.TimeoutExpired:
                    health_passed = False
                    health_error = "Systemd health probe UNKNOWN: timeout expired after 5.0s"
                except Exception as ex:
                    health_passed = False
                    health_error = f"Systemd health probe UNKNOWN: {ex}"

        if not health_passed:
            if auto_rollback:
                rb_ok, rb_code, rb_out = execute_rollback(target_generation=prev_gen_num)
                # Verify that active generation after rollback strictly equals prev_gen_num
                restored_gen = get_active_generation()
                rollback_proven = (rb_ok and restored_gen is not None and str(restored_gen) == str(prev_gen_num))
                if not rollback_proven:
                    rb_out = f"{rb_out} | POSTCONDITION FAILED: Expected restored generation #{prev_gen_num}, got #{restored_gen}"

                journal.mark_rolled_back(tx_id, {
                    "reason": health_error,
                    "rollback_success": rollback_proven,
                    "restored_generation": restored_gen,
                    "rollback_output": rb_out
                })
                return False, (0 if rollback_proven else 1), {
                    "stage": "AUTO_ROLLBACK",
                    "error": health_error,
                    "rollback_executed": True,
                    "rollback_verified": rollback_proven,
                    "restored_generation": restored_gen,
                    "rollback_output": rb_out
                }
            else:
                journal.abort_transaction(tx_id, health_error)
                return False, 1, {
                    "stage": "HEALTH_CHECK_FAILED",
                    "error": health_error,
                    "active_generation": new_gen_num
                }

        # Stage: COMMIT
        journal.commit_transaction(tx_id, {
            "previous_generation": prev_gen_num,
            "new_generation": new_gen_num
        })
        return True, 0, {
            "stage": "COMMITTED",
            "previous_generation": prev_gen_num,
            "new_generation": new_gen_num,
            "transaction_id": tx_id
        }

    except Exception as ex:
        journal.abort_transaction(tx_id, str(ex))
        return False, 1, {"stage": "EXCEPTION", "error": str(ex)}
    finally:
        lock.release()

def stage_system_update(
    flake_uri: Optional[str] = None,
    dry_run: bool = False
) -> Tuple[bool, int, Dict[str, Any]]:
    """
    Executes a transactional staged system update (prepared for next boot).
    Invokes `nixos-rebuild boot --flake <target>`.
    Acquires concurrency lock, logs to transaction journal, and commits.
    Returns (success: bool, return_code: int, result_dict: dict).
    """
    repo_root = get_repo_root()
    flake_target = flake_uri or repo_root

    current_gen = get_active_generation()
    prev_gen_num = int(current_gen) if (current_gen and str(current_gen).isdigit()) else 0

    if dry_run:
        cmd = ["nixos-rebuild", "dry-build", "--flake", flake_target]
        try:
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
            output = proc.stdout + proc.stderr
            return (proc.returncode == 0), proc.returncode, {
                "stage": "DRY_RUN",
                "output": output,
                "current_generation": prev_gen_num
            }
        except Exception as e:
            return False, 1, {"stage": "DRY_RUN", "error": str(e)}

    # Acquire exclusive concurrency lock
    try:
        lock = OperationLock("system_stage")
        lock.acquire()
    except ConcurrentOperationError as e:
        return False, 126, {"stage": "LOCK_ACQUISITION", "error": str(e)}

    journal = TransactionJournal()
    tx_id = journal.start_transaction("system_stage", {
        "previous_generation": prev_gen_num,
        "flake_target": flake_target,
        "mode": "staged"
    })

    try:
        journal.update_transaction(tx_id, TransactionState.APPLYING)

        cmd = []
        if os.geteuid() != 0 and shutil.which("sudo"):
            cmd.append("sudo")
        cmd.extend(["nixos-rebuild", "boot", "--flake", flake_target])

        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        output = proc.stdout + proc.stderr

        if proc.returncode != 0:
            journal.abort_transaction(tx_id, f"nixos-rebuild boot failed with code {proc.returncode}: {output}")
            return False, proc.returncode, {
                "stage": "STAGE_BUILD",
                "error": output,
                "generation": prev_gen_num
            }

        # Stage: COMMIT
        journal.commit_transaction(tx_id, {
            "previous_generation": prev_gen_num,
            "staged_mode": True,
            "flake_target": flake_target
        })
        return True, 0, {
            "stage": "COMMITTED",
            "mode": "staged",
            "previous_generation": prev_gen_num,
            "transaction_id": tx_id,
            "message": "System staged for next boot successfully."
        }
    except Exception as ex:
        journal.abort_transaction(tx_id, str(ex))
        return False, 1, {"stage": "EXCEPTION", "error": str(ex)}
    finally:
        lock.release()

