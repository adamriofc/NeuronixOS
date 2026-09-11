"""
Operational Semantic Layer (OSL) Coherence Evaluation Engine.
Evaluates Operational Contract Envelopes against state commitments, enforces selective
semanticization tiers (Tier 0 to Tier 2), and gates mutation actions via human sovereignty.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from neuronix_core.state import canonical_json_bytes, compute_state_root
from neuronix_core.uef.models import ExecutionReceiptData, OperationalContext, WorkloadSpec
from neuronix_core.uef.resolver import ProviderResolver, create_default_resolver


class CoherenceApprovalRequired(Exception):
    """Raised when an operation requires explicit human operator or owner approval."""

    def __init__(self, envelope: Dict[str, Any]) -> None:
        self.envelope = envelope
        action = envelope.get("intent", {}).get("action", "unknown.action")
        env_id = envelope.get("envelope_id", "unknown-env")
        super().__init__(
            f"Human approval required to execute envelope '{env_id}' for action '{action}'."
        )


class CoherenceStateRootMismatch(Exception):
    """Raised when preflight StateRoot does not match observed system state."""

    def __init__(self, expected: str, observed: str) -> None:
        self.expected = expected
        self.observed = observed
        super().__init__(
            f"StateRoot preflight mismatch: expected '{expected}', observed '{observed}'."
        )


class CoherenceInvariantViolation(Exception):
    """Raised when an enforced security or operational invariant is violated."""

    def __init__(self, invariant: str, reason: str) -> None:
        self.invariant = invariant
        self.reason = reason
        super().__init__(
            f"Invariant violation '{invariant}': {reason}."
        )


class CoherenceUnexecutableError(Exception):
    """Raised when an envelope has no executable entrypoint or registered skill mapping."""

    def __init__(self, action: str, reason: str) -> None:
        self.action = action
        self.reason = reason
        super().__init__(f"Operation '{action}' is unexecutable: {reason}.")


@dataclass(frozen=True)
class CoherenceVerdict:
    """Evaluation verdict produced by CoherenceEngine."""

    authorized: bool
    semantic_tier: str  # TIER_0_PASSTHROUGH, TIER_1_LIGHTWEIGHT, TIER_2_FULL_CONTRACT
    resolved_provider_id: Optional[str] = None
    rejection_reason: Optional[str] = None


class CoherenceEngine:
    """Evaluates and enforces operational contracts in NEURONIX OS."""

    def __init__(self, resolver: Optional[ProviderResolver] = None) -> None:
        self.resolver = resolver or create_default_resolver()

    def evaluate_envelope(
        self,
        envelope: Dict[str, Any],
        current_state_root: Optional[str] = None,
    ) -> CoherenceVerdict:
        """Evaluate whether envelope is authorized and assign semantic execution tier."""
        intent = envelope.get("intent", {})
        category = intent.get("category", "READ")
        action = intent.get("action", "")
        actor = envelope.get("actor", {})
        principal_type = actor.get("principal_type", "AI_AGENT")
        principal_id = actor.get("principal_id", "")
        authority = envelope.get("authority", {})
        tier = authority.get("tier", "OBSERVE_ONLY")

        # Invariant syntax and security posture validation
        invariants = list(envelope.get("invariants", []))
        req_invariants = envelope.get("preconditions", {}).get("required_invariants", [])
        for inv in req_invariants:
            if inv not in invariants:
                invariants.append(inv)

        for inv in invariants:
            if not re.match(r"^INV-SEC-[0-9]{3}$", inv):
                raise CoherenceInvariantViolation(
                    inv, "Malformed invariant format (must match ^INV-SEC-[0-9]{3}$)"
                )
            if inv == "INV-SEC-002":
                iso = envelope.get("environment", {}).get("isolation_tier", "TIER_0_HOST")
                if iso == "TIER_3_FORMAL" and not os.path.exists("/dev/kvm"):
                    raise CoherenceInvariantViolation(
                        inv, "Tier 3 boundary unavailable without hardware KVM"
                    )
            elif inv == "INV-SEC-014":
                payload_str = json.dumps(envelope)
                if "AGE-SECRET-KEY-" in payload_str:
                    raise CoherenceInvariantViolation(
                        inv, "Plaintext Age private key detected in operational contract payload"
                    )

        # Precondition StateRoot verification
        preconditions = envelope.get("preconditions", {})
        req_stateroot = preconditions.get("required_state_root")
        if req_stateroot and current_state_root:
            if req_stateroot != current_state_root:
                raise CoherenceStateRootMismatch(req_stateroot, current_state_root)

        # Tier 0: Side-effect free reads
        if category == "READ":
            return CoherenceVerdict(
                authorized=True,
                semantic_tier="TIER_0_PASSTHROUGH",
                resolved_provider_id="native.linux",
            )

        # Tier 1: Propose-only / non-destructive dry runs
        if category == "PROPOSE":
            return CoherenceVerdict(
                authorized=True,
                semantic_tier="TIER_1_LIGHTWEIGHT",
                resolved_provider_id="native.linux",
            )

        # Tier 2: State mutations
        if category == "MUTATE":
            # Human sovereignty gate: AI agents require authentic, unrevoked delegation
            if principal_type == "AI_AGENT":
                token = authority.get("token", "")
                if not token:
                    raise CoherenceApprovalRequired(envelope)

                from neuronix_core import skills
                dispatcher = skills.get_dispatcher()
                input_digest = envelope.get("evidence", {}).get("input_digest")
                grant = dispatcher.delegations.validate_token(
                    token=token,
                    skill_id=action,
                    input_digest=input_digest,
                )
                if not grant:
                    raise CoherenceApprovalRequired(envelope)
                if grant.principal_id != principal_id:
                    raise CoherenceApprovalRequired(envelope)
                if grant.granted_tier not in [
                    skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL,
                    skills.DelegatedAuthorityTier.PRIVILEGED_EXECUTE,
                    skills.DelegatedAuthorityTier.USERSPACE_EXECUTE,
                    "FULL_OPERATOR",
                    "DELEGATED_SCOPED",
                ]:
                    raise CoherenceApprovalRequired(envelope)

            elif principal_type in ["HUMAN_OWNER", "HUMAN_OPERATOR"]:
                if tier not in ["FULL_OPERATOR", "DELEGATED_SCOPED"]:
                    raise CoherenceApprovalRequired(envelope)
            else:
                raise CoherenceApprovalRequired(envelope)

            return CoherenceVerdict(
                authorized=True,
                semantic_tier="TIER_2_FULL_CONTRACT",
                resolved_provider_id="native.linux",
            )

        return CoherenceVerdict(
            authorized=False,
            semantic_tier="REJECTED",
            rejection_reason=f"Unknown category: {category}",
        )

    def execute_envelope(
        self,
        envelope: Dict[str, Any],
        current_state_root: Optional[str] = None,
    ) -> ExecutionReceiptData:
        """Evaluate, resolve provider, execute workload, and return verified receipt."""
        verdict = self.evaluate_envelope(envelope, current_state_root)
        if not verdict.authorized:
            raise RuntimeError(f"Envelope rejected: {verdict.rejection_reason}")

        intent = envelope.get("intent", {})
        action = intent.get("action", "unknown.action")
        entrypoint = intent.get("entrypoint")

        if not entrypoint:
            from neuronix_core import skills
            dispatcher = skills.get_dispatcher()
            skill_def = dispatcher.registry.get(action)
            if skill_def:
                entrypoint = [sys.executable, "-m", "neuronix_core.skills", "execute", action]
            else:
                raise CoherenceUnexecutableError(
                    action=action,
                    reason="No explicit entrypoint provided and no registered skill contract exists",
                )

        workload = WorkloadSpec(
            workload_id=envelope.get("envelope_id", f"wl-{int(time.time())}"),
            format=envelope.get("environment", {}).get("workload_format", "elf-binary"),
            entrypoint=entrypoint,
            arguments=intent.get("arguments", []),
            working_dir=envelope.get("environment", {}).get("working_dir", "/"),
            timeout_seconds=envelope.get("environment", {}).get("timeout_seconds", 30.0),
        )
        context = OperationalContext(
            requested_isolation_tier=envelope.get("environment", {}).get(
                "isolation_tier", "TIER_0_HOST"
            )
        )

        provider, score, _ = self.resolver.resolve(workload, context)
        prepared = provider.prepare(workload)
        try:
            receipt = provider.execute(prepared, envelope)
        finally:
            provider.cleanup(prepared)

        return receipt
