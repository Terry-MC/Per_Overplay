#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DSOverplay"
APP_BUNDLE="${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"

swift build -c release --product OverplayApp
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
cp "${BIN_DIR}/OverplayApp" "${MACOS_DIR}/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
for resource_bundle in "${BIN_DIR}"/Overplay_*.bundle; do
  [ -d "$resource_bundle" ] || continue
  bundle_name="$(basename "$resource_bundle")"
  rm -rf "${APP_BUNDLE}/Contents/Resources/${bundle_name}"
  cp -R "$resource_bundle" "${APP_BUNDLE}/Contents/Resources/"
done

plutil -lint "${APP_BUNDLE}/Contents/Info.plist"
codesign --force --sign - --timestamp=none "${APP_BUNDLE}"
codesign --verify --strict "${APP_BUNDLE}"

echo "built: $(pwd)/${APP_BUNDLE}"
