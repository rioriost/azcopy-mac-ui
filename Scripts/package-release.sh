#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

RETRY=false
if [[ $# -eq 1 && "$1" == "--retry" ]]; then
  RETRY=true
elif [[ $# -ne 0 ]]; then
  echo "Usage: Scripts/package-release.sh [--retry]" >&2
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
if [[ -L release || -L "${STAGE_PATH}" || ( -e "${STAGE_PATH}" && "${RETRY}" != true ) ]]; then
  echo "Refusing an existing release stage or symlink: ${STAGE_PATH}. Use --retry to preserve and replace a real stage." >&2
  exit 1
fi

SETTINGS_TEXT="$(python3 -B "${SCRIPT_DIR}/release-config.py" export --validate)"
SETTINGS=()
while IFS= read -r value; do SETTINGS+=("${value}"); done <<<"${SETTINGS_TEXT}"
DEVELOPER_ID_APPLICATION="${SETTINGS[0]}"
APPLE_TEAM_ID="${SETTINGS[1]}"
NOTARY_PROFILE="${SETTINGS[2]}"
NOTARY_KEYCHAIN="${SETTINGS[3]:-}"
NOTARY_OPTIONS=(--keychain-profile "${NOTARY_PROFILE}")
if [[ -n "${NOTARY_KEYCHAIN}" ]]; then
  NOTARY_OPTIONS+=(--keychain "${NOTARY_KEYCHAIN}")
fi

mkdir -p release
LOCK_PATH="release/.${VERSION}.lock"
if ! mkdir "${LOCK_PATH}"; then
  echo "Another release may be running. Inspect ${LOCK_PATH} before retrying; no artifacts were changed." >&2
  exit 1
fi
trap 'rm -f "${LOCK_PATH}/pid"; rmdir "${LOCK_PATH}" || echo "Release lock requires manual inspection: ${LOCK_PATH}" >&2' EXIT
printf '%s\n' "$$" > "${LOCK_PATH}/pid"
if [[ -L "${STAGE_PATH}" || ( -e "${STAGE_PATH}" && "${RETRY}" != true ) ]]; then
  echo "Release stage changed during credential validation; refusing to overwrite ${STAGE_PATH}." >&2
  exit 1
fi
if [[ -e "${STAGE_PATH}" ]]; then
  BACKUP_PATH="$(mktemp -d "release/.retry-${VERSION}.XXXXXX")"
  mv -- "${STAGE_PATH}" "${BACKUP_PATH}/artifacts"
  echo "Previous release stage preserved at: ${BACKUP_PATH}/artifacts"
fi
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
  "${NOTARY_OPTIONS[@]}" \
  --wait

xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
spctl --assess --type execute --verbose=4 "${APP_PATH}"

rm -f -- "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
(cd "${STAGE_PATH}" && shasum -a 256 "${ZIP_PATH##*/}" > "${SHA256_PATH##*/}")

echo "Release artifact: ${ZIP_PATH}"
echo "Homebrew cask sha256: $(awk '{print $1}' "${SHA256_PATH}")"
