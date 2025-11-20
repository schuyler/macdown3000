#!/bin/bash
#
# regenerate-golden-files.sh
#
# Regenerates golden HTML files for markdown rendering tests.
# This script automates the process of enabling regeneration mode,
# running tests, copying files back to source, and verifying.
#
# Usage: ./scripts/regenerate-golden-files.sh [scheme-name]
#
# If scheme-name is not provided, it will try to detect it automatically.

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project configuration
PROJECT_NAME="MacDown 3000.xcodeproj"
SCHEME_NAME="${1:-}"
TEST_FILES=(
    "MacDownTests/MPMarkdownRenderingTests.m"
    "MacDownTests/MPSyntaxHighlightingTests.m"
    "MacDownTests/MPMathJaxRenderingTests.m"
)
REGENERATE_DEFINE="#define REGENERATE_GOLDEN_FILES"
COMMENT_DEFINE="// #define REGENERATE_GOLDEN_FILES"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Golden File Regeneration Script${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Find the project root (where .xcodeproj is)
if [ ! -d "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: $PROJECT_NAME not found in current directory${NC}"
    echo "Please run this script from the repository root"
    exit 1
fi

# Auto-detect scheme if not provided
if [ -z "$SCHEME_NAME" ]; then
    echo -e "${YELLOW}No scheme specified, detecting available schemes...${NC}"
    SCHEMES=$(xcodebuild -project "$PROJECT_NAME" -list | grep -A 100 "Schemes:" | tail -n +2 | grep -v "^$" | sed 's/^[[:space:]]*//')

    # Try to find a scheme that looks like the main app
    SCHEME_NAME=$(echo "$SCHEMES" | grep -i "macdown" | head -1 | xargs)

    if [ -z "$SCHEME_NAME" ]; then
        echo -e "${RED}Could not auto-detect scheme. Available schemes:${NC}"
        echo "$SCHEMES"
        echo ""
        echo "Usage: $0 <scheme-name>"
        exit 1
    fi

    echo -e "${GREEN}Using scheme: $SCHEME_NAME${NC}"
fi

# Step 1: Enable regeneration mode
echo ""
echo -e "${BLUE}Step 1: Enabling regeneration mode...${NC}"
for file in "${TEST_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: $file not found${NC}"
        exit 1
    fi

    # Uncomment the define
    sed -i.bak "s|$COMMENT_DEFINE|$REGENERATE_DEFINE|g" "$file"
    rm "${file}.bak"
    echo -e "${GREEN}  ✓ Enabled in $file${NC}"
done

# Step 2: Run tests to regenerate files
echo ""
echo -e "${BLUE}Step 2: Running tests to regenerate golden files...${NC}"
echo -e "${YELLOW}(Tests will fail during regeneration - this is expected)${NC}"
echo ""

set +e  # Don't exit on test failure
xcodebuild test \
    -project "$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -destination 'platform=macOS' \
    2>&1 | tee /tmp/xcodebuild-regen.log

TEST_EXIT_CODE=$?
set -e

# Check if regeneration messages appear in output
if grep -q "Regenerated golden file:" /tmp/xcodebuild-regen.log; then
    echo -e "${GREEN}✓ Golden files regenerated successfully${NC}"
else
    echo -e "${RED}Warning: No 'Regenerated golden file' messages found in output${NC}"
    echo -e "${YELLOW}Check /tmp/xcodebuild-regen.log for details${NC}"
fi

# Step 3: Find and copy regenerated files
echo ""
echo -e "${BLUE}Step 3: Copying regenerated files to source directory...${NC}"

# Find the DerivedData path from the build log
DERIVED_DATA_PATH=$(grep -o "/Users/.*/DerivedData/[^/]*/Build/Products/Debug/MacDown 3000.app" /tmp/xcodebuild-regen.log | head -1)

if [ -z "$DERIVED_DATA_PATH" ]; then
    # Try default DerivedData location
    DERIVED_DATA_BASE="$HOME/Library/Developer/Xcode/DerivedData"
    DERIVED_DATA_PATH=$(find "$DERIVED_DATA_BASE" -name "MacDown 3000.app" -type d -path "*/Debug/*" | head -1)
fi

if [ -z "$DERIVED_DATA_PATH" ]; then
    echo -e "${RED}Error: Could not locate built app in DerivedData${NC}"
    echo -e "${YELLOW}Please manually copy files from:${NC}"
    echo "  ~/Library/Developer/Xcode/DerivedData/.../Debug/MacDown 3000.app/Contents/PlugIns/MacDownTests.xctest/Contents/Resources/Fixtures/"
    echo -e "${YELLOW}To:${NC}"
    echo "  MacDownTests/Fixtures/"
    exit 1
fi

FIXTURE_SOURCE="${DERIVED_DATA_PATH}/Contents/PlugIns/MacDownTests.xctest/Contents/Resources/Fixtures"
FIXTURE_DEST="MacDownTests/Fixtures"

if [ ! -d "$FIXTURE_SOURCE" ]; then
    echo -e "${RED}Error: Source fixtures directory not found: $FIXTURE_SOURCE${NC}"
    exit 1
fi

# Copy HTML files
HTML_COUNT=$(find "$FIXTURE_SOURCE" -name "*.html" | wc -l | xargs)
cp "${FIXTURE_SOURCE}/"*.html "$FIXTURE_DEST/"
echo -e "${GREEN}  ✓ Copied $HTML_COUNT HTML files${NC}"

# Step 4: Disable regeneration mode
echo ""
echo -e "${BLUE}Step 4: Disabling regeneration mode...${NC}"
for file in "${TEST_FILES[@]}"; do
    sed -i.bak "s|$REGENERATE_DEFINE|$COMMENT_DEFINE|g" "$file"
    rm "${file}.bak"
    echo -e "${GREEN}  ✓ Disabled in $file${NC}"
done

# Step 5: Run tests again to verify
echo ""
echo -e "${BLUE}Step 5: Running tests to verify golden files...${NC}"
echo ""

xcodebuild test \
    -project "$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -destination 'platform=macOS' \
    2>&1 | tee /tmp/xcodebuild-verify.log

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo -e "${GREEN}======================================${NC}"
else
    echo ""
    echo -e "${RED}======================================${NC}"
    echo -e "${RED}✗ Tests failed${NC}"
    echo -e "${RED}======================================${NC}"
    echo -e "${YELLOW}Check /tmp/xcodebuild-verify.log for details${NC}"
    exit 1
fi

# Step 6: Show git status
echo ""
echo -e "${BLUE}Step 6: Checking git status...${NC}"
echo ""
git status MacDownTests/Fixtures/

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Regeneration complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review the changes: git diff MacDownTests/Fixtures/"
echo "  2. Commit the changes: git add MacDownTests/Fixtures/*.html"
echo "  3. Create commit: git commit -m 'Regenerate golden HTML files'"
echo "  4. Push to remote: git push"
echo ""
