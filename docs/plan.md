# azcopy-mac-ui implementation plan

## Goal

Build `azcopy-mac-ui` as a native macOS GUI for [AzCopy](https://github.com/Azure/azure-storage-azcopy). The app wraps the Homebrew-installed `azcopy` CLI, exposes safe transfer/authentication workflows, and is prepared for notarized Homebrew distribution.

## Requirements baseline

| Area | Decision |
| --- | --- |
| Language/tooling | Swift 6, SwiftUI/AppKit where necessary, SwiftPM core library plus a real Xcode macOS app target for archive/notarization. |
| Version | Start at `0.1.0`. |
| License | MIT. |
| Distribution | Homebrew cask metadata for a custom tap with `depends_on formula: "azcopy"`; release artifacts are signed, notarized, stapled, and checksumed. |
| macOS support | Target macOS 14 Sonoma or newer, covering Apple-supported macOS releases as of 2026-07: macOS 14 Sonoma, 15 Sequoia, and 26 Tahoe. |
| CPU support | arm64 only. CI and packaging fail if x86_64 artifacts are produced. |
| Azure dependency | `azcopy` is not bundled. The app resolves `/opt/homebrew/bin/azcopy` first, allows explicit user selection when needed, and surfaces installation guidance if missing. |
| Tests | Unit tests target 80%+ line coverage for the `AzCopyMacUICore` library: command-building, auth modeling, process execution, validation, and security guardrails. |
| Release gates | Coverage and security review are required before release packaging. |
| CI/CD | GitHub Actions for test/coverage, security review, archive/sign/notarize/staple, and Homebrew artifact preparation. |

## Architecture

Use a small, testable core library plus a native GUI shell:

1. `AzCopyMacUICore`
   - `AzCopyLocator`: finds the Homebrew `azcopy` executable and validates `azcopy --version`.
   - `AzCopyCommandBuilder`: creates argument arrays without shell interpolation.
   - `AzCopyProcessRunner`: launches only a resolved executable URL with `Process`, streams output, and supports cancellation.
   - `TransferRequest`: typed model for `copy`, `sync`, `list`, `remove`, and job-management commands.
   - `AuthenticationMethod`: typed model for all supported Azure auth flows.
   - `CredentialRedactor`: redacts SAS signatures, account keys, client secrets, certificate passwords, and access tokens in logs/UI.
   - `SecurityPolicy`: validates executable location, argument construction, URL schemes, secret handling, and disallows shell evaluation.
2. `AzCopyMacUI`
   - SwiftUI app in an Xcode app target following macOS HIG: sidebar navigation, clear primary actions, progressive disclosure for advanced flags, native alerts/sheets, keyboard navigation, accessibility labels, and system appearance support.
   - Owns `Info.plist`, bundle identifier, entitlements, app icon placeholder, version metadata, hardened runtime signing settings, and archive configuration.
   - Views: Dashboard, Transfer, Authentication, Jobs, Settings, and Logs.
3. Tests
   - Unit tests for all pure core logic.
   - Process-runner tests use a local fixture executable instead of real Azure access.
   - UI smoke tests can be added after the first Xcode project archive is stable.

## Azure authentication support

Azure authorization is modeled explicitly. The GUI must not hide incompatible options or persist secrets unexpectedly.

| Method | AzCopy mechanism | UI behavior |
| --- | --- | --- |
| Microsoft Entra user identity | `azcopy login [--tenant-id]` or `AZCOPY_AUTO_LOGIN_TYPE=DEVICE` | Interactive login screen with tenant field and device-code output capture. |
| Azure CLI session | `AZCOPY_AUTO_LOGIN_TYPE=AZCLI`, optional `AZCOPY_TENANT_ID` | Treats Azure CLI as an external prerequisite and reports missing CLI/session clearly. |
| Azure PowerShell session | `AZCOPY_AUTO_LOGIN_TYPE=PSCRED`, optional `AZCOPY_TENANT_ID` | Supported as an advanced option for users who already authenticate through PowerShell. |
| Service principal with client secret | `AZCOPY_AUTO_LOGIN_TYPE=SPN`, `AZCOPY_SPA_APPLICATION_ID`, `AZCOPY_SPA_CLIENT_SECRET`, `AZCOPY_TENANT_ID` or `azcopy login --service-principal` | Secret input uses secure fields, never appears in command preview, logs, or persisted preferences. |
| Service principal with certificate | `AZCOPY_AUTO_LOGIN_TYPE=SPN`, `AZCOPY_SPA_APPLICATION_ID`, `AZCOPY_SPA_CERT_PATH`, `AZCOPY_SPA_CERT_PASSWORD`, `AZCOPY_TENANT_ID` or `azcopy login --service-principal --certificate-path` | File picker for certificate path; password redacted and not persisted. |
| Managed identity, system-assigned | `AZCOPY_AUTO_LOGIN_TYPE=MSI` or `azcopy login --identity` | Available with guidance that it only succeeds on supported Azure hosts. |
| Managed identity, user-assigned client ID | `AZCOPY_AUTO_LOGIN_TYPE=MSI`, `AZCOPY_MSI_CLIENT_ID` or `azcopy login --identity --identity-client-id` | Validates a non-empty client ID. |
| Managed identity, user-assigned object ID | `AZCOPY_AUTO_LOGIN_TYPE=MSI`, `AZCOPY_MSI_OBJECT_ID` or `azcopy login --identity --identity-object-id` | Validates a non-empty object ID. |
| Managed identity, user-assigned resource ID | `AZCOPY_AUTO_LOGIN_TYPE=MSI`, `AZCOPY_MSI_RESOURCE_STRING` or `azcopy login --identity --identity-resource-id` | Validates Azure resource ID shape where possible. |
| SAS token | SAS query string appended to source/destination URL | Redacts `sig` and other sensitive query values in previews/logs. |
| Account key-derived SAS helper | The app may help users produce or paste SAS URLs, but AzCopy v10 authorization is performed with SAS, not account-key auth | Account keys are not modeled as a direct AzCopy auth method; if added later, key material must be redacted and never persisted. |

References used during planning:

- Azure MCP / Microsoft Learn: `storage-use-azcopy-v10#authorize-azcopy`
- Microsoft Learn: `storage-use-azcopy-authorize-user-identity`
- Microsoft Learn: `storage-use-azcopy-authorize-service-principal`
- Microsoft Learn: `storage-use-azcopy-authorize-managed-identity`

## Security design

1. Never invoke `azcopy` through a shell. Use executable URL plus argument array only.
2. Redact secrets at the model boundary and before log persistence.
3. Store non-secret preferences in `UserDefaults`; do not store service-principal secrets, SAS tokens, account keys, or certificate passwords in this version.
4. Validate `azcopy` resolution so the default path is Homebrew on Apple Silicon (`/opt/homebrew/bin/azcopy`) and warn when the user explicitly selects another executable.
5. Require HTTPS for Azure URLs unless the user explicitly enables local/emulator scenarios in advanced settings.
6. Add a CI security review gate that runs static checks for shell invocation, secret patterns, dependency audit, and artifact signing/notarization prerequisites.
7. Include a human-readable `docs/security-review.md` checklist for release reviewers and use a protected GitHub Environment/manual approval on the release workflow for the human review gate.
8. Use hardened runtime for notarization, but do not enable App Sandbox in this version because the app must spawn Homebrew `azcopy` and access user-selected local paths.

## CI/CD and release gates

1. `ci.yml`
   - Runs on Apple Silicon macOS runners.
   - `swift test --enable-code-coverage`.
   - Fails if `AzCopyMacUICore` coverage is below 80%.
   - Builds the app target with Swift 6.
2. `security.yml`
   - Runs dependency audit and repository secret scanning.
   - Runs project-specific checks that fail on shell-based process execution, unredacted secret logging, or missing hardened runtime/notarization config.
3. `release.yml`
   - Triggered by version tags such as `v0.1.0`.
   - Requires CI and security gates.
   - Builds arm64 release artifact.
   - Codesigns with hardened runtime.
   - Submits to Apple notarization, staples the ticket, creates checksum.
   - Publishes GitHub Release assets.
4. `homebrew/azcopy-mac-ui.rb`
   - Provides Homebrew distribution metadata and `depends_on "azcopy"`.
   - Uses released, notarized artifact URL and SHA-256.
   - Is updated by the release workflow after stapling/checksum generation, either by pull request or by committing to the custom tap.

## Implementation phases

1. Repository foundation
   - Add `LICENSE`, `README.md`, `Package.swift`, Xcode app project, source/test directories, `.gitignore`, entitlements, `Info.plist`, and version metadata.
2. Core implementation
   - Implement typed command/auth models, command builder, locator, runner, redaction, and security policy.
3. GUI implementation
   - Implement SwiftUI shell and core views using HIG-aligned navigation and controls.
4. Tests
   - Add unit tests for command/auth coverage, redaction, locator, process runner, and security policy.
5. CI/CD
   - Add GitHub Actions workflows, coverage threshold script, security review script, release packaging script, and Homebrew metadata.
6. Review and validation
   - Review this plan before implementation.
   - Run local build/test/security checks where tooling is available.
   - Leave real Azure transfer and notarization validation for the requested physical-machine test pass because they require credentials and Apple Developer secrets.

## Definition of done for the initial implementation

- The repository builds as a Swift 6 macOS project in Xcode/SwiftPM.
- Core logic has unit tests and an 80% coverage gate script.
- Security review automation and checklist are present.
- CI/CD workflows define coverage and security as release gates.
- Homebrew metadata declares `depends_on "azcopy"`.
- App version is `0.1.0`.
- MIT license is present.
- Azure authentication modes are represented in typed code and visible in the UI.
- Runtime MCP integration is not required; Azure MCP was used during planning to ground AzCopy authentication choices in official Microsoft Learn documentation.
- Version `0.1.0` has a single source of truth in `VERSION` and is mirrored into bundle metadata, tags, and Homebrew cask metadata by release scripts.
