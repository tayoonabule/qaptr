# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability. Contact the repository owner through the private GitHub security advisory flow, or use the maintainer contact listed in the repository profile. Include the affected version/build, reproduction steps, impact, and whether any credentials or personal data may have been exposed.

Do not include real screenshots, capture bundles, databases, provider credentials, access tokens, or private machine paths in a report.

## Security boundaries

Qaptr is designed around these constraints:

- Captures remain local until a person explicitly starts analysis and approves the prepared boundary.
- Provider credentials remain owned by the supported local CLI applications.
- The helper owns the macOS permissions it actually uses.
- Release artifacts are checksummed when published.

These constraints are product goals, not a promise that every environment-dependent acceptance path has been verified. See `docs/release.md` for evidence and known blocked boundaries.
