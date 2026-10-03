#!/bin/sh
# Builds build/Taggart.app: a release build, wrapped in an app bundle and
# ad-hoc signed. Usage: scripts/build-app.sh && open build/Taggart.app
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product Taggart
bin="$(swift build -c release --show-bin-path)"

app=build/Taggart.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Taggart" "$app/Contents/MacOS/Taggart"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$app"
echo "Built $app"
