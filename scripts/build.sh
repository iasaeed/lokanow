#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Lokanow.xcodeproj -scheme Lokanow -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
/usr/bin/ditto build/DerivedData/Build/Products/Release/Lokanow.app 'build/Lokanow.app'
printf '%s\n' "Built: $(pwd)/build/Lokanow.app"
