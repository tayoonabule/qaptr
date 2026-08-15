#!/usr/bin/env python3

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "external_acceptance_preflight.py"
SPEC = importlib.util.spec_from_file_location("external_acceptance_preflight", SCRIPT)
assert SPEC and SPEC.loader
preflight = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = preflight
SPEC.loader.exec_module(preflight)


def evidence(kind, provenance="external", reference=None):
    return {
        "kind": kind,
        "provenance": provenance,
        "observed_at_utc": "2026-08-15T18:00:00Z",
        "reference": reference or f"evidence/{kind}.txt",
        "summary": "sanitized evidence summary",
    }


def passing_manifest():
    required = {
        check_id: list(spec.required_kinds)
        for check_id, spec in preflight.CHECKS.items()
    }
    return {
        "schema_version": "1",
        "environment": {"architecture": "arm64", "os_version": "redacted-safe-value"},
        "checks": [
            {
                "id": check_id,
                "status": "passed",
                "evidence": [evidence(kind) for kind in kinds],
                "blockers": [],
            }
            for check_id, kinds in required.items()
        ],
    }


class ExternalAcceptancePreflightTests(unittest.TestCase):
    def test_empty_report_is_blocked_for_every_external_row(self):
        report = preflight.build_report(None, "2026-08-15T18:00:00Z")

        self.assertFalse(report["passable"])
        self.assertEqual(report["overall_status"], "blocked")
        self.assertEqual(len(report["checks"]), 5)
        self.assertTrue(all(row["status"] == "blocked" for row in report["checks"]))

    def test_all_required_real_evidence_is_passable(self):
        report = preflight.build_report(passing_manifest(), "2026-08-15T18:00:00Z")

        self.assertTrue(report["passable"])
        self.assertEqual(report["overall_status"], "passed")
        self.assertTrue(all(row["evidence_state"] == "actual" for row in report["checks"]))

    def test_missing_required_evidence_downgrades_requested_pass(self):
        manifest = passing_manifest()
        packaged = next(row for row in manifest["checks"] if row["id"] == "packaged_real_capture")
        packaged["evidence"] = [evidence("packaged_real_capture")]

        report = preflight.build_report(manifest, "2026-08-15T18:00:00Z")
        row = next(row for row in report["checks"] if row["id"] == "packaged_real_capture")

        self.assertFalse(report["passable"])
        self.assertEqual(row["status"], "blocked")
        self.assertIn("helper_login_item", " ".join(row["blockers"]))

    def test_fixture_or_contract_evidence_cannot_pass(self):
        manifest = passing_manifest()
        vision = next(row for row in manifest["checks"] if row["id"] == "vision_corpus")
        vision["evidence"] = [
            evidence(kind, "fixture") for kind in preflight.CHECKS["vision_corpus"].required_kinds
        ]

        report = preflight.build_report(manifest, "2026-08-15T18:00:00Z")
        row = next(row for row in report["checks"] if row["id"] == "vision_corpus")

        self.assertEqual(row["status"], "blocked")
        self.assertIn("real external evidence", " ".join(row["blockers"]))

    def test_secrets_and_raw_capture_fields_are_removed_and_block_pass(self):
        manifest = passing_manifest()
        manifest["checks"][0]["api_key"] = "sk-or-v1-do-not-store-this"
        manifest["checks"][0]["raw_capture"] = "data:image/png;base64,AAAA"
        manifest["checks"][0]["evidence"][0]["summary"] = "Bearer super-secret-token"

        report = preflight.build_report(manifest, "2026-08-15T18:00:00Z")
        serialized = json.dumps(report)
        row = next(row for row in report["checks"] if row["id"] == "packaged_real_capture")

        self.assertTrue(report["input_redacted"])
        self.assertFalse(report["passable"])
        self.assertEqual(row["status"], "blocked")
        self.assertNotIn("do-not-store-this", serialized)
        self.assertNotIn("data:image", serialized)
        self.assertNotIn("super-secret-token", serialized)

    def test_raw_media_reference_is_not_acceptable(self):
        manifest = passing_manifest()
        manifest["checks"][0]["evidence"][0]["reference"] = "captures/first.png"

        report = preflight.build_report(manifest, "2026-08-15T18:00:00Z")
        row = next(row for row in report["checks"] if row["id"] == "packaged_real_capture")

        self.assertEqual(row["status"], "blocked")
        self.assertIn("safe non-raw artifact reference", " ".join(row["blockers"]))

    def test_cli_writes_scrubbed_report_and_uses_nonzero_for_blocked(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            exit_code = preflight.main(["--output", str(output)])
            self.assertEqual(exit_code, 1)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertFalse(report["passable"])
            self.assertEqual(len(report["checks"]), 5)


if __name__ == "__main__":
    unittest.main()
