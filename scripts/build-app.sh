#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usagebar-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/usagebar-modules"
build_path="${TMPDIR:-/tmp}/usagebar-build"
cache_path="${TMPDIR:-/tmp}/usagebar-cache"
swift build --product UsageBar -c release -debug-info-format none --scratch-path "$build_path" --cache-path "$cache_path" --disable-sandbox
binary_dir="$(swift build --product UsageBar -c release -debug-info-format none --scratch-path "$build_path" --cache-path "$cache_path" --disable-sandbox --show-bin-path)"
app_path="$PWD/dist/UsageBar.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/UsageBar" "$app_path/Contents/MacOS/UsageBar"
# SwiftPM stamps the deployment target as the SDK version; without the real SDK
# macOS runs the app in compatibility mode (no Liquid Glass). Must run before codesign.
binary="$app_path/Contents/MacOS/UsageBar"
minos="$(xcrun vtool -show-build "$binary" | awk '/minos/{print $2}')"
xcrun vtool -set-build-version macos "$minos" "$(xcrun --show-sdk-version)" -replace -output "$binary" "$binary"
cp README.md scripts/claude-statusline.py scripts/connect-claude.py "$app_path/Contents/Resources/"
iconset="$build_path/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>UsageBar</string>
<key>CFBundleIdentifier</key><string>local.usagebar</string>
<key>CFBundleName</key><string>UsageBar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_path"
printf 'App criado: %s\n' "$app_path"
