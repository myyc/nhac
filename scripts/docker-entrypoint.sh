#!/bin/bash
# Docker entrypoint for Linux builds

# Accept Flutter licenses
yes | flutter doctor --android-licenses 2>/dev/null || true

# Run Flutter doctor to verify setup
flutter doctor -v

# Execute the passed command
exec "$@"