#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep build caches beside the project; also works in restricted workspaces.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
if [ ! -f Resources/AppIcon.icns ] || [ ! -f Resources/Assets.car ] || [ Resources/AppIcon-v5.png -nt Resources/Assets.car ] || [ Resources/AppIcon.icon/icon.json -nt Resources/Assets.car ]; then
  bash scripts/build-icon.sh
fi
APP="$PWD/dist/屏幕译.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ScreenTranslator "$APP/Contents/MacOS/ScreenTranslator"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Assets.car "$APP/Contents/Resources/Assets.car"
codesign --force --sign - --identifier local.yyy.ScreenTranslator "$APP"
codesign --verify --deep --strict "$APP"
touch "$APP"
echo "$APP"
