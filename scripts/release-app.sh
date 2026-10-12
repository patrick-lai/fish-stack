#!/bin/sh
# Builds FishStack, signs it with Developer ID, notarizes it with an App Store Connect API key,
# staples the ticket and writes the download and a checksum manifest into dist/.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
identity=${FISH_STACK_SIGN_IDENTITY:?set FISH_STACK_SIGN_IDENTITY to your Developer ID Application identity}
key_id=${ASC_KEY_ID:?set ASC_KEY_ID to the App Store Connect key id}
issuer=${ASC_ISSUER_ID:?set ASC_ISSUER_ID to the App Store Connect issuer id}
key_path=${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$key_id.p8}

"$root/scripts/build-app.sh" >/dev/null
app="$root/build/FishStack.app"
version=$(plutil -extract CFBundleShortVersionString raw "$root/app/Info.plist")

codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"

dist="$root/dist"
rm -rf "$dist"
mkdir -p "$dist"
name="FishStack-$version.zip"
zip="$dist/$name"
ditto -c -k --keepParent "$app" "$zip"

xcrun notarytool submit "$zip" --key "$key_path" --key-id "$key_id" --issuer "$issuer" --wait

xcrun stapler staple "$app"
xcrun stapler validate "$app"
# Re-zip after stapling so the download carries the ticket.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose=4 "$app"

sha=$(shasum -a 256 "$zip" | awk '{print $1}')
size=$(stat -f %z "$zip")
cat > "$dist/latest.json" <<JSON
{
  "name": "FishStack",
  "version": "$version",
  "file": "$name",
  "sha256": "$sha",
  "bytes": $size,
  "notarized": true,
  "team": "$(printf '%s' "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
}
JSON
echo "$zip"
cat "$dist/latest.json"
