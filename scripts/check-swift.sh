#!/usr/bin/env bash
# Swift lint/check helper for Linux
# Usage: ./scripts/check-swift.sh [file.swift]

set -e
cd "$(dirname "$0")/.."

if [ -n "$1" ]; then
    echo "Checking: $1"
    swiftlint lint --path "$1"
else
    echo "Running SwiftLint on all Swift files..."
    swiftlint lint --quiet
    echo "✓ SwiftLint passed"
fi
