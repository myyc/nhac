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

echo "App bundle ready at: build/macos/Build/Products/Release/nhac.app"

echo "==================================="
echo "macOS build completed successfully!"
echo "===================================="