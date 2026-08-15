# External acceptance preflight

`bench/scripts/external_acceptance_preflight.py` is an evidence-only helper for
the remaining external acceptance rows. It reads a JSON manifest and emits a
scrubbed report. It never requests permissions, reads credentials, calls a
provider, runs signing/release tools, deletes artifacts, or uses the network.

The report is passable only when every row has all required evidence kinds with
`external` or `controlled_external` provenance. Fixture, contract, synthetic,
missing, malformed, or secret-bearing evidence is recorded as blocked. A local
`artifact_scrub_audit` is allowed only as the hygiene proof alongside the real
external observations.

## Usage

Generate a truthful blocked report without performing any external action:

```sh
python3 bench/scripts/external_acceptance_preflight.py \
  --output bench/results/external_acceptance_report.json
```

Validate a separately collected, scrubbed manifest:

```sh
python3 bench/scripts/external_acceptance_preflight.py \
  --input evidence-manifest.json \
  --output bench/results/external_acceptance_report.json
```

Exit status is `0` only when all five rows are passable, `1` when the report is
truthfully blocked or failed, and `2` for invalid input/output handling. The
JSON contract is in `bench/external_acceptance_evidence.schema.json`.

Evidence references are opaque, safe artifact IDs such as
`evidence/vision-run-summary.txt`. They must not be absolute paths or point to
images, video, audio, screenshots, or raw payloads. The helper removes
sensitive fields and redacts secret-like values before writing a report.

## Checklist mapping

| Report row | Checklist rows | Required real evidence kinds |
|---|---|---|
| `packaged_real_capture` | `qaptr-next-session-todos.md` 0.2 rows 27–33; 7.1 rows 195–196 | `packaged_real_capture`, `helper_login_item`, `review_persisted_state`, `capture_failure_matrix`, `artifact_scrub_audit` |
| `openrouter_cli` | 3.3 rows 114–117; 3.4 rows 120–126; 6.2 rows 186–190 | `openrouter_detection`, `openrouter_model_resolution`, `consent_summary`, `openrouter_invocation`, `openrouter_normalized_response`, `cli_end_to_end`, `artifact_scrub_audit` |
| `vision_corpus` | 6.1 rows 180–183 | `vision_real_corpus`, `vision_environment`, `vision_recall_result`, `artifact_scrub_audit` |
| `clean_machine_soak` | 7.2 rows 200–203; external blockers 234 and 236 | `clean_machine_bootstrap`, `reference_machine_soak`, `twelve_hour_soak`, `opened_app_budget`, `artifact_scrub_audit` |
| `signing_notarization` | 7.3 rows 206–209; `qaptr-v1.md` U22 | `developer_id_signature`, `notarization_ticket`, `gatekeeper_assessment`, `reboot_login_item`, `reproducibility_comparison`, `artifact_scrub_audit` |

This helper does not close any checklist row by itself. It makes the missing
external evidence explicit and prevents a report from claiming completion based
on the existing deterministic fixture, contract tests, or idle launch checks.
