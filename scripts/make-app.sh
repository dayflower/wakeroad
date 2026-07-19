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

# The app icon is an Icon Composer document (icons/wakeroad.icon). Pass it to
# actool directly (as "AppIcon.icon"), compile it into an Assets.car, and merge
# the icon keys actool emits into the bundle Info.plist. Requires a full Xcode
# (actool >= 26, Icon Composer support) — Command Line Tools alone will fail.
actool="$(xcrun --find actool)"
icon_tmp="$(mktemp -d)"
trap 'rm -rf "$icon_tmp"' EXIT
cp -R icons/wakeroad.icon "$icon_tmp/AppIcon.icon"
mkdir -p "$icon_tmp/out"
partial_plist="$icon_tmp/assetcatalog_generated_info.plist"

# Clear any stuck actool daemon that can make the compile silently produce nothing.
killall ibtoold >/dev/null 2>&1 || true

# Icon Composer (liquid glass) icons need a macOS 26 deployment target here; this
# is intentionally separate from the app's own (macOS 13) build target.
# With an older target actool emits no icon and still exits 0.
"$actool" "$icon_tmp/AppIcon.icon" \
	--compile "$icon_tmp/out" \
	--output-format human-readable-text \
	--notices --warnings --errors \
	--output-partial-info-plist "$partial_plist" \
	--app-icon AppIcon \
	--include-all-app-icons \
	--enable-on-demand-resources NO \
	--development-region en \
	--target-device mac \
	--minimum-deployment-target 26.0 \
	--platform macosx

if [ ! -f "$icon_tmp/out/Assets.car" ]; then
	echo "Error: actool did not generate Assets.car (app icon would be missing)" >&2
	"$actool" --version || true
	exit 1
fi

cp "$icon_tmp/out/Assets.car" "$app/Contents/Resources/Assets.car"
# actool also emits a legacy .icns; ship it so the CFBundleIconFile key it puts
# in the partial plist resolves (and pre-macOS 26 systems get an icon too).
if [ -f "$icon_tmp/out/AppIcon.icns" ]; then
	cp "$icon_tmp/out/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
fi
/usr/libexec/PlistBuddy -c "Merge $partial_plist" "$app/Contents/Info.plist"
# Ensure the icon-name key is present even if actool's partial plist omitted it.
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$app/Contents/Info.plist"

codesign --force --sign - "$app"

echo "built $app"
