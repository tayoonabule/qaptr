# Packaged smoke evidence handoff

`bench/release_validation.md` was already modified before this change and was
intentionally not edited. The next U23 report regeneration should include the
new `packaged_fixture_smoke` gate and preserve the distinction between fixture
proof and real capture proof.

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
```

The gate proves the normal nested package launches the review executable and
consumes isolated scalar progress while a deterministic, non-empty review result
fixture is validated. It does not close the external `0.2` items requiring a
real helper-generated sealed capture, Screen Recording permission, login-item
startup, or a clean-machine fresh-install flow. Those claims remain blocked or
unverified until their evidence is run on the validation machine.
