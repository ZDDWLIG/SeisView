#!/bin/bash
# 构建可分发的通用二进制 SeisView.app（arm64 + x86_64），并打包 DMG 与 ZIP。
# 用法：./scripts/release.sh [版本号，默认 0.1.0]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP="SeisView.app"
OUT="dist"
STAGING="$(mktemp -d)"

echo "==> 构建 arm64 + x86_64 (release)"
swift build -c release --arch arm64
swift build -c release --arch x86_64

echo "==> 合并通用二进制"
lipo -create \
  .build/arm64-apple-macosx/release/SeisView \
  .build/x86_64-apple-macosx/release/SeisView \
  -output "$STAGING/SeisView"

echo "==> 组装 $OUT/$APP"
rm -rf "$OUT/$APP"
mkdir -p "$OUT/$APP/Contents/MacOS" "$OUT/$APP/Contents/Resources"
cp "$STAGING/SeisView" "$OUT/$APP/Contents/MacOS/SeisView"
cp Sources/SeisView/Info.plist "$OUT/$APP/Contents/Info.plist"
cp Resources/SeisView.icns "$OUT/$APP/Contents/Resources/SeisView.icns"
printf 'APPL????' > "$OUT/$APP/Contents/PkgInfo"

echo "==> ad-hoc 签名"
codesign --force --sign - "$OUT/$APP"

echo "==> 打 DMG 与 ZIP"
hdiutil create -volname "SeisView" -srcfolder "$OUT/$APP" -ov -format UDZO "$OUT/SeisView-$VERSION.dmg" >/dev/null
ditto -c -k --keepParent "$OUT/$APP" "$OUT/SeisView-$VERSION.zip"

echo "==> 完成"
lipo -info "$OUT/$APP/Contents/MacOS/SeisView"
codesign -dv "$OUT/$APP" 2>&1 | grep -E "Identifier|Signature" || true
ls -lh "$OUT/SeisView-$VERSION.dmg" "$OUT/SeisView-$VERSION.zip"
rm -rf "$STAGING"
