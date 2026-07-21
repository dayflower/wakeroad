#!/bin/bash
# Assembles dist/WakeRoad.app from the SwiftPM release build and signs it.
# SwiftPM cannot produce .app bundles itself, and SMAppService (launch at
# login) only works from a proper bundle.
#
# The wakeroad CLI ships inside the bundle too, so a single notarized and
# stapled artifact covers both; the Homebrew cask links it onto the PATH.
#
# Signing uses CODESIGN_IDENTITY when set (see the sign() helper below) and
# falls back to an ad-hoc signature otherwise.
set -euo pipefail

cd "$(dirname "$0")/.."

# --product takes a single value, so build the two products separately. They
# land in the same bin path.
swift build -c release --product WakeRoadApp
swift build -c release --product wakeroad
bin_path="$(swift build -c release --product WakeRoadApp --show-bin-path)"

app="dist/WakeRoad.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$bin_path/WakeRoadApp" "$app/Contents/MacOS/WakeRoad"
# Contents/Helpers rather than Contents/MacOS: macOS filesystems are normally
# case-insensitive, so "wakeroad" next to "WakeRoad" would clobber the app's own
# executable. Helpers is an allowed nested-code location too.
cp "$bin_path/wakeroad" "$app/Contents/Helpers/wakeroad"
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

# Sign one path with the release identity when CODESIGN_IDENTITY is set, adding
# the hardened runtime and secure timestamp that notarization requires. Without
# it, fall back to an ad-hoc signature, which is enough to run on the build
# machine. CODESIGN_KEYCHAIN narrows where the identity is looked up, for CI
# runs that import the certificate into a throwaway keychain.
sign() {
	if [ -n "${CODESIGN_IDENTITY:-}" ]; then
		local args=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY")
		if [ -n "${CODESIGN_KEYCHAIN:-}" ]; then
			args+=(--keychain "$CODESIGN_KEYCHAIN")
		fi
		codesign "${args[@]}" "$1"
	else
		codesign --force --sign - "$1"
	fi
}

# The bundled CLI is nested code, so it has to be signed before the bundle that
# seals it.
sign "$app/Contents/Helpers/wakeroad"
sign "$app"
codesign --verify --strict --verbose=2 "$app"

echo "built $app"
