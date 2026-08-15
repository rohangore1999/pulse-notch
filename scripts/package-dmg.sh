#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_DIR}/dist"
APP_NAME="Pulse Notch.app"
APP_DIR="${DIST_DIR}/${APP_NAME}"
DMG_NAME="PulseNotch.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
CHECKSUM_PATH="${DMG_PATH}.sha256"
TEMP_ROOT="${TMPDIR:-/tmp}"
STAGING_DIR="$(/usr/bin/mktemp -d "${TEMP_ROOT%/}/pulse-notch-dmg.XXXXXX")"

cleanup() {
  /bin/rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT INT TERM

if [[ ! -d "${APP_DIR}" ]]; then
  print -u2 "Missing release app: ${APP_DIR}"
  print -u2 "Run ./scripts/build-local-app.sh release first."
  exit 1
fi

/bin/mkdir -p "${DIST_DIR}"
/usr/bin/ditto "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}"
/bin/ln -s /Applications "${STAGING_DIR}/Applications"

/bin/rm -f "${DMG_PATH}" "${CHECKSUM_PATH}"
/usr/bin/hdiutil create \
  -volname "Pulse Notch" \
  -srcfolder "${STAGING_DIR}" \
  -format UDZO \
  -ov \
  "${DMG_PATH}"

/usr/bin/hdiutil verify "${DMG_PATH}"
(
  cd "${DIST_DIR}"
  /usr/bin/shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)

print "Packaged ${DMG_PATH}"
print "Checksum ${CHECKSUM_PATH}"
