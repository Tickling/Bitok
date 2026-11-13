#!/usr/bin/env bash
# Скриншоты реального приложения в симуляторе для раздела «Помощь».
# Использование: screenshots.sh <путь к Bitok.app> <папка для PNG>
set -euo pipefail
APP="$1"; OUT="$2"; mkdir -p "$OUT"
DEVICE=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
names=[x for r in d for x in d[r] if x['name'].startswith('iPhone 16 Pro') and 'Max' not in x['name']] or \
      [x for r in d for x in d[r] if x['name'].startswith('iPhone')]
print(names[0]['udid'])")
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$DEVICE" "$APP"
BUNDLE=app.bitok.ios

shot() {  # имя, затем аргументы приложения
  local name="$1"; shift
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$DEVICE" "$BUNDLE" -AppleLanguages "(ru)" -AppleLocale ru_RU "$@" >/dev/null
  sleep 6
  xcrun simctl io "$DEVICE" screenshot "$OUT/$name.png" >/dev/null
  echo "📸 $name"
}

# Ученик
shot student-calendar -uiReset YES -uiAccount student -uiTab calendar -uiPage day
shot student-chat     -uiAccount student -uiTab chat -uiChat alexey
shot student-players  -uiAccount student -uiTab chat -uiPage players
shot student-progress -uiAccount student -uiTab profile
shot student-shop     -uiAccount student -uiTab content -uiPage market
shot student-news     -uiAccount student -uiTab content
shot student-profile  -uiAccount student -uiTab profile
# Тренер
shot coach-day        -uiAccount coach -uiTab calendar -uiPage tomorrow
shot coach-week       -uiAccount coach -uiTab calendar -uiPage week
shot coach-chat       -uiAccount coach -uiTab chat -uiChat natasha
shot coach-students   -uiAccount coach -uiTab people
shot coach-profile    -uiAccount coach -uiTab profile
shot coach-venues     -uiAccount coach -uiTab profile -uiPage venues
shot coach-settings   -uiAccount coach -uiTab profile -uiPage settings
# Биток Про (демо-экраны камеры без настоящей камеры)
shot pro-exercise     -uiAccount dmitry -uiTab profile -uiPage proExercise
shot pro-framing      -uiAccount dmitry -uiPage proFraming
shot pro-marks        -uiAccount dmitry -uiPage proMarks
shot pro-balls        -uiAccount dmitry -uiPage proBalls
shot pro-perform      -uiAccount dmitry -uiPage proPerform
shot pro-result       -uiAccount dmitry -uiPage proResult
shot pro-help         -uiAccount dmitry -uiTab profile -uiPage help
