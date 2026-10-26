#!/bin/bash
# Regenerate only the rendering golden fixtures, then verify them normally.
# Usage: scripts/regenerate-golden-files.sh [scheme-name]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
WORKSPACE="MacDown 3000.xcworkspace"
SCHEME_NAME="${1:-MacDown}"
TEST_FILES=(MacDownTests/MPMarkdownRenderingTests.m
            MacDownTests/MPSyntaxHighlightingTests.m
            MacDownTests/MPMathJaxRenderingTests.m)
TEST_TARGETS=(-only-testing:MacDownTests/MPMarkdownRenderingTests
              -only-testing:MacDownTests/MPSyntaxHighlightingTests
              -only-testing:MacDownTests/MPMathJaxRenderingTests)
[[ -d "$WORKSPACE" ]] || { echo "Workspace missing: $WORKSPACE" >&2; exit 1; }
# Preflight every file before changing any definition. Already-enabled mode
# requires an explicit review, because it cannot be restored unambiguously.
for file in "${TEST_FILES[@]}"; do
    [[ -f "$file" ]] && grep -q '^// #define REGENERATE_GOLDEN_FILES$' "$file" &&
        ! grep -q '^#define REGENERATE_GOLDEN_FILES$' "$file" || {
        echo "Expected disabled regeneration definition in $file" >&2; exit 1;
    }
done
RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/macdown-golden.XXXXXX")
CHANGED_FILES=()
CHANGED_COUNT=0
restore_definitions() {
    [[ "$CHANGED_COUNT" -gt 0 ]] || return 0
    for file in "${CHANGED_FILES[@]}"; do
        sed -i.bak 's|^#define REGENERATE_GOLDEN_FILES$|// #define REGENERATE_GOLDEN_FILES|' "$file"
        rm -f "$file.bak"
    done
    CHANGED_FILES=()
    CHANGED_COUNT=0
}
trap restore_definitions EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for file in "${TEST_FILES[@]}"; do
    CHANGED_FILES+=("$file")
    CHANGED_COUNT=$((CHANGED_COUNT + 1))
    sed -i.bak 's|^// #define REGENERATE_GOLDEN_FILES$|#define REGENERATE_GOLDEN_FILES|' "$file"
    rm -f "$file.bak"
done

echo "Regenerating fixtures; logs and build products: $RUN_DIR"
# XCTest deliberately fails golden assertions while writing new fixtures.
set +e
xcodebuild test -workspace "$WORKSPACE" -scheme "$SCHEME_NAME" \
    -destination 'platform=macOS' -derivedDataPath "$RUN_DIR/DerivedData" \
    "${TEST_TARGETS[@]}" 2>&1 | tee "$RUN_DIR/regenerate.log"
REGENERATE_STATUS=${PIPESTATUS[0]}
set -e
if ! grep -q 'Regenerated golden file:' "$RUN_DIR/regenerate.log"; then
    echo "No fixtures regenerated (xcodebuild status $REGENERATE_STATUS); see $RUN_DIR/regenerate.log" >&2
    exit 1
fi
FIXTURE_SOURCE="$RUN_DIR/DerivedData/Build/Products/Debug/MacDown 3000.app/Contents/PlugIns/MacDownTests.xctest/Contents/Resources/Fixtures"
[[ -d "$FIXTURE_SOURCE" ]] || { echo "Built fixtures missing: $FIXTURE_SOURCE" >&2; exit 1; }
shopt -s nullglob
HTML_FILES=("$FIXTURE_SOURCE/"*.html)
[[ ${#HTML_FILES[@]} -gt 0 ]] || { echo "No golden HTML files produced" >&2; exit 1; }
cp "${HTML_FILES[@]}" MacDownTests/Fixtures/
restore_definitions

# pipefail propagates test or build failure through tee; EXIT always restores
# source definitions even if an interrupted or failed build exits early.
xcodebuild test -workspace "$WORKSPACE" -scheme "$SCHEME_NAME" \
    -destination 'platform=macOS' -derivedDataPath "$RUN_DIR/DerivedData" \
    "${TEST_TARGETS[@]}" 2>&1 | tee "$RUN_DIR/verify.log"
echo "Golden fixtures regenerated and verified. Review: git diff MacDownTests/Fixtures/"
