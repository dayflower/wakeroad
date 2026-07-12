#!/bin/bash
# Assembles dist/WakeRoad.app from the SwiftPM release build and ad-hoc signs
# it. SwiftPM cannot produce .app bundles itself, and SMAppService (launch at
# login) only works from a proper bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product WakeRoadApp
bin_path="$(swift build -c release --product WakeRoadApp --show-bin-path)"

app="dist/WakeRoad.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/WakeRoadApp" "$app/Contents/MacOS/WakeRoad"
cp Resources/Info.plist "$app/Contents/Info.plist"

codesign --force --sign - "$app"

echo "built $app"
