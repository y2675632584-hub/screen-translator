#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Resources/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon-v5.png --out "Resources/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon-v5.png --out "Resources/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
# Compile the macOS 26 Icon Composer document. Assets.car tells the system
# this is a current app icon so it can apply the final shape without wrapping
# the already rounded artwork in a second legacy tile.
ASSET_OUTPUT="$PWD/.build/icon-assets"
mkdir -p "$ASSET_OUTPUT"
xcrun actool Resources/AppIcon.icon \
  --compile "$ASSET_OUTPUT" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$ASSET_OUTPUT/Info.plist" \
  --standalone-icon-behavior all
cp "$ASSET_OUTPUT/AppIcon.icns" Resources/AppIcon.icns
cp "$ASSET_OUTPUT/Assets.car" Resources/Assets.car
