"""
Operational Semantic Layer (OSL) Core Package.
Provides typed operational contract envelopes and the Coherence Engine.
"""

from .coherence import (
    CoherenceApprovalRequired,
    CoherenceEngine,
    CoherenceInvariantViolation,
    CoherenceStateRootMismatch,
    CoherenceVerdict,
)

__all__ = [
    "CoherenceApprovalRequired",
    "CoherenceEngine",
    "CoherenceInvariantViolation",
    "CoherenceStateRootMismatch",
    "CoherenceVerdict",
]
