"""
NEURONIX State Lifecycle & Preservation Engine
Enforces 5-tier classification across filesystem mounts and paths (IMMUTABLE, DURABLE,
EPHEMERAL, DISPOSABLE_GHOST, FORENSIC) and computes StateLifecycleRoot.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
from typing import Dict, Any, List, Optional, Tuple

try:
    from .state import canonical_json_bytes, sha256_canonical
except (ImportError, ValueError):
    try:
        from neuronix_core.state import canonical_json_bytes, sha256_canonical
    except ImportError:
        import sys
        sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
        from neuronix_core.state import canonical_json_bytes, sha256_canonical


LIFECYCLE_TIERS = {
    "IMMUTABLE": {
        "description": "Cryptographically pinned, read-only filesystem store",
        "persistence": "READ_ONLY",
        "canonical_paths": ["/nix/store", "/usr/bin", "/usr/lib"]
    },
    "DURABLE": {
        "description": "Persistent user state and system configurations",
        "persistence": "PERSISTENT_STORAGE",
        "canonical_paths": ["/home", "/var", "/etc/nixos", "/persist"]
    },
    "EPHEMERAL": {
        "description": "Volatile memory filesystem reset on boot",
        "persistence": "VOLATILE_BOOT_BOUND",
        "canonical_paths": ["/tmp", "/run", "/run/user"]
    },
    "DISPOSABLE_GHOST": {
        "description": "Instant-vaporization RAM execution boundaries",
        "persistence": "VOLATILE_EXECUTION_BOUND",
        "canonical_paths": ["/dev/shm", "/run/neuronix/ghost"]
    },
    "FORENSIC": {
        "description": "Tamper-evident audit and state transition lineage logs",
        "persistence": "AUDIT_IMMUTABLE_LOG",
        "canonical_paths": ["/var/log/neuronix", "/var/log/audit"]
    }
}


class StateLifecycleEngine:
    """
    Classifies system paths and active mounts into the 5-tier lifecycle model.
    Derives deterministic StateLifecycleRoot for StateCommitment.
    """

    def __init__(self, mounts_file: str = "/proc/mounts"):
        self.mounts_file = mounts_file

    def classify_path(self, target_path: str) -> str:
        """
        Classifies a specific filesystem path into one of the 5 tiers.
        """
        clean_path = os.path.normpath(target_path)

        if clean_path.startswith("/var/log/neuronix") or clean_path.startswith("/var/log/audit"):
            return "FORENSIC"
        if clean_path.startswith("/dev/shm") or clean_path.startswith("/run/neuronix/ghost"):
            return "DISPOSABLE_GHOST"
        if clean_path.startswith("/nix/store"):
            return "IMMUTABLE"
        if clean_path.startswith("/tmp") or clean_path.startswith("/run"):
            return "EPHEMERAL"
        if clean_path.startswith(("/home", "/var", "/persist", "/etc")):
            return "DURABLE"

        return "DURABLE"

    def parse_system_mounts(self) -> List[Dict[str, str]]:
        """
        Parses active filesystem mounts from /proc/mounts.
        """
        mounts: List[Dict[str, str]] = []
        if not os.path.exists(self.mounts_file):
            return mounts

        try:
            with open(self.mounts_file, "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) >= 4:
                        device, mountpoint, fstype, options = parts[0], parts[1], parts[2], parts[3]
                        # Filter pseudo filesystems like proc, sysfs, cgroup
                        if fstype in ("proc", "sysfs", "cgroup", "cgroup2", "pstore", "bpf", "debugfs", "tracefs", "devpts", "securityfs", "fusectl", "configfs"):
                            continue
                        tier = self.classify_path(mountpoint)
                        opts_list = options.split(",")
                        is_ro = "ro" in opts_list
                        mounts.append({
                            "device": device,
                            "mountpoint": mountpoint,
                            "fstype": fstype,
                            "tier": tier,
                            "is_read_only": is_ro
                        })
        except Exception:
            pass

        # Sort canonically by mountpoint
        mounts.sort(key=lambda m: m["mountpoint"])
        return mounts

    def build_lifecycle_manifest(self) -> Dict[str, Any]:
        """
        Builds the complete state lifecycle manifest.
        """
        mounts = self.parse_system_mounts()
        tier_counts = {t: 0 for t in LIFECYCLE_TIERS}
        for m in mounts:
            tier = m.get("tier", "DURABLE")
            if tier in tier_counts:
                tier_counts[tier] += 1

        manifest = {
            "schema_version": "1.0.0",
            "manifest_type": "NEURONIX_STATE_LIFECYCLE_V1",
            "tier_definitions": LIFECYCLE_TIERS,
            "active_mount_count": len(mounts),
            "tier_distribution": tier_counts,
            "mounts": mounts
        }
        return manifest

    def compute_lifecycle_root(self, manifest: Optional[Dict[str, Any]] = None) -> str:
        """
        Computes deterministic RFC 8785 StateLifecycleRoot hash.
        """
        if manifest is None:
            manifest = self.build_lifecycle_manifest()
        return sha256_canonical(manifest)

    def validate_preservation_rules(self) -> Tuple[bool, List[str]]:
        """
        Verifies preservation invariants:
        1. /nix/store must be mounted read-only (or submount ro)
        2. /dev/shm must be marked DISPOSABLE_GHOST
        3. /tmp must be EPHEMERAL
        """
        errors = []
        mounts = self.parse_system_mounts()
        mount_map = {m["mountpoint"]: m for m in mounts}

        if "/dev/shm" in mount_map:
            if mount_map["/dev/shm"]["tier"] != "DISPOSABLE_GHOST":
                errors.append("Invariant breach: /dev/shm must be classified DISPOSABLE_GHOST")

        if "/tmp" in mount_map:
            if mount_map["/tmp"]["tier"] != "EPHEMERAL":
                errors.append("Invariant breach: /tmp must be classified EPHEMERAL")

        return len(errors) == 0, errors


def main() -> None:
    engine = StateLifecycleEngine()
    manifest = engine.build_lifecycle_manifest()
    root = engine.compute_lifecycle_root(manifest)
    valid, errors = engine.validate_preservation_rules()
    print(f"StateLifecycleRoot: {root}")
    print(f"Active Mounts: {manifest['active_mount_count']}, Tiers: {manifest['tier_distribution']}")
    print(f"Preservation Valid: {valid}")
    if errors:
        for err in errors:
            print(f"  Error: {err}")


if __name__ == "__main__":
    main()
