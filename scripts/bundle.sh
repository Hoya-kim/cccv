#!/bin/bash
# release 빌드 후 build/cccv.app 으로 조립·서명한다.
# 서명 인증서가 있으면 CODESIGN_IDENTITY 로 지정. 없으면 ad-hoc(-) 서명.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/cccv.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/cccv "$APP/Contents/MacOS/cccv"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>cccv</string>
    <key>CFBundleIdentifier</key><string>local.cccv</string>
    <key>CFBundleName</key><string>cccv</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "$APP"
