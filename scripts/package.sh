#!/bin/bash
# 지인 공유용 dist/cccv.zip 을 만든다: 빌드 → CCCV.app + install.sh 를 cccv/ 폴더로 묶어 압축.
# 받는 쪽은 zip 을 풀고 `bash ~/Downloads/cccv/install.sh` 한 줄이면 된다.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh >/dev/null # → /Applications/CCCV.app
codesign --verify --strict /Applications/CCCV.app

STAGE=dist/cccv
rm -rf dist
mkdir -p "$STAGE"
ditto /Applications/CCCV.app "$STAGE/CCCV.app" # cp 대신 ditto — 서명·확장 속성을 그대로 복사
cp scripts/install.sh "$STAGE/install.sh"
chmod +x "$STAGE/install.sh"
ditto -c -k --keepParent "$STAGE" dist/cccv.zip
rm -rf "$STAGE"

echo "dist/cccv.zip ($(du -h dist/cccv.zip | cut -f1))"
