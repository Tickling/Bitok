#!/usr/bin/env bash
# Скриншоты Android-приложения в эмуляторе для раздела «Помощь».
# Использование: screenshots.sh <Bitok.apk> <папка для PNG>
set -euo pipefail
APK="$1"; OUT="$2"; mkdir -p "$OUT"
adb install -r "$APK"
adb shell settings put global window_animation_scale 0 || true
adb shell settings put global transition_animation_scale 0 || true
adb shell cmd uimode night no || true
COMPONENT=app.bitok.android/.MainActivity

shot() {  # имя, затем дополнительные extras
  local name="$1"; shift
  adb shell am force-stop app.bitok.android
  adb shell am start -W -n "$COMPONENT" "$@" >/dev/null
  sleep 7
  adb exec-out screencap -p > "$OUT/$name.png"
  echo "📸 $name"
}

# Ученик
shot student-calendar --es uiAccount IVAN --ez uiReset true --es uiTab CALENDAR --es uiPage day
shot student-chat     --es uiAccount IVAN --es uiTab CHAT --es uiChat alexey
shot student-players  --es uiAccount IVAN --es uiTab CHAT --es uiPage players
shot student-progress --es uiAccount IVAN --es uiTab PEOPLE
shot student-shop     --es uiAccount IVAN --es uiTab CONTENT --es uiPage market
shot student-news     --es uiAccount IVAN --es uiTab CONTENT
shot student-profile  --es uiAccount IVAN --es uiTab PROFILE
# Тренер
shot coach-day        --es uiAccount ALEXEY --es uiTab CALENDAR --es uiPage tomorrow
shot coach-week       --es uiAccount ALEXEY --es uiTab CALENDAR --es uiPage week
shot coach-chat       --es uiAccount ALEXEY --es uiTab CHAT --es uiChat natasha
shot coach-students   --es uiAccount ALEXEY --es uiTab PEOPLE
shot coach-profile    --es uiAccount ALEXEY --es uiTab PROFILE
shot coach-venues     --es uiAccount ALEXEY --es uiTab PROFILE --es uiPage venues
shot coach-settings   --es uiAccount ALEXEY --es uiTab PROFILE --es uiPage settings
adb logcat -d -s AndroidRuntime:E > "$OUT/crash-log.txt" || true
