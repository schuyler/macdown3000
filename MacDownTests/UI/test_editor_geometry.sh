#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/macdown-editor-geometry.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
editor_source="${1:-$repo_root/MacDown/Code/View/MPEditorView.m}"
# Bound both compilation and dispatch_main: a stalled production operation
# must fail the regression runner instead of holding CI indefinitely.
run_bounded() {
  python3 - "$@" <<'PY'
import subprocess
import sys
try:
    result = subprocess.run(sys.argv[2:], timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    print("FAIL editor geometry command exceeded " + sys.argv[1] + " seconds", file=sys.stderr)
    sys.exit(124)
sys.exit(result.returncode)
PY
}
run_bounded 60 clang -fobjc-arc -include Cocoa/Cocoa.h -include CoreServices/CoreServices.h \
  -framework Cocoa -framework CoreServices \
  -I "$repo_root/MacDown/Code/View" \
  -I "$repo_root/MacDown/Code/Extension" \
  -I "$repo_root/MacDown/Code/Utility" \
  "$repo_root/MacDownTests/UI/EditorGeometryRegression.m" \
  "$editor_source" \
  "$repo_root/MacDown/Code/Extension/NSPasteboard+Types.m" \
  "$repo_root/MacDown/Code/Utility/FileURLInlining.m" \
  -o "$test_dir/editor-geometry-regression"
run_bounded 30 "$test_dir/editor-geometry-regression"
