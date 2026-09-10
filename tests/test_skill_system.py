import os
import json
import re
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = PROJECT_ROOT / "data" / "skills"
SCHEMAS_DIR = PROJECT_ROOT / "data" / "schemas"
SPEC_DIR = PROJECT_ROOT / "docs" / "specifications"


class TestSkillSystemAndConductorArchitecture(unittest.TestCase):
    def setUp(self):
        self.schema_path = SCHEMAS_DIR / "skill_contract.schema.json"
        self.assertTrue(self.schema_path.exists(), "Skill contract schema must exist")
        with open(self.schema_path, "r", encoding="utf-8") as f:
            self.schema = json.load(f)

    def test_schema_structural_integrity(self):
        """Validate that the skill contract schema contains all required top-level constraints."""
        self.assertIn("required", self.schema)
        expected_required = [
            "skill_id",
            "version",
            "category",
            "title",
            "description",
            "invariants_required",
            "approval_gate_required",
            "inputs_schema",
            "outputs_schema",
        ]
        for field in expected_required:
            self.assertIn(field, self.schema["required"])
        self.assertFalse(self.schema.get("additionalProperties", True))

    def test_canonical_skills_compliance(self):
        """Validate all canonical skills in data/skills/ against the contract schema."""
        skill_files = list(SKILLS_DIR.glob("*.json"))
        self.assertGreaterEqual(len(skill_files), 5, "At least 5 foundational skills must be defined")

        for skill_path in skill_files:
            with self.subTest(skill=skill_path.name):
                with open(skill_path, "r", encoding="utf-8") as f:
                    skill = json.load(f)

                # Check required properties
                for field in self.schema["required"]:
                    self.assertIn(field, skill, f"Missing '{field}' in {skill_path.name}")

                # Check skill_id pattern
                self.assertTrue(
                    re.match(r"^[a-z0-9_]+\.[a-z0-9_]+$", skill["skill_id"]),
                    f"Invalid skill_id in {skill_path.name}: {skill['skill_id']}",
                )

                # Check semantic version
                self.assertTrue(
                    re.match(r"^[0-9]+\.[0-9]+\.[0-9]+$", skill["version"]),
                    f"Invalid semver in {skill_path.name}: {skill['version']}",
                )

                # Check category enum
                self.assertIn(skill["category"], ["READ", "PROPOSE", "MUTATE"])

                # Check strings
                self.assertGreater(len(skill["title"]), 0)
                self.assertGreater(len(skill["description"]), 0)

                # Check invariant format
                for inv in skill["invariants_required"]:
                    self.assertTrue(
                        re.match(r"^INV-SEC-[0-9]{3}$", inv),
                        f"Malformed invariant reference in {skill_path.name}: {inv}",
                    )

                # Check approval gate rule: MUTATE skills must have approval_gate_required == True
                if skill["category"] == "MUTATE":
                    self.assertTrue(
                        skill["approval_gate_required"],
                        f"MUTATE skill {skill['skill_id']} must enforce approval_gate_required == True",
                    )

                # Inputs and outputs schemas must be valid dicts
                self.assertIsInstance(skill["inputs_schema"], dict)
                self.assertIsInstance(skill["outputs_schema"], dict)

    def test_zero_unicode_dashes_in_specs_and_skills(self):
        """Strictly enforce zero Unicode em-dashes and en-dashes across specifications and skills."""
        unicode_dash_pattern = re.compile(r"[\u2013\u2014]")

        # Check all specifications
        for doc in SPEC_DIR.glob("*.md"):
            with open(doc, "r", encoding="utf-8") as f:
                content = f.read()
            matches = unicode_dash_pattern.findall(content)
            self.assertEqual(
                len(matches),
                0,
                f"Found {len(matches)} Unicode dashes in {doc.name}",
            )

        # Check all skills and schemas
        for jf in list(SKILLS_DIR.glob("*.json")) + list(SCHEMAS_DIR.glob("*.json")):
            with open(jf, "r", encoding="utf-8") as f:
                content = f.read()
            matches = unicode_dash_pattern.findall(content)
            self.assertEqual(
                len(matches),
                0,
                f"Found {len(matches)} Unicode dashes in {jf.name}",
            )


if __name__ == "__main__":
    unittest.main()
