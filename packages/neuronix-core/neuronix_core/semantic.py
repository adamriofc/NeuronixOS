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
import subprocess
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
    # NEURONIX Security Primitives
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
    "neuronix.security.strictUmask.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enforce system-wide umask 027 preventing world-readable files."
    },

    # NEURONIX Storage & Memory Shield
    "neuronix.storage.zramSwap.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enable compressed ZRAM swap with active PSI memory stall guarding."
    },
    "neuronix.storage.zramSwap.priority": {
        "type": "integer",
        "default": 32767,
        "description": "ZRAM swap device priority (32767 maximal)."
    },
    "neuronix.storage.layout": {
        "type": "string",
        "default": "gpt-luks2-btrfs",
        "allowed_values": ["gpt-luks2-btrfs", "gpt-btrfs-plain", "gpt-ext4"],
        "description": "Standard declarative partition and filesystem layout."
    },

    # NEURONIX Hyperion Adaptive Isolation
    "neuronix.hyperion.defaultTier": {
        "type": "string",
        "default": "TIER_1_RAM_GHOST",
        "allowed_values": ["TIER_0_FAST_PATH", "TIER_1_RAM_GHOST", "TIER_2_EBPF_ENCLAVE", "TIER_3_MICRO_VM"],
        "description": "Default adaptive isolation tier for workload execution."
    },
    "neuronix.hyperion.allowedBackends": {
        "type": "list",
        "default": ["host_direct", "tmpfs_overlay", "bwrap_seccomp", "kvm_qemu_v1"],
        "description": "Approved runtime execution hypervisors and sandboxes."
    },

    # NEURONIX Capability-Bound Secret Fabric
    "neuronix.secrets.ramMaterialization": {
        "type": "boolean",
        "default": True,
        "description": "Materialize decrypted Age secrets exclusively in volatile tmpfs RAM (/run/neuronix/secrets)."
    },
    "neuronix.secrets.aiVisibility": {
        "type": "string",
        "default": "METADATA_ONLY",
        "allowed_values": ["METADATA_ONLY", "NONE"],
        "description": "AI agent visibility policy restricting access to secret metadata only (SEC-014)."
    },
    "neuronix.provable_state.enforce": {
        "type": "boolean",
        "default": True,
        "description": "Enforce cryptographic state proofs and integrity verification across lifecycle transitions."
    },

    # Standard NixOS Core Subsystems
    "services.openssh.enable": {
        "type": "boolean",
        "default": False,
        "description": "Enable OpenSSH secure shell daemon."
    },
    "services.pipewire.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enable PipeWire low-latency multimedia routing daemon."
    },
    "services.tailscale.enable": {
        "type": "boolean",
        "default": False,
        "description": "Enable Tailscale zero-trust mesh networking."
    },
    "networking.firewall.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enable host packet filtering firewall."
    },
    "networking.hostName": {
        "type": "string",
        "default": "neuronix",
        "description": "System network hostname."
    },
    "boot.loader.systemd-boot.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enable systemd-boot EFI bootloader."
    },
    "boot.initrd.systemd.enable": {
        "type": "boolean",
        "default": True,
        "description": "Enable systemd in Stage 1 initramfs."
    }
}

PROHIBITED_OPTION_PATTERNS = [
    r"users\.users\..*\.password",
    r"users\.users\..*\.initialPassword",
    r"security\.sudo\.wheelNeedsPassword\s*=\s*false",
    r"boot\.loader\.grub\.device\s*=\s*\"/dev/.*\"",
    r"nix\.settings\.trusted-users\s*=\s*\[\s*\"\*\"\s*\]"
]


class SemanticAstEngine:
    """
    Evaluates Nix expressions and governs AI state transition proposals (MES-NRX-002).
    Wraps upstream Nix evaluation/parsing semantics and enforces the Proposer-Only invariant (SEC-019).
    """

    def __init__(self, root_dir: Optional[str] = None):
        self.root_dir = root_dir or os.environ.get("PROJECT_ROOT", "")

    @staticmethod
    def parse_nix_ast(nix_code: str) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
        """
        Wraps official 'nix-instantiate --parse' to validate Nix syntax into an AST.
        Falls back to internal lexical parser if nix-instantiate is unavailable in the environment.
        """
        if not nix_code or not nix_code.strip():
            return True, "EMPTY_EXPRESSION", {"type": "empty"}

        # Attempt invocation of official nix-instantiate
        try:
            res = subprocess.run(
                ["nix-instantiate", "--parse", "-E", nix_code],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5
            )
            if res.returncode == 0:
                return True, "NIX_SYNTAX_VALID", {"ast_text": res.stdout.strip()}
            else:
                return False, f"NIX_SYNTAX_ERROR: {res.stderr.strip()}", None
        except (FileNotFoundError, PermissionError):
            # nix-instantiate not in PATH: perform lexical/bracket validation
            return SemanticAstEngine._fallback_lexical_parse(nix_code)
        except Exception as e:
            return False, f"NIX_PARSER_EXCEPTION: {str(e)}", None

    @staticmethod
    def _fallback_lexical_parse(nix_code: str) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
        """
        Deterministic lexical and bracket-balance parser for offline or containerized environments.
        """
        stack = []
        in_string = False
        escape = False

        for idx, char in enumerate(nix_code):
            if in_string:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == '"':
                    in_string = False
                continue

            if char == '"':
                in_string = True
            elif char in "({[":
                stack.append((char, idx))
            elif char in ")}]":
                if not stack:
                    return False, f"SYNTAX_ERROR: Unmatched closing bracket '{char}' at index {idx}", None
                opening, _ = stack.pop()
                if (opening, char) not in [("(", ")"), ("{", "}"), ("[", "]")]:
                    return False, f"SYNTAX_ERROR: Mismatched bracket '{opening}' and '{char}' at index {idx}", None

        if in_string:
            return False, "SYNTAX_ERROR: Unterminated string literal in Nix expression", None
        if stack:
            opening, idx = stack[-1]
            return False, f"SYNTAX_ERROR: Unclosed bracket '{opening}' opened at index {idx}", None

        return True, "SYNTAX_VALID_LEXICAL", {"tokens": len(nix_code.split())}

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

    def generate_dry_run_diff(self, changes: Dict[str, Any]) -> str:
        """
        Synthesizes a declarative NixOS configuration diff.
        """
        diff_lines = [
            "--- /etc/nixos/configuration.nix (active)",
            "+++ /run/neuronix/proposed.nix (dry-run proposal)",
            "@@ -1,5 +1,10 @@"
        ]
        for k, v in sorted(changes.items()):
            if isinstance(v, bool):
                val_str = "true" if v else "false"
            elif isinstance(v, str):
                val_str = f'"{v}"'
            else:
                val_str = json.dumps(v)
            diff_lines.append(f"+  {k} = {val_str};")
        return "\n".join(diff_lines)

    def simulate_proposal(self, proposal: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
        """
        Simulates an AI state transition proposal against security invariants,
        type constraints, and option schemas (SEC-019).
        """
        if not isinstance(proposal, dict):
            return False, "PROPOSAL_MALFORMED: Root must be a JSON dictionary", {}

        # 1. Proposer-only invariant check (SEC-019)
        if "proposer_mode" not in proposal:
            return False, "FIREWALL_BREACH: Missing mandatory proposer_mode flag (SEC-019)", {}
        is_proposer = proposal.get("proposer_mode")
        if not is_proposer or proposal.get("direct_commit", False):
            return False, "FIREWALL_BREACH: AI models are restricted to PROPOSER_ONLY mode (direct commit prohibited)", {}

        # 2. Secret plaintext scan (SEC-013)
        proposal_str = json.dumps(proposal)
        for pattern in [r"BEGIN\s+PRIVATE\s+KEY", r"BEGIN\s+OPENSSH\s+PRIVATE\s+KEY", r"password\s*[:=]\s*\"[^\"]+\""]:
            if re.search(pattern, proposal_str, re.IGNORECASE):
                return False, "SECURITY_VIOLATION: Plaintext secrets detected in proposal (SEC-013)", {}

        # 3. Validate Nix syntax if nix_expression supplied
        nix_expr = proposal.get("nix_expression")
        if nix_expr:
            ok, nix_err, _ = self.parse_nix_ast(nix_expr)
            if not ok:
                return False, f"NIX_AST_VALIDATION_FAILED: {nix_err}", {}

        # 4. Prohibited configuration patterns check
        changes = proposal.get("changes", {})
        if not changes:
            return False, "PROPOSAL_EMPTY: No configuration changes declared in proposal", {}

        for opt_key, opt_val in changes.items():
            for regex in PROHIBITED_OPTION_PATTERNS:
                if re.match(regex, opt_key):
                    return False, f"SECURITY_VIOLATION: Option '{opt_key}' violates security baseline", {}

            # Strict canonical allowlist
            if opt_key not in CANONICAL_OPTIONS:
                return False, f"SECURITY_VIOLATION: Option '{opt_key}' is not in CANONICAL_OPTIONS allowlist", {}

            # Type checking against schema
            opt_spec = CANONICAL_OPTIONS[opt_key]
            expected_type = opt_spec.get("type")
            if expected_type == "boolean" and not isinstance(opt_val, bool):
                return False, f"TYPE_MISMATCH: Option '{opt_key}' expects boolean, got {type(opt_val).__name__}", {}
            elif expected_type == "integer" and not isinstance(opt_val, int):
                return False, f"TYPE_MISMATCH: Option '{opt_key}' expects integer, got {type(opt_val).__name__}", {}
            elif expected_type == "string":
                if not isinstance(opt_val, str):
                    return False, f"TYPE_MISMATCH: Option '{opt_key}' expects string, got {type(opt_val).__name__}", {}
                allowed = opt_spec.get("allowed_values")
                if allowed and opt_val not in allowed:
                    return False, f"INVALID_VALUE: Option '{opt_key}' value '{opt_val}' not in allowed {allowed}", {}
            elif expected_type == "list":
                if not isinstance(opt_val, list):
                    return False, f"TYPE_MISMATCH: Option '{opt_key}' expects list, got {type(opt_val).__name__}", {}

        # 5. Synthesize proposal hash, diff, and simulation report
        proposal_canonical = dict(proposal)
        proposal_canonical["simulated_at"] = 1700000000  # deterministic timestamp for hash
        proposal_hash = sha256_canonical(proposal_canonical)

        diff = self.generate_dry_run_diff(changes)

        report = {
            "schema_version": "1.1.0",
            "proposal_id": f"PRP-{proposal_hash[:16]}",
            "simulation_verdict": "ACCEPTED_FOR_OPERATOR_REVIEW",
            "proposal_hash": proposal_hash,
            "options_affected": len(changes),
            "changes_summary": {k: str(v) for k, v in changes.items()},
            "configuration_diff": diff,
            "blast_radius": "ISOLATED_CONFIGURATION_DELTA",
            "requires_operator_signature": True,
            "safe_for_operator_review": True,
            "safe_for_operator_apply": True
        }
        return True, "PROPOSAL_SIMULATION_PASSED", report

SemanticAIGovernor = SemanticAstEngine
parse_nix_ast = SemanticAstEngine.parse_nix_ast


def main() -> None:
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
        "nix_expression": "{ services.openssh.enable = true; networking.firewall.enable = true; }",
        "changes": {
            "services.openssh.enable": True,
            "networking.firewall.enable": True
        }
    }
    valid, msg, report = engine.simulate_proposal(sample_proposal)
    print(f"\nProposal Simulation: {msg} (Verdict: {report.get('simulation_verdict')})")
    print(f"Proposal ID: {report.get('proposal_id')}")
    print(f"Proposal Diff:\n{report.get('configuration_diff')}")


if __name__ == "__main__":
    main()

