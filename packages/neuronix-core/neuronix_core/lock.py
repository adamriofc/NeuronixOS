"""
Operation concurrency lock manager for NEURONIX OS.
Guarantees exclusive execution for state-mutating operations
(system updates, generation rollbacks, Nix garbage collection).

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import fcntl
import json
import time
import getpass
from typing import Optional

class ConcurrentOperationError(Exception):
    """Raised when an operation cannot acquire the exclusive system operation lock."""
    pass

class OperationLock:
    """
    Context manager providing mutual exclusion for critical system operations.
    Uses non-blocking fcntl.flock to guarantee atomic lock acquisition.
    """

    DEFAULT_LOCK_DIR = "/run/neuronix"
    FALLBACK_LOCK_DIR = "/tmp/neuronix-locks"

    def __init__(self, operation_name: str, lock_path: Optional[str] = None):
        self.operation_name = operation_name
        self.lock_path = lock_path or os.environ.get("NEURONIX_LOCK_FILE")
        self._fd: Optional[int] = None
        self._locked = False

        if not self.lock_path:
            target_dir = self.DEFAULT_LOCK_DIR
            try:
                os.makedirs(target_dir, exist_ok=True)
            except (PermissionError, OSError):
                target_dir = self.FALLBACK_LOCK_DIR
                os.makedirs(target_dir, exist_ok=True)
            self.lock_path = os.path.join(target_dir, "operation.lock")

    def __enter__(self):
        self.acquire()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.release()

    def acquire(self) -> None:
        """Acquires the exclusive operation lock or raises ConcurrentOperationError."""
        lock_dir = os.path.dirname(self.lock_path)
        if not os.path.exists(lock_dir):
            try:
                os.makedirs(lock_dir, exist_ok=True)
            except (PermissionError, OSError):
                self.lock_path = os.path.join(self.FALLBACK_LOCK_DIR, "operation.lock")
                os.makedirs(os.path.dirname(self.lock_path), exist_ok=True)

        try:
            self._fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT, 0o600)
            fcntl.flock(self._fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self._locked = True

            # Write lock metadata
            metadata = {
                "operation": self.operation_name,
                "pid": os.getpid(),
                "user": getpass.getuser(),
                "timestamp": time.time(),
                "time_iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            }
            os.ftruncate(self._fd, 0)
            os.lseek(self._fd, 0, os.SEEK_SET)
            os.write(self._fd, json.dumps(metadata, indent=2).encode("utf-8"))
            os.fsync(self._fd)

        except (BlockingIOError, OSError) as e:
            active_info = self._read_existing_metadata()
            holder_desc = (
                f"operation '{active_info.get('operation', 'unknown')}' "
                f"(PID {active_info.get('pid', 'unknown')}, started {active_info.get('time_iso', 'unknown')})"
                if active_info else "another active process"
            )
            if self._fd is not None:
                try:
                    os.close(self._fd)
                except OSError:
                    pass
                self._fd = None
            raise ConcurrentOperationError(
                f"Concurrent operation blocked: System is currently executing {holder_desc}. "
                f"Cannot acquire lock '{self.lock_path}'."
            ) from e

    def release(self) -> None:
        """Releases the exclusive operation lock and cleans up metadata."""
        if self._locked and self._fd is not None:
            try:
                os.ftruncate(self._fd, 0)
                fcntl.flock(self._fd, fcntl.LOCK_UN)
            except OSError:
                pass
            finally:
                try:
                    os.close(self._fd)
                except OSError:
                    pass
                self._fd = None
                self._locked = False

    def _read_existing_metadata(self) -> dict:
        """Attempts to read lock metadata from the existing locked file."""
        if not os.path.exists(self.lock_path):
            return {}
        try:
            with open(self.lock_path, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if content:
                    return json.loads(content)
        except Exception:
            pass
        return {}
