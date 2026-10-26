#!/bin/bash
# Build the Mac app (Debug) and launch a fresh copy, so a UI change can be looked at straight away.
set -euo pipefail
cd "$(dirname "$0")/../App"
pkill -x "Per My Last" 2>/dev/null || true
xcodebuild -project PerMyLast.xcodeproj -scheme PerMyLast -configuration Debug -derivedDataPath build build -quiet
open -n "build/Build/Products/Debug/Per My Last.app"
