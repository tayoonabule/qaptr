# Qaptr v1 release evidence

## U16 provider detection evidence

Recorded on 2026-08-14 UTC on the Apple-silicon development machine.

| Provider | Resolved executable | Version command output | Parsed version | Detection result |
|---|---|---|---|---|
| Codex CLI | `/Users/light/.codex/packages/standalone/releases/0.147.0-aarch64-apple-darwin/bin/codex` | `codex-cli 0.147.0` | `0.147.0` | Installed, authenticated, gate accepted |
| Jcode CLI | `/Users/light/.jcode/builds/versions/22db449/jcode` | `jcode v0.75.23-dev (22db449)` | `0.75.23` | Installed, authenticated, gate accepted |

The version strings above were parsed by U14's `VersionProbe`, not copied from
configuration. The real detection tests were run through `ProviderGate` and
U14's `CliRuntime` with the installed executables.

Codex's sandboxed `codex login status` probe returned no status bytes and a
signal-style non-zero exit on this machine. The adapter did not read the OAuth
file or any token. For the production constructor only, it used a metadata-only
fallback that checked that `~/.codex/auth.json` exists and is non-empty. This
keeps the token inside Codex while still distinguishing the installed existing
session from an absent login. The in-process unauthenticated test uses the CLI
probe output and returns `NotAuthenticated` without this production fallback.

The sandboxed Jcode auth probe returned tabular status containing `claude`
`available` and `openai` `available`; no credential contents were read by Qaptr.

## U15 Claude detection evidence

Recorded on 2026-08-15 UTC on the Apple-silicon development machine. With the
cmux session shim removed from `PATH`, discovery resolves the genuine Claude
Code installation to `/Users/light/.local/share/claude/versions/2.1.228`, a
real arm64 Mach-O. Direct invocation outside U14's sandbox reports
`2.1.228 (Claude Code)` and `loggedIn: true` with exit 0. Qaptr did not read,
store, or forward any Claude login token.

The Claude adapter now allowlists the canonical executable's parent and, for
the versioned `<install>/versions/<version>` layout, the derived installation
root. This fixes the resource-mapping failure without weakening U14's
deny-by-default profile. The sandboxed CLI then reaches the version and auth
probes, but reports `loggedIn: false` because Claude's existing session is
macOS-Keychain-backed and U14 intentionally grants no Keychain access. The
shared gate preserves this as typed `NotAuthenticated`, not a runtime failure.
The ignored test is:

```sh
cargo test -p qaptr-provider-cli --test claude -- --ignored installed_claude_reports_sandbox_auth_honestly
```

The test runs detection through `ProviderGate` and U14's `CliRuntime`. It
passes only when Claude reaches a correctly-versioned authenticated result or
the honest typed `NotAuthenticated` limitation above. It must not be made
green by granting broad Keychain access or by reading Claude credentials.
OpenCode is also installed at `~/.opencode/bin/opencode`, but it is outside the
four release-gating providers and has no Qaptr adapter.

U16 also verifies missing installation, unauthenticated state, old versions,
malformed output, image-capability refusal, and identical normalized response
shape using deterministic in-process executors. Codex and Jcode adapters expose
no credential argument and contain no API-key environment path. Their only
invocation path is a U13 `ProviderInvocation` proof produced by `ProviderGate`.

## U22 packaging evidence

U22 packages the SwiftUI review app and the capture helper without changing either
product surface. The produced hierarchy is:

```text
Qaptr.app/
  Contents/MacOS/Qaptr
  Contents/Applications/QaptrReview.app/
    Contents/MacOS/QaptrReview
    Contents/Frameworks/libqaptr_review_ffi.dylib
    Contents/Library/LoginItems/QaptrHelper.app/
      Contents/MacOS/QaptrHelper
      Contents/Frameworks/libqaptr_ffi.dylib
```

The outer launcher opens `QaptrReview.app`. The review app owns the helper login
item at the standard `Contents/Library/LoginItems` location. The helper keeps
`CFBundleIdentifier=com.qaptr.helper` and `LSUIElement=true`; the review app is
`com.qaptr.review` and the outer app is `com.qaptr.app`.

### Local verification without Apple credentials

No Developer ID identity, Apple account, password, API key, or notarytool profile
is needed for the local gate. From the repository root on Apple silicon:

```sh
swift test --package-path apps/helper
bash packaging/release.sh --dry-run
```

The dry-run builds both Swift packages, assembles the nested bundle, signs every
Mach-O and app deepest-first with `codesign --sign - --options runtime`, and runs
these release-blocking checks:

- each code-directory identifier equals its bundle `CFBundleIdentifier`, including
  the executable inside each app;
- `codesign --verify --deep --strict` succeeds for the outer app and every nested
  app, preventing the U3 resource-sealing failure class;
- the helper is in `Contents/Library/LoginItems`, has `LSUIElement=true`, has an
  executable, and is accepted by LaunchServices;
- the shipped helper executable does not link `Security.framework` and has no
  imported Keychain or decryption symbols (`SecItem*`, `SecKeychain*`, decryption
  `SecKey*`, or CommonCrypto cryptor/key-derivation imports);
- embedded entitlements equal `packaging/signing/entitlements.plist` and contain
  no broader sandbox, JIT, unsigned-executable, library-validation, or network
  capability; and
- a verified UDZO DMG is produced while notarization is explicitly dry-run only.

The empty entitlements plist is intentional. Qaptr is unsandboxed in v1, uses
TCC for Screen Recording and Accessibility, and uses app-scoped non-synchronizing
Keychain items. None requires a broader entitlement. TCC consent is a user
permission, not an entitlement.

To verify packaging from two clean archived checkouts after committing the
packaging change:

```sh
bash packaging/release.sh --dry-run --reproducibility-check
```

This refuses a dirty checkout, archives `HEAD` twice, runs the complete dry-run
in both clean trees, and compares hashes for every bundle file and the DMG. It is
also part of the manual release workflow.

### Developer ID release procedure

A release owner must perform these steps on a dedicated macOS release runner.
Credentials must be configured in the runner's keychain or secret manager, not
committed to this repository and not entered into this agent session.

1. Install a valid **Developer ID Application** certificate and private key in the
   runner login keychain. Confirm the identity name with
   `security find-identity -v -p codesigning`; never put the private key in git.
2. Create a `notarytool` keychain profile on that runner using Apple's approved
   credential setup. Pass only its profile name as `QAPTR_NOTARY_PROFILE`.
3. Set `QAPTR_SIGNING_IDENTITY` to the installed identity and run:

   ```sh
   QAPTR_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
   QAPTR_NOTARY_PROFILE='qaptr-release' \
   bash packaging/release.sh --reproducibility-check
   ```

`packaging/sign.sh` signs nested dylibs and executables, then nested apps, then
the outer app. `packaging/notarize.sh` creates a temporary zip, submits it with
`xcrun notarytool --keychain-profile ... --wait`, staples the ticket to the app,
and validates it with `xcrun stapler validate`. Only after that does `dmg.sh`
create the final DMG. Real mode runs `spctl --assess` on the Developer ID app.

The self-hosted `.github/workflows/release.yml` is manual and expects the
`qaptr-release` runner label. Its keychain and notarytool profile are release
owner infrastructure. If those credentials are unavailable, the workflow must
not be run and the DMG must not be represented as notarized.

### Credential-blocked claims

This checkout can prove ad-hoc signing, hardened-runtime flag usage, nested
bundle identity/resource sealing, helper placement, entitlement exactness, and
static dependency boundaries. It cannot prove a Developer ID chain,
notarization acceptance, ticket stapling, Gatekeeper assessment under a fresh
user profile, or helper persistence across logout/reboot. Those remain
release-blocking tests requiring a provisioned clean macOS profile and real
Apple credentials. No notarization result is claimed here.

### Rejected alternatives

- Tauri was not used for the review app. U3 selected SwiftUI and recorded a
  concrete Tauri code-directory/Info.plist mismatch plus strict resource-seal
  failure.
- Ad-hoc signing is not treated as a release signature. It is only the local
  verification shape available without Developer ID credentials.
- No broad entitlements were added to make launch or TCC behavior appear to
  work. A future required entitlement must be reviewed explicitly.
