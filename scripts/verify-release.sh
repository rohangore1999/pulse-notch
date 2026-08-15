#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_DIR}/dist"
APP_NAME="Pulse Notch.app"
APP_DIR="${DIST_DIR}/${APP_NAME}"
INFO_PLIST="${APP_DIR}/Contents/Info.plist"
EXECUTABLE="${APP_DIR}/Contents/MacOS/PulseNotch"
DMG_NAME="PulseNotch.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
CHECKSUM_PATH="${DMG_PATH}.sha256"
EXPECTED_BUNDLE_ID="com.rohangore.pulsenotch"
EXPECTED_VERSION="0.1.0"
EXPECTED_MINIMUM_MACOS="13.0"
TEMP_ROOT="${TMPDIR:-/tmp}"
MOUNT_DIR="$(/usr/bin/mktemp -d "${TEMP_ROOT%/}/pulse-notch-verify.XXXXXX")"
MOUNT_DIR_REAL="$(cd "${MOUNT_DIR}" && /bin/pwd -P)"
IS_MOUNTED=false

fail() {
  print -u2 "Release verification failed: $1"
  exit 1
}

cleanup() {
  if [[ "${IS_MOUNTED}" == true ]]; then
    /usr/bin/hdiutil detach "${MOUNT_DIR}" -quiet || true
  fi
  /bin/rmdir "${MOUNT_DIR}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

[[ -d "${APP_DIR}" ]] || fail "missing app at ${APP_DIR}"
[[ -f "${INFO_PLIST}" ]] || fail "missing Info.plist"
[[ -x "${EXECUTABLE}" ]] || fail "missing executable"
[[ -f "${DMG_PATH}" ]] || fail "missing DMG at ${DMG_PATH}"
[[ -f "${CHECKSUM_PATH}" ]] || fail "missing checksum at ${CHECKSUM_PATH}"

ARCHITECTURES="$(/usr/bin/lipo -archs "${EXECUTABLE}")"
[[ "${ARCHITECTURES}" == "arm64" ]] || fail "expected arm64-only executable, found: ${ARCHITECTURES}"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${INFO_PLIST}")"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}")"
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "${INFO_PLIST}")"
ICON_FILE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "${INFO_PLIST}")"

[[ "${BUNDLE_ID}" == "${EXPECTED_BUNDLE_ID}" ]] || fail "expected bundle ID ${EXPECTED_BUNDLE_ID}, found ${BUNDLE_ID}"
[[ "${VERSION}" == "${EXPECTED_VERSION}" ]] || fail "expected version ${EXPECTED_VERSION}, found ${VERSION}"
[[ "${MINIMUM_MACOS}" == "${EXPECTED_MINIMUM_MACOS}" ]] || fail "expected minimum macOS ${EXPECTED_MINIMUM_MACOS}, found ${MINIMUM_MACOS}"
[[ -n "${ICON_FILE}" ]] || fail "CFBundleIconFile is empty"
[[ -s "${APP_DIR}/Contents/Resources/${ICON_FILE}" ]] || fail "bundled icon ${ICON_FILE} is missing or empty"

/usr/bin/codesign --verify --strict --verbose=2 "${APP_DIR}"
SIGNATURE_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "${APP_DIR}" 2>&1)"
print -r -- "${SIGNATURE_DETAILS}" | /usr/bin/grep -q '^Signature=adhoc$' || fail "app is not ad-hoc signed"

(
  cd "${DIST_DIR}"
  /usr/bin/shasum -a 256 -c "${DMG_NAME}.sha256"
)
/usr/bin/hdiutil verify "${DMG_PATH}"
/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "${MOUNT_DIR}" \
  "${DMG_PATH}" >/dev/null
IS_MOUNTED=true

[[ -d "${MOUNT_DIR}/${APP_NAME}" ]] || fail "mounted DMG does not contain ${APP_NAME}"
[[ -L "${MOUNT_DIR}/Applications" ]] || fail "mounted DMG does not contain an Applications symlink"
[[ -s "${MOUNT_DIR}/.DS_Store" ]] || fail "mounted DMG does not contain Finder layout metadata"
[[ -s "${MOUNT_DIR}/.VolumeIcon.icns" ]] || fail "mounted DMG does not contain its volume icon"
APPLICATIONS_TARGET="$(/usr/bin/readlink "${MOUNT_DIR}/Applications")"
[[ "${APPLICATIONS_TARGET}" == "/Applications" ]] || fail "Applications symlink points to ${APPLICATIONS_TARGET}"

MOUNT_DETAILS="$(/sbin/mount | /usr/bin/grep -F " on ${MOUNT_DIR_REAL} " || true)"
print -r -- "${MOUNT_DETAILS}" | /usr/bin/grep -q 'read-only' || fail "DMG was not mounted read-only"

if /usr/sbin/spctl --assess --type execute --verbose=4 "${APP_DIR}"; then
  print "Gatekeeper assessment accepted the app."
else
  print "Gatekeeper rejected the ad-hoc signed app as expected; this is not a verification failure."
fi

print "Verified ${APP_DIR}"
print "Verified ${DMG_PATH}"
