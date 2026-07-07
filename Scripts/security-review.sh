#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "security-review: $1" >&2
  exit 1
}

if grep -R --line-number --include='*.swift' -F '/bin/sh' Sources ||
   grep -R --line-number --include='*.swift' -F '/bin/bash' Sources ||
   grep -R --line-number --include='*.swift' -F '/bin/zsh' Sources ||
   grep -R --line-number --include='*.swift' -F '/usr/bin/env' Sources ||
   grep -R --line-number --include='*.swift' -F 'popen(' Sources; then
  fail "shell execution pattern found"
fi

if grep -R --line-number --include='*.swift' -F 'system(' Sources | grep -v -F '.system('; then
  fail "shell execution pattern found"
fi

if {
  grep -R --line-number --include='*.swift' -F 'print(' Sources
  grep -R --line-number --include='*.swift' -F 'NSLog(' Sources
} | grep -E '(SECRET|PASSWORD|TOKEN|SAS|sig|AZCOPY_SPA)' ; then
  fail "possible secret logging found"
fi

if grep -R --line-number -E 'AZCOPY_ACCOUNT_KEY' Sources Tests | grep -Ev 'CredentialRedactor.swift|SecurityPolicy.swift|SecurityPolicyTests.swift'; then
  fail "direct account key authentication found"
fi

if ! grep -q 'ENABLE_HARDENED_RUNTIME = YES' AzCopyMacUI.xcodeproj/project.pbxproj; then
  fail "hardened runtime is not enabled in the Xcode project"
fi

if grep -q 'com.apple.security.app-sandbox.*true' AzCopyMacUI/AzCopyMacUI.entitlements; then
  fail "App Sandbox should not be enabled for this version"
fi

echo "security-review: passed"
