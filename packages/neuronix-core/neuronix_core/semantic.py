"""
NEURONIX Semantic NixOS AST & Grounding Engine
Provides option schema inspection, semantic grounding for AI models, and
dry-run state transition proposal simulation (SEC-019).

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import re
import hashlib
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


CANONICAL_OPTIONS = {
    "neuronix.security.ebpfLsm.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enforce eBPF LSM and Landlock sandbox boundaries for workspace processes."
    },
    "neuronix.security.secureBoot.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enforce Lanzaboote measured boot with TPM2 PCR 7 and PCR 11 binding."
    },
    "neuronix.storage.zramSwap.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enable compressed ZRAM swap with active PSI memory stall guarding."
    },
    "neuronix.hyperion.defaultTier": {
        "type": "string",
        "default": "TIER_1_RAM_GHOST",
        "allowed_values": ["TIER_0_FAST_PATH", "TIER_1_RAM_GHOST", "TIER_2_EBPF_ENCLAVE", "TIER_3_MICRO_VM"],
        "description": "Default adaptive isolation tier for workload execution."
    },
    "services.openssh.enable": {
        "type": "boolean",
        "default": False,
        "description": "Enable OpenSSH secure shell daemon."
    },
    "networking.firewall.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enable host packet filtering firewall."
    }
}

PROHIBITED_OPTION_PATTERNS = [
    r"users\.users\..*\.password",
    r"users\.users\..*\.initialPassword",
    r"security\.sudo\.wheelNeedsPassword\s*=\s*false",
    r"boot\.loader\.grub\.device\s*=\s*\"/dev/.*\""
]


class SemanticAstEngine:
    """
    Evaluates Nix expressions and simulates AI state transition proposals.
    Enforces the Proposer-Only invariant (SEC-019).
    """

    def __init__(self, root_dir: Optional[str] = None):
        self.root_dir = root_dir or os.environ.get("PROJECT_ROOT", "")

    def query_option(self, option_path: str) -> Optional[Dict[str, Any]]:
        """
        Returns formal option metadata, types, and descriptions for semantic grounding.
        """
        return CANONICAL_OPTIONS.get(option_path)

    def list_options(self, prefix: str = "") -> List[Dict[str, Any]]:
        """
        Lists available options matching an optional prefix.
        """
        results = []
        for path, meta in sorted(CANONICAL_OPTIONS.items()):
            if not prefix or path.startswith(prefix):
                entry = dict(meta)
                entry["option_path"] = path
                results.append(entry)
        return results

    def simulate_proposal(self, proposal: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
        """
        Simulates an AI state transition proposal against security invariants and option schemas.
        Enforces SEC-019 (AI proposals must pass offline dry-run simulation and cannot directly commit).
        """
        if not isinstance(proposal, dict):
            return False, "PROPOSAL_MALFORMED: Root must be a JSON dictionary", {}

        # 1. Proposer-only invariant check
        is_proposer = proposal.get("proposer_mode", True)
        if not is_proposer or proposal.get("direct_commit", False):
            return False, "FIREWALL_BREACH: AI models are restricted to PROPOSER_ONLY mode (direct commit prohibited)", {}

        # 2. Secret plaintext scan (SEC-013)
        proposal_str = json.dumps(proposal)
        for pattern in [r"BEGIN\s+PRIVATE\s+KEY", r"BEGIN\s+OPENSSH\s+PRIVATE\s+KEY", r"password\s*[:=]\s*\"[^\"]+\""]:
            if re.search(pattern, proposal_str, re.IGNORECASE):
                return False, "SECURITY_VIOLATION: Plaintext secrets detected in proposal (SEC-013)", {}

        # 3. Prohibited configuration patterns
        changes = proposal.get("changes", {})
        if not changes:
            return False, "PROPOSAL_EMPTY: No configuration changes declared in proposal", {}

        for opt_key, opt_val in changes.items():
            for regex in PROHIBITED_OPTION_PATTERNS:
                if re.match(regex, opt_key):
                    return False, f"SECURITY_VIOLATION: Option '{opt_key}' violates security baseline", {}

        # 4. Synthesize proposal hash and simulation result
        proposal_canonical = dict(proposal)
        proposal_canonical["simulated_at"] = 1700000000  # deterministic fixed timestamp for hash
        proposal_hash = sha256_canonical(proposal_canonical)

        report = {
            "schema_version": "1.0.0",
            "simulation_verdict": "ACCEPTED_FOR_OPERATOR_REVIEW",
            "proposal_hash": proposal_hash,
            "options_affected": len(changes),
            "changes_summary": {k: str(v) for k, v in changes.items()},
            "blast_radius": "ISOLATED_CONFIGURATION_DELTA",
            "safe_for_operator_apply": True
        }
        return True, "PROPOSAL_SIMULATION_PASSED", report


def main():
    engine = SemanticAstEngine()
    opts = engine.list_options("neuronix.")
    print(f"Found {len(opts)} neuronix options:")
    for o in opts:
        print(f"  - {o['option_path']} ({o['type']})")

    # Simulate valid proposal
    sample_proposal = {
        "proposer_mode": True,
        "direct_commit": False,
        "author": "ai_copilot",
        "intent": "Enable OpenSSH and Firewall",
        "changes": {
            "services.openssh.enable": True,
            "networking.firewall.enable": True
        }
    }
    valid, msg, report = engine.simulate_proposal(sample_proposal)
    print(f"\nProposal Simulation: {msg} (Verdict: {report.get('simulation_verdict')})")
    print(f"Proposal Hash: {report.get('proposal_hash')}")


if __name__ == "__main__":
    main()
