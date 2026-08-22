#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -- "$script_dir/../.." && pwd -P)"
bundle="$root_dir/build/Pointer.app"
executable="$bundle/Contents/MacOS/Pointer"
fixture_roots=()

cleanup_fixtures() {
    for fixture in "${fixture_roots[@]}"; do
        if [[ -d "$fixture" ]]; then
            rm -rf -- "$fixture"
        fi
    done
}
trap cleanup_fixtures EXIT

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

test_untracked_plist_rejected() {
    local fixture output
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/pointer-build-contract.XXXXXX")"
    fixture_roots+=("$fixture")
    cp "$root_dir/Package.swift" "$fixture/Package.swift"
    cp -R "$root_dir/Sources" "$fixture/Sources"
    cp -R "$root_dir/Tests" "$fixture/Tests"
    mkdir -p "$fixture/Bundle" "$fixture/scripts"
    cp "$root_dir/Bundle/Info.plist" "$fixture/Bundle/Info.plist"
    cp "$root_dir/scripts/build-app.sh" "$fixture/scripts/build-app.sh"
    chmod +x "$fixture/scripts/build-app.sh"
    git -C "$fixture" init -q
    git -C "$fixture" add Package.swift Sources Tests scripts/build-app.sh

    if output="$(cd -- "$fixture" && "$fixture/scripts/build-app.sh" 2>&1)"; then
        echo "untracked Info.plist was accepted: $output" >&2
        return 1
    fi
    if [[ "$output" != *"Bundle/Info.plist must be tracked"* ]]; then
        echo "unexpected untracked-metadata failure: $output" >&2
        return 1
    fi
}

test_verifier_rejects_wrong_overlay_count() {
    local overlay_count="$1" fixture output
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/pointer-verify-contract.XXXXXX")"
    fixture_roots+=("$fixture")
    mkdir -p "$fixture/Bundle" "$fixture/scripts" "$fixture/build/Pointer.app/Contents/MacOS"
    cp "$root_dir/Bundle/Info.plist" "$fixture/Bundle/Info.plist"
    cp "$root_dir/Bundle/Info.plist" "$fixture/build/Pointer.app/Contents/Info.plist"
    cp "$root_dir/scripts/verify.sh" "$fixture/scripts/verify.sh"
    chmod +x "$fixture/scripts/verify.sh"
    printf '%s\n' '#!/bin/bash' 'set -euo pipefail' > "$fixture/scripts/build-app.sh"
    chmod +x "$fixture/scripts/build-app.sh"

    printf '%s\n' \
        '// swift-tools-version: 5.10' \
        'import PackageDescription' \
        'let package = Package(name: "VerifyFixture", targets: [' \
        '    .target(name: "VerifyFixture"),' \
        '    .testTarget(name: "VerifyFixtureTests", dependencies: ["VerifyFixture"])' \
        '])' > "$fixture/Package.swift"
    mkdir -p "$fixture/Sources/VerifyFixture" "$fixture/Tests/VerifyFixtureTests"
    printf '%s\n' 'public struct VerifyFixture {}' > "$fixture/Sources/VerifyFixture/VerifyFixture.swift"
    printf '%s\n' \
        'import XCTest' \
        '@testable import VerifyFixture' \
        'final class VerifyFixtureTests: XCTestCase {' \
        '    func testFixture() { XCTAssertTrue(true) }' \
        '}' > "$fixture/Tests/VerifyFixtureTests/VerifyFixtureTests.swift"

    printf '%s\n' \
        "print(#\"{\"mode\":\"standby\",\"overlayCount\":${overlay_count},\"paletteCount\":1,\"shortcutID\":\"control-option-command-p\"}\"#)" \
        > "$fixture/Smoke.swift"
    /usr/bin/xcrun swiftc -O -o "$fixture/build/Pointer.app/Contents/MacOS/Pointer" "$fixture/Smoke.swift"
    chmod +x "$fixture/build/Pointer.app/Contents/MacOS/Pointer"
    /usr/bin/codesign --force --sign - "$fixture/build/Pointer.app"

    if output="$(cd -- "$fixture" && "$fixture/scripts/verify.sh" 2>&1)"; then
        echo "verifier accepted overlayCount=$overlay_count: $output" >&2
        return 1
    fi
    if [[ "$output" != *"smoke report did not plan one overlay"* ]]; then
        echo "unexpected overlay-count failure: $output" >&2
        return 1
    fi
}

regression_failures=0
if ! test_untracked_plist_rejected; then
    regression_failures=$((regression_failures + 1))
fi
if ! test_verifier_rejects_wrong_overlay_count 0; then
    regression_failures=$((regression_failures + 1))
fi
if ! test_verifier_rejects_wrong_overlay_count 10; then
    regression_failures=$((regression_failures + 1))
fi
if (( regression_failures > 0 )); then
    echo "build-contract regressions failed: $regression_failures" >&2
    exit 1
fi

echo "build contract passed: $bundle"
