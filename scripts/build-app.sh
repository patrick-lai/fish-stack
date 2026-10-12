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
# The setup tool ships inside the app, so a Mac without Homebrew can install the Python runtime.
uv_bin=${UV_BIN:-$(command -v uv || true)}
if [ -z "$uv_bin" ] || [ ! -x "$uv_bin" ]; then
  echo "uv is needed to bundle the setup tool: brew install uv, or set UV_BIN to its path" >&2
  exit 1
fi
mkdir -p "$app/Contents/Resources/bin"
cp "$uv_bin" "$app/Contents/Resources/bin/uv"
chmod 755 "$app/Contents/Resources/bin/uv"
# Bytecode caches written by a previous run would break the code signature.
find "$app/Contents/Resources/runtime" -name __pycache__ -type d -prune -exec rm -rf {} +
codesign --force --sign - "$app"
echo "$app"
