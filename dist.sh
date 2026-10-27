#!/bin/bash

# Squeeze - Distribution script
# Builds a versioned DMG + ZIP in dist/ (override version with VERSION=x.y ./dist.sh)
# Requires: build.sh, hdiutil, ditto (all stock macOS)

set -e

APP_NAME="Squeeze"
VERSION="${VERSION:-1.0}"
ARCH="arm64"
DIST_DIR="dist"
DMG_NAME="$APP_NAME-$VERSION-macOS-$ARCH.dmg"
ZIP_NAME="$APP_NAME-$VERSION-macOS-$ARCH.zip"

echo "🔨 Building $APP_NAME v$VERSION..."
./build.sh >/dev/null

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/staging"
cp -R "build/$APP_NAME.app" "$DIST_DIR/staging/"
ln -s /Applications "$DIST_DIR/staging/Applications"

echo "💿 Creating DMG..."
hdiutil create -volname "$APP_NAME" -srcfolder "$DIST_DIR/staging" -ov -format UDZO "$DIST_DIR/$DMG_NAME" >/dev/null

echo "🤐 Creating ZIP..."
ditto -c -k --sequesterRsrc --keepParent "build/$APP_NAME.app" "$DIST_DIR/$ZIP_NAME"

echo "🔏 Checksums..."
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > SHA256SUMS.txt)

rm -rf "$DIST_DIR/staging"

echo "✅ Distribution complete:"
ls -lh "$DIST_DIR"
