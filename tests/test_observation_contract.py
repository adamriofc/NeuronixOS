"""
Unit tests for Vital Laboratory Observation Contract Schema.
Validates telemetry classification, provenance tracking, and the invariant
that unknown/unexposed sensors strictly evaluate to null.
Adheres to SPEC-NRX-VTL-020 and SPEC-NRX-CND-021.
"""

from __future__ import annotations

import os
import sys
import json
import re
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCHEMAS_DIR = PROJECT_ROOT / "data" / "schemas"
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core import vital


class TestObservationContract(unittest.TestCase):
    def setUp(self):
        self.schema_path = SCHEMAS_DIR / "observation_contract.schema.json"
        self.assertTrue(self.schema_path.exists(), "observation_contract.schema.json must exist")
        with open(self.schema_path, "r", encoding="utf-8") as f:
            self.schema = json.load(f)

    def _validate_observation_record(self, record: dict) -> List[str]:
        """Validates a single observation record dictionary against the contract schema."""
        errors = []
        # Required fields
        for field in self.schema["required"]:
            if field not in record:
                errors.append(f"Missing required field: {field}")

        # Metric pattern
        if "metric" in record:
            if not re.match(r"^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$", str(record["metric"])):
                errors.append(f"Invalid metric identifier pattern: {record['metric']}")

        # Telemetry class enum
        allowed_classes = self.schema["properties"]["telemetry_class"]["enum"]
        if record.get("telemetry_class") not in allowed_classes:
            errors.append(f"Invalid telemetry_class: {record.get('telemetry_class')}")

        # Monotonic time
        mono = record.get("monotonic_at")
        if not isinstance(mono, int) or mono <= 0:
            errors.append(f"monotonic_at must be positive integer nanoseconds, got: {mono}")

        # Quality enum
        allowed_qualities = ["FRESH", "RECENT", "STALE", "UNAVAILABLE", "fresh", "recent", "stale", "unavailable"]
        if record.get("quality") not in allowed_qualities:
            errors.append(f"Invalid quality: {record.get('quality')}")

        # Availability enum
        allowed_avail = self.schema["properties"]["availability"]["enum"]
        if record.get("availability") not in allowed_avail:
            errors.append(f"Invalid availability: {record.get('availability')}")

        # Invariant: Unknown must remain unknown
        # When availability is UNAVAILABLE, value MUST be None
        if record.get("availability") == "UNAVAILABLE" and record.get("value") is not None:
            errors.append(f"Violation of invariant 'Unknown must remain unknown': availability is UNAVAILABLE but value is {record.get('value')}")

        return errors

    def test_schema_structural_declarations(self):
        """Validates that observation_contract.schema.json enforces all laboratory contract fields."""
        self.assertEqual(self.schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertIn("required", self.schema)
        expected_fields = [
            "metric",
            "telemetry_class",
            "value",
            "unit",
            "observed_at",
            "monotonic_at",
            "source",
            "freshness_ms",
            "quality",
            "confidence",
            "provenance",
            "availability"
        ]
        for ef in expected_fields:
            self.assertIn(ef, self.schema["required"])

    def test_live_snapshot_records_compliance(self):
        """Verify that every metric produced by vital.snapshot() strictly satisfies the observation contract."""
        snap = vital.snapshot()
        self.assertIn("domains", snap)

        records_checked = 0
        for domain_name, domain_metrics in snap["domains"].items():
            for metric_key, record in domain_metrics.items():
                if isinstance(record, dict) and "metric" in record:
                    errs = self._validate_observation_record(record)
                    self.assertEqual(
                        len(errs), 0,
                        f"Validation failure on {domain_name}.{metric_key}: {errs}"
                    )
                    records_checked += 1

        self.assertGreaterEqual(records_checked, 10, "At least 10 observation records must be validated")

    def test_telemetry_class_separation(self):
        """Verify explicit separation between raw hardware facts (OBSERVED) and computed metrics (DERIVED)."""
        snap = vital.snapshot()
        cpu_domain = snap["domains"]["cpu"]
        mem_domain = snap["domains"]["memory"]
        thermal_domain = snap["domains"]["thermals"]

        # Raw observations
        self.assertEqual(cpu_domain["load_1m"]["telemetry_class"], "OBSERVED")
        self.assertEqual(mem_domain["total_bytes"]["telemetry_class"], "OBSERVED")
        self.assertEqual(thermal_domain["cpu_package_celsius"]["telemetry_class"], "OBSERVED")

        # Derived calculations
        self.assertEqual(mem_domain["used_percent"]["telemetry_class"], "DERIVED")
        self.assertEqual(mem_domain["pressure"]["telemetry_class"], "DERIVED")
        self.assertEqual(thermal_domain["thermal_status"]["telemetry_class"], "DERIVED")
        self.assertEqual(snap["system_health"]["telemetry_class"], "DERIVED")

    def test_invariant_unknown_remains_unknown(self):
        """Ensure that unavailable sensors strictly report value=None and availability=UNAVAILABLE."""
        obs = vital.VitalObservatory()
        record = obs._create_record(
            metric="thermal.mock_sensor",
            value=None,
            unit="celsius",
            source="hwmon_mock",
            telemetry_class="OBSERVED",
            reason="sensor_absent"
        ).to_dict()

        self.assertIsNone(record["value"])
        self.assertEqual(record["availability"], "UNAVAILABLE")
        self.assertEqual(record["quality"], "unavailable")

        # Synthetic fallback rejection test
        synthetic_record = {
            "metric": "thermal.cpu_package_celsius",
            "telemetry_class": "OBSERVED",
            "value": 45.0,  # Synthetic fallback is prohibited when UNAVAILABLE
            "unit": "celsius",
            "observed_at": "2026-09-10T12:00:00Z",
            "monotonic_at": 123456789,
            "source": "hwmon",
            "freshness_ms": 0,
            "quality": "unavailable",
            "confidence": 0.5,
            "provenance": "nrx-vtl:hwmon",
            "availability": "UNAVAILABLE"
        }
        errs = self._validate_observation_record(synthetic_record)
        self.assertTrue(any("Unknown must remain unknown" in e for e in errs))


if __name__ == "__main__":
    unittest.main()
