#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/macdown-plural-rules.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
run_bounded() {
  python3 - "$@" <<'PYTHON'
import subprocess
import sys
try:
    result = subprocess.run(sys.argv[2:], timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    print("FAIL plural rule command exceeded " + sys.argv[1] + " seconds", file=sys.stderr)
    sys.exit(124)
sys.exit(result.returncode)
PYTHON
}
run_bounded 60 clang -fobjc-arc -framework Foundation \
  -I "$repo_root/Pods/JJPluralForm/JJPluralForm" \
  "$repo_root/MacDownTests/Localization/PluralRuleRegression.m" \
  "$repo_root/Pods/JJPluralForm/JJPluralForm/JJPluralForm.m" \
  -o "$test_dir/plural-rules"
run_bounded 30 "$test_dir/plural-rules" "${1:-$repo_root/MacDown/Localization}"
