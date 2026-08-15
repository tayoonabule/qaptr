# Deterministic packaged smoke fixture

This directory is a credential-free, Screen Recording-independent fixture for the
packaged-app portion of U23. It is deliberately not evidence of a real capture:
the real helper-generated capture gate remains external until a packaged helper
runs with Screen Recording permission.

`bench/scripts/packaged_fixture_smoke.sh` validates the normal nested bundle
layout, validates the committed 24-capture session inventory, launches the
packaged review executable in an isolated `HOME`, and checks a scalar capture
status plus a non-empty review-session result fixture. The review result models
the production-shaped acceptance boundary without making provider calls or
persisting image bytes.

The fixture uses images already covered by `fixtures/session/manifest.csv`; no
new screenshot material is stored here.
