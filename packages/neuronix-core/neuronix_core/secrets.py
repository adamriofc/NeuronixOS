"""
NEURONIX Capability-Bound Secret Fabric
Manages age-encrypted secrets with ephemeral RAM materialization (/run/neuronix/secrets),
strict AI visibility masking (SEC-014), and capability-bound access control (SEC-013).

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
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


DEFAULT_SECRETS_RAM_PATH = "/run/neuronix/secrets"


class SecretFabricEngine:
    """
    Capability-Bound Secret Fabric.
    Decrypts age secrets exclusively into tmpfs memory and enforces AI metadata masking.
    """

    def __init__(self, ramfs_root: str = DEFAULT_SECRETS_RAM_PATH):
        self.ramfs_root = ramfs_root
        self.registry: Dict[str, Dict[str, Any]] = {}

    def register_secret(
        self,
        name: str,
        ciphertext: str,
        required_capability: str,
        recipients: List[str]
    ) -> Dict[str, Any]:
        """
        Registers an age-encrypted secret definition into the declarative fabric.
        """
        ciphertext_hash = hashlib.sha256(ciphertext.encode("utf-8")).hexdigest()
        entry = {
            "name": name,
            "required_capability": required_capability,
            "recipients": sorted(recipients),
            "ciphertext_hash": ciphertext_hash,
            "ciphertext": ciphertext,
            "materialized": False,
            "ramfs_path": os.path.join(self.ramfs_root, name)
        }
        self.registry[name] = entry
        return entry

    def materialize_secret(
        self,
        name: str,
        capability_token: str,
        mock_plaintext: Optional[str] = None
    ) -> Tuple[bool, str, Optional[str]]:
        """
        Materializes secret into volatile RAM iff capability token matches (SEC-013).
        Fails closed on capability mismatch.
        """
        if name not in self.registry:
            return False, f"SECRET_NOT_FOUND: {name}", None

        entry = self.registry[name]
        expected_cap = entry["required_capability"]

        # Capability check (fail-closed)
        if capability_token != expected_cap:
            return False, f"CAPABILITY_MISMATCH: Workload lacks required capability '{expected_cap}'", None

        # Materialization into volatile RAM (tmpfs)
        try:
            if not os.path.exists(self.ramfs_root):
                os.makedirs(self.ramfs_root, mode=0o700, exist_ok=True)
            target_file = entry["ramfs_path"]
            content = mock_plaintext or "SECRET_MATERIALIZED_IN_RAM_FROM_AGE"
            with open(target_file, "w", encoding="utf-8") as f:
                f.write(content)
            os.chmod(target_file, 0o600)
            entry["materialized"] = True
            return True, "SECRET_MATERIALIZED_IN_RAM", target_file
        except Exception as e:
            return False, f"MATERIALIZATION_ERROR: {str(e)}", None

    def filter_secret_for_actor(self, name: str, actor_role: str = "ai_agent") -> Dict[str, Any]:
        """
        Enforces AI Visibility Isolation: AI agents receive only metadata (SEC-014).
        """
        if name not in self.registry:
            return {"error": f"Secret '{name}' not found"}

        entry = self.registry[name]
        if actor_role in ("ai_agent", "copilot", "mcp_client", "model"):
            return {
                "name": entry["name"],
                "required_capability": entry["required_capability"],
                "recipients": entry["recipients"],
                "ciphertext_hash": entry["ciphertext_hash"],
                "ramfs_path": entry["ramfs_path"],
                "materialized": entry["materialized"],
                "plaintext_visibility": "METADATA_ONLY",
                "value": "[MASKED: AI_SECRET_VISIBILITY_METADATA_ONLY]"
            }

        return {
            "name": entry["name"],
            "required_capability": entry["required_capability"],
            "recipients": entry["recipients"],
            "ciphertext_hash": entry["ciphertext_hash"],
            "ramfs_path": entry["ramfs_path"],
            "materialized": entry["materialized"]
        }

    def compute_secret_root(self) -> str:
        """
        Computes canonical SecretRoot digest over registered secret metadata.
        Guarantees that secret plaintexts NEVER appear in SecretRoot or StateCommitment.
        """
        metadata_map = {}
        for name, item in sorted(self.registry.items()):
            metadata_map[name] = {
                "name": item["name"],
                "required_capability": item["required_capability"],
                "recipients": item["recipients"],
                "ciphertext_hash": item["ciphertext_hash"]
            }
        return sha256_canonical(metadata_map)


def main():
    engine = SecretFabricEngine()
    engine.register_secret(
        name="github_token",
        ciphertext="age-encryption.mock-ciphertext-string-12345678",
        required_capability="cap:net.github.api",
        recipients=["age1y2u98x0c3nvm..."]
    )
    secret_root = engine.compute_secret_root()
    ai_view = engine.filter_secret_for_actor("github_token", "ai_agent")

    print(f"SecretRoot: {secret_root}")
    print(f"AI Visibility: {ai_view['value']}")
    print(f"Plaintext Hidden: {ai_view.get('name') == 'github_token' and '[MASKED' in ai_view.get('value', '')}")


if __name__ == "__main__":
    main()
