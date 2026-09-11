"""
Universal Execution Fabric (UEF) Core Package.
Provides provider abstraction, lifecycle management, and dynamic scoring resolution.
"""

from .models import (
    CompatibilityReport,
    ExecutionReceiptData,
    OperationalContext,
    PreparedEnvironment,
    ProviderCapability,
    ResourceReleaseProof,
    WorkloadSpec,
)
from .provider import ExecutionProvider

__all__ = [
    "CompatibilityReport",
    "ExecutionProvider",
    "ExecutionReceiptData",
    "OperationalContext",
    "PreparedEnvironment",
    "ProviderCapability",
    "ResourceReleaseProof",
    "WorkloadSpec",
]
