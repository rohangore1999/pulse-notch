#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_CONFIGURATION="${1:-debug}"
APP_DIR="${PROJECT_DIR}/dist/Pulse Notch.app"
LOCAL_BUILD_DIR="${PROJECT_DIR}/.build/local/${BUILD_CONFIGURATION}"
MODULE_CACHE_DIR="${PROJECT_DIR}/.build/clang-module-cache"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
SDK_INTERFACE="${SDK_PATH}/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"

if [[ ! -f "${SDK_INTERFACE}" ]]; then
  print -u2 "Could not determine the Swift SDK interface version"
  exit 1
fi

SDK_SWIFT_VERSION="$(/usr/bin/sed -n 's@// swift-compiler-version: Apple Swift version \([^ ]*\).*@\1@p' "${SDK_INTERFACE}" | /usr/bin/head -1)"
SOURCE_FILES=("${PROJECT_DIR}"/Sources/PulseNotch/**/*.swift(N))

if (( ${#SOURCE_FILES[@]} == 0 )); then
  print -u2 "No Swift source files found"
  exit 1
fi

/bin/mkdir -p "${LOCAL_BUILD_DIR}" "${MODULE_CACHE_DIR}"

OPTIMIZATION_FLAGS=(-Onone -g)
if [[ "${BUILD_CONFIGURATION}" == "release" ]]; then
  OPTIMIZATION_FLAGS=(-O)
fi

/usr/bin/swiftc \
  -swift-version 5 \
  -interface-compiler-version "${SDK_SWIFT_VERSION}" \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "${MODULE_CACHE_DIR}" \
  "${OPTIMIZATION_FLAGS[@]}" \
  "${SOURCE_FILES[@]}" \
  -framework AppKit \
  -framework Combine \
  -framework CoreBluetooth \
  -framework SwiftUI \
  -framework UserNotifications \
  -o "${LOCAL_BUILD_DIR}/PulseNotch"

if [[ "${APP_DIR}" != "${PROJECT_DIR}/dist/Pulse Notch.app" ]]; then
  print -u2 "Unexpected app output path"
  exit 1
fi

/bin/rm -rf "${APP_DIR}"
/bin/mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
/usr/bin/install -m 755 "${LOCAL_BUILD_DIR}/PulseNotch" "${APP_DIR}/Contents/MacOS/PulseNotch"
/usr/bin/install -m 644 "${PROJECT_DIR}/Support/Info.plist" "${APP_DIR}/Contents/Info.plist"
/usr/bin/install -m 644 "${PROJECT_DIR}/Support/PulseNotch.icns" "${APP_DIR}/Contents/Resources/PulseNotch.icns"

/usr/bin/plutil -lint "${APP_DIR}/Contents/Info.plist"
/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --entitlements "${PROJECT_DIR}/Support/PulseNotch.entitlements" \
  "${APP_DIR}"
/usr/bin/codesign --verify --strict --verbose=2 "${APP_DIR}"

print "Built ${APP_DIR}"
