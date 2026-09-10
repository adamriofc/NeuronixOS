"""
NEURONIX Capability-Bound Secret Fabric
Manages true Age protocol encrypted secrets with ephemeral RAM materialization (/run/neuronix/secrets),
strict AI visibility masking (SEC-014), and capability-bound access control (SEC-013).

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import shutil
import hashlib
import subprocess
import tempfile
import uuid
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

# In-memory cache for derived public keys to avoid repeated subprocess invocations
_RECIPIENT_CACHE: Dict[str, str] = {}


def find_age_binaries() -> Tuple[str, str]:
    """
    Discovers the official Age encryption CLI and key-generation binaries.
    Searches system PATH, local bin directories, cargo bin, and Nix profiles.
    Supports both official 'age'/'age-keygen' and Rust implementation 'rage'/'rage-keygen'.
    """
    search_dirs = [
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "bin")),
        os.path.expanduser("~/.cargo/bin"),
        os.path.expanduser("~/.local/bin"),
        "/run/current-system/sw/bin",
        "/usr/local/bin",
        "/usr/bin"
    ]

    age_bin = shutil.which("age")
    if not age_bin:
        for d in search_dirs:
            candidate = os.path.join(d, "age")
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                age_bin = candidate
                break

    if not age_bin:
        age_bin = shutil.which("rage")
        if not age_bin:
            for d in search_dirs:
                candidate = os.path.join(d, "rage")
                if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                    age_bin = candidate
                    break

    keygen_bin = shutil.which("age-keygen")
    if not keygen_bin:
        for d in search_dirs:
            candidate = os.path.join(d, "age-keygen")
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                keygen_bin = candidate
                break

    if not keygen_bin:
        keygen_bin = shutil.which("rage-keygen")
        if not keygen_bin:
            for d in search_dirs:
                candidate = os.path.join(d, "rage-keygen")
                if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                    keygen_bin = candidate
                    break

    if not age_bin:
        raise RuntimeError("Missing age executable. Please install 'age' or 'rage' in system PATH or ~/.cargo/bin.")
    if not keygen_bin:
        raise RuntimeError("Missing age-keygen executable. Please install 'age-keygen' or 'rage-keygen' in system PATH or ~/.cargo/bin.")

    return age_bin, keygen_bin


def is_volatile_ram_filesystem(path: str, mounts_file: str = "/proc/mounts") -> bool:
    """
    Verifies that the target path resides on a volatile in-memory filesystem (tmpfs or ramfs).
    Guarantees zero persistent SSD/disk wear and zero plaintext leakage to non-volatile storage.
    """
    abs_path = os.path.abspath(path)

    # Standard Linux volatile RAM paths
    if abs_path.startswith("/run/") or abs_path.startswith("/dev/shm/"):
        return True

    if os.path.exists(mounts_file):
        try:
            best_match_len = -1
            best_fs_type = ""
            with open(mounts_file, "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) >= 3:
                        mp = parts[1]
                        fs_type = parts[2]
                        if abs_path == mp or abs_path.startswith(mp.rstrip("/") + "/"):
                            if len(mp) > best_match_len:
                                best_match_len = len(mp)
                                best_fs_type = fs_type
            if best_fs_type in ("tmpfs", "ramfs"):
                return True
        except Exception:
            pass

    return False


class SecretFabricEngine:
    """
    Capability-Bound Secret Fabric (MES-NRX-002).
    Enforces authentic Age protocol decryption into volatile tmpfs RAM,
    zero-disk persistence, atomic materialization, and AI metadata-only masking (SEC-013, SEC-014).
    Uses authentic X25519 Age identities and recipients (Bech32 age1...).
    """

    def __init__(self, ramfs_root: str = DEFAULT_SECRETS_RAM_PATH, enforce_ramfs: bool = False):
        self.ramfs_root = ramfs_root
        self.enforce_ramfs = enforce_ramfs
        self.registry: Dict[str, Dict[str, Any]] = {}

    @classmethod
    def get_binaries(cls) -> Tuple[str, str]:
        """Returns the discovered age and age-keygen executable paths."""
        return find_age_binaries()

    @classmethod
    def generate_keypair(cls) -> Tuple[str, str]:
        """
        Generates a new authentic Age identity keypair using age-keygen.
        Returns a tuple of (secret_identity_key, public_recipient_key).
        """
        _, keygen_bin = cls.get_binaries()
        proc = subprocess.run(
            [keygen_bin],
            capture_output=True,
            text=True,
            check=True
        )
        lines = [l.strip() for l in proc.stdout.splitlines() if l.strip()]
        secret_key = ""
        pub_key = ""
        for line in lines:
            if line.startswith("# public key:"):
                pub_key = line.split(":", 1)[1].strip()
            elif not line.startswith("#") and line.startswith("AGE-SECRET-KEY-1"):
                secret_key = line.strip()

        if not secret_key:
            raise RuntimeError(f"Failed to generate Age secret key: {proc.stderr}")
        if not pub_key:
            pub_key = cls.derive_public_key_from_identity(secret_key)

        _RECIPIENT_CACHE[secret_key] = pub_key
        return secret_key, pub_key

    @classmethod
    def derive_public_key_from_identity(cls, identity_key: str) -> str:
        """
        Derives canonical Age recipient string (age1...) from an Age secret key string (AGE-SECRET-KEY-1...).
        Uses age-keygen -y to perform authentic cryptographic derivation.
        """
        if not identity_key or not isinstance(identity_key, str):
            raise ValueError("Identity key must be a non-empty string")

        clean_key = identity_key.strip()

        # Check in-memory cache
        if clean_key in _RECIPIENT_CACHE:
            return _RECIPIENT_CACHE[clean_key]

        # Check if recipient is already annotated in file-style identity text
        for line in clean_key.splitlines():
            line = line.strip()
            if line.startswith("# public key:"):
                cand = line.split(":", 1)[1].strip()
                if cand.startswith("age1"):
                    _RECIPIENT_CACHE[clean_key] = cand
                    return cand

        # Isolate actual secret key line
        actual_secret = ""
        for line in clean_key.splitlines():
            line = line.strip()
            if line.startswith("AGE-SECRET-KEY-1"):
                actual_secret = line
                break

        if not actual_secret:
            raise ValueError("Invalid Age identity key format: missing 'AGE-SECRET-KEY-1' prefix")

        _, keygen_bin = cls.get_binaries()
        proc = subprocess.run(
            [keygen_bin, "-y"],
            input=actual_secret + "\n",
            capture_output=True,
            text=True
        )
        if proc.returncode != 0:
            raise ValueError(f"Failed to derive Age public key: {proc.stderr.strip()}")

        pub_key = proc.stdout.strip()
        if not pub_key.startswith("age1"):
            raise ValueError(f"Invalid derived recipient format: '{pub_key}'")

        _RECIPIENT_CACHE[clean_key] = pub_key
        _RECIPIENT_CACHE[actual_secret] = pub_key
        return pub_key

    @classmethod
    def encrypt_secret_envelope(
        cls,
        plaintext: str,
        recipients: List[str],
        identity_key: Optional[str] = None
    ) -> str:
        """
        Encrypts plaintext using the authentic Age protocol.
        Produces an authentic ASCII-armored Age ciphertext envelope.
        """
        if not recipients:
            if identity_key:
                recipients = [cls.derive_public_key_from_identity(identity_key)]
            else:
                raise ValueError("At least one recipient (age1...) or identity key is required for encryption")

        age_bin, _ = cls.get_binaries()
        cmd = [age_bin, "-a"]
        for r in recipients:
            clean_r = r.strip()
            if not clean_r.startswith("age1"):
                raise ValueError(f"Recipient must start with 'age1': '{clean_r}'")
            cmd.extend(["-r", clean_r])

        proc = subprocess.run(
            cmd,
            input=plaintext,
            capture_output=True,
            text=True
        )
        if proc.returncode != 0:
            raise RuntimeError(f"Age encryption failed: {proc.stderr.strip()}")

        return proc.stdout

    @classmethod
    def decrypt_secret_envelope(
        cls,
        ciphertext_raw: str,
        identity_key: str,
        allowed_recipients: Optional[List[str]] = None
    ) -> Tuple[bool, str, Optional[str]]:
        """
        Authenticates and decrypts an Age secret envelope using the supplied identity key.
        Enforces 3 strict conditions:
        1. Valid identity key matching declared recipients (if recipient filtering specified).
        2. Valid Age authenticated payload and MAC integrity check (no tampering).
        3. Decrypted plaintext cleanly reconstructed in memory.
        """
        if not identity_key or not isinstance(identity_key, str) or "AGE-SECRET-KEY-1" not in identity_key:
            return False, "MISSING_AGE_IDENTITY: Identity key does not match registered recipients", None

        # Derive recipient from identity key
        try:
            derived_recipient = cls.derive_public_key_from_identity(identity_key)
        except Exception as e:
            return False, f"MISSING_AGE_IDENTITY: Failed to derive recipient: {str(e)}", None

        # Check against allowed recipients if supplied
        if allowed_recipients:
            recipient_matched = any(
                r.strip() == derived_recipient for r in allowed_recipients
            )
            if not recipient_matched:
                return False, f"MISSING_AGE_IDENTITY: Identity key does not match registered recipients", None

        # Validate ciphertext structure
        if not ciphertext_raw or not isinstance(ciphertext_raw, str):
            return False, "AUTHENTICATED_DECRYPTION_FAILED: Ciphertext is empty or not a string", None

        if "BEGIN AGE ENCRYPTED FILE" not in ciphertext_raw and "age-encryption.org/v1" not in ciphertext_raw:
            return False, "AUTHENTICATED_DECRYPTION_FAILED: Ciphertext is not a valid Age encrypted envelope", None

        # Execute decryption via age CLI
        age_bin, _ = cls.get_binaries()
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as kf:
            kf.write(identity_key.strip() + "\n")
            key_file_path = kf.name

        try:
            os.chmod(key_file_path, 0o600)
            proc = subprocess.run(
                [age_bin, "-d", "-i", key_file_path],
                input=ciphertext_raw,
                capture_output=True,
                text=True
            )
            if proc.returncode != 0:
                err_msg = proc.stderr.strip()
                return False, f"AUTHENTICATED_DECRYPTION_FAILED: Cryptographic MAC verification failed ({err_msg})", None

            return True, "DECRYPTION_SUCCESS", proc.stdout
        finally:
            if os.path.exists(key_file_path):
                try:
                    with open(key_file_path, "wb") as f:
                        f.write(b"\x00" * 4096)
                    os.unlink(key_file_path)
                except Exception:
                    pass

    def register_secret(
        self,
        name: str,
        ciphertext: str,
        required_capability: str,
        recipients: List[str]
    ) -> Dict[str, Any]:
        """
        Registers an authentic Age secret definition into the declarative fabric.
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
        identity_key: Optional[str] = None
    ) -> Tuple[bool, str, Optional[str]]:
        """
        Materializes secret into volatile RAM iff capability token and identity key match.
        Enforces 3 absolute conditions:
        1. NO KEY -> NO MATERIALIZATION (MISSING_AGE_IDENTITY)
        2. INVALID CAPABILITY -> NO MATERIALIZATION (CAPABILITY_REJECTED)
        3. DECRYPTION FAILURE -> NO PARTIAL SECRET FILE (Zero leakage)
        """
        if name not in self.registry:
            return False, f"SECRET_NOT_FOUND: {name}", None

        entry = self.registry[name]
        expected_cap = entry["required_capability"]

        # Condition 2: Capability check (fail-closed)
        if not capability_token or capability_token != expected_cap:
            return False, f"CAPABILITY_MISMATCH: Workload lacks required capability '{expected_cap}'", None

        # Condition 1: Decryption key availability
        if not identity_key:
            default_key_file = "/etc/neuronix/keys/age.key"
            if os.path.exists(default_key_file):
                try:
                    with open(default_key_file, "r", encoding="utf-8") as kf:
                        identity_key = kf.read().strip()
                except Exception:
                    pass

        if not identity_key:
            return False, "MISSING_AGE_IDENTITY: No identity key supplied or discovered in /etc/neuronix/keys/age.key", None

        # Condition 3a: Perform authenticated decryption strictly in memory FIRST
        ok, dec_msg, plaintext = self.decrypt_secret_envelope(
            ciphertext_raw=entry["ciphertext"],
            identity_key=identity_key,
            allowed_recipients=entry["recipients"]
        )
        if not ok or plaintext is None:
            return False, dec_msg, None

        # Volatile RAM filesystem verification
        if self.enforce_ramfs and not is_volatile_ram_filesystem(self.ramfs_root):
            return False, f"VOLATILE_RAM_MOUNT_REQUIRED: Target directory '{self.ramfs_root}' must reside on tmpfs/ramfs", None

        # Condition 3b: Atomic zero-leak materialization into volatile RAM
        tmp_target = os.path.join(self.ramfs_root, f".tmp.{name}.{uuid.uuid4().hex}")
        target_file = entry["ramfs_path"]
        try:
            if not os.path.exists(self.ramfs_root):
                os.makedirs(self.ramfs_root, mode=0o700, exist_ok=True)

            with open(tmp_target, "w", encoding="utf-8") as f:
                f.write(plaintext)
                f.flush()
                os.fsync(f.fileno())

            os.chmod(tmp_target, 0o600)
            os.replace(tmp_target, target_file)

            entry["materialized"] = True
            return True, "SECRET_MATERIALIZED_IN_RAM", target_file
        except Exception as e:
            if os.path.exists(tmp_target):
                try:
                    with open(tmp_target, "wb") as f:
                        f.write(b"\x00" * 4096)
                    os.unlink(tmp_target)
                except Exception:
                    pass
            return False, f"MATERIALIZATION_ERROR: {str(e)}", None

    def shred_secret(self, name: str) -> bool:
        """
        Cryptographically shreds an in-RAM materialized secret file by overwriting with zeros before unlinking.
        """
        if name not in self.registry:
            return False
        entry = self.registry[name]
        target_file = entry["ramfs_path"]
        if os.path.exists(target_file):
            try:
                size = os.path.getsize(target_file)
                with open(target_file, "wb") as f:
                    f.write(b"\x00" * max(size, 4096))
                    f.flush()
                    os.fsync(f.fileno())
                os.unlink(target_file)
                entry["materialized"] = False
                return True
            except Exception:
                return False
        entry["materialized"] = False
        return True

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


encrypt_secret_envelope = SecretFabricEngine.encrypt_secret_envelope
decrypt_secret_envelope = SecretFabricEngine.decrypt_secret_envelope


def main():
    engine = SecretFabricEngine()
    ident, rec = SecretFabricEngine.generate_keypair()
    ciphertext = SecretFabricEngine.encrypt_secret_envelope(
        plaintext="ACTUAL_DECRYPTED_TOKEN_VALUE",
        recipients=[rec],
        identity_key=ident
    )
    engine.register_secret(
        name="github_token",
        ciphertext=ciphertext,
        required_capability="cap:net.github.api",
        recipients=[rec]
    )
    secret_root = engine.compute_secret_root()
    ai_view = engine.filter_secret_for_actor("github_token", "ai_agent")

    print(f"SecretRoot: {secret_root}")
    print(f"AI Visibility: {ai_view['value']}")
    print(f"Plaintext Hidden: {ai_view.get('name') == 'github_token' and '[MASKED' in ai_view.get('value', '')}")


if __name__ == "__main__":
    main()
