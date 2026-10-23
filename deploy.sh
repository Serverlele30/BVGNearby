#!/bin/bash
# Baut BVGNearby + Widget, signiert mit ldid (AppSync) und installiert aufs iPhone.
#   ./deploy.sh              normal
#   NO_WIDGET=1 ./deploy.sh  ohne Widget/App Group (falls das Widget Probleme macht)
set -e
cd "$(dirname "$0")"

python3 BVGNearby/check_methods.py BVGNearby

# 1) App bauen
xcodebuild -project BVGNearby.xcodeproj -scheme BVGNearby -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO INFOPLIST_KEY_UIMainStoryboardFile= \
  -quiet build

APP=build/Build/Products/Debug-iphoneos/BVGNearby.app
PB=/usr/libexec/PlistBuddy
plutil -remove UIMainStoryboardFile "$APP/Info.plist" 2>/dev/null || true

# URL-Schema bvgnearby:// (Widget oeffnet damit Haltestellen in der App)
$PB -c "Delete :CFBundleURLTypes" "$APP/Info.plist" 2>/dev/null || true
$PB -c "Add :CFBundleURLTypes array" \
    -c "Add :CFBundleURLTypes:0 dict" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.serverlele.BVGNearby" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string bvgnearby" "$APP/Info.plist"

# 2) Widget bauen (ohne Xcode-Target, direkt mit clang)
rm -rf "$APP/PlugIns"
if [ -z "$NO_WIDGET" ]; then
  APPEX="$APP/PlugIns/BVGWidget.appex"
  mkdir -p "$APPEX"
  xcrun -sdk iphoneos clang -arch armv7 -arch arm64 -miphoneos-version-min=9.0 \
    -fobjc-arc -fmodules -fapplication-extension -e _NSExtensionMain \
    -framework Foundation -framework UIKit -framework NotificationCenter -framework CoreLocation \
    Widget/TodayViewController.m -o "$APPEX/BVGWidget"
  cp Widget/Info.plist "$APPEX/Info.plist"
  # Versionsnummern muessen zur App passen
  V=$($PB -c "Print CFBundleShortVersionString" "$APP/Info.plist")
  B=$($PB -c "Print CFBundleVersion" "$APP/Info.plist")
  $PB -c "Set :CFBundleShortVersionString $V" -c "Set :CFBundleVersion $B" "$APPEX/Info.plist"
  plutil -convert binary1 "$APPEX/Info.plist"
  ldid -SWidget/widget.entitlements "$APPEX/BVGWidget"
  ldid -SWidget/app.entitlements "$APP/BVGNearby"
else
  ldid -S "$APP/BVGNearby"
fi

# 3) Paket bauen und installieren
rm -rf build/Payload build/BVGNearby.ipa
mkdir build/Payload && cp -r "$APP" build/Payload/
(cd build && zip -qr BVGNearby.ipa Payload)
ideviceinstaller install build/BVGNearby.ipa
