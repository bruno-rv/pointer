#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -- "$script_dir/.." && pwd -P)"
bundle="$root_dir/build/Pointer.app"

"$script_dir/build-app.sh"
[[ -d "$bundle" ]] || {
    echo "run-app.sh: bundle was not created: $bundle" >&2
    exit 1
}
/usr/bin/open "$bundle"
