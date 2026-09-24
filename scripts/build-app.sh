#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usagebar-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/usagebar-modules"
build_path="${TMPDIR:-/tmp}/usagebar-build"
cache_path="${TMPDIR:-/tmp}/usagebar-cache"
build_flags=(-c release -debug-info-format none --scratch-path "$build_path" --cache-path "$cache_path" --disable-sandbox)
swift build --product UsageBar "${build_flags[@]}"
swift build --product UsageBarWidget "${build_flags[@]}"
binary_dir="$(swift build "${build_flags[@]}" --show-bin-path)"
app_path="$PWD/dist/UsageBar.app"
widget_path="$app_path/Contents/PlugIns/UsageBarWidget.appex"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$widget_path/Contents/MacOS"
cp "$binary_dir/UsageBar" "$app_path/Contents/MacOS/UsageBar"
cp "$binary_dir/UsageBarWidget" "$widget_path/Contents/MacOS/UsageBarWidget"
# SwiftPM stamps the deployment target as the SDK version; without the real SDK
# macOS runs the app in compatibility mode (no Liquid Glass). Must run before codesign.
for binary in "$app_path/Contents/MacOS/UsageBar" "$widget_path/Contents/MacOS/UsageBarWidget"; do
    minos="$(xcrun vtool -show-build "$binary" | awk '/minos/{print $2}')"
    xcrun vtool -set-build-version macos "$minos" "$(xcrun --show-sdk-version)" -replace -output "$binary" "$binary"
done
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
cat > "$widget_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>UsageBarWidget</string>
<key>CFBundleIdentifier</key><string>local.usagebar.widget</string>
<key>CFBundleName</key><string>UsageBarWidget</string>
<key>CFBundleDisplayName</key><string>UsageBar</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSExtension</key><dict>
<key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
</dict>
</dict></plist>
PLIST
# The extension is signed first, with its sandbox entitlements, then sealed inside the app.
codesign --force --sign - --entitlements Resources/UsageBarWidget.entitlements "$widget_path"
codesign --force --sign - "$app_path"
printf 'App criado: %s\n' "$app_path"
