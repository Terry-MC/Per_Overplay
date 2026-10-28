#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

XCODE_DEVELOPER="/Applications/Xcode.app/Contents/Developer"
if [[ -d "${XCODE_DEVELOPER}" ]]; then
  export DEVELOPER_DIR="${XCODE_DEVELOPER}"
fi

swift test "$@"
