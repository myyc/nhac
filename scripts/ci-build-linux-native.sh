#!/bin/bash
set -e

echo "==================================="
echo "Building nhac for Linux (Native)"
echo "==================================="

# Add Flutter to PATH if not already there
export PATH="$PATH:$HOME/flutter/bin"

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Build Linux app
echo "Building Linux app (release mode)..."
flutter build linux --release --tree-shake-icons

# Check if build was successful
if [ ! -f "build/linux/x64/release/bundle/nhac" ]; then
    echo "Error: Linux build failed"
    exit 1
fi

echo "Linux build complete!"

# Generate icons if needed
if [ -f "generate_app_icons.py" ]; then
    echo "Generating app icons..."
    python3 generate_app_icons.py || true
fi

# Build Flatpak if manifest exists and flatpak-builder is available
if [ -f "dev.myyc.nhac.yaml" ] && command -v flatpak-builder &> /dev/null; then
    echo "==================================="
    echo "Building Flatpak"
    echo "==================================="
    
    # Ensure Flatpak runtime is installed
    flatpak install --user -y flathub org.freedesktop.Platform//24.08 || true
    flatpak install --user -y flathub org.freedesktop.Sdk//24.08 || true
    
    # Build Flatpak (using cache if available)
    # First build creates the app
    flatpak-builder --ccache --keep-build-dirs --repo=repo build-dir dev.myyc.nhac.yaml
    
    # Build single-file bundle
    flatpak build-bundle repo nhac.flatpak dev.myyc.nhac
    
    echo "Flatpak build complete!"
else
    echo "Skipping Flatpak build (flatpak-builder not found or manifest missing)"
fi


echo "==================================="
echo "Linux builds completed successfully!"
echo "==================================="