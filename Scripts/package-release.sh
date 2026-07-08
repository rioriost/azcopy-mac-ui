#!/usr/bin/env bash
set -euo pipefail

VERSION="$(tr -d '[:space:]' < VERSION)"
APP_NAME="AzCopy Mac UI"
ARCHIVE_PATH="release/AzCopyMacUI.xcarchive"
EXPORT_PATH="release/export"
EXPORT_OPTIONS_PLIST="release/ExportOptions.plist"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
ZIP_PATH="release/azcopy-mac-ui-${VERSION}-macos-arm64.zip"
SHA256_PATH="${ZIP_PATH}.sha256"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

if [ -z "${APPLE_TEAM_ID:-}" ]; then
  APPLE_TEAM_ID="$(printf '%s\n' "${DEVELOPER_ID_APPLICATION}" | sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\)).*/\1/p')"
fi

: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or include the team ID in DEVELOPER_ID_APPLICATION}"

rm -rf release
mkdir -p release

/usr/libexec/PlistBuddy -c 'Clear dict' "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :method string developer-id' "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :destination string export' "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c "Add :teamID string ${APPLE_TEAM_ID}" "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c "Add :signingCertificate string ${DEVELOPER_ID_APPLICATION}" "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :manageAppVersionAndBuildNumber bool false' "${EXPORT_OPTIONS_PLIST}"

xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null

xcodebuild archive \
  -project AzCopyMacUI.xcodeproj \
  -scheme AzCopyMacUI \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign_details="$(codesign --display --verbose=4 "${APP_PATH}" 2>&1)"
grep -q 'Runtime Version' <<<"${codesign_details}"

ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

xcrun notarytool submit "${ZIP_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
spctl --assess --type execute --verbose=4 "${APP_PATH}"

rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" > "${SHA256_PATH}"

echo "Release artifact: ${ZIP_PATH}"
echo "Homebrew cask sha256: $(awk '{print $1}' "${SHA256_PATH}")"
