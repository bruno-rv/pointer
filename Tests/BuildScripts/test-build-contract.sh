#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -- "$script_dir/../.." && pwd -P)"
bundle="$root_dir/build/Pointer.app"
executable="$bundle/Contents/MacOS/Pointer"

[[ "$(uname -s)" == "Darwin" ]] || {
    echo "build contract requires macOS" >&2
    exit 1
}

"$root_dir/scripts/build-app.sh"
[[ -d "$bundle" ]]
[[ -x "$executable" ]]
[[ "$(/usr/bin/plutil -p "$bundle/Contents/Info.plist")" == *"org.pointer.app"* ]]
[[ "$(/usr/bin/lipo -archs "$executable")" == *arm64* ]]
"/usr/bin/codesign" --verify --deep --strict "$bundle"
first_bundle_path="$(cd -- "$bundle" && pwd -P)"

"$root_dir/scripts/build-app.sh"
[[ -d "$bundle" ]]
[[ -x "$executable" ]]
"/usr/bin/plutil" -lint "$bundle/Contents/Info.plist"
[[ "$(/usr/bin/lipo -archs "$executable")" == *arm64* ]]
"/usr/bin/codesign" --verify --deep --strict "$bundle"
second_bundle_path="$(cd -- "$bundle" && pwd -P)"
[[ "$first_bundle_path" == "$second_bundle_path" ]]

smoke_json="$("$executable" --smoke --format json --display built-in --display external)"
[[ "$smoke_json" == *'"paletteCount":1'* ]]
[[ "$smoke_json" == *'"overlayCount":2'* ]]
[[ "$smoke_json" == *'"mode":"standby"'* ]]
[[ "$smoke_json" == *'"shortcutID":"control-option-command-p"'* ]]

echo "build contract passed: $bundle"
