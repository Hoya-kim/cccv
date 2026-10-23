#!/bin/bash
# CCCV 설치 — 이 스크립트 옆의 CCCV.app 을 응용 프로그램 폴더에 설치하고 실행한다.
# 사용: bash ~/Downloads/cccv/install.sh   (업데이트도 같은 명령)
#
# 공증(notarization)을 받지 않은 앱이라 그대로 열면 Gatekeeper 가 막는다.
# 이 스크립트는 설치한 CCCV.app 의 격리 표시(quarantine)를 지워 그 검사를 우회한다.
# 직접 빌드했거나 출처를 믿는 빌드에만 실행할 것.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/CCCV.app"
DEST=/Applications/CCCV.app

fail() { echo "❌ $1" >&2; exit 1; }

[ -d "$SRC" ] || fail "CCCV.app 을 찾을 수 없습니다: $SRC (zip 을 푼 폴더 안에서 실행해 주세요)"
[ "$(uname -m)" = "arm64" ] || fail "Apple Silicon(M 시리즈) Mac 에서만 실행됩니다."
OS_MAJOR="$(sw_vers -productVersion)"
OS_MAJOR="${OS_MAJOR%%.*}"
[ "$OS_MAJOR" -ge 26 ] || fail "macOS 26 이상이 필요합니다. (현재 $(sw_vers -productVersion))"

# 관리자 계정이 아니라 /Applications 에 쓸 수 없으면 사용자 응용 프로그램 폴더로
if [ ! -w /Applications ]; then
    mkdir -p "$HOME/Applications"
    DEST="$HOME/Applications/CCCV.app"
fi

# 같은 이름의 다른 앱은 지우지 않는다
if [ -e "$DEST" ] && [ "$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "local.cccv" ]; then
    fail "$DEST 에 CCCV 가 아닌 다른 앱이 있습니다. 직접 확인해 주세요."
fi

# 실행 중이면 종료 (업데이트)
if pgrep -xq cccv; then
    echo "실행 중인 CCCV 를 종료합니다…"
    osascript -e 'quit app id "local.cccv"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do pgrep -xq cccv || break; sleep 1; done
    pgrep -xq cccv && pkill -x cccv || true
fi

echo "⚠️  격리 표시(com.apple.quarantine)를 지운 뒤 설치합니다. Gatekeeper 검사를 우회하므로, 직접 빌드했거나 출처를 믿는 경우에만 이 스크립트를 쓰세요."
echo "설치 위치: $DEST"
rm -rf "$DEST"
ditto "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

open "$DEST"

cat <<'EOF'

✅ 설치했습니다. 메뉴바에 ⌘C 아이콘이 보이면 실행된 것입니다.

손쉬운 사용 (붙여넣기에 필요):
  1. "손쉬운 사용" 권한 창이 뜨면 → 시스템 설정 열기 → CCCV 켜기
     (안 뜨면: 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → CCCV 켜기)
  2. 권한을 켠 뒤 메뉴바 ⌘C 아이콘 → 종료 → 응용 프로그램에서 CCCV 다시 열기

업데이트해도 이 권한은 유지됩니다 (1.0.2 이하에서 올라올 때만 한 번 다시 허용).
붙여넣기 대신 클립보드에만 복사되면, 손쉬운 사용에서 − 로 CCCV 를 지운 뒤 다시 추가하고, 2번처럼 다시 여세요.

사용법: 아무 데서나 ⇧⌘V → ←→ 로 고르고 Return
설정·단축키: 메뉴바 ⌘C 아이콘 → 설정…
EOF
