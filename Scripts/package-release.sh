#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

if [[ $# -ne 0 ]]; then
  echo "Usage: Scripts/package-release.sh" >&2
  exit 1
fi

# No credential access, signing, artifact replacement, or notarization before all gates pass.
"${SCRIPT_DIR}/release-preflight.sh"

VERSION="$(tr -d '[:space:]' < VERSION)"
APP_NAME="AzCopy Mac UI"
STAGE_PATH="release/${VERSION}"
ARCHIVE_PATH="${STAGE_PATH}/AzCopyMacUI.xcarchive"
EXPORT_PATH="${STAGE_PATH}/export"
EXPORT_OPTIONS_PLIST="${STAGE_PATH}/ExportOptions.plist"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
ZIP_PATH="${STAGE_PATH}/azcopy-mac-ui-${VERSION}-macos-arm64.zip"
SHA256_PATH="${ZIP_PATH}.sha256"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

if [ -z "${APPLE_TEAM_ID:-}" ]; then
  APPLE_TEAM_ID="$(printf '%s\n' "${DEVELOPER_ID_APPLICATION}" | sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\)).*/\1/p')"
fi

: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or include the team ID in DEVELOPER_ID_APPLICATION}"

if [[ ! "${APPLE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "APPLE_TEAM_ID must contain exactly 10 uppercase letters or digits" >&2
  exit 1
fi
if [[ -L release || -e "${STAGE_PATH}" || -L "${STAGE_PATH}" ]]; then
  echo "Refusing an existing release stage or symlink: ${STAGE_PATH}. Move it aside deliberately before retrying." >&2
  exit 1
fi
mkdir -p release
mkdir "${STAGE_PATH}"

python3 - "${EXPORT_OPTIONS_PLIST}" "${APPLE_TEAM_ID}" "${DEVELOPER_ID_APPLICATION}" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "xb") as stream:
    plistlib.dump({
        "method": "developer-id",
        "destination": "export",
        "signingStyle": "manual",
        "teamID": sys.argv[2],
        "signingCertificate": sys.argv[3],
        "stripSwiftSymbols": True,
        "manageAppVersionAndBuildNumber": False,
    }, stream)
PY

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

python3 -B "${SCRIPT_DIR}/check-release-app.py" \
  "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" --archive "${ARCHIVE_PATH}"

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

python3 -B "${SCRIPT_DIR}/check-release-app.py" "${APP_PATH}"
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

rm -f -- "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" > "${SHA256_PATH}"

echo "Release artifact: ${ZIP_PATH}"
echo "Homebrew cask sha256: $(awk '{print $1}' "${SHA256_PATH}")"
