#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -- "$script_dir/.." && pwd -P)"
bundle="$root_dir/build/Pointer.app"

fail() {
    echo "build-app.sh: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ "$(uname -m)" == "arm64" ]] || fail "Apple silicon (arm64) is required"

developer_dir="${DEVELOPER_DIR:-}"
if [[ -z "$developer_dir" ]]; then
    developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
fi
[[ -n "$developer_dir" ]] || fail "no active Xcode developer directory"
export DEVELOPER_DIR="$developer_dir"

xcodebuild_bin="$(/usr/bin/xcrun --find xcodebuild 2>/dev/null || true)"
swift_bin="$(/usr/bin/xcrun --find swift 2>/dev/null || true)"
plutil_bin="$(/usr/bin/xcrun --find plutil 2>/dev/null || true)"
codesign_bin="$(/usr/bin/xcrun --find codesign 2>/dev/null || true)"
lipo_bin="$(/usr/bin/xcrun --find lipo 2>/dev/null || true)"
[[ -x "$xcodebuild_bin" ]] || fail "xcodebuild is unavailable in $developer_dir"
[[ -x "$swift_bin" ]] || fail "swift is unavailable in $developer_dir"
[[ -x "$plutil_bin" ]] || fail "plutil is unavailable"
[[ -x "$codesign_bin" ]] || fail "codesign is unavailable"
[[ -x "$lipo_bin" ]] || fail "lipo is unavailable"
[[ -x /usr/bin/open ]] || fail "open is unavailable"

xcode_version="$("$xcodebuild_bin" -version | sed -n 's/^Xcode //p' | head -n 1)"
IFS=. read -r xcode_major xcode_minor _ <<< "$xcode_version"
[[ "$xcode_major" =~ ^[0-9]+$ && "$xcode_minor" =~ ^[0-9]+$ ]] || fail "could not determine Xcode version"
(( xcode_major > 15 || (xcode_major == 15 && xcode_minor >= 4) )) || \
    fail "Xcode 15.4 or later is required (found $xcode_version)"

[[ -f "$root_dir/Package.swift" ]] || fail "Package.swift is missing"
[[ -f "$root_dir/Bundle/Info.plist" ]] || fail "Bundle/Info.plist is missing"
"$plutil_bin" -lint "$root_dir/Bundle/Info.plist" >/dev/null

mkdir -p "$root_dir/build"
cd -- "$root_dir"
bin_path="$("$swift_bin" build --show-bin-path -c release --product Pointer)"
"$swift_bin" build -c release --product Pointer >/dev/null
[[ -d "$bin_path" ]] || fail "SwiftPM binary directory was not found: $bin_path"
source_executable="$bin_path/Pointer"
[[ -x "$source_executable" ]] || fail "Release executable was not produced: $source_executable"
[[ "$($lipo_bin -archs "$source_executable")" == *arm64* ]] || \
    fail "Release executable is not arm64"

staging="$(mktemp -d "$root_dir/build/.Pointer.app.XXXXXX")"
cleanup() {
    if [[ -n "${staging:-}" && -d "$staging" ]]; then
        rm -rf -- "$staging"
    fi
}
trap cleanup EXIT

mkdir -p "$staging/Contents/MacOS"
cp "$root_dir/Bundle/Info.plist" "$staging/Contents/Info.plist"
cp "$source_executable" "$staging/Contents/MacOS/Pointer"
chmod 755 "$staging/Contents/MacOS/Pointer"
"$plutil_bin" -lint "$staging/Contents/Info.plist" >/dev/null
[[ "$($lipo_bin -archs "$staging/Contents/MacOS/Pointer")" == *arm64* ]] || \
    fail "staged executable is not arm64"
"$codesign_bin" --force --sign - "$staging"
"$codesign_bin" --verify --deep --strict "$staging"

rm -rf -- "$bundle"
mv -- "$staging" "$bundle"
staging=""

"$plutil_bin" -lint "$bundle/Contents/Info.plist" >/dev/null
[[ -x "$bundle/Contents/MacOS/Pointer" ]] || fail "bundle executable is missing"
[[ "$($lipo_bin -archs "$bundle/Contents/MacOS/Pointer")" == *arm64* ]] || \
    fail "bundle executable is not arm64"
"$codesign_bin" --verify --deep --strict "$bundle"
echo "built $bundle"
