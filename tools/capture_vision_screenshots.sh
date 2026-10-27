#!/bin/zsh
#
# Captures the raw Vision Pro App Store screenshots on the visionOS simulator,
# through devicectl (DeviceHub's command line), into
# fastlane/screenshots_raw/<locale>/Vision Pro NN.png. Frame them with
# `fastlane frame_vision_screenshots`.
#
# The simulator can't be pinched from the command line, so each state is
# reached with the Debug-only launch arguments in ScreenshotLaunch.swift.
# Every shot starts from a fresh install, so no window restored from the
# last one leaks in.
#
# Framing crops each shot to its subject (VISION_CROPS in the Fastfile), which
# assumes the simulator's viewpoint: the default living room, seated, with the
# map volume where it opens. Recentre the view in DeviceHub before capturing.
#
# Usage: tools/capture_vision_screenshots.sh [simulator-udid]

set -eu
ROOT=${0:A:h:h}
DEVICE=${1:-$(xcrun simctl list devices booted | grep -m1 "Apple Vision Pro" | grep -oE "[0-9A-F-]{36}")}
BUNDLE_ID=com.kfpun.twaqi
DERIVED=/tmp/twaqi-vision-screenshots
HUALIEN=104

# NN | launch arguments. Hualien stands alone on the east coast, so its pin
# and card don't overlap a neighbour's.
shots=(
  "01|"
  "02|-TWAQIStation $HUALIEN"
  "03|-TWAQIWindMode YES"
  "04|-TWAQIStation $HUALIEN -TWAQIOpen station"
)

xcodebuild -project "$ROOT/TWAQI.xcodeproj" -scheme TWAQIVision -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED" build -quiet
APP="$DERIVED/Build/Products/Debug-xrsimulator/TWAQIVision.app"

for locale in en-US zh-Hant; do
  if [[ $locale == zh-Hant ]]; then
    language=(-AppleLanguages "(zh-Hant)" -AppleLocale zh_TW)
  else
    language=(-AppleLanguages "(en)" -AppleLocale en_US)
  fi
  out="$ROOT/fastlane/screenshots_raw/$locale"
  mkdir -p "$out"

  for shot in $shots; do
    number=${shot%%|*}
    arguments=${shot#*|}
    xcrun devicectl device uninstall app --device "$DEVICE" "$BUNDLE_ID" -q >/dev/null 2>&1 || true
    xcrun devicectl device install app --device "$DEVICE" "$APP" -q >/dev/null
    xcrun devicectl device process launch --device "$DEVICE" --terminate-existing -q "$BUNDLE_ID" \
      -- ${=arguments} $language >/dev/null
    # Long enough for the opening to play out and live readings to arrive.
    sleep 30
    xcrun devicectl device capture screenshot --device "$DEVICE" \
      --destination "$out/Vision Pro $number.png" -q >/dev/null
    echo "$locale/Vision Pro $number.png"
  done
done
