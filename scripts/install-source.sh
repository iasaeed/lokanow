#!/bin/sh
set -eu
# Build on this Mac and install for the current user. No sudo is used.
[ "$(uname -s)" = Darwin ] || { echo "Lokanow requires macOS." >&2; exit 1; }
[ "$(id -u)" != 0 ] || { echo "Run this installer as your regular user, without sudo." >&2; exit 1; }
version_major="$(/usr/bin/xcodebuild -version 2>/dev/null | awk '/^Xcode / { split($2, v, "."); print v[1]; exit }')"
case "$version_major" in
  ''|*[!0-9]*) echo "Select Xcode 26 or later. Command Line Tools alone are insufficient." >&2; exit 1 ;;
esac
[ "$version_major" -ge 26 ] || { echo "Xcode 26 or later is required." >&2; exit 1; }
ref="${1:-v1.0.2}"
printf '%s\n' "$ref" | /usr/bin/grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || {
  echo "Expected a version such as v1.0.2." >&2; exit 1;
}
appdir="$HOME/Applications"
target="$appdir/Lokanow.app"
[ ! -L "$appdir" ] && [ ! -e "$target" ] && [ ! -L "$target" ] || {
  echo "Installation stopped: Applications is a symlink or Lokanow.app already exists. Move the existing app first." >&2; exit 1;
}
work="$(mktemp -d "${TMPDIR:-/tmp}/lokanow-install.XXXXXX")"
staging=""
build_log=""
cleanup() {
  status=$?
  trap - 0
  rm -rf "$work"
  if [ -n "$staging" ]; then rm -rf "$staging"; fi
  if [ -n "$build_log" ]; then
    if [ "$status" -eq 0 ]; then
      rm -f "$build_log"
    else
      printf '%s\n' "Installation did not complete. Build log saved at: $build_log" >&2
    fi
  fi
  exit "$status"
}
trap cleanup 0
trap 'printf "\nInstallation cancelled.\n" >&2; exit 130' INT
trap 'printf "\nInstallation terminated.\n" >&2; exit 143' TERM
printf '%s\n' "Downloading Lokanow $ref source..."
/usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  "https://github.com/iasaeed/lokanow/archive/refs/tags/$ref.tar.gz" -o "$work/source.tar.gz"
mkdir "$work/source"
/usr/bin/tar -xzf "$work/source.tar.gz" -C "$work/source" --strip-components=1
build_log="$(mktemp "${TMPDIR:-/tmp}/lokanow-build.XXXXXX")"
printf '%s\n' "Building locally. The first build downloads and compiles SwiftSyntax and may take several minutes." \
  "Live Xcode output follows. Some compiler steps can be quiet while running." "Build log: $build_log"
(
set +e
/usr/bin/xcodebuild -project "$work/source/Lokanow.xcodeproj" -scheme Lokanow \
  -configuration Release -destination 'platform=macOS' -derivedDataPath "$work/DerivedData" \
  ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
build_status=$?
printf '%s\n' "$build_status" > "$work/build-status"
exit "$build_status"
) 2>&1 | /usr/bin/tee "$build_log"
# POSIX sh has no pipefail. Preserve the compiler status separately from tee.
[ -f "$work/build-status" ] || { echo "Build interrupted before completion." >&2; exit 1; }
build_status="$(cat "$work/build-status")"
[ "$build_status" -eq 0 ] || exit "$build_status"
app="$work/DerivedData/Build/Products/Release/Lokanow.app"
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p "$appdir"
staging="$(mktemp -d "$appdir/.lokanow-install.XXXXXX")"
/usr/bin/ditto "$app" "$staging/Lokanow.app"
[ ! -e "$target" ] && [ ! -L "$target" ] || { echo "Destination appeared during build. Stopping." >&2; exit 1; }
/bin/mv -n "$staging/Lokanow.app" "$target"
[ ! -e "$staging/Lokanow.app" ] || { echo "Destination was not installed." >&2; exit 1; }
printf '%s\n' "Installed: $target" "This is a locally built, ad hoc signed app. Launch it from Finder."
