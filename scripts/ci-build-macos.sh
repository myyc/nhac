#!/bin/bash
set -e

echo "==================================="
echo "Building nhac for macOS"
echo "==================================="

# Flutter should be available via Homebrew in PATH

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Run code generation if needed
if [ -f "build_runner.yaml" ]; then
    echo "Running code generation..."
    flutter pub run build_runner build --delete-conflicting-outputs
fi

# Build macOS app
echo "Building macOS app..."
flutter build macos --release

# Check if build was successful
if [ ! -d "build/macos/Build/Products/Release/nhac.app" ]; then
    echo "Error: macOS build failed - app bundle not found"
    exit 1
fi

# Get version from pubspec.yaml
VERSION=$(grep "^version:" pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)
echo "Built version: $VERSION"

# Optional: Create a DMG for distribution
if command -v create-dmg &> /dev/null; then
    echo "Creating DMG..."
    create-dmg \
        --volname "nhac" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "nhac.app" 150 150 \
        --hide-extension "nhac.app" \
        --app-drop-link 450 150 \
        --no-internet-enable \
        "nhac-$VERSION.dmg" \
        "build/macos/Build/Products/Release/"
    echo "DMG created: nhac-$VERSION.dmg"
else
    echo "Note: create-dmg not found, skipping DMG creation"
    echo "Install with: npm install -g create-dmg"
fi

echo "==================================="
echo "macOS build completed successfully!"
echo "===================================="