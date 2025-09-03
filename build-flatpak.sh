#!/bin/bash
set -e

echo "Building Flatpak for nhac..."

# First, build the Flutter app locally
echo "Building Flutter app (release mode)..."
flutter build linux --release --tree-shake-icons

if [ ! -f "build/linux/x64/release/bundle/nhac" ]; then
    echo "Error: Flutter build failed"
    exit 1
fi

echo "Flutter build complete!"

# Install the runtime and SDK if not already installed
echo "Installing Flatpak runtime and SDK..."
flatpak install --user -y flathub org.freedesktop.Platform//24.08
flatpak install --user -y flathub org.freedesktop.Sdk//24.08

# Build the Flatpak (just packages the pre-built binaries)
echo "Packaging Flatpak..."
flatpak-builder --force-clean build-dir dev.myyc.nhac.yaml

# Create a repository and export the Flatpak
echo "Exporting Flatpak..."
flatpak-builder --repo=repo --force-clean build-dir dev.myyc.nhac.yaml

# Build a single-file bundle
echo "Creating Flatpak bundle..."
flatpak build-bundle repo nhac.flatpak dev.myyc.nhac

echo ""
echo "✅ Flatpak build complete!"
echo ""
echo "The Flatpak bundle has been created: nhac.flatpak"
echo ""
echo "To install locally:"
echo "  flatpak install --user nhac.flatpak"
echo ""
echo "To run:"
echo "  flatpak run dev.myyc.nhac"
echo ""
echo "To test without installing:"
echo "  flatpak-builder --run build-dir dev.myyc.nhac.yaml nhac"