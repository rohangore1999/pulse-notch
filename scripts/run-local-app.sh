#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

"${SCRIPT_DIR}/build-local-app.sh" debug
/usr/bin/open "${PROJECT_DIR}/dist/Pulse Notch.app"
