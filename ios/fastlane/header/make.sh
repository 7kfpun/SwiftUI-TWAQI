#!/bin/zsh
# Builds the 3840x1646 App Store product page header for one locale from the
# framed iPhone captures (fastlane ios frame_screenshots) and the watch face
# capture. Writes fastlane/header/<locale>.png:
#
#   fastlane/header/make.sh en-US "Clean air, at a glance." "Live AQI from every station in Taiwan, on your iPhone and Apple Watch." \
#     "/System/Library/Fonts/Supplemental/Arial Bold.ttf" "/System/Library/Fonts/Supplemental/Arial.ttf" fastlane/header/en-US.png
#   fastlane/header/make.sh zh-Hant $'空氣好不好，\n一眼就知道' $'全台測站即時 AQI，\niPhone 與 Apple Watch 都能看。' \
#     "/System/Library/Fonts/STHeiti Medium.ttc" "/System/Library/Fonts/STHeiti Light.ttc" fastlane/header/zh-Hant.png
set -e
R=/Users/kf/Documents/Workspace/SwiftUI-TWAQI
L=$1; H=$2; SUB=$3; FB=$4; FR=$5; OUT=$6
T=$(mktemp -d)
W=3840; HH=1646
magick -size ${W}x${HH} gradient:'#A6E7F6-#5CC4E3' $T/bg.png
# icon, rounded
magick $R/TWAQI/Assets.xcassets/AppIcon.appiconset/icon-1024.png -resize 300x300 \
  \( -size 300x300 xc:none -fill white -draw "roundrectangle 0,0,299,299,68,68" \) -compose DstIn -composite $T/icon.png
magick -background none -fill '#0B3A49' -font "$FB" -pointsize 140 -size 1350x caption:"$H" $T/h.png
magick -background none -fill '#1A5D71' -font "$FR" -pointsize 70 -size 1300x caption:"$SUB" $T/s.png
# phones
magick "$R/fastlane/.frameit_work/$L/iPhone 17 Pro 01_framed.png" -resize x1440 $T/p1.png
magick "$R/fastlane/.frameit_work/$L/iPhone 17 Pro 02_framed.png" -resize x1300 $T/p2.png
# watch: screen with rounded corners inside a dark case
magick "$R/fastlane/screenshots/$L/AppleWatch_01.png" -resize 624x744 \
  \( -size 624x744 xc:none -fill white -draw "roundrectangle 0,0,623,743,110,110" \) -compose DstIn -composite $T/ws.png
magick -size 704x824 xc:none -fill '#1C1C1E' -stroke '#3A3A3C' -strokewidth 6 -draw "roundrectangle 3,3,700,820,150,150" \
  $T/ws.png -gravity center -compose over -composite \
  \( -size 40x150 xc:none -fill '#2C2C2E' -draw "roundrectangle 0,0,39,149,14,14" \) -gravity east -geometry -30-120 -compose dst-over -composite \
  $T/w.png
magick $T/w.png -resize 68% $T/w.png
# shadows
for f in p1 p2 w; do magick $T/$f.png \( +clone -background '#0B3A49' -shadow 35x30+0+25 \) +swap -background none -layers merge +repage $T/${f}s.png; done
magick $T/bg.png \
  $T/icon.png -gravity northwest -geometry +230+330 -composite \
  $T/h.png -gravity northwest -geometry +230+700 -composite \
  $T/s.png -gravity northwest -geometry +235+$((700 + $(magick identify -format '%h' $T/h.png) + 40)) -composite \
  $T/p2s.png -gravity northwest -geometry +2780+250 -composite \
  $T/p1s.png -gravity northwest -geometry +2050+90 -composite \
  $T/ws.png -gravity northwest -geometry +1700+860 -composite \
  -alpha remove -alpha off -strip PNG24:"$OUT"
magick identify -format '%f %wx%h\n' "$OUT"
rm -rf $T
