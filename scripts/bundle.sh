#!/bin/bash
# release 빌드 후 build/CCCV.app 으로 조립·서명한다.
# 서명: CODESIGN_IDENTITY > 키체인의 자체 서명 인증서 "CCCV Code Signing" > ad-hoc(-).
# 자체 서명 인증서는 유료 프로그램 없이 만든 것이라 개인 이름·Team ID 가 들어가지 않고,
# 같은 인증서로 서명하는 한 손쉬운 사용(TCC) 권한이 업데이트 뒤에도 유지된다.
# ad-hoc 은 빌드마다 cdhash 가 바뀌어 그 권한이 풀린다 (인증서가 없는 Mac 에서 빌드할 때).
# hardened runtime(--options runtime)은 쓰지 않는다. 공증용 Developer ID 가 없고,
# ad-hoc 에 runtime 을 얹어도 권한이 유지되지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/CCCV.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/cccv "$APP/Contents/MacOS/cccv"

# 앱 아이콘: 1024 원본 → iconset → icns
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>CCCV</string>
    <key>CFBundleExecutable</key><string>cccv</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.cccv</string>
    <key>CFBundleName</key><string>CCCV</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

SELF_SIGNED="CCCV Code Signing"
if [ -z "${CODESIGN_IDENTITY:-}" ] && security find-certificate -c "$SELF_SIGNED" >/dev/null 2>&1; then
    CODESIGN_IDENTITY=$SELF_SIGNED
fi
IDENTITY=${CODESIGN_IDENTITY:--}
if [ "$IDENTITY" = "-" ]; then
    echo "warning: ad-hoc 서명합니다. 재빌드마다 손쉬운 사용 권한을 다시 줘야 합니다. 인증서로 서명하려면 CODESIGN_IDENTITY 를 지정하세요." >&2
fi
codesign --force --sign "$IDENTITY" "$APP"

# 로그인 시 자동 실행은 앱 경로 기준이라 고정 위치에 설치한다.
# 같은 이름의 다른 앱을 지우지 않도록 번들 ID 가 local.cccv 일 때만 교체한다.
DEST=/Applications/CCCV.app
if [ -e "$DEST" ] && [ "$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "local.cccv" ]; then
    echo "error: $DEST 가 CCCV 가 아닌 다른 앱입니다. 설치를 건너뜁니다." >&2
    exit 1
fi
rm -rf "$DEST"
# 복사가 아니라 이동 — build/ 에 사본이 남으면 Spotlight·앱 목록에 CCCV 가 두 개 뜬다.
mv "$APP" "$DEST"
echo "$DEST"
