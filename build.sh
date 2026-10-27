#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DSOverlay"
APP_BUNDLE="${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

swiftc \
  -O \
  -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -framework AppKit \
  Sources/*.swift \
  -o "${MACOS_DIR}/${APP_NAME}"

cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
cp sample-config.json "${RESOURCES_DIR}/sample-config.json"

plutil -lint "${APP_BUNDLE}/Contents/Info.plist"
codesign --force --sign - "${APP_BUNDLE}"
codesign --verify --strict "${APP_BUNDLE}"

echo "built: $(pwd)/${APP_BUNDLE}"
