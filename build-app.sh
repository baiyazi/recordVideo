#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# 本机若同时存在多个 Command Line Tools SDK，优先使用与 Swift 5.10 匹配的 14.4。
SDK_14="/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk"
if [[ -d "$SDK_14" ]]; then
  export SDKROOT="$SDK_14"
fi
mkdir -p .build/release
mkdir -p Resources/AppIcon.iconset
swift Tools/IconGenerator.swift Resources/AppIcon-1024.png
sips -z 16 16 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_16x16.png >/dev/null
sips -z 32 32 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_16x16@2x.png >/dev/null
sips -z 32 32 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_32x32.png >/dev/null
sips -z 64 64 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_32x32@2x.png >/dev/null
sips -z 128 128 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_128x128.png >/dev/null
sips -z 256 256 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_128x128@2x.png >/dev/null
sips -z 256 256 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_256x256.png >/dev/null
sips -z 512 512 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_256x256@2x.png >/dev/null
sips -z 512 512 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_512x512.png >/dev/null
cp Resources/AppIcon-1024.png Resources/AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
swiftc -O -parse-as-library \
  -sdk "$SDKROOT" \
  -target x86_64-apple-macosx13.0 \
  -framework AppKit -framework SwiftUI -framework ScreenCaptureKit -framework AVFoundation -framework Carbon -framework CoreImage \
  Sources/ScreenFlowLite/main.swift \
  -o .build/release/ScreenFlowLite
APP="$PWD/dist/轻录屏.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ScreenFlowLite "$APP/Contents/MacOS/ScreenFlowLite"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "已生成：$APP"
