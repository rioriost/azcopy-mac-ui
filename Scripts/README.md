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

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Example (ABCDEFGHIJ)" \
NOTARY_PROFILE="existing-keychain-profile" \
Scripts/package-release.sh
```

`APPLE_TEAM_ID` can be supplied explicitly; otherwise it is extracted from the signing
identity. Signing inputs are passed as arguments/serialized plist strings, not evaluated
as shell or PlistBuddy commands. The script uses the existing notarytool keychain profile;
it neither creates nor modifies credentials.

Packaging always reruns the preflight **before** reading signing inputs, accessing
the keychain, signing, or creating release artifacts; there is no skip-gates switch.
It reserves `release/<VERSION>/` and refuses an existing stage or a symlinked release
root. To retry a failed run, deliberately move its exact version directory aside;
the script never wipes `release/` or previous versions.

Archive/export remain Developer ID signed with hardened runtime/timestamp checks.
Both archive and exported app versions are checked against source metadata, and every
bundled Mach-O must be arm64-only, before submitting to notarization. The app is then
stapled, validated and assessed with Gatekeeper; the final ZIP is regenerated after
stapling and SHA-256 is written alongside it:

```text
release/<VERSION>/azcopy-mac-ui-<VERSION>-macos-arm64.zip
release/<VERSION>/azcopy-mac-ui-<VERSION>-macos-arm64.zip.sha256
```

One CI job runs the same preflight once, records the dependency inventory, and verifies
an unsigned arm64 Release app build (there is no redundant security workflow runner).
Script tests use offline fake signing/notary commands and project-local fixture
directories; they never exercise credentials. Actual signing/notarization and deployment
remain local release steps and are not claimed by the offline regression suite.
