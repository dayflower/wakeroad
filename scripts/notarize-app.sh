#!/bin/bash
# Submits dist/WakeRoad.app to Apple's notary service and staples the resulting
# ticket into the bundle, so Gatekeeper accepts it on machines that have never
# seen the app and without network access.
#
# The app must already be signed with a Developer ID identity and the hardened
# runtime — run scripts/make-app.sh with CODESIGN_IDENTITY set first.
#
# Credentials come from an App Store Connect API key:
#   NOTARY_KEY_ID     Key ID of the key
#   NOTARY_ISSUER_ID  Issuer ID of the team
#   NOTARY_KEY_PATH   Path to the AuthKey_*.p8 private key
set -euo pipefail

cd "$(dirname "$0")/.."

: "${NOTARY_KEY_ID:?NOTARY_KEY_ID is required}"
: "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required}"
: "${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required}"

app="dist/WakeRoad.app"
if [ ! -d "$app" ]; then
	echo "Error: $app not found; run scripts/make-app.sh first" >&2
	exit 1
fi

# notarytool only accepts zip/pkg/dmg, so submit a throwaway archive. The ticket
# it issues is stapled to the .app itself afterwards, which means any archive
# built for distribution has to be created after this script runs.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app" "$tmp/WakeRoad.zip"

# --wait exits non-zero unless the submission comes back Accepted. It prints the
# submission id, so `xcrun notarytool log <id> --key ...` explains a rejection.
xcrun notarytool submit "$tmp/WakeRoad.zip" \
	--key "$NOTARY_KEY_PATH" \
	--key-id "$NOTARY_KEY_ID" \
	--issuer "$NOTARY_ISSUER_ID" \
	--wait

xcrun stapler staple "$app"
# Confirm Gatekeeper would let the app run from the stapled ticket alone.
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"

echo "notarized $app"
