#!/bin/bash
set -e
cd "$(dirname "$0")"

xcodebuild -project BVGNearby.xcodeproj -scheme BVGNearby -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO INFOPLIST_KEY_UIMainStoryboardFile= \
  -quiet build

APP=build/Build/Products/Debug-iphoneos/BVGNearby.app
plutil -remove UIMainStoryboardFile "$APP/Info.plist" 2>/dev/null || true
ldid -S "$APP/BVGNearby"

rm -rf build/Payload build/BVGNearby.ipa
mkdir build/Payload && cp -r "$APP" build/Payload/
(cd build && zip -qr BVGNearby.ipa Payload)
ideviceinstaller install build/BVGNearby.ipa
