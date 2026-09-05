"""
Transaction journaling and recovery engine for NEURONIX OS.
Tracks multi-step state mutations (updates, generation rollbacks) to guarantee
crash recovery, idempotency, and automatic rollback on interrupted execution.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import time
import uuid
import tempfile
from typing import Optional, Dict, Any, List

class TransactionState:
    PENDING = "PENDING"
    APPLYING = "APPLYING"
    COMMITTED = "COMMITTED"
    ROLLED_BACK = "ROLLED_BACK"
    FAILED = "FAILED"

class TransactionJournal:
    """
    Manages persistent record of system mutations to support crash recovery
    and automated rollback of interrupted operations.
    """

    DEFAULT_JOURNAL_DIR = "/var/lib/neuronix"
    FALLBACK_JOURNAL_DIR = "/tmp/neuronix-state"

    def __init__(self, journal_path: Optional[str] = None):
        self.journal_path = journal_path or os.environ.get("NEURONIX_JOURNAL_FILE")
        if not self.journal_path:
            target_dir = self.DEFAULT_JOURNAL_DIR
            try:
                os.makedirs(target_dir, exist_ok=True)
            except (PermissionError, OSError):
                target_dir = self.FALLBACK_JOURNAL_DIR
                os.makedirs(target_dir, exist_ok=True)
            self.journal_path = os.path.join(target_dir, "operation_journal.json")

    def _read_journal(self) -> Dict[str, Any]:
        """Reads transactions from disk, returning default structure if missing or corrupt."""
        if not os.path.exists(self.journal_path):
            return {"schema_version": "1.0.0", "transactions": {}}
        try:
            with open(self.journal_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict) and "transactions" in data:
                    return data
        except Exception:
            pass
        return {"schema_version": "1.0.0", "transactions": {}}

    def _write_journal(self, data: Dict[str, Any]) -> None:
        """Atomically persists journal data to disk."""
        journal_dir = os.path.dirname(self.journal_path)
        os.makedirs(journal_dir, exist_ok=True)

        temp_file = tempfile.NamedTemporaryFile("w", dir=journal_dir, delete=False, encoding="utf-8")
        try:
            json.dump(data, temp_file, indent=2)
            temp_file.flush()
            os.fsync(temp_file.fileno())
            temp_file.close()
            os.replace(temp_file.name, self.journal_path)
        except Exception:
            if os.path.exists(temp_file.name):
                try:
                    os.unlink(temp_file.name)
                except OSError:
                    pass
            raise

    def start_transaction(self, operation_type: str, details: Optional[Dict[str, Any]] = None) -> str:
        """Initializes a new transaction in PENDING state."""
        tx_id = f"tx_{int(time.time())}_{uuid.uuid4().hex[:8]}"
        journal = self._read_journal()
        now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

        journal["transactions"][tx_id] = {
            "id": tx_id,
            "operation": operation_type,
            "state": TransactionState.PENDING,
            "created_at": now_iso,
            "updated_at": now_iso,
            "details": details or {}
        }
        self._write_journal(journal)
        return tx_id

    def update_transaction(self, tx_id: str, state: str, details: Optional[Dict[str, Any]] = None) -> None:
        """Updates the state and details of an ongoing transaction."""
        journal = self._read_journal()
        if tx_id not in journal["transactions"]:
            raise KeyError(f"Transaction '{tx_id}' not found in journal.")

        tx = journal["transactions"][tx_id]
        tx["state"] = state
        tx["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        if details:
            tx["details"].update(details)

        self._write_journal(journal)

    def commit_transaction(self, tx_id: str, details: Optional[Dict[str, Any]] = None) -> None:
        """Marks a transaction as COMMITTED after successful postcondition verification."""
        self.update_transaction(tx_id, TransactionState.COMMITTED, details)

    def abort_transaction(self, tx_id: str, reason: Optional[str] = None) -> None:
        """Marks a transaction as FAILED or ROLLED_BACK."""
        details = {"abort_reason": reason} if reason else {}
        self.update_transaction(tx_id, TransactionState.FAILED, details)

    def mark_rolled_back(self, tx_id: str, rollback_details: Optional[Dict[str, Any]] = None) -> None:
        """Marks a transaction as ROLLED_BACK after recovery action."""
        self.update_transaction(tx_id, TransactionState.ROLLED_BACK, rollback_details)

    def get_transaction(self, tx_id: str) -> Optional[Dict[str, Any]]:
        """Retrieves a specific transaction record."""
        journal = self._read_journal()
        return journal["transactions"].get(tx_id)

    def get_dangling_transactions(self) -> List[Dict[str, Any]]:
        """
        Returns all transactions left uncommitted in APPLYING or PENDING states,
        indicating process termination, crash, or unexpected failure.
        """
        journal = self._read_journal()
        dangling = []
        for tx_id, tx in journal.get("transactions", {}).items():
            if tx.get("state") in (TransactionState.APPLYING, TransactionState.PENDING):
                dangling.append(tx)
        return dangling

    def recover_dangling_transactions(self) -> List[Dict[str, Any]]:
        """
        Inspects and remediates dangling transactions found in journal.
        Returns report of recovered operations.
        """
        dangling = self.get_dangling_transactions()
        recovery_report = []

        for tx in dangling:
            tx_id = tx["id"]
            op = tx.get("operation")
            prev_gen = tx.get("details", {}).get("previous_generation")

            action_taken = "MARKED_FAILED"
            if op in ("system_update", "rollback") and prev_gen:
                action_taken = f"NEEDS_ROLLBACK_TO_GEN_{prev_gen}"

            self.update_transaction(
                tx_id,
                TransactionState.FAILED,
                {"recovery_action": action_taken, "recovered_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
            )
            recovery_report.append({
                "transaction_id": tx_id,
                "operation": op,
                "action": action_taken
            })

        return recovery_report
