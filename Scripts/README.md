# Quality and local release gates

Run from any directory:

```sh
Scripts/release-preflight.sh
```

The common CI/local preflight checks version metadata, runs the offline Python script
regressions, runs the repository's security pattern checks, and runs **all** SwiftPM
tests once with coverage. It does not access signing identities or the keychain.
The security checks are a limited source-pattern gate, not a vulnerability audit.
The CI dependency inventory step lists packages; it is not a vulnerability audit
(there are currently no external package dependencies).

For narrower checks:

```sh
python3 -B -m unittest discover -s Tests/Scripts -p 'test_*.py'
python3 Scripts/check-version.py
Scripts/test-with-coverage.sh
Scripts/check-coverage.sh                         # existing default .build run
Scripts/check-coverage.sh --build-path .build/coverage-runs/<run-id>
```

## Coverage contract

`test-with-coverage.sh` creates a new `.build/coverage-runs/<run-id>` scratch path
and prints it. No existing build or release artifacts are deleted. Inspect/remove
old run directories deliberately when no longer needed. This costs a clean build
but avoids mixing historical profiles or removed test products with this run.

The checker asks the selected SwiftPM toolchain for its current binary directory.
It supports macOS Swift 6 native layouts (`.build/<triple>/debug`, a single
`*PackageTests.xctest` executable) and Swift 6.4/Xcode 27's default swiftbuild
layout (`.build/out/Products/Debug`, one `.xctest` per test target). To explicitly
select a supported build system for the test/preflight command:

```sh
SWIFTPM_BUILD_SYSTEM=native Scripts/test-with-coverage.sh
# Checking that same run later:
Scripts/check-coverage.sh --build-path .build/coverage-runs/<run-id> --build-system native
```

The default is the installed toolchain's default; older toolchains need not understand
`--build-system swiftbuild`. Both the tests and checker receive the same selection.
The checker never searches other build directories for fallback artifacts.
Missing profiles/binaries, unexpected or incomplete test product sets, profiles older
than binaries or Swift sources, and LLVM export failures/mismatch warnings fail
explicitly. A standalone check validates existing artifacts; use the fresh-run wrapper
for release evidence rather than relying on timestamps alone.

One `llvm-cov export` invocation loads **all current test executables**, using
`-object` for additional products (including `AzCopyMacUIModelTests`). LLVM merges
shared source coverage before JSON export. Only files under `Sources/AzCopyMacUICore`
contribute; the gate sums `summary.lines.covered` / `summary.lines.count`, not region
coverage, displayed percentages, or averages of file/product percentages. Identical
duplicate file records count once; conflicting duplicates fail rather than guessing.
This includes coverage contributed by AppModel tests without charging UI source lines
to the core denominator. Non-executable constants need not appear in coverage.
The unrounded ratio must be **at least 80%**. `COVERAGE_THRESHOLD` may tighten the
requirement to at most 100%, but cannot lower it.

## Packaging

After updating `VERSION`, `AppVersion.current`, `CFBundleShortVersionString`, and every
Xcode `MARKETING_VERSION` to the same stable release version, ensure
`CFBundleVersion` equals every `CURRENT_PROJECT_VERSION`. The cask may still reference
the previous published version and is intentionally excluded.

### One-time credential binding

```sh
python3 Scripts/release-config.py configure --notary-profile "existing-keychain-profile"
```

This validates an existing profile with `notarytool history` and saves only nonsecret
references in the checkout's local Git configuration. It does not export passwords,
create/update Keychain credentials, sign code, or create release artifacts.
The unique valid Developer ID Application identity and its team are selected automatically.
Multiple identities require an explicit `--signing-identity` (certificate name or SHA-1
fingerprint); `--team-id` can narrow the selection and must match the certificate.

| Environment override | Local Git setting |
| --- | --- |
| `DEVELOPER_ID_APPLICATION` | `azcopyRelease.signingIdentity` |
| `APPLE_TEAM_ID` | `azcopyRelease.teamID` |
| `NOTARY_PROFILE` | `azcopyRelease.notaryProfile` |
| `NOTARY_KEYCHAIN` | `azcopyRelease.notaryKeychain` |

Configuration arguments override environment values; environment values override local
Git settings. The selected references survive new shells/restarts but are not committed.
Each new checkout/CI machine needs its own binding or explicit overrides.
Only a successfully validated configuration is saved.

For a file-based custom Keychain, pass `--notary-keychain "/path/to/release.keychain-db"`.
The same file is used for both credential validation and notarization submission.
To return to notarytool's default/protected Keychain, configure with `--default-keychain`.
Do not assume that the default store is `login.keychain-db`: `store-credentials --sync`
uses iCloud Keychain/Local Items, while `--keychain` explicitly selects a file.

```sh
python3 Scripts/release-config.py show   # nonsecret resolved references; no Apple request
python3 Scripts/release-config.py check  # signing identity + credential/network check
Scripts/package-release.sh             # no exports needed after configuration
```

An unset `NOTARY_PROFILE` is a missing reference, **not evidence of absent credentials**.
`notarytool` has no profile-list command. It has its own Keychain access group, and
ordinary `security dump-keychain`/unentitled queries may not see protected profiles.
Supply the exact name originally given to `notarytool store-credentials`, rather than
guessing names or recreating credentials. If that name is not recorded, it must be
obtained from the existing signing setup or its owner before this checkout can be bound.
The helper does not bypass Keychain access restrictions.

Diagnostics distinguish an unconfigured reference, an explicitly missing Keychain file,
an unreadable/locked profile, Apple's credential rejection, and other validation/network
failures. A failed check preserves prior configuration and release artifacts.
For actual credential expiry/revocation, update the known profile using Apple's
interactive `notarytool store-credentials` workflow; do not put passwords in Git,
configuration files, or command-line examples.

Signing inputs are passed as argument arrays/serialized plist strings, not evaluated
as shell or PlistBuddy commands.

Packaging always reruns the preflight **before** resolving signing inputs, accessing
the Keychain, signing, or creating release artifacts; there is no skip-gates switch.
The standalone configuration/check commands are credential diagnostics, not packaging
shortcuts. Credential validation happens before creating a release stage, so a bad
reference or expired credentials cannot leave a blocking partial stage.

An existing `release/<VERSION>/` is refused by default. To deliberately retry:

```sh
Scripts/package-release.sh --retry
```

After gates and credential validation succeed, the previous stage is moved intact
to `release/.retry-<VERSION>.<unique>/artifacts`, then a fresh stage is created.
Symlinked stages/release roots are refused even with `--retry`; previous versions are
not touched. No recursive deletion or silent overwrite is performed.
A per-version `release/.<VERSION>.lock` prevents concurrent packaging from moving an
active stage. Normal exits release the lock. After a hard process/machine crash,
inspect the recorded PID in the lock's `pid` file and verify no corresponding packaging
process is still running before deliberately removing that PID file and empty lock.

Archive/export remain Developer ID signed with hardened runtime/timestamp checks.
Both archive and exported app versions are checked against source metadata, and every
bundled Mach-O must be arm64-only, before submitting to notarization. The app is then
stapled, validated and assessed with Gatekeeper; the final ZIP is regenerated after
stapling and SHA-256 is written alongside it:

```text
release/<VERSION>/azcopy-mac-ui-<VERSION>-macos-arm64.zip
release/<VERSION>/azcopy-mac-ui-<VERSION>-macos-arm64.zip.sha256
```

The checksum records the ZIP basename, so it remains verifiable after downloading or
moving the ZIP and checksum together.

One CI job runs the same preflight once, records the dependency inventory, and verifies
an unsigned arm64 Release app build (there is no redundant security workflow runner).
Script tests use offline fake signing/notary commands and project-local fixture
directories; they never exercise credentials. Actual signing/notarization and deployment
remain local release steps and are not claimed by the offline regression suite.
