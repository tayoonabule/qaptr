#!/usr/bin/env python3
"""Validate external acceptance evidence without performing external actions.

This helper only reads a JSON evidence manifest and writes a scrubbed report. It
does not request permissions, access credentials, call providers, run release or
signing tools, touch Screen Recording, delete artifacts, or use the network.

Exit status is 0 only when all five external rows have the required real
evidence. Missing, synthetic, fixture-only, malformed, or secret-bearing input
can never produce a pass.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPORT_KIND = "external_acceptance_preflight"
SCHEMA_VERSION = "1"
REAL_PROVENANCE = {"external", "controlled_external"}
SAFE_LOCAL_PROVENANCE = REAL_PROVENANCE | {"local_measurement"}
KNOWN_PROVENANCE = SAFE_LOCAL_PROVENANCE | {"fixture", "contract", "synthetic", "unknown"}
SAFE_ENVIRONMENT_KEYS = {
    "architecture",
    "display_class",
    "host_label",
    "machine_class",
    "machine_memory_gb",
    "observed_at_utc",
    "os_version",
}
SAFE_REFERENCE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,180}$")
RAW_REFERENCE_SUFFIXES = (
    ".png",
    ".jpg",
    ".jpeg",
    ".heic",
    ".gif",
    ".bmp",
    ".mov",
    ".mp4",
    ".webm",
    ".wav",
    ".m4a",
    ".raw",
)
SENSITIVE_KEY = re.compile(
    r"(?:api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password|"
    r"authorization|cookie|credential|raw(?:_|$)|payload|screenshot|thumbnail|"
    r"image[_-]?bytes|capture[_-]?bytes|provider[_-]?(?:request|response|payload))",
    re.IGNORECASE,
)
SECRET_VALUE = re.compile(
    r"(?:sk-or-v1-[A-Za-z0-9_-]{12,}|sk-[A-Za-z0-9_-]{16,}|"
    r"Bearer\s+[A-Za-z0-9._~+/=-]{12,}|"
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----|data:image/|"
    r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})",
    re.IGNORECASE,
)
BASE64_VALUE = re.compile(r"^[A-Za-z0-9+/=_-]{512,}$")


@dataclass(frozen=True)
class CheckSpec:
    description: str
    required_kinds: tuple[str, ...]


CHECKS: dict[str, CheckSpec] = {
    "packaged_real_capture": CheckSpec(
        "Packaged helper real Screen Recording capture and persisted review state.",
        (
            "packaged_real_capture",
            "helper_login_item",
            "review_persisted_state",
            "capture_failure_matrix",
            "artifact_scrub_audit",
        ),
    ),
    "openrouter_cli": CheckSpec(
        "Credentialed OpenRouter proof plus one authenticated CLI provider flow.",
        (
            "openrouter_detection",
            "openrouter_model_resolution",
            "consent_summary",
            "openrouter_invocation",
            "openrouter_normalized_response",
            "cli_end_to_end",
            "artifact_scrub_audit",
        ),
    ),
    "vision_corpus": CheckSpec(
        "Approved real Vision recognizer and 24-capture preparation corpus.",
        (
            "vision_real_corpus",
            "vision_environment",
            "vision_recall_result",
            "artifact_scrub_audit",
        ),
    ),
    "clean_machine_soak": CheckSpec(
        "Clean-machine bootstrap, reference hardware, and uninterrupted soak evidence.",
        (
            "clean_machine_bootstrap",
            "reference_machine_soak",
            "twelve_hour_soak",
            "opened_app_budget",
            "artifact_scrub_audit",
        ),
    ),
    "signing_notarization": CheckSpec(
        "Developer ID signing, notarization, Gatekeeper, reboot persistence, and reproducibility.",
        (
            "developer_id_signature",
            "notarization_ticket",
            "gatekeeper_assessment",
            "reboot_login_item",
            "reproducibility_comparison",
            "artifact_scrub_audit",
        ),
    ),
}


def now_utc() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _scrub(value: Any, path: str, unsafe_paths: list[str]) -> Any:
    """Return safe JSON-shaped data and record anything removed or redacted."""

    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, child in value.items():
            key_text = str(key)
            child_path = f"{path}.{key_text}" if path else key_text
            if SENSITIVE_KEY.search(key_text):
                unsafe_paths.append(child_path)
                continue
            result[key_text] = _scrub(child, child_path, unsafe_paths)
        return result
    if isinstance(value, list):
        return [_scrub(child, f"{path}[{index}]", unsafe_paths) for index, child in enumerate(value)]
    if isinstance(value, str):
        lower_value = value.lower()
        looks_like_raw_media_path = lower_value.endswith(RAW_REFERENCE_SUFFIXES) and (
            "/" in value or "\\" in value or value.startswith("file:")
        )
        looks_like_raw_provider_data = len(value) > 512 and (
            value.lstrip().startswith(("{", "["))
            or '"choices"' in value
            or '"messages"' in value
        )
        if (
            SECRET_VALUE.search(value)
            or BASE64_VALUE.fullmatch(value)
            or looks_like_raw_media_path
            or looks_like_raw_provider_data
        ):
            unsafe_paths.append(path)
            return "[REDACTED]"
        return value
    if value is None or isinstance(value, (bool, int, float)):
        return value
    unsafe_paths.append(path)
    return "[REDACTED]"


def _blocked_row(check_id: str, reason: str) -> dict[str, Any]:
    return {
        "id": check_id,
        "status": "blocked",
        "evidence_state": "blocked",
        "evidence": [],
        "blockers": [reason],
        "notes": [CHECKS[check_id].description],
    }


def template_report(timestamp: str | None = None) -> dict[str, Any]:
    """Create a truthful report when no external evidence has been supplied."""

    return {
        "schema_version": SCHEMA_VERSION,
        "report_kind": REPORT_KIND,
        "generated_at_utc": timestamp or now_utc(),
        "overall_status": "blocked",
        "passable": False,
        "input_redacted": False,
        "validation_errors": [],
        "environment": {},
        "checks": [
            _blocked_row(check_id, "no external evidence manifest was supplied")
            for check_id in CHECKS
        ],
    }


def _safe_reference(reference: Any) -> bool:
    if not isinstance(reference, str) or not SAFE_REFERENCE.fullmatch(reference):
        return False
    if reference.startswith("/") or ".." in Path(reference).parts:
        return False
    return not reference.lower().endswith(RAW_REFERENCE_SUFFIXES)


def _evidence_item(raw: Any, index: int, errors: list[str]) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        errors.append(f"evidence[{index}] is not an object")
        return None
    allowed = {"kind", "provenance", "observed_at_utc", "reference", "summary", "metrics", "artifact_sha256"}
    item = {key: raw[key] for key in allowed if key in raw}
    missing = [key for key in ("kind", "provenance", "observed_at_utc", "reference") if key not in item]
    if missing:
        errors.append(f"evidence[{index}] missing: {', '.join(missing)}")
        return None
    if not isinstance(item["kind"], str) or not item["kind"]:
        errors.append(f"evidence[{index}] kind must be a non-empty string")
    if item["provenance"] not in KNOWN_PROVENANCE:
        errors.append(f"evidence[{index}] has unsupported provenance")
    if not isinstance(item["observed_at_utc"], str) or not item["observed_at_utc"]:
        errors.append(f"evidence[{index}] observed_at_utc must be non-empty")
    if not _safe_reference(item["reference"]):
        errors.append(f"evidence[{index}] reference must be a safe non-raw artifact reference")
    if "summary" in item and (not isinstance(item["summary"], str) or len(item["summary"]) > 500):
        errors.append(f"evidence[{index}] summary must be at most 500 characters")
    if "metrics" in item and not isinstance(item["metrics"], dict):
        errors.append(f"evidence[{index}] metrics must be an object")
    if "artifact_sha256" in item and (
        not isinstance(item["artifact_sha256"], str)
        or not re.fullmatch(r"[a-fA-F0-9]{64}", item["artifact_sha256"])
    ):
        errors.append(f"evidence[{index}] artifact_sha256 must be 64 hexadecimal characters")
    return item


def build_report(manifest: dict[str, Any] | None, timestamp: str | None = None) -> dict[str, Any]:
    """Validate and scrub a manifest into a pass-gated report."""

    if manifest is None:
        return template_report(timestamp)
    unsafe_paths: list[str] = []
    safe_manifest = _scrub(manifest, "", unsafe_paths)
    if not isinstance(safe_manifest, dict):
        return template_report(timestamp)

    errors: list[str] = []
    if safe_manifest.get("schema_version", SCHEMA_VERSION) != SCHEMA_VERSION:
        errors.append("unsupported schema_version")
    raw_checks = safe_manifest.get("checks", [])
    if not isinstance(raw_checks, list):
        raw_checks = []
        errors.append("checks must be an array")
    by_id: dict[str, dict[str, Any]] = {}
    for raw_check in raw_checks:
        if not isinstance(raw_check, dict):
            errors.append("check row is not an object")
            continue
        check_id = raw_check.get("id")
        if check_id not in CHECKS:
            errors.append(f"unknown check id: {check_id!r}")
            continue
        if check_id in by_id:
            errors.append(f"duplicate check id: {check_id}")
            continue
        by_id[check_id] = raw_check

    rows: list[dict[str, Any]] = []
    for check_id, spec in CHECKS.items():
        raw_check = by_id.get(check_id)
        if raw_check is None:
            rows.append(_blocked_row(check_id, "no evidence manifest row was supplied"))
            continue

        row_errors: list[str] = []
        status = raw_check.get("status", "blocked")
        if status not in {"passed", "failed", "blocked", "unverified"}:
            row_errors.append("status must be passed, failed, blocked, or unverified")
            status = "blocked"
        raw_evidence = raw_check.get("evidence", [])
        if not isinstance(raw_evidence, list):
            row_errors.append("evidence must be an array")
            raw_evidence = []
        evidence: list[dict[str, Any]] = []
        for index, item in enumerate(raw_evidence):
            parsed = _evidence_item(item, index, row_errors)
            if parsed is not None:
                evidence.append(parsed)
        blockers = raw_check.get("blockers", [])
        if not isinstance(blockers, list) or not all(isinstance(item, str) for item in blockers):
            row_errors.append("blockers must be an array of strings")
            blockers = []
        blockers = list(blockers)
        notes = raw_check.get("notes", [])
        if not isinstance(notes, list) or not all(isinstance(item, str) for item in notes):
            row_errors.append("notes must be an array of strings")
            notes = []
        notes = list(notes)

        evidence_kinds = {item.get("kind") for item in evidence}
        missing = [kind for kind in spec.required_kinds if kind not in evidence_kinds]
        if status == "passed":
            if unsafe_paths:
                row_errors.append("input contained secret or raw-capture material and was redacted")
            if missing:
                row_errors.append("missing required evidence: " + ", ".join(missing))
            if any(
                item.get("provenance") not in REAL_PROVENANCE
                and not (
                    item.get("kind") == "artifact_scrub_audit"
                    and item.get("provenance") in SAFE_LOCAL_PROVENANCE
                )
                for item in evidence
            ):
                row_errors.append("passed rows require real external evidence, not fixtures or contracts")
            if blockers:
                row_errors.append("passed rows cannot retain blockers")
            if row_errors:
                status = "blocked"
                blockers.extend(row_errors)
        elif status == "failed":
            if not evidence or not any(item.get("provenance") in REAL_PROVENANCE for item in evidence):
                row_errors.append("failed rows require at least one real external observation")
            if not blockers:
                row_errors.append("failed rows require a concise blocker or failure reason")
            if row_errors:
                status = "blocked"
                blockers.extend(row_errors)
        elif status in {"blocked", "unverified"} and not blockers:
            blockers.append("status is not passable without an explicit blocker reason")

        rows.append(
            {
                "id": check_id,
                "status": status,
                "evidence_state": "actual" if status in {"passed", "failed"} else "blocked",
                "evidence": evidence,
                "blockers": blockers,
                "notes": notes or [spec.description],
            }
        )

    if unsafe_paths:
        errors.append("input contained secret or raw-capture material; sensitive fields were omitted")
    raw_environment = safe_manifest.get("environment", {})
    environment: dict[str, str | int | float | bool | None] = {}
    if isinstance(raw_environment, dict):
        for key in SAFE_ENVIRONMENT_KEYS:
            value = raw_environment.get(key)
            if value is None or isinstance(value, (str, int, float, bool)):
                if key in raw_environment:
                    environment[key] = value
            else:
                errors.append(f"environment.{key} must be a scalar")
    else:
        errors.append("environment must be an object")
    overall_status = "passed"
    if any(row["status"] in {"blocked", "unverified"} for row in rows):
        overall_status = "blocked"
    elif any(row["status"] == "failed" for row in rows):
        overall_status = "failed"
    elif errors:
        overall_status = "blocked"
    return {
        "schema_version": SCHEMA_VERSION,
        "report_kind": REPORT_KIND,
        "generated_at_utc": timestamp or now_utc(),
        "overall_status": overall_status,
        "passable": overall_status == "passed",
        "input_redacted": bool(unsafe_paths),
        "validation_errors": errors,
        "environment": environment,
        "checks": rows,
    }


def _read_manifest(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("evidence manifest must contain a JSON object")
    return value


def _write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write("\n")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate only supplied external evidence. This command performs no permissions, "
            "credential, signing, release, deletion, or network action."
        )
    )
    parser.add_argument("--input", type=Path, help="JSON evidence manifest; omitted means all rows are blocked")
    parser.add_argument("--output", type=Path, help="write the scrubbed report JSON to this path")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        manifest = _read_manifest(args.input) if args.input else None
        report = build_report(manifest)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"external acceptance preflight input error: {error}", file=sys.stderr)
        return 2
    if args.output:
        try:
            _write_report(args.output, report)
        except OSError as error:
            print(f"external acceptance preflight output error: {error}", file=sys.stderr)
            return 2
    else:
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    return 0 if report["passable"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
