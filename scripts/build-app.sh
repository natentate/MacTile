#!/usr/bin/env bash
# Builds MacTile.app into ./build.
#
#   scripts/build-app.sh               # universal (arm64 + x86_64) release build
#   ARCHS="arm64" scripts/build-app.sh # single architecture, faster
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# Without SIGN_IDENTITY the app is ad-hoc signed, which is fine for local use.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/MacTile.app"

arch_flags=()
for arch in $ARCHS; do
  arch_flags+=(--arch "$arch")
done

swift build -c "$CONFIGURATION" "${arch_flags[@]}"
BIN_DIR="$(swift build -c "$CONFIGURATION" "${arch_flags[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacTile" "$APP/Contents/MacOS/MacTile"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"

echo "Built $APP"
