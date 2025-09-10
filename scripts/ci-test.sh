#!/bin/bash
set -e

echo "==================================="
echo "Running nhac tests"
echo "==================================="

# Flutter should be available via Homebrew in PATH

# Get dependencies first
echo "Getting dependencies..."
flutter pub get

# Analyze code for issues
echo "Running Flutter analyze..."
flutter analyze --no-fatal-infos --no-fatal-warnings || {
    echo "Warning: Flutter analyze found issues (continuing anyway)"
}

# Format check (optional - can be strict)
echo "Checking code formatting..."
dart format --set-exit-if-changed --output=none . || {
    echo "Warning: Code formatting issues found"
    echo "Run 'dart format .' to fix formatting"
    # Uncomment the next line to make formatting checks strict
    # exit 1
}

# Run tests
echo "Running unit tests..."
if [ -d "test" ] && [ "$(ls -A test/*.dart 2>/dev/null)" ]; then
    flutter test --coverage --no-pub
    
    # If you want to check coverage threshold (requires lcov)
    if command -v lcov &> /dev/null && [ -f "coverage/lcov.info" ]; then
        echo "Generating coverage report..."
        lcov --summary coverage/lcov.info
    fi
else
    echo "No tests found in test/ directory"
fi

# Run integration tests if they exist
if [ -d "integration_test" ] && [ "$(ls -A integration_test/*.dart 2>/dev/null)" ]; then
    echo "Running integration tests..."
    flutter test integration_test/
fi

echo "==================================="
echo "All tests completed!"
echo "===================================="