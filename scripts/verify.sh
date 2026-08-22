#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -- "$script_dir/.." && pwd -P)"
bundle="$root_dir/build/Pointer.app"
executable="$bundle/Contents/MacOS/Pointer"

developer_dir="${DEVELOPER_DIR:-}"
if [[ -z "$developer_dir" ]]; then
    developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
fi
[[ -n "$developer_dir" ]] || {
    echo "verify.sh: no active Xcode developer directory" >&2
    exit 1
}
[[ "$(uname -m)" == "arm64" ]] || {
    echo "verify.sh: Apple silicon (arm64) is required" >&2
    exit 1
}
export DEVELOPER_DIR="$developer_dir"
swift_bin="$(/usr/bin/xcrun --find swift 2>/dev/null || true)"
[[ -x "$swift_bin" ]] || {
    echo "verify.sh: swift is unavailable in $developer_dir" >&2
    exit 1
}

cd -- "$root_dir"
"$swift_bin" test
"$script_dir/build-app.sh"

plutil_bin="$(/usr/bin/xcrun --find plutil 2>/dev/null || true)"
codesign_bin="$(/usr/bin/xcrun --find codesign 2>/dev/null || true)"
lipo_bin="$(/usr/bin/xcrun --find lipo 2>/dev/null || true)"
[[ -x "$plutil_bin" && -x "$codesign_bin" && -x "$lipo_bin" ]] || {
    echo "verify.sh: bundle validation tools are unavailable" >&2
    exit 1
}
"$plutil_bin" -lint "$bundle/Contents/Info.plist"
"$codesign_bin" --verify --deep --strict "$bundle"
[[ "$($lipo_bin -archs "$executable")" == *arm64* ]] || {
    echo "verify.sh: bundle executable is not arm64" >&2
    exit 1
}

smoke_json="$("$executable" --smoke --format json)"
[[ "$smoke_json" == *'"paletteCount":1'* ]] || {
    echo "verify.sh: smoke report did not plan one palette: $smoke_json" >&2
    exit 1
}
if ! /usr/bin/grep -Eq '"overlayCount"[[:space:]]*:[[:space:]]*1([[:space:]]*,|[[:space:]]*})' <<< "$smoke_json"; then
    echo "verify.sh: smoke report did not plan one overlay: $smoke_json" >&2
    exit 1
fi
[[ "$smoke_json" == *'"mode":"standby"'* ]] || {
    echo "verify.sh: smoke report was not standby: $smoke_json" >&2
    exit 1
}
[[ "$smoke_json" == *'"shortcutID":"control-option-command-p"'* ]] || {
    echo "verify.sh: smoke report used an invalid shortcut: $smoke_json" >&2
    exit 1
}
echo "verification passed"
