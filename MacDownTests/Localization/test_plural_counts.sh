#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/macdown-plural.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
clang -fobjc-arc -framework Foundation \
  -I "$repo_root/Pods/JJPluralForm/JJPluralForm" \
  "$repo_root/MacDownTests/Localization/PluralCountRegression.m" \
  "$repo_root/Pods/JJPluralForm/JJPluralForm/JJPluralForm.m" \
  -o "$test_dir/plural-count-regression"
"$test_dir/plural-count-regression" "$repo_root/MacDown/Localization"
