#!/bin/bash
set -euo pipefail
# Build on this Mac and install for the current user. No sudo is used.
[[ "$(uname -s)" == Darwin ]] || { echo "Lokanow requires macOS." >&2; exit 1; }
[[ "$(id -u)" != 0 ]] || { echo "Run this installer as your regular user, without sudo." >&2; exit 1; }
version="$(/usr/bin/xcodebuild -version 2>/dev/null | head -n 1)"
[[ "$version" =~ ^Xcode\ ([0-9]+) ]] && (( BASH_REMATCH[1] >= 26 )) || {
  echo "Select Xcode 26 or later before installing. Command Line Tools alone are insufficient." >&2; exit 1;
}
ref="${1:-v1.0.0}"
[[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a version such as v1.0.0." >&2; exit 1; }
appdir="$HOME/Applications"
target="$appdir/Lokanow.app"
[[ ! -L "$appdir" && ! -e "$target" && ! -L "$target" ]] || {
  echo "Installation stopped: Applications is a symlink or Lokanow.app already exists. Move the existing app first." >&2; exit 1;
}
work="$(mktemp -d "${TMPDIR:-/tmp}/lokanow-install.XXXXXX")"
staging=""
build_log=""
cleanup() {
  status=$?
  trap - EXIT
  rm -rf "$work"
  if [[ -n "$staging" ]]; then rm -rf "$staging"; fi
  if [[ -n "$build_log" ]]; then
    if (( status == 0 )); then
      rm -f "$build_log"
    else
      printf '%s\n' "Installation did not complete. Build log saved at: $build_log" >&2
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'printf "\nInstallation cancelled.\n" >&2; exit 130' INT
trap 'printf "\nInstallation terminated.\n" >&2; exit 143' TERM
printf '%s\n' "Downloading Lokanow $ref source..."
/usr/bin/curl --fail --location --proto '=https' --tlsv1.2 \
  "https://github.com/iasaeed/lokanow/archive/refs/tags/$ref.tar.gz" -o "$work/source.tar.gz"
mkdir "$work/source"
/usr/bin/tar -xzf "$work/source.tar.gz" -C "$work/source" --strip-components=1
build_log="$(mktemp "${TMPDIR:-/tmp}/lokanow-build.XXXXXX")"
printf '%s\n' "Building locally. The first build downloads and compiles SwiftSyntax and may take several minutes." \
  "Live Xcode output follows. Some compiler steps can be quiet while running." "Build log: $build_log"
/usr/bin/xcodebuild -project "$work/source/Lokanow.xcodeproj" -scheme Lokanow \
  -configuration Release -destination 'platform=macOS' -derivedDataPath "$work/DerivedData" \
  ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build 2>&1 | /usr/bin/tee "$build_log"
app="$work/DerivedData/Build/Products/Release/Lokanow.app"
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p "$appdir"
staging="$(mktemp -d "$appdir/.lokanow-install.XXXXXX")"
/usr/bin/ditto "$app" "$staging/Lokanow.app"
[[ ! -e "$target" && ! -L "$target" ]] || { echo "Destination appeared during build. Stopping." >&2; exit 1; }
/bin/mv -n "$staging/Lokanow.app" "$target"
[[ ! -e "$staging/Lokanow.app" ]] || { echo "Destination was not installed." >&2; exit 1; }
printf '%s\n' "Installed: $target" "This is a locally built, ad hoc signed app. Launch it from Finder."
