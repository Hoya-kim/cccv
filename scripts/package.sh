#!/bin/bash
# 지인 공유용 dist/cccv.zip 과 dist/CCCV.dmg 를 만든다.
# zip: CCCV.app + install.sh 를 cccv/ 폴더로 묶어 압축.
# dmg: CCCV.app, /Applications 심볼릭 링크, install.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh >/dev/null # → /Applications/CCCV.app
codesign --verify --strict /Applications/CCCV.app

rm -rf dist
mkdir -p dist

ZIP_STAGE=dist/cccv
mkdir -p "$ZIP_STAGE"
ditto /Applications/CCCV.app "$ZIP_STAGE/CCCV.app" # cp 대신 ditto — 서명·확장 속성을 그대로 복사
cp scripts/install.sh "$ZIP_STAGE/install.sh"
chmod +x "$ZIP_STAGE/install.sh"
ditto -c -k --keepParent "$ZIP_STAGE" dist/cccv.zip
rm -rf "$ZIP_STAGE"

DMG_STAGE=dist/dmg-src
mkdir -p "$DMG_STAGE"
ditto /Applications/CCCV.app "$DMG_STAGE/CCCV.app"
cp scripts/install.sh "$DMG_STAGE/install.sh"
chmod +x "$DMG_STAGE/install.sh"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname CCCV -srcfolder "$DMG_STAGE" -format UDZO dist/CCCV.dmg
rm -rf "$DMG_STAGE"

echo "dist/cccv.zip ($(du -h dist/cccv.zip | cut -f1))"
echo "dist/CCCV.dmg ($(du -h dist/CCCV.dmg | cut -f1))"
