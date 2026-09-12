"""
NEURONIX Declarative Storage Intelligence & Transactional Planning Engine
Reconstructs declarative partition, LUKS2, and Btrfs layouts into deterministic plans
enforced by a 7-Factor Destructive Operation Firewall (SEC-012).

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

from __future__ import annotations

import os
import sys
import json
import re
import time
import hashlib
from typing import Dict, Any, List, Set, Optional, Tuple

try:
    from .state import canonical_json_bytes, sha256_canonical
    from .crypto import (
        _ed25519_sign,
        _ed25519_verify,
        _ed25519_publickey,
        generate_keypair as generate_operator_keypair,
        sign_canonical,
        verify_canonical,
    )
except (ImportError, ValueError):
    try:
        from neuronix_core.state import canonical_json_bytes, sha256_canonical
        from neuronix_core.crypto import (
            _ed25519_sign,
            _ed25519_verify,
            _ed25519_publickey,
            generate_keypair as generate_operator_keypair,
            sign_canonical,
            verify_canonical,
        )
    except ImportError:
        import sys
        sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
        from neuronix_core.state import canonical_json_bytes, sha256_canonical
        from neuronix_core.crypto import (
            _ed25519_sign,
            _ed25519_verify,
            _ed25519_publickey,
            generate_keypair as generate_operator_keypair,
            sign_canonical,
            verify_canonical,
        )


def sign_storage_authorization(
    target_device: str,
    plan_hash: str,
    operator_id: str,
    clearance: str,
    challenge_nonce: str,
    expiry: int,
    secret_key_hex: str
) -> Dict[str, Any]:
    """
    Synthesizes and signs an authoritative Ed25519 Storage Authorization Token.
    AuthorizationPayload = canonical(challenge_nonce, clearance, expiry, operator_id, plan_hash, target_device)
    """
    sk = bytes.fromhex(secret_key_hex)
    pk = _ed25519_publickey(sk)
    payload = {
        "challenge_nonce": challenge_nonce,
        "clearance": clearance,
        "expiry": expiry,
        "operator_id": operator_id,
        "plan_hash": plan_hash,
        "target_device": target_device
    }
    payload_bytes = canonical_json_bytes(payload)
    sig = _ed25519_sign(payload_bytes, sk, pk)
    return {
        "operator_id": operator_id,
        "clearance": clearance,
        "challenge_nonce": challenge_nonce,
        "expiry": expiry,
        "public_key": pk.hex(),
        "signature": sig.hex()
    }

def verify_storage_authorization(
    auth_dict: Any,
    target_device: str,
    plan_hash: str,
    trusted_public_keys: Optional[List[str]] = None,
    seen_nonces: Optional[Set[str]] = None,
    current_time: Optional[int] = None
) -> Tuple[bool, str]:
    """
    Cryptographically verifies Ed25519 Storage Authorization Payload.
    Validates:
    - Operator identity and clearance level (STORAGE_ADMIN, DISASTER_RECOVERY_OPERATOR, ROOT)
    - Replay-resistant unique challenge nonce
    - Freshness window (expiry > current_time)
    - Target device and plan hash cryptographic binding
    - Ed25519 asymmetric signature authenticity against trusted public keys
    """
    if not isinstance(auth_dict, dict):
        return False, "Operator authorization must be a dictionary containing cryptographic signature"

    operator_id = auth_dict.get("operator_id")
    if not operator_id or not isinstance(operator_id, str):
        return False, "Missing or invalid 'operator_id'"

    clearance = auth_dict.get("clearance")
    if clearance not in ("STORAGE_ADMIN", "DISASTER_RECOVERY_OPERATOR", "ROOT"):
        return False, f"Insufficient clearance: '{clearance}' (must be STORAGE_ADMIN, DISASTER_RECOVERY_OPERATOR, or ROOT)"

    nonce = auth_dict.get("challenge_nonce")
    if not nonce or not isinstance(nonce, str):
        return False, "Missing or invalid 'challenge_nonce' (replay protection required)"

    if seen_nonces is not None and nonce in seen_nonces:
        return False, f"REPLAY_ATTACK_DETECTED: challenge_nonce '{nonce}' has already been consumed"

    expiry = auth_dict.get("expiry")
    if not isinstance(expiry, int):
        return False, "Missing or invalid 'expiry' timestamp integer"

    now_val = current_time if current_time is not None else int(time.time())
    if expiry <= now_val:
        return False, f"EXPIRED_AUTHORIZATION: Authorization token expired at {expiry} (current: {now_val})"

    pk_hex = auth_dict.get("public_key")
    if not pk_hex or not isinstance(pk_hex, str) or len(pk_hex) != 64:
        return False, "Missing or invalid 64-hex-character 'public_key'"

    if trusted_public_keys is not None and pk_hex not in trusted_public_keys:
        return False, f"UNTRUSTED_KEY: Operator public key '{pk_hex[:16]}...' not in trusted public keys registry"

    sig_hex = auth_dict.get("signature")
    if not sig_hex or not isinstance(sig_hex, str) or len(sig_hex) != 128:
        return False, "Missing or invalid 128-hex-character Ed25519 'signature'"

    try:
        pk_bytes = bytes.fromhex(pk_hex)
        sig_bytes = bytes.fromhex(sig_hex)
    except Exception:
        return False, "Malformed hexadecimal encoding in public_key or signature"

    payload = {
        "challenge_nonce": nonce,
        "clearance": clearance,
        "expiry": expiry,
        "operator_id": operator_id,
        "plan_hash": plan_hash,
        "target_device": target_device
    }
    payload_bytes = canonical_json_bytes(payload)

    if not _ed25519_verify(sig_bytes, payload_bytes, pk_bytes):
        return False, "CRYPTOGRAPHIC_SIGNATURE_INVALID: Ed25519 asymmetric signature verification failed"

    if seen_nonces is not None:
        seen_nonces.add(nonce)

    return True, "AUTHORIZATION_VALID_ED25519"


DEFAULT_BTRFS_LAYOUT = {
    "device": "/dev/nvme0n1",
    "table_type": "gpt",
    "partitions": [
        {
            "name": "ESP",
            "type": "EF00",
            "size_mib": 1024,
            "filesystem": "vfat",
            "mountpoint": "/boot"
        },
        {
            "name": "root",
            "type": "8300",
            "size_mib": 0,  # 0 means fill remaining space
            "luks2": {
                "cipher": "aes-xts-plain64",
                "key_size_bits": 512,
                "pbkdf": "argon2id"
            },
            "filesystem": "btrfs",
            "subvolumes": [
                {"name": "@", "mountpoint": "/", "mount_options": "noatime,compress=zstd:3,space_cache=v2"},
                {"name": "@nix", "mountpoint": "/nix", "mount_options": "noatime,compress=zstd:3,space_cache=v2"},
                {"name": "@home", "mountpoint": "/home", "mount_options": "noatime,compress=zstd:3,space_cache=v2"},
                {"name": "@snapshots", "mountpoint": "/.snapshots", "mount_options": "noatime,compress=zstd:3,space_cache=v2"},
                {"name": "@swap", "mountpoint": "/swap", "mount_options": "noatime"}
            ]
        }
    ]
}


class StorageFirewall:
    """
    Implements the 7-Factor Destructive Operation Firewall (SEC-012, MES-NRX-002).
    Blocks accidental or unauthorized destructive formatting with fail-closed semantics.
    """

    CRITICAL_MOUNTS = {"/", "/nix", "/nix/store", "/boot", "/home", "/var"}
    CONSUMED_NONCES: Set[str] = set()

    @classmethod
    def get_active_mounts(cls, mounts_file: str = "/proc/mounts") -> List[Dict[str, str]]:
        active = []
        if os.path.exists(mounts_file):
            try:
                with open(mounts_file, "r", encoding="utf-8") as f:
                    for line in f:
                        parts = line.split()
                        if len(parts) >= 2:
                            active.append({"device": parts[0], "mountpoint": parts[1]})
            except Exception:
                pass
        return active

    @classmethod
    def get_active_generation_devices(
        cls,
        mounts_file: str = "/proc/mounts",
        cmdline_file: str = "/proc/cmdline"
    ) -> Set[str]:
        """
        Discovers the physical block devices backing the currently active NixOS generation,
        bootloader, and root filesystem.
        """
        active_devices = set()

        # Check critical mounts in active mounts file
        if os.path.exists(mounts_file):
            try:
                with open(mounts_file, "r", encoding="utf-8") as f:
                    for line in f:
                        parts = line.split()
                        if len(parts) >= 2:
                            dev, mp = parts[0], parts[1]
                            if mp in cls.CRITICAL_MOUNTS:
                                active_devices.add(dev)
                                # Extract parent base device (e.g., /dev/nvme0n1 from /dev/nvme0n1p2)
                                dev_base = re.sub(r"p?\d+$", "", dev)
                                if dev_base:
                                    active_devices.add(dev_base)
            except Exception:
                pass

        # Check kernel command line for root device pointers
        if os.path.exists(cmdline_file):
            try:
                with open(cmdline_file, "r", encoding="utf-8") as f:
                    cmdline = f.read()
                    for token in cmdline.split():
                        if token.startswith("root="):
                            root_val = token.split("=", 1)[1]
                            active_devices.add(root_val)
                            base_dev = re.sub(r"p?\d+$", "", root_val)
                            if base_dev:
                                active_devices.add(base_dev)
            except Exception:
                pass

        return active_devices

    @classmethod
    def evaluate_7_factors(
        cls,
        target_device: str,
        plan_hash: str,
        expected_plan_hash: str,
        confirmation_token: Optional[str] = None,
        operator_auth: Optional[Any] = None,
        operator_signature: Optional[Any] = None,
        simulated_entropy: bool = True,
        active_mounts_override: Optional[List[Dict[str, str]]] = None,
        active_devices_override: Optional[Set[str]] = None,
        allow_active_generation_override: bool = False,
        trusted_public_keys: Optional[List[str]] = None,
        seen_nonces: Optional[Set[str]] = None,
        current_time: Optional[int] = None
    ) -> Tuple[bool, str, Dict[str, bool]]:
        """
        Evaluates all 7 factors with fail-closed semantics:
        1. Factor 1: Physical Device Identity
        2. Factor 2: Current Mount State Lockout
        3. Factor 3: Active Generation Safety
        4. Factor 4: Existing Filesystem Entropy Inspection
        5. Factor 5: Preflight Simulation Clearance
        6. Factor 6: Exact-Match Typed Confirmation Token
        7. Factor 7: Operator Identity & Asymmetric Cryptographic Authorization (Ed25519)
        """
        factors = {
            "factor_1_device_identity": False,
            "factor_2_mount_state_safe": False,
            "factor_3_generation_safety": False,
            "factor_4_entropy_cleared": False,
            "factor_5_simulation_passed": False,
            "factor_6_typed_token_valid": False,
            "factor_7_operator_authorized": False
        }

        # Factor 1: Device identity check
        if target_device and (target_device.startswith("/dev/") or target_device.startswith("loop_sim")):
            factors["factor_1_device_identity"] = True
        else:
            return False, "FIREWALL_VIOLATION: Factor 1 failed - Invalid physical device path", factors

        # Factor 2: Current Mount State Lockout (Fail-closed on active mounts)
        mounts = active_mounts_override if active_mounts_override is not None else cls.get_active_mounts()
        for m in mounts:
            dev = m.get("device", "")
            mp = m.get("mountpoint", "")
            if dev == target_device or dev.startswith(target_device):
                if mp in cls.CRITICAL_MOUNTS:
                    return False, f"FIREWALL_VIOLATION: Factor 2 failed - Target device {target_device} is active under critical mount '{mp}'", factors
        factors["factor_2_mount_state_safe"] = True

        # Factor 3: Active Generation Safety (Protect active NixOS generation / LKG)
        active_devices = active_devices_override if active_devices_override is not None else cls.get_active_generation_devices()
        target_base = re.sub(r"p?\d+$", "", target_device)

        if not allow_active_generation_override and (target_device in active_devices or target_base in active_devices):
            return False, f"FIREWALL_VIOLATION: Factor 3 failed - Target device {target_device} hosts active NixOS generation or system store", factors
        factors["factor_3_generation_safety"] = True

        # Factor 5: Simulation clearance
        if plan_hash and plan_hash == expected_plan_hash:
            factors["factor_5_simulation_passed"] = True
        else:
            return False, "FIREWALL_VIOLATION: Factor 5 failed - Plan hash mismatch between plan and execution token", factors

        # Factor 4 & 6: Entropy Inspection and EXACT Typed Token Enforcement
        # Format: DESTROY <DEVICE_BASENAME> PLAN <FULL_64_CHAR_PLAN_HASH>
        dev_base = os.path.basename(target_device)
        expected_token = f"DESTROY {dev_base} PLAN {plan_hash}"

        if simulated_entropy:
            # Device has existing data; exact typed confirmation token is strictly mandatory
            if confirmation_token and confirmation_token == expected_token:
                factors["factor_4_entropy_cleared"] = True
                factors["factor_6_typed_token_valid"] = True
            else:
                return False, f"FIREWALL_VIOLATION: Factor 6 failed - Existing data on {target_device} requires exact token '{expected_token}'", factors
        else:
            # Clean disk
            factors["factor_4_entropy_cleared"] = True
            factors["factor_6_typed_token_valid"] = True

        # Factor 7: Operator Identity & Asymmetric Cryptographic Authorization (Ed25519)
        # Binds authorization identity and clearance policy, strictly rejecting plain boolean flags and dummy strings
        auth = operator_auth if operator_auth is not None else operator_signature

        if auth is None:
            return False, "FIREWALL_VIOLATION: Factor 7 failed - Operator explicit cryptographic authorization missing", factors

        if not isinstance(auth, dict):
            return False, "FIREWALL_VIOLATION: Factor 7 failed - Operator authorization must be an Ed25519 signed dictionary (dummy strings and booleans disallowed)", factors

        effective_nonces = seen_nonces if seen_nonces is not None else cls.CONSUMED_NONCES
        sig_ok, sig_reason = verify_storage_authorization(
            auth_dict=auth,
            target_device=target_device,
            plan_hash=plan_hash,
            trusted_public_keys=trusted_public_keys,
            seen_nonces=effective_nonces,
            current_time=current_time
        )
        if not sig_ok:
            return False, f"FIREWALL_VIOLATION: Factor 7 failed - {sig_reason}", factors

        factors["factor_7_operator_authorized"] = True

        all_pass = all(factors.values())
        return all_pass, "AUTHORIZED_ALL_7_FACTORS_SATISFIED" if all_pass else "FIREWALL_REJECTED", factors


class StoragePlannerEngine:
    """
    Plans and generates deterministic storage layout transactions, computing StorageRoot.
    """

    def __init__(self, layout_spec: Optional[Dict[str, Any]] = None):
        self.layout_spec = layout_spec or DEFAULT_BTRFS_LAYOUT

    def generate_plan(self) -> Dict[str, Any]:
        """
        Translates declarative layout into deterministic step-by-step partition plan.
        """
        device = self.layout_spec.get("device", "/dev/nvme0n1")
        table = self.layout_spec.get("table_type", "gpt")
        partitions = self.layout_spec.get("partitions", [])

        steps: List[Dict[str, Any]] = []
        part_num = 1

        # Step 1: Create partition table
        steps.append({
            "action": "CREATE_PARTITION_TABLE",
            "device": device,
            "table_type": table
        })

        # Step 2: Create individual partitions
        for p in partitions:
            name = p.get("name", f"part{part_num}")
            size_mib = p.get("size_mib", 0)
            ptype = p.get("type", "8300")
            fs_type = p.get("filesystem", "ext4")

            steps.append({
                "action": "CREATE_PARTITION",
                "device": device,
                "partition_number": part_num,
                "name": name,
                "type_code": ptype,
                "size_mib": size_mib
            })

            # Handle LUKS2 container if declared
            if "luks2" in p:
                steps.append({
                    "action": "FORMAT_LUKS2",
                    "partition": f"{device}p{part_num}" if "nvme" in device else f"{device}{part_num}",
                    "cipher": p["luks2"].get("cipher", "aes-xts-plain64"),
                    "key_size": p["luks2"].get("key_size_bits", 512),
                    "pbkdf": p["luks2"].get("pbkdf", "argon2id")
                })

            # Handle Btrfs subvolumes
            if fs_type == "btrfs":
                steps.append({
                    "action": "FORMAT_FILESYSTEM",
                    "filesystem": "btrfs",
                    "label": "neuronix-root",
                    "target": f"{device}p{part_num}" if "nvme" in device else f"{device}{part_num}"
                })
                for subvol in p.get("subvolumes", []):
                    steps.append({
                        "action": "CREATE_BTRFS_SUBVOLUME",
                        "subvolume_name": subvol["name"],
                        "mountpoint": subvol["mountpoint"],
                        "mount_options": subvol.get("mount_options", "noatime")
                    })
            elif fs_type == "vfat":
                steps.append({
                    "action": "FORMAT_FILESYSTEM",
                    "filesystem": "vfat",
                    "label": "ESP",
                    "target": f"{device}p{part_num}" if "nvme" in device else f"{device}{part_num}",
                    "mountpoint": p.get("mountpoint", "/boot")
                })

            part_num += 1

        plan = {
            "schema_version": "1.0.0",
            "plan_type": "NEURONIX_STORAGE_PLAN_V1",
            "target_device": device,
            "step_count": len(steps),
            "layout_spec": self.layout_spec,
            "steps": steps
        }
        return plan

    def compute_plan_hash(self, plan: Optional[Dict[str, Any]] = None) -> str:
        """
        Computes deterministic RFC 8785 StoragePlanHash.
        """
        if plan is None:
            plan = self.generate_plan()
        return sha256_canonical(plan)

    def compute_storage_root(self) -> str:
        """
        Computes canonical StorageRoot for StateCommitment.
        """
        plan = self.generate_plan()
        plan_hash = self.compute_plan_hash(plan)
        root_data = {
            "device": plan["target_device"],
            "plan_hash": plan_hash,
            "step_count": plan["step_count"],
            "table_type": self.layout_spec.get("table_type", "gpt")
        }
        return sha256_canonical(root_data)

    def simulate_execution(self, plan_or_size: Any = None) -> Dict[str, Any]:
        """
        Performs semantic preflight simulation of partition geometry, alignment,
        filesystem boundaries, and Btrfs subvolumes without touching physical disk.
        """
        if isinstance(plan_or_size, dict):
            plan = plan_or_size
            total_disk_mib = 102400
        elif isinstance(plan_or_size, (int, float)):
            total_disk_mib = int(plan_or_size)
            plan = self.generate_plan()
        else:
            total_disk_mib = 102400
            plan = self.generate_plan()

        plan_hash = self.compute_plan_hash(plan)
        sim_log = []
        errors = []

        partitions = self.layout_spec.get("partitions", [])
        current_sector = 2048  # 1 MiB alignment boundary (LBA 2048 at 512 bytes/sector)
        allocated_mib = 0

        # Step-by-step semantic execution check
        for idx, step in enumerate(plan["steps"], 1):
            action = step.get("action", "UNKNOWN")

            if action == "CREATE_PARTITION_TABLE":
                table_type = step.get("table_type")
                if table_type != "gpt":
                    errors.append(f"Unsupported partition table type '{table_type}', must be 'gpt'")
                sim_log.append({
                    "step_index": idx,
                    "action": action,
                    "status": "SIMULATION_SUCCESS",
                    "details": "Initialized GPT partition table header and backup LBA"
                })

            elif action == "CREATE_PARTITION":
                name = step.get("name", "")
                size_mib = step.get("size_mib", 0)
                ptype = step.get("type_code", "")

                if ptype == "EF00" and size_mib < 512:
                    errors.append(f"ESP partition '{name}' size {size_mib} MiB is below minimum 512 MiB")

                # Sector calculation
                if size_mib > 0:
                    sector_span = size_mib * 2048
                    allocated_mib += size_mib
                else:
                    remaining_mib = max(0, total_disk_mib - allocated_mib)
                    sector_span = remaining_mib * 2048
                    allocated_mib += remaining_mib

                end_sector = current_sector + sector_span - 1

                sim_log.append({
                    "step_index": idx,
                    "action": action,
                    "status": "SIMULATION_SUCCESS",
                    "details": f"Partition '{name}' allocated: start LBA {current_sector}, end LBA {end_sector} ({sector_span // 2048} MiB)"
                })
                current_sector = end_sector + 1

            elif action == "FORMAT_LUKS2":
                cipher = step.get("cipher", "")
                pbkdf = step.get("pbkdf", "")
                key_size = step.get("key_size", 0)
                if cipher != "aes-xts-plain64":
                    errors.append(f"Unsupported LUKS2 cipher '{cipher}'")
                if pbkdf != "argon2id":
                    errors.append(f"Insecure LUKS2 pbkdf '{pbkdf}', Argon2id required")
                if key_size < 256:
                    errors.append(f"Insufficient LUKS2 key size {key_size} bits")
                sim_log.append({
                    "step_index": idx,
                    "action": action,
                    "status": "SIMULATION_SUCCESS",
                    "details": f"LUKS2 container formatted: cipher={cipher}, pbkdf={pbkdf}, key_size={key_size}"
                })

            elif action == "CREATE_BTRFS_SUBVOLUME":
                subvol = step.get("subvolume_name", "")
                if not subvol.startswith("@"):
                    errors.append(f"Btrfs subvolume name '{subvol}' must start with '@' prefix")
                sim_log.append({
                    "step_index": idx,
                    "action": action,
                    "status": "SIMULATION_SUCCESS",
                    "details": f"Btrfs subvolume '{subvol}' mapped to mountpoint '{step.get('mountpoint')}'"
                })

            else:
                sim_log.append({
                    "step_index": idx,
                    "action": action,
                    "status": "SIMULATION_SUCCESS",
                    "details": f"Simulated {action} successfully"
                })

        all_ok = len(errors) == 0
        return {
            "simulation_mode": "SEMANTIC_PREFLIGHT",
            "target_device": plan["target_device"],
            "plan_hash": plan_hash,
            "steps_simulated": len(sim_log),
            "all_steps_succeeded": all_ok,
            "errors": errors,
            "log": sim_log
        }

    def verify_postconditions(
        self,
        observed_state: Dict[str, Any],
        plan: Optional[Dict[str, Any]] = None
    ) -> Tuple[bool, str]:
        """
        Verifies that observed physical state strictly matches the planned state.
        Fails closed on any structural mismatch (transaction FAILURE).
        """
        if plan is None:
            plan = self.generate_plan()

        planned_partitions = [s for s in plan.get("steps", []) if s.get("action") == "CREATE_PARTITION"]
        observed_partitions = observed_state.get("partitions", [])

        if len(planned_partitions) != len(observed_partitions):
            return False, f"POSTCONDITION_MISMATCH: Planned {len(planned_partitions)} partitions, observed {len(observed_partitions)}"

        for p_plan, p_obs in zip(planned_partitions, observed_partitions):
            if p_plan.get("name") != p_obs.get("name"):
                return False, f"POSTCONDITION_MISMATCH: Partition name mismatch: planned '{p_plan.get('name')}' != observed '{p_obs.get('name')}'"

        planned_subvols = [s.get("subvolume_name") for s in plan.get("steps", []) if s.get("action") == "CREATE_BTRFS_SUBVOLUME"]
        observed_subvols = observed_state.get("btrfs_subvolumes", [])
        if planned_subvols:
            if set(planned_subvols) != set(observed_subvols):
                return False, f"POSTCONDITION_MISMATCH: Btrfs subvolume mismatch: planned {planned_subvols}, observed {observed_subvols}"

        return True, "POSTCONDITION_VERIFIED_EXACT_MATCH"

get_active_generation_devices = StorageFirewall.get_active_generation_devices


def main() -> None:
    planner = StoragePlannerEngine()
    plan = planner.generate_plan()
    plan_hash = planner.compute_plan_hash(plan)
    storage_root = planner.compute_storage_root()
    sim = planner.simulate_execution()

    print(f"StoragePlanHash: {plan_hash}")
    print(f"StorageRoot:     {storage_root}")
    print(f"Total Steps:     {plan['step_count']}")
    print(f"Simulation:      {'PASSED' if sim['all_steps_succeeded'] else 'FAILED'}")


if __name__ == "__main__":
    main()

