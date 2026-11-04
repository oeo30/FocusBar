<p align="center">
  <img src="FocusBar/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="FocusBar 아이콘">
</p>

<h1 align="center">FocusBar</h1>

<p align="center">macOS 메뉴바 뽀모도로 타이머</p>

## 기능

- **다이얼 타이머.** 60분 다이얼을 돌려 집중 시간과 휴식 시간을 5분 단위로 정합니다.
- **메뉴바 카운트다운.** 실행 중에는 줄어드는 파이와 남은 시간이 캡슐로 표시되고, 대기 중에는 45분까지 감긴 작은 다이얼이 보입니다.
- **전환은 직접.** 세션이 끝나면 타이머가 멈추고 알림음이 울립니다. 알림의 *휴식 시작* / *집중 시작* 버튼으로 바로 다음 세션을 시작할 수 있고, 반응할 때까지 메뉴바가 깜빡입니다. 저절로 시작되는 것은 없습니다.
- **기록.** 오늘 집중한 총 시간과 세션 목록을 보여줍니다. 하루는 06:00부터 다음 날 05:59까지이며, 5분 미만 세션은 집계하지 않습니다.
- **색 설정.** 집중과 휴식 색을 직접 고를 수 있고, 다이얼·메뉴바·기록 카드에 함께 적용됩니다.
- **로그인 시 실행**, **메뉴바 시간 표시 켜고 끄기**, **알림음 볼륨**.

한국어와 영어를 지원하며 시스템 언어를 따릅니다.

## 설치

1. [Releases](../../releases)에서 최신 `FocusBar-*.dmg`를 받아 엽니다. (zip도 함께 제공합니다.)
2. 열린 창에서 **FocusBar**를 **Applications** 폴더로 끌어다 놓습니다.
3. 공증되지 않은 앱이라 처음 실행할 때는 앱을 **우클릭 → 열기**로 실행하고 확인을 눌러야 합니다. 또는 터미널에서 한 번만 아래 명령을 실행해도 됩니다.

```bash
xattr -d com.apple.quarantine /Applications/FocusBar.app
```

macOS 11 이상에서 동작합니다.

## 소스에서 빌드

```bash
git clone https://github.com/oeo30/FocusBar.git
cd FocusBar
xcodebuild -project FocusBar.xcodeproj -scheme FocusBar -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Release/FocusBar.app
```

또는 `FocusBar.xcodeproj`를 Xcode에서 열고 `FocusBar` 스킴을 실행합니다.

## 자동화

터미널이나 단축어 앱에서 타이머를 켜고 끌 수 있습니다.

```bash
open focusbar://startStop
```

## 크레딧

FocusBar는 Ilya Voronin의 [TomatoBar](https://github.com/ivoronin/TomatoBar)를 바탕으로 다시 만든 앱입니다.
알림음은 [buddhabeats](https://www.buddhabeats.net/)의 라이선스를 받았습니다.

의존성: [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin), [SwiftState](https://github.com/ReactKit/SwiftState)

## 라이선스

MIT. [LICENSE](LICENSE)를 참고하세요. Copyright © 2022–2023 Ilya Voronin, © 2026 oeo30.
