# U23 review-session fixture

`manifest.csv` is the committed 24-capture fixture session used by release
validation. Each row is a logical production capture with the same 1600 x 1000
downscaled image dimensions used by the committed Vision corpus. The `source`
column points at an existing committed image fixture; the repeated sources are
intentional so the session exercises 24 scheduled captures without adding
synthetic pixels that are not already covered by U9.

The manifest is input to `bench/scripts/release_validate.sh`. It is suitable for
the real Vision preparation measurement. The current review app does not yet
expose analysis, observation detail, workflow generation, or export controls,
so the full UI review-session gate must remain a reported failure until a
production-shaped driver exists.
