#!/bin/bash
# Docker entrypoint for Linux builds

# Run Flutter doctor for Linux only
flutter doctor -v --linux-only

# Execute the passed command
exec "$@"