#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a Keychain notarytool profile}"
version="${VERSION:-1.0.4}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be major.minor.patch.' >&2; exit 1; }
xcodebuild -project Lokanow.xcodeproj -scheme Lokanow -configuration Release -archivePath build/Lokanow.xcarchive DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" MARKETING_VERSION="$version" ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' archive
xcodebuild -exportArchive -archivePath build/Lokanow.xcarchive -exportPath build/Release -exportOptionsPlist Resources/ExportOptions.plist
app='build/Release/Lokanow.app'
/usr/bin/ditto -c -k --keepParent "$app" build/notarization-upload.zip
xcrun notarytool submit build/notarization-upload.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose "$app"
archive="Lokanow-${version}-universal.zip"
/usr/bin/ditto -c -k --keepParent "$app" "build/$archive"
(cd build && shasum -a 256 "$archive" > "$archive.sha256")
printf 'Verified release: build/%s\n' "$archive"
