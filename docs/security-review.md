# Security review checklist

Run this checklist before approving a release environment deployment.

## Required automated gates

- `Scripts/release-preflight.sh` passes for the exact source being packaged.
- `Scripts/security-review.sh` passes.
- `Scripts/check-coverage.sh` reports at least 80% coverage for `AzCopyMacUICore`.
- Release artifact is arm64-only.
- Release artifact is signed with hardened runtime.
- Notarization submission succeeds and the ticket is stapled.

## Manual review

- No code path invokes `/bin/sh`, `/bin/bash`, `/bin/zsh`, `/usr/bin/env azcopy`, or shell interpolation.
- `Process` receives a resolved executable URL and argument array.
- Service-principal secrets, certificate passwords, SAS signatures, tokens, and account keys are redacted before display/logging.
- Secret values are not persisted to `UserDefaults`, repository files, crash reports, or CI logs.
- Non-Homebrew AzCopy paths are explicit user choices, not silent PATH hijacks.
- Azure Storage URLs default to HTTPS.
- The selected recursive/dry-run/delete/overwrite settings cannot be overridden by additional flags.
- SAS flags with separate values and credentials split across output reads remain redacted.
- Existing saved credentials are removed during preferences migration.
- Cancellation stops only the current child process and never reports success.
- App Sandbox remains disabled for this version; hardened runtime remains enabled for notarization.

The source-pattern script is a limited automated check, not a substitute for this
manual review or a vulnerability audit. Dependency inventory is not a vulnerability
audit. Local packaging always enforces the common preflight before signing and
notarization; no release workflow bypass is provided.
