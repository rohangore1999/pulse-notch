#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEST_BUILD_DIR="${PROJECT_DIR}/.build/local-tests"
MODULE_CACHE_DIR="${PROJECT_DIR}/.build/clang-module-cache"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
SDK_INTERFACE="${SDK_PATH}/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
SDK_SWIFT_VERSION="$(/usr/bin/sed -n 's@// swift-compiler-version: Apple Swift version \([^ ]*\).*@\1@p' "${SDK_INTERFACE}" | /usr/bin/head -1)"

DOMAIN_FILES=("${PROJECT_DIR}"/Sources/PulseNotch/Domain/*.swift(N))
TEST_FILES=("${PROJECT_DIR}"/Tests/LocalTestRunner/*.swift(N))

/bin/mkdir -p "${TEST_BUILD_DIR}" "${MODULE_CACHE_DIR}"

/usr/bin/swiftc \
  -swift-version 5 \
  -interface-compiler-version "${SDK_SWIFT_VERSION}" \
  -sdk "${SDK_PATH}" \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "${MODULE_CACHE_DIR}" \
  "${DOMAIN_FILES[@]}" \
  "${TEST_FILES[@]}" \
  -o "${TEST_BUILD_DIR}/PulseNotchLocalTests"

"${TEST_BUILD_DIR}/PulseNotchLocalTests"
