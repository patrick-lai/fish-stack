#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$root/app"
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)

app="$root/build/FishStack.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/runtime"
cp "$bin_dir/FishStack" "$app/Contents/MacOS/FishStack"
cp "$root/app/Info.plist" "$app/Contents/Info.plist"
# The app draws its own icon set from the same fish geometry as the menu-bar glyph, then iconutil packs it.
iconset="$root/build/AppIcon.iconset"
rm -rf "$iconset"
"$bin_dir/FishStack" --render-icon "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp "$root/runtime/pyproject.toml" "$root/runtime/uv.lock" "$app/Contents/Resources/runtime/"
cp -R "$root/runtime/src" "$app/Contents/Resources/runtime/src"
codesign --force --sign - "$app"
echo "$app"
