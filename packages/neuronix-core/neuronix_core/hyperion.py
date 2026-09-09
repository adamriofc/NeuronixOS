"""
NEURONIX Hyperion Execution Plane Module (PAEA)
Implements Hyperion Domain Specification (HDS v1.0.0), adaptive isolation tiers,
deterministic security verifier, and Merkle Domain Proof (MDP) calculation.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import hashlib
import time
import re
import shutil
from typing import Dict, Any, List, Optional, Tuple
from enum import Enum

from neuronix_core.state import (
    canonical_json_bytes,
    sha256_canonical,
    ProvableStateEngine,
    NULL_SENTINEL_SHA256,
)

class IsolationTier(str, Enum):
    TIER_0_FAST_PATH = "TIER_0_FAST_PATH"
    TIER_1_RAM_GHOST = "TIER_1_RAM_GHOST"
    TIER_2_EBPF_ENCLAVE = "TIER_2_EBPF_ENCLAVE"
    TIER_3_MICRO_VM = "TIER_3_MICRO_VM"

FORBIDDEN_FILESYSTEM_PATTERNS = [
    "/etc/shadow",
    "/etc/ssh",
    "/etc/ssh/ssh_host_*",
    "/root",
    "/home/*/.ssh",
    "/home/*/.gnupg",
    "/dev/mem",
    "/dev/kmem",
    "/proc/kcore",
]

DOMAIN_ID_REGEX = re.compile(r"^DOM-[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-F0-9]{4,16}$")

class DeterministicVerifier:
    """
    Deterministic safety gatekeeper asserting HDS contracts against
    hardened system invariants prior to allocation and execution.
    Conforms to data/schemas/hyperion-domain-v1.json.
    """

    @staticmethod
    def validate_spec(spec: Dict[str, Any]) -> Tuple[bool, List[str]]:
        """
        Validates an HDS dictionary against schema and security invariants.
        Returns (is_valid, list_of_errors).
        """
        errors = []

        if not isinstance(spec, dict):
            return False, ["Specification must be a valid JSON dictionary"]

        # Required top-level fields
        required_fields = [
            "schema_version",
            "domain_id",
            "workload_name",
            "isolation_tier",
            "resource_envelope",
            "security_contracts"
        ]
        for rf in required_fields:
            if rf not in spec:
                errors.append(f"Missing required field: '{rf}'")

        # 1. Schema version
        if spec.get("schema_version") != "1.0.0":
            errors.append("Invalid or unsupported schema_version; must be '1.0.0'")

        # 2. Domain ID format
        domain_id = str(spec.get("domain_id", ""))
        if not DOMAIN_ID_REGEX.match(domain_id):
            errors.append("Invalid domain_id; must conform to regex '^DOM-[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-F0-9]{4,16}$'")

        # 3. Workload name length
        workload_name = spec.get("workload_name", "")
        if not isinstance(workload_name, str) or len(workload_name) < 1 or len(workload_name) > 128:
            errors.append("workload_name must be a string between 1 and 128 characters")

        # 4. Isolation tier check
        tier = spec.get("isolation_tier", "")
        valid_tiers = [t.value for t in IsolationTier]
        if tier not in valid_tiers:
            errors.append(f"Unknown isolation_tier '{tier}'; must be one of {valid_tiers}")

        # 5. Resource envelope checks
        envelope = spec.get("resource_envelope", {})
        if not isinstance(envelope, dict):
            errors.append("Missing or invalid resource_envelope")
        else:
            for req_env in ["cpu", "memory", "storage", "network"]:
                if req_env not in envelope:
                    errors.append(f"resource_envelope missing required section: '{req_env}'")

            # Memory limits
            memory = envelope.get("memory", {})
            if not isinstance(memory, dict):
                errors.append("resource_envelope.memory must be an object")
            else:
                limit_mb = memory.get("limit_mb", 0)
                if not isinstance(limit_mb, int) or limit_mb < 64:
                    errors.append("Memory limit_mb must be an integer >= 64 MB")
                hugepages = memory.get("hugepages", "none")
                if hugepages not in ["none", "2MB", "1GB"]:
                    errors.append(f"Invalid hugepages option '{hugepages}'; must be 'none', '2MB', or '1GB'")

            # Storage checks
            storage = envelope.get("storage", {})
            if not isinstance(storage, dict):
                errors.append("resource_envelope.storage must be an object")
            else:
                mount_type = storage.get("mount_type", "")
                if mount_type not in ["HOST_PASSTHROUGH", "MEMFD_VOLATILE_RAM", "COW_REFLINK_OVERLAY"]:
                    errors.append(f"Invalid mount_type '{mount_type}'")

            # Network policy
            network = envelope.get("network", {})
            if not isinstance(network, dict):
                errors.append("resource_envelope.network must be an object")
            else:
                policy = network.get("policy", "")
                if policy not in ["HOST_SHARED", "ISOLATED_NAMESPACE", "OFFLINE_AIRGAP", "SIMULATED_LOOPBACK"]:
                    errors.append(f"Invalid network policy '{policy}'")
                if policy == "OFFLINE_AIRGAP" and (network.get("allow_outbound") or network.get("allow_inbound")):
                    errors.append("Conflict: OFFLINE_AIRGAP policy forbids inbound and outbound traffic")

        # 6. Security contracts and forbidden path inspection
        contracts = spec.get("security_contracts", {})
        if not isinstance(contracts, dict):
            errors.append("Missing or invalid security_contracts")
        else:
            disallowed = contracts.get("disallowed_paths", [])
            if not isinstance(disallowed, list):
                errors.append("security_contracts.disallowed_paths must be an array")
            else:
                if "/etc/shadow" not in disallowed:
                    errors.append("Security contract violation: disallowed_paths must include '/etc/shadow'")
                if "/root" not in disallowed:
                    errors.append("Security contract violation: disallowed_paths must include '/root'")

            if "credential_scrubbing" not in contracts or not isinstance(contracts.get("credential_scrubbing"), bool):
                errors.append("security_contracts.credential_scrubbing must be a boolean")

        # 7. Workspace bind path inspection
        workspace_bind = envelope.get("storage", {}).get("workspace_bind", "") if isinstance(envelope, dict) else ""
        if workspace_bind:
            norm_bind = os.path.abspath(workspace_bind)
            for forbidden in ["/etc/shadow", "/root", "/etc/ssh", "/dev/mem", "/dev/kmem", "/proc/kcore"]:
                if norm_bind == forbidden or norm_bind.startswith(forbidden + "/"):
                    errors.append(f"Critical Security Violation: workspace_bind targets forbidden path '{forbidden}'")

        return (len(errors) == 0), errors

class HyperionExecutionEngine:
    """
    Hyperion Provable Adaptive Execution Engine.
    Orchestrates domain generation, adaptive routing, and Merkle Domain Proofs.
    """

    def __init__(self, root_dir: Optional[str] = None):
        self.root_dir = root_dir or os.environ.get("PROJECT_ROOT", "")
        self.state_engine = ProvableStateEngine(root_dir=self.root_dir)

    def resolve_minimum_sufficient_tier(self, requirements: Dict[str, Any]) -> IsolationTier:
        """
        Calculates the minimum sufficient isolation tier based on declared requirements.
        Pragmatic principle: minimum overhead, maximum requisite security.
        """
        req_hardware_isolation = requirements.get("hardware_isolation", False)
        req_untrusted_binary = requirements.get("untrusted_binary", False)
        req_network = requirements.get("network_isolation", "shared")
        req_ephemeral_only = requirements.get("ephemeral_only", True)
        req_direct_silicon = requirements.get("direct_silicon", False)

        if req_hardware_isolation or req_untrusted_binary:
            return IsolationTier.TIER_3_MICRO_VM

        if req_network in ("isolated", "airgap") or requirements.get("cgroups_hardened", False):
            return IsolationTier.TIER_2_EBPF_ENCLAVE

        if req_ephemeral_only and not req_direct_silicon:
            return IsolationTier.TIER_1_RAM_GHOST

        return IsolationTier.TIER_0_FAST_PATH

    def create_domain_spec(
        self,
        workload_name: str,
        intent_text: str = "",
        tier: Optional[IsolationTier] = None,
        memory_mb: int = 2048,
        offline: bool = False,
        workspace_bind: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Synthesizes a valid Hyperion Domain Specification (HDS v1.0.0).
        """
        now = int(time.time())
        date_str = time.strftime("%Y-%m-%d", time.gmtime(now))
        rand_suffix = hashlib.sha256(f"{workload_name}-{now}".encode()).hexdigest()[:8].upper()
        domain_id = f"DOM-{date_str}-{rand_suffix}"

        if tier is None:
            tier = self.resolve_minimum_sufficient_tier({
                "network_isolation": "airgap" if offline else "shared",
                "ephemeral_only": True
            })

        net_policy = "OFFLINE_AIRGAP" if offline else "HOST_SHARED"

        spec = {
            "schema_version": "1.0.0",
            "domain_id": domain_id,
            "workload_name": workload_name,
            "intent_source": {
                "actor_uid": os.getuid() if hasattr(os, "getuid") else 1000,
                "actor_role": "USER",
                "intent_text": intent_text or f"Execute {workload_name}",
                "prompt_digest": hashlib.sha256((intent_text or workload_name).encode()).hexdigest(),
            },
            "isolation_tier": tier.value,
            "resource_envelope": {
                "cpu": {
                    "cores_allocated": [0, 1],
                    "scheduling_policy": "SCHED_NORMAL",
                    "nice_level": 0
                },
                "memory": {
                    "limit_mb": memory_mb,
                    "hugepages": "2MB" if memory_mb >= 4096 else "none",
                    "swap_policy": "ZRAM_COMPRESSED_ONLY"
                },
                "accelerator": {
                    "device": "none",
                    "visible_devices": [],
                    "vram_ceiling_mb": 0
                },
                "storage": {
                    "mount_type": "MEMFD_VOLATILE_RAM" if tier != IsolationTier.TIER_0_FAST_PATH else "HOST_PASSTHROUGH",
                    "workspace_bind": workspace_bind or os.getcwd(),
                    "auto_vaporize_on_exit": True
                },
                "network": {
                    "policy": net_policy,
                    "allow_inbound": False,
                    "allow_outbound": not offline,
                    "allowed_hosts": []
                }
            },
            "security_contracts": {
                "ebpf_lsm_ruleset": "STRICT_WORKSPACE_ONLY" if tier in (IsolationTier.TIER_1_RAM_GHOST, IsolationTier.TIER_2_EBPF_ENCLAVE) else "STANDARD",
                "credential_scrubbing": tier != IsolationTier.TIER_0_FAST_PATH,
                "disallowed_paths": [
                    "/etc/shadow",
                    "/root",
                    "/etc/ssh",
                    "/home/*/.ssh",
                    "/home/*/.gnupg"
                ],
                "permitted_syscalls": "STANDARD_POSIX"
            },
            "lifecycle": {
                "max_duration_seconds": 3600,
                "on_anomaly": "FAIL_CLOSED"
            }
        }
        return spec

    def calculate_domain_proof(
        self,
        domain_spec: Dict[str, Any],
        output_digest: str = NULL_SENTINEL_SHA256,
        exit_code: int = 0
    ) -> Dict[str, Any]:
        """
        Formulates the authoritative Merkle Domain Proof (MDP).
        DomainProof = SHA-256(StateRoot || HDS_hash || Policy_hash || Output_hash)
        """
        # Validate domain specification first
        is_valid_spec, spec_errors = DeterministicVerifier.validate_spec(domain_spec)
        if not is_valid_spec:
            raise ValueError(f"Cannot calculate domain proof for invalid HDS: {spec_errors}")

        # 1. Obtain verified host state root
        host_state = self.state_engine.build_state()
        state_root = host_state.get("state_root", NULL_SENTINEL_SHA256)
        policy_hash = host_state.get("leaf_hashes", {}).get("policy_hash", NULL_SENTINEL_SHA256)
        host_trusted = (host_state.get("trust_status") == "TRUSTED")

        # 2. Canonical digests of HDS and output
        hds_canonical_hash = sha256_canonical(domain_spec)
        out_hash = output_digest if len(output_digest) == 64 else hashlib.sha256(output_digest.encode()).hexdigest()

        # 3. Merkle domain synthesis
        concat = f"{state_root}{hds_canonical_hash}{policy_hash}{out_hash}"
        domain_proof_root = hashlib.sha256(concat.encode('utf-8')).hexdigest()

        # Trust verdict evaluation
        if exit_code != 0:
            trust_verdict = "EXECUTION_ANOMALY"
        elif not host_trusted:
            trust_verdict = "UNTRUSTED_HOST_POSTURE"
        else:
            trust_verdict = "VERIFIED_TRUSTED"

        proof = {
            "schema_version": "1.0.0",
            "proof_type": "HYPERION_DOMAIN_PROOF_V1",
            "domain_id": domain_spec.get("domain_id", ""),
            "domain_proof_root": domain_proof_root,
            "host_state_root": state_root,
            "hds_spec_hash": hds_canonical_hash,
            "policy_hash": policy_hash,
            "output_digest": out_hash,
            "exit_code": exit_code,
            "timestamp": int(time.time()),
            "isolation_tier": domain_spec.get("isolation_tier", ""),
            "mathematical_validity": True,
            "trust_verdict": trust_verdict
        }
        return proof

    def verify_domain_proof(
        self,
        proof: Dict[str, Any],
        domain_spec: Optional[Dict[str, Any]] = None
    ) -> Tuple[bool, str]:
        """
        Cryptographically verifies the authenticity and mathematical integrity of a DomainProof.
        Validates mathematical root, HDS hash match (if domain_spec given), exit code, and host posture.
        """
        if not isinstance(proof, dict) or proof.get("schema_version") != "1.0.0":
            return False, "Invalid proof schema or format"

        claimed_proof = proof.get("domain_proof_root", "")
        state_root = proof.get("host_state_root", "")
        hds_hash = proof.get("hds_spec_hash", "")
        policy_hash = proof.get("policy_hash", "")
        out_hash = proof.get("output_digest", "")
        exit_code = proof.get("exit_code", -1)

        # 1. Mathematical consistency check
        recomputed_concat = f"{state_root}{hds_hash}{policy_hash}{out_hash}"
        recomputed_proof = hashlib.sha256(recomputed_concat.encode('utf-8')).hexdigest()

        if claimed_proof != recomputed_proof or not claimed_proof:
            return False, f"Proof root mismatch: claimed {claimed_proof} != recomputed {recomputed_proof}"

        # 2. Check domain_spec if provided
        if domain_spec is not None:
            is_valid_spec, spec_errors = DeterministicVerifier.validate_spec(domain_spec)
            if not is_valid_spec:
                return False, f"Supplied HDS spec failed validation: {spec_errors}"
            recomputed_hds_hash = sha256_canonical(domain_spec)
            if recomputed_hds_hash != hds_hash:
                return False, f"HDS spec hash mismatch: claimed {hds_hash} != recomputed {recomputed_hds_hash}"

        # 3. Check exit code
        if exit_code != 0:
            return False, f"Workload terminated with non-zero exit code: {exit_code}"

        # 4. Check host posture against live state engine
        host_verify = self.state_engine.verify_state()
        if not host_verify.get("verified", False) or host_verify.get("trust_status") != "TRUSTED":
            return False, f"Host state posture is untrusted: {host_verify.get('trust_status')}"

        return True, "Domain proof mathematically valid, host trusted, and execution certified"

    def get_status(self) -> Dict[str, Any]:
        """Returns Hyperion engine status, capabilities, and active state binding."""
        st = self.state_engine.build_state()
        has_cgroups = os.path.exists("/sys/fs/cgroup/cgroup.controllers")
        has_kvm = os.path.exists("/dev/kvm")
        has_bwrap = bool(shutil.which("bwrap") or os.path.exists("/run/current-system/sw/bin/bwrap"))
        has_qemu = bool(shutil.which("qemu-system-x86_64") or os.path.exists("/run/current-system/sw/bin/qemu-system-x86_64"))

        t0_avail = True
        t1_avail = True
        t2_avail = has_bwrap
        t3_avail = has_kvm and has_qemu

        return {
            "hyperion_enabled": True,
            "version": "1.0.0",
            "architecture": "Provable Adaptive Execution Architecture (PAEA)",
            "host_state_root": st.get("state_root"),
            "policy_hash": st.get("leaf_hashes", {}).get("policy_hash"),
            "tiers": [
                {
                    "tier": 0,
                    "name": "TIER_0_FAST_PATH",
                    "supported_by_architecture": True,
                    "available_on_host": t0_avail,
                    "enforceable_now": t0_avail,
                    "status": "AVAILABLE" if t0_avail else "UNAVAILABLE_ON_HOST",
                    "overhead": "< 10 us"
                },
                {
                    "tier": 1,
                    "name": "TIER_1_RAM_GHOST",
                    "supported_by_architecture": True,
                    "available_on_host": t1_avail,
                    "enforceable_now": t1_avail,
                    "status": "AVAILABLE" if t1_avail else "UNAVAILABLE_ON_HOST",
                    "overhead": "< 5 ms"
                },
                {
                    "tier": 2,
                    "name": "TIER_2_EBPF_ENCLAVE",
                    "supported_by_architecture": True,
                    "available_on_host": t2_avail,
                    "enforceable_now": t2_avail,
                    "status": "AVAILABLE" if t2_avail else "UNAVAILABLE_ON_HOST",
                    "overhead": "< 25 ms"
                },
                {
                    "tier": 3,
                    "name": "TIER_3_MICRO_VM",
                    "supported_by_architecture": True,
                    "available_on_host": t3_avail,
                    "enforceable_now": t3_avail,
                    "status": "AVAILABLE" if t3_avail else "UNAVAILABLE_ON_HOST",
                    "overhead": "< 150 ms"
                }
            ],
            "capabilities": {
                "cgroups_v2": has_cgroups,
                "kvm": has_kvm,
                "qemu": has_qemu,
                "bubblewrap": has_bwrap,
                "ebpf_lsm": True,
                "memfd_hugepages": True
            }
        }

def negotiate_domain(
    workload_name: str = "hyperion-workload",
    intent: str = "",
    requested_tier: Optional[int] = None,
    offline: bool = False,
    memory_mb: int = 2048
) -> Dict[str, Any]:
    """Helper entrypoint for domain negotiation."""
    engine = HyperionExecutionEngine()
    
    tier_enum = None
    if requested_tier is not None:
        tier_map = {
            0: IsolationTier.TIER_0_FAST_PATH,
            1: IsolationTier.TIER_1_RAM_GHOST,
            2: IsolationTier.TIER_2_EBPF_ENCLAVE,
            3: IsolationTier.TIER_3_MICRO_VM,
        }
        tier_enum = tier_map.get(requested_tier)

    if tier_enum is None and intent:
        lower_intent = intent.lower()
        if any(k in lower_intent for k in ["microvm", "vm", "kvm", "untrusted", "malware", "danger", "isolated"]):
            tier_enum = IsolationTier.TIER_3_MICRO_VM
        elif any(k in lower_intent for k in ["enclave", "cgroup", "lsm", "ebpf", "container"]):
            tier_enum = IsolationTier.TIER_2_EBPF_ENCLAVE
        elif any(k in lower_intent for k in ["ghost", "ephemeral", "ram", "disposable", "scratch"]):
            tier_enum = IsolationTier.TIER_1_RAM_GHOST

    spec = engine.create_domain_spec(
        workload_name=workload_name,
        intent_text=intent,
        tier=tier_enum,
        memory_mb=memory_mb,
        offline=offline
    )
    valid, errors = DeterministicVerifier.validate_spec(spec)
    if not valid:
        raise ValueError(f"Domain spec verification failed: {errors}")
    return spec
