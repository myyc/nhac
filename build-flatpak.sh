#!/bin/bash
set -e

echo "Building Flatpak for nhac..."

# Install the runtime and SDK if not already installed
echo "Installing Flatpak runtime and SDK..."
flatpak install -y flathub org.freedesktop.Platform//24.08
flatpak install -y flathub org.freedesktop.Sdk//24.08

# Build the Flatpak
echo "Building the Flatpak..."
flatpak-builder --force-clean build-dir dev.myyc.nhac.yaml

# Create a repository and export the Flatpak
echo "Exporting the Flatpak..."
flatpak-builder --repo=repo --force-clean build-dir dev.myyc.nhac.yaml

# Build a single-file bundle
echo "Creating bundle..."
flatpak build-bundle repo nhac.flatpak dev.myyc.nhac

echo "Flatpak build complete!"
echo ""
echo "To install the Flatpak locally, run:"
echo "  flatpak install --user nhac.flatpak"
echo ""
echo "To run the application:"
echo "  flatpak run dev.myyc.nhac"
echo ""
echo "To test the build without installing:"
echo "  flatpak-builder --run build-dir dev.myyc.nhac.yaml nhac"