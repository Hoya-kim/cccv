<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="cccv 아이콘">
</p>

<h1 align="center">cccv</h1>

<p align="center">⌘C 한 것들을 다시 꺼내 쓰는 macOS 클립보드 매니저</p>

---

복사한 텍스트·이미지·파일·링크·색상을 기록해 두고, <kbd>⇧⌘V</kbd> 로 바를 열어 골라 붙여넣습니다.
[Paste](https://pasteapp.io/)·[PastePal](https://github.com/IndieGoodies/PastePal) 를 참고해 개인용으로 만들었습니다.

<p align="center"><img src="docs/images/bar.png" alt="⇧⌘V 로 연 하단 바 — 링크·이미지·JSON·색상·서식 텍스트·파일 카드"></p>

## 주요 기능

- **기록** — 텍스트, 서식 텍스트, 이미지, 파일, 링크, 색상(`#RRGGBB`). 같은 내용을 다시 복사하면 하나로 합쳐 맨 앞으로.
- **바** — 커서가 있는 화면의 아래·위·왼쪽·오른쪽 가장자리. 카드 크기 4단계.
- **검색·필터** — 본문, 이름, 링크 제목, **이미지 속 글자(OCR)** 까지 검색. 종류·출처 앱 필터, 고정 항목만 보기.
- **붙여넣기** — 커서 위치에 바로. 서식 없이 붙여넣기, 앱별로 항상 서식 없이(터미널·코드 편집기 등).
- **미리보기** — <kbd>Space</kbd> 로 선택한 카드 옆에 크게.
- **개발자 변환** — <kbd>⌘T</kbd> 로 URL·JSON·Base64·JWT·타임스탬프·camel/snake/kebab 변환해서 붙여넣기.
- **정리** — 고정(보존 기간에서 제외), 이름 붙이기, 내용 편집, 삭제·되돌리기.
- **개인정보** — 비밀번호 관리자 항목은 기록 안 함, 제외 앱, 정규식 패턴으로 기록 안 함 또는 N분 뒤 자동 삭제(토큰 등), 일시정지.
- **링크 미리보기** — 링크 카드에 페이지 제목·대표 이미지.

<p align="center"><img src="docs/images/preview.png" alt="Space 로 선택한 카드 위에 띄운 미리보기"></p>
<p align="center"><sub>Space — 선택한 카드 옆에 크게 미리보기</sub></p>

<p align="center"><img src="docs/images/transform.png" alt="⌘T 변환 목록과 결과 미리보기"></p>
<p align="center"><sub>⌘T — 변환 목록과 결과 미리보기</sub></p>

## 설치 (공유받은 zip)

> Apple Silicon(M 시리즈) Mac, **macOS 26 이상**에서 실행됩니다.

1. `cccv.zip` 을 받아 압축을 풉니다 (보통 `다운로드/cccv` 폴더가 생깁니다).
2. 터미널을 열고 아래 한 줄을 실행합니다.
   ```sh
   bash ~/Downloads/cccv/install.sh
   ```
   응용 프로그램 폴더에 설치하고 실행합니다. 업데이트할 때도 새 zip 을 풀고 같은 명령을 실행하면 됩니다.
3. **손쉬운 사용 권한**을 허용합니다 (시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → cccv). 허용한 뒤 cccv 를 한 번 종료했다 다시 엽니다.
   이 권한이 있어야 고른 항목이 커서 위치에 바로 붙여넣어집니다. 없으면 클립보드에 복사만 됩니다.

> cccv 는 Apple 공증(notarization)을 받지 않은 앱이라, 그냥 열면 macOS 가 "확인되지 않은 개발자" 로 막습니다.
> `install.sh` 는 설치한 cccv.app 의 격리 표시를 지워 이 경고를 넘깁니다. 믿을 수 있는 사람에게 받은 경우에만 설치하세요.

## 사용법

<kbd>⇧⌘V</kbd> 로 바를 열고, 바로 입력하면 검색됩니다.

| 키 | 동작 |
|---|---|
| <kbd>←</kbd> <kbd>→</kbd> (세로 바 <kbd>↑</kbd> <kbd>↓</kbd>) | 항목 이동 |
| <kbd>Return</kbd> / <kbd>⇧</kbd><kbd>Return</kbd> | 붙여넣기 / 서식 반대로 붙여넣기 |
| <kbd>⌘</kbd><kbd>1</kbd>–<kbd>9</kbd> | 앞에서 N번째 바로 붙여넣기 |
| <kbd>Space</kbd> / <kbd>⌘</kbd><kbd>Y</kbd> | 크게 미리보기 (검색 중엔 방향키로 고른 뒤 Space, 또는 ⌘Y) |
| <kbd>⌘</kbd><kbd>[</kbd> <kbd>⌘</kbd><kbd>]</kbd> | 전체 / 고정 전환 |
| <kbd>⌘</kbd><kbd>P</kbd> · <kbd>⌘</kbd><kbd>R</kbd> · <kbd>⌘</kbd><kbd>E</kbd> | 고정 · 이름 변경 · 내용 편집 |
| <kbd>⌘</kbd><kbd>T</kbd> | 변환해서 붙여넣기 |
| <kbd>⌫</kbd> / <kbd>⌘</kbd><kbd>Z</kbd> | 삭제 / 되돌리기 (검색어가 비어 있을 때) |
| <kbd>Esc</kbd> | 검색어 지우기 → 바 닫기 |

카드를 우클릭해도 같은 동작을 고를 수 있습니다. 바 열기 단축키, 바 위치, 카드 크기, 보존 기간(기본 30일), 로그인 시 자동 실행 등은 메뉴바 ⌘C 아이콘 → **설정…** 에서 바꿉니다.

<p align="center">
  <img src="docs/images/settings-general.png" width="32%" alt="설정 — 일반">
  <img src="docs/images/settings-paste.png" width="32%" alt="설정 — 붙여넣기">
  <img src="docs/images/settings-privacy.png" width="32%" alt="설정 — 개인정보 보호">
</p>

## 개인정보

- 기록은 이 Mac 의 `~/Library/Application Support/cccv/` 에만 저장됩니다. 서버로 보내지 않습니다.
- 네트워크 요청은 **링크 미리보기**뿐입니다. 링크 카드가 처음 보일 때 그 주소로 요청을 보냅니다. 1회용 링크(로그인·비밀번호 재설정)는 요청만으로 만료될 수 있으니, 필요하면 설정 → 개인정보 보호에서 끄세요.
- 메뉴바 앱(OTP 앱 등)에서 복사한 내용은 출처 앱을 알 수 없어 "제외 앱" 으로 막히지 않습니다. 정규식 패턴(기본: 숫자 6자리)으로 막으세요.

## 직접 빌드

macOS 26, Xcode 26 (Swift 6.2) 이 필요합니다.

```sh
swift test               # 핵심 로직 테스트
./scripts/bundle.sh      # 빌드 → 서명 → /Applications/cccv.app 설치
./scripts/package.sh     # 공유용 dist/cccv.zip (cccv.app + install.sh)
```

- 서명: 키체인의 첫 Apple Development 인증서를 씁니다 (`CODESIGN_IDENTITY` 로 지정 가능). 없으면 ad-hoc 서명이라 빌드할 때마다 손쉬운 사용 권한이 풀립니다.
- 구조: `Sources/CCCVCore` (저장소·분류·변환 등 테스트 가능한 로직), `Sources/cccv` (AppKit·SwiftUI 앱).
