# AzCopy compatibility and macOS GUI verification

Date: 2026-09-21. Baseline: `d8faec0`. Scope: development version 0.2.1;
compatibility qualification and GUI improvements, without changing deployment targets,
authentication boundaries, distribution, or release version.

## Design contract

A native macOS utility for selecting an AzCopy operation, entering its inputs,
reviewing the redacted command, and observing/cancelling execution. Preserve the
Operations / Settings / Logs navigation and existing command model. Use native
SwiftUI forms and sections, semantic colors and symbols, explicit control names,
and persistent execution feedback. Keep the primary action and command preview
reachable while long forms scroll. Support pointer and keyboard input, a standard
Settings window, and a discoverable Operation menu. Keep secret fields secure and
existing immutable destructive-command confirmation intact. No custom animation,
new data collection, localization expansion, or OS target change.

## Environment and sources

Minimum deployment: macOS 14.0. Build and tested runtime: Xcode 27.0 (27A266a),
macOS SDK 27.0, macOS 27.0 (26A428), arm64. Apple's release feed identifies macOS
27.0 and Xcode 27 as public releases dated September 14, 2026; it separately lists
macOS 27.2 beta dated September 16. The beta was not tested.

Sources retrieved 2026-09-21; HIG wording is guidance, not an App Review rule:

| Label | Source | Applied scope |
| --- | --- | --- |
| APPLE-HIG | [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | Resizable windows, familiar controls, menus and keyboard access |
| APPLE-HIG | [Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields) | Persistent labels, secure entry, consistent spacing, logical Tab order |
| APPLE-HIG | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | Clear action titles, restrained prominence, system button behavior |
| APPLE-HIG | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | System colors, non-color state cues, accessible names, keyboard operation |
| APPLE-SDK | [Form](https://developer.apple.com/documentation/swiftui/form) | Platform-specific native form layout and grouping |
| APPLE-RESOURCE | [Apple releases](https://developer.apple.com/news/releases/) | Public-release versus beta context |
| Upstream | [AzCopy v10.32.8](https://github.com/Azure/azure-storage-azcopy/releases/tag/v10.32.8) | Latest stable version checked on the verification date |

HIG text was retrieved from Apple's DocC data using the HIG skill's reader. No
copied HIG corpus is included here. The 170-point label column, 860 × 640 minimum
content size and 1060 × 820 default size are implementation choices (HEURISTIC),
not Apple-mandated dimensions. The Buttons page's broad hit-region recommendation
and Accessibility page's macOS-specific dimensions have different scopes; this work
uses native macOS controls and makes no blanket touch-target compliance claim.

## Findings and fixes

| ID | Severity / evidence | Change | Verification |
| --- | --- | --- | --- |
| GUI-1 | Major / OBSERVATION: form and rows forced to 760 points, independent of available detail width | Native grouped forms, flexible content column, wrapping labels and resizable sidebar | Build and runtime visual inspection |
| GUI-2 | Major / OBSERVATION: fields and pickers used empty labels; folder buttons exposed generic “Move” names | Meaningful field/picker names and explicit browse/tenant button accessibility labels | Runtime accessibility tree shows name, role, value and state |
| GUI-3 | Moderate / OBSERVATION: Run was at the end of a scrollable form | Persistent command/action area; action-specific titles and explicit dry-run message | Runtime preview, disabled and destructive-confirmation states |
| GUI-4 | Moderate / HEURISTIC: Settings available only through navigation | Standard Settings scene and ⌘,; Operation menu with ⌘Return scoped to Operations | Runtime menu/keyboard checks |
| GUI-5 | Moderate / OBSERVATION: status and empty logs were plain text without a distinct state cue | Status symbols and native empty-output view | Runtime empty/result views |
| GUI-6 | Moderate / HEURISTIC: merely opening Settings started Azure CLI tenant lookup | Explicit “Load tenants” action | Settings opens without lookup; lookup cancellation remains available |

## Compatibility evidence

`node Scripts/test-azcopy-compatibility.mjs /opt/homebrew/bin/azcopy` uses the actual
`AzCopyCommandBuilder` and `AzCopyProcessRunner`; no mock AzCopy executable is used.
Azurite 3.37.0 and Azure Storage Blob JS SDK 12.33.0 are optional, isolated test tools.
The checked binary reports `azcopy version 10.32.8`.

| Check | Result |
| --- | --- |
| All 15 operation commands with form-managed options plus `--help` | PASS |
| Eight supported sign-in argument variants plus `--help` | PASS; no authentication attempted |
| Unknown option negative control with `--help` | PASS; CLI rejects it |
| Version, environment, empty job listing/cleanup in isolated directories | PASS |
| Recursive SAS Blob upload including spaces and Japanese content, include/exclude filters | PASS |
| Blob download compared byte-for-byte with source | PASS |
| Metadata set and verified through HTTP response metadata | PASS |
| Sync dry run leaves original bytes; actual sync updates downloaded bytes | PASS |
| Copy dry run leaves storage empty; remove dry run retains target | PASS |
| Actual remove deletes only target and retains the other nested blob | PASS |
| Actual job listing/show/removal against test-only plan files | PASS |
| `make` against Azurite account-prefixed URL | Not qualified: CLI rejects this emulator URL as non-top-level; covered only by help parsing |
| Entra/service principal/managed identity/Azure CLI/PowerShell authentication | NOT RUN |
| Real Azure Blob, Azure Files, ADLS, benchmark, interrupted-job resume | NOT RUN |

Temporary loopback HTTP is enabled only in the test runner. Explicit emulator
service flags are added through the same additional-flags path available to the
builder. The app's HTTPS policy and user's credentials/job history are unchanged.
The script tears down only its own emulator and generated data. CLI argument
recognition is deliberately distinguished from successful cloud authorization.

## GUI and regression verification

Screenshots and the native accessibility tree were inspected in the task. GUI test
values are synthetic and subsequent interaction uses a separately identified review
app with its own preferences. Standard macOS keyboard navigation traversed browse
buttons as well as fields; VoiceOver was not enabled.

| Check | Result / evidence |
| --- | --- |
| `Scripts/release-preflight.sh` | PASS: 101 offline Swift tests (85 Core + 16 AppModel), 66 script tests, security patterns, version consistency; 3 opt-in integration tests skipped in this offline run |
| Core line coverage | PASS: 96.06% (1389/1446), threshold 80% |
| Dedicated installed-AzCopy integration suite | PASS: 3 tests, including the actual Blob workflow above |
| Final Xcode Debug app build | PASS: arm64, code signing disabled for development validation |
| Standard Operations view | PASS: final 1060 × 820 window (capture scaled by the tool to 993 × 768) screenshot in [`images/screenshot.jpg`](../images/screenshot.jpg) |
| Minimum content size | PASS: 860 × 640 content (860 × 692 captured outer window), using a review build with only default window size overridden; fields remain reachable, footer stays visible while scrolling |
| Light / Dark appearance | PASS: visual inspection in both; Light forced only in a disposable review bundle, no global appearance setting changed |
| Settings | PASS: sidebar and ⌘, open correctly; certificate password exposes a secure text-field role and name; no automatic tenant lookup |
| Accessibility tree | PASS for sampled fields/pickers, browse buttons, secure entry, progress, disabled Run, updated status and primary-action names |
| Keyboard | PASS: source → browse → destination Tab order, file-dialog Escape dismissal, ⌘Return execution, Escape cancellation |
| Destructive confirmation | PASS: exact snapshot shown, Cancel initially focused, Escape dismisses without running |
| Operation menu | PASS: runs real `azcopy env`; disabled after navigating away from Operations |
| Running and cancelled UI | PASS using a local delayed-output fixture (no network): output streams, progress/Cancel appear, primary action disables, Escape yields “Command cancelled.”; this is UI-state coverage, not cloud-transfer evidence |
| Empty Logs | PASS: native empty-state explanation inspected |
| VoiceOver spoken order and announcements | NOT RUN; runtime tree inspection is not a VoiceOver test |
| Full Keyboard Access mode, large accessibility text, Increase Contrast, Reduce Transparency, Reduce Motion, long localization/RTL | NOT RUN; no custom animation was introduced |
| macOS 14 / 15 / 26 runtimes and macOS 27.2 beta | NOT RUN; deployment target remains macOS 14 |
| Developer ID signing, notarization, distribution | NOT RUN; no release or publication requested |

Build log: `/tmp/azcopy-ui-final-build.log`; preflight log:
`/tmp/azcopy-ui-final-preflight.log`; integration log:
`/tmp/azcopy-compatibility.log`. Logs are local, transient evidence, not release
artifacts. The only Xcode warning was skipped App Intents metadata extraction
because this app has no AppIntents framework dependency.

This is a bounded HIG-aligned implementation review, not a claim of complete HIG
or accessibility compliance. The verified runtime and emulator coverage must not
be generalized to older macOS versions, actual cloud credentials, or services that
were not exercised.
