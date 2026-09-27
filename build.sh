#!/bin/bash

# Video Compressor - Build Script
# This script builds the Video Compressor app for macOS

set -e

APP_NAME="Squeeze"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🎬 Building Video Compressor..."

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy Info.plist (values are literal — no Xcode variables to expand)
cp Info.plist "$CONTENTS_DIR/"

# Compile Swift files
echo "📦 Compiling Swift files..."
swiftc -o "$MACOS_DIR/$APP_NAME" \
    -parse-as-library \
    -target arm64-apple-macos13.0 \
    -framework SwiftUI \
    -framework AppKit \
    VideoCompressorApp.swift ContentView.swift

# Make executable
chmod +x "$MACOS_DIR/$APP_NAME"

# Ad-hoc sign so the bundle has a consistent identity
# (still unsigned for Gatekeeper — recipients use right-click > Open)
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || echo "⚠️  codesign skipped"

echo "✅ Build complete!"
echo "📱 App bundle created at: $APP_BUNDLE"
echo ""
echo "To run the app:"
echo "  open $APP_BUNDLE"
echo ""
echo "To install to Applications:"
echo "  cp -r $APP_BUNDLE /Applications/"
