#!/bin/bash
# Docker entrypoint for Linux builds

# Run Flutter doctor (ignore failures for missing platforms)
flutter doctor -v || true

# Execute the passed command
exec "$@"