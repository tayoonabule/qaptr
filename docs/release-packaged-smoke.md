# Packaged smoke evidence handoff

The legacy release-validation report and its one-off benchmark probes have been
removed. Use `bench/scripts/packaged_fixture_smoke.sh` as the maintained package
gate, while preserving the distinction between fixture proof and real capture
proof.

Recommended report evidence after running the validator:

```text
packaged_fixture_smoke=PASS
fixture=fixtures/packaged-smoke
manifest_captures=24
scalar_capture_count=1
review_observations=1
review_workflows=1
exports=4
provider_requests=0
login_item_status_code=0
```

The gate proves the normal nested package launches the review executable and
consumes isolated scalar progress while a deterministic, non-empty review result
fixture is validated. It does not close the external `0.2` items requiring a
real helper-generated sealed capture, Screen Recording permission, login-item
startup, or a clean-machine fresh-install flow. Those claims remain blocked or
unverified until their evidence is run on the validation machine.

### Login-item scalar-status probe (7.1 row 197, partial)

The smoke script also compiles a tiny C probe against the packaged
`libqaptr_review_ffi.dylib` and calls `qaptr_login_item_status`, the exact
symbol `ReviewBridge.loginItemEnabled()` calls in the shipped review app. This
proves the scalar status path from the review app into the packaged FFI
library is real, reachable code on this machine, returning one of the
documented codes (`1`=granted, `0`=denied, `-2`=query failure). An ad-hoc-signed
dry-run package reports `0` (denied), which is expected since `SMAppService`
requires a Developer-ID signed, Team-ID-matched build to register successfully.

This closes only the "visible to the review app through scalar status" half of
row 197. It does **not** prove "the helper starts as the login item": that
still requires a signed build registered via `SMAppService` on a validation
machine, which remains an external, credentialed claim tracked as blocked.
