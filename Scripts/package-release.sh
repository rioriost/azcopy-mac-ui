#!/usr/bin/env bash
set -euo pipefail

VERSION="$(tr -d '[:space:]' < VERSION)"
ARCHIVE_PATH="release/AzCopyMacUI.xcarchive"
EXPORT_PATH="release/export"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION}"
: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD}"

rm -rf release
mkdir -p release

xcodebuild archive \
  -project AzCopyMacUI.xcodeproj \
  -scheme AzCopyMacUI \
  -destination 'generic/platform=macOS,arch=arm64' \
  -archivePath "${ARCHIVE_PATH}" \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64

ditto -c -k --keepParent "${ARCHIVE_PATH}/Products/Applications/AzCopy Mac UI.app" "release/azcopy-mac-ui-${VERSION}-macos-arm64.zip"

xcrun notarytool submit "release/azcopy-mac-ui-${VERSION}-macos-arm64.zip" \
  --apple-id "${APPLE_ID}" \
  --team-id "${APPLE_TEAM_ID}" \
  --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
  --wait

xcrun stapler staple "${ARCHIVE_PATH}/Products/Applications/AzCopy Mac UI.app"
ditto -c -k --keepParent "${ARCHIVE_PATH}/Products/Applications/AzCopy Mac UI.app" "release/azcopy-mac-ui-${VERSION}-macos-arm64.notarized.zip"
shasum -a 256 "release/azcopy-mac-ui-${VERSION}-macos-arm64.notarized.zip" > "release/azcopy-mac-ui-${VERSION}-macos-arm64.notarized.zip.sha256"

