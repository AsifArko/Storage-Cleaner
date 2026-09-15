#!/bin/bash
# Double-click this file in Finder to build and launch Storage Cleaner.
# First launch compiles the app (typically 15–30 seconds); later launches are much faster.
set -euo pipefail
cd "$(dirname "$0")"
echo "Building Storage Cleaner..."
swift run -c release
