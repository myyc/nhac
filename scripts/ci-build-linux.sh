#!/bin/bash
set -e

echo "==================================="
echo "Building nhac for Linux (Docker)"
echo "==================================="

# Build Docker image if it doesn't exist or is outdated
DOCKER_IMAGE="nhac-linux-builder:latest"
echo "Building Docker image..."
docker build -f Dockerfile.linux-build -t $DOCKER_IMAGE .

# Run the build in Docker
echo "Running Linux build in Docker..."
docker run --rm \
    -v "$(pwd):/app" \
    -w /app \
    $DOCKER_IMAGE \
    bash -c "
        set -e
        
        echo '==================================='
        echo 'Building nhac for Linux'
        echo '==================================='
        
        # Setup Flutter
        export PATH=\"\$PATH:/opt/flutter/bin\"
        flutter --version
        flutter doctor -v || true
        
        # Clean previous builds
        echo 'Cleaning previous builds...'
        flutter clean
        
        # Get dependencies
        echo 'Getting dependencies...'
        flutter pub get
        
        # Build Linux app (x64 only)
        echo 'Building Linux app (release mode, x64)...'
        flutter build linux --release --tree-shake-icons --target-platform linux-x64 || {
            echo 'Error: Linux build failed'
            exit 1
        }
        
        # Check if build was successful
        if [ ! -f 'build/linux/x64/release/bundle/nhac' ]; then
            echo 'Error: Linux x64 build output not found'
            exit 1
        fi
        
        echo 'Linux build complete!'
        
        # Generate icons if needed
        if [ -f 'generate_app_icons.py' ]; then
            echo 'Generating app icons...'
            python3 generate_app_icons.py || true
        fi
        
        # Build Flatpak if manifest exists
        if [ -f 'dev.myyc.nhac.yaml' ]; then
            echo '==================================='
            echo 'Building Flatpak'
            echo '==================================='
            
            # Build Flatpak
            flatpak-builder --force-clean build-dir dev.myyc.nhac.yaml
            
            # Create repository and export
            flatpak-builder --repo=repo --force-clean build-dir dev.myyc.nhac.yaml
            
            # Build single-file bundle
            flatpak build-bundle repo nhac.flatpak dev.myyc.nhac
            
            echo 'Flatpak build complete!'
        fi
        
        # Create tarball of Linux binary bundle
        echo 'Creating binary tarball...'
        cd build/linux/x64/release/bundle
        tar czf ../../../../../nhac-linux-x64.tar.gz *
        cd -
        
        echo '==================================='
        echo 'Linux builds completed successfully!'
        echo '==================================='
    "

# Check outputs
if [ -f "nhac.flatpak" ]; then
    echo "Flatpak bundle created: nhac.flatpak"
fi

if [ -f "nhac-linux-x64.tar.gz" ]; then
    echo "Binary tarball created: nhac-linux-x64.tar.gz"
fi

echo "Linux build artifacts ready!"