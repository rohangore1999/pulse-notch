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
DMG_CONFIG_DIR="${PROJECT_DIR}/Configuration/dmg"
DMG_SETTINGS="${DMG_CONFIG_DIR}/dmgbuild_settings.py"
DMG_REQUIREMENTS="${DMG_CONFIG_DIR}/requirements.txt"
DMG_VENV_DIR="${PROJECT_DIR}/.build/dmgbuild-venv"
DMG_PYTHON="${DMG_VENV_DIR}/bin/python3"
DMGBUILD="${DMG_VENV_DIR}/bin/dmgbuild"
VOLUME_ICON="${PROJECT_DIR}/Support/PulseNotch.icns"
PYTHON_BOOTSTRAP="${PULSE_NOTCH_DMGBUILD_PYTHON:-$(command -v python3)}"

if [[ ! -d "${APP_DIR}" ]]; then
  print -u2 "Missing release app: ${APP_DIR}"
  print -u2 "Run ./scripts/build-local-app.sh release first."
  exit 1
fi

[[ -f "${DMG_SETTINGS}" ]] || {
  print -u2 "Missing dmgbuild settings: ${DMG_SETTINGS}"
  exit 1
}
[[ -f "${DMG_REQUIREMENTS}" ]] || {
  print -u2 "Missing dmgbuild requirements: ${DMG_REQUIREMENTS}"
  exit 1
}
[[ -s "${VOLUME_ICON}" ]] || {
  print -u2 "Missing volume icon: ${VOLUME_ICON}"
  exit 1
}

if [[ -z "${PYTHON_BOOTSTRAP}" ]] || ! "${PYTHON_BOOTSTRAP}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
  print -u2 "DMG packaging requires Python 3.10 or newer."
  exit 1
fi

if [[ -x "${DMG_PYTHON}" ]] && ! "${DMG_PYTHON}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
  if [[ "${DMG_VENV_DIR}" != "${PROJECT_DIR}/.build/dmgbuild-venv" ]]; then
    print -u2 "Refusing to replace an unexpected DMG virtual environment path."
    exit 1
  fi
  /bin/rm -rf "${DMG_VENV_DIR}"
fi

if [[ ! -x "${DMG_PYTHON}" ]]; then
  "${PYTHON_BOOTSTRAP}" -m venv "${DMG_VENV_DIR}"
fi

if ! "${DMG_PYTHON}" -c 'import importlib.metadata as m; raise SystemExit(0 if m.version("dmgbuild") == "1.6.7" and m.version("ds-store") == "1.3.3" and m.version("mac-alias") == "2.2.3" else 1)' 2>/dev/null; then
  "${DMG_PYTHON}" -m pip install \
    --disable-pip-version-check \
    --require-hashes \
    --requirement "${DMG_REQUIREMENTS}"
fi

/bin/mkdir -p "${DIST_DIR}"
/bin/rm -f "${DMG_PATH}" "${CHECKSUM_PATH}"

export PULSE_NOTCH_DMG_APP_PATH="${APP_DIR}"
export PULSE_NOTCH_DMG_VOLUME_ICON_PATH="${VOLUME_ICON}"
"${DMGBUILD}" \
  --settings "${DMG_SETTINGS}" \
  "Pulse Notch" \
  "${DMG_PATH}"

/usr/bin/hdiutil verify "${DMG_PATH}"
(
  cd "${DIST_DIR}"
  /usr/bin/shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)

print "Packaged ${DMG_PATH}"
print "Checksum ${CHECKSUM_PATH}"
