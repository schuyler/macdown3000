# Golden File Regeneration Checklist

**Branch:** `claude/resolve-issue-58-015pvzomykZejWB2WZYkUWpQ`
**Pull Request:** #152
**Related Issue:** #58

## Overview

The test implementation for issue #58 includes placeholder golden HTML files. These need to be regenerated on macOS to capture the actual renderer output from MPRenderer.

## Prerequisites

- macOS machine (10.14+)
- Xcode installed
- Repository cloned locally

## Quick Start (Automated)

**Recommended method using the automated script:**

```bash
# 1. Check out the branch
git fetch origin
git checkout claude/resolve-issue-58-015pvzomykZejWB2WZYkUWpQ

# 2. Run the regeneration script
./scripts/regenerate-golden-files.sh

# The script will automatically:
# - Enable regeneration mode
# - Run tests to generate files
# - Copy files from DerivedData to source
# - Disable regeneration mode
# - Verify tests pass
# - Show git status

# 3. Review and commit the changes
git diff MacDownTests/Fixtures/
git add MacDownTests/Fixtures/*.html
git commit -m "Regenerate golden HTML files with actual renderer output"
git push origin claude/resolve-issue-58-015pvzomykZejWB2WZYkUWpQ
```

**Note:** If you need to specify a custom scheme name, pass it as an argument:
```bash
./scripts/regenerate-golden-files.sh "YourSchemeName"
```

## Step-by-Step Instructions (Manual Method)

If you prefer to do it manually or the script doesn't work for your setup:

### 1. Check Out the Branch

```bash
git fetch origin
git checkout claude/resolve-issue-58-015pvzomykZejWB2WZYkUWpQ
```

### 2. Enable Golden File Regeneration Mode

Edit the following three test files and **uncomment** line ~15:

**Files to edit:**
- `MacDownTests/MPMarkdownRenderingTests.m` (line 15)
- `MacDownTests/MPSyntaxHighlightingTests.m` (line 14)
- `MacDownTests/MPMathJaxRenderingTests.m` (line 15)

**Change from:**
```objective-c
// #define REGENERATE_GOLDEN_FILES
```

**To:**
```objective-c
#define REGENERATE_GOLDEN_FILES
```

### 3. Run the Tests

This will execute all tests and write the actual renderer output to the golden HTML files:

```bash
xcodebuild test -scheme "MacDown 3000" -destination 'platform=macOS'
```

**Expected output:**
- Tests will run and generate HTML files
- Console will show messages like: `"Regenerated golden file: basic.html"`
- All golden files in `MacDownTests/Fixtures/*.html` will be updated

### 4. Disable Regeneration Mode

Edit the same three test files and **re-comment** the regeneration flag:

**Change back to:**
```objective-c
// #define REGENERATE_GOLDEN_FILES
```

This ensures future test runs will compare against the golden files instead of regenerating them.

### 5. Review the Changes

Verify that the golden files were updated:

```bash
git status
```

You should see modifications to:
```
MacDownTests/Fixtures/autolinks.html
MacDownTests/Fixtures/basic.html
MacDownTests/Fixtures/blockquotes.html
MacDownTests/Fixtures/code-fenced.html
MacDownTests/Fixtures/code-inline.html
MacDownTests/Fixtures/code-languages.html
MacDownTests/Fixtures/edge-cases.html
MacDownTests/Fixtures/emphasis.html
MacDownTests/Fixtures/horizontal-rules.html
MacDownTests/Fixtures/images.html
MacDownTests/Fixtures/links.html
MacDownTests/Fixtures/lists-nested.html
MacDownTests/Fixtures/lists-ordered.html
MacDownTests/Fixtures/lists-unordered.html
MacDownTests/Fixtures/mathjax-in-code.html
MacDownTests/Fixtures/mathjax-syntax.html
MacDownTests/Fixtures/mixed-complex.html
MacDownTests/Fixtures/regression-issue34.html
MacDownTests/Fixtures/regression-issue36.html
MacDownTests/Fixtures/regression-issue37.html
MacDownTests/Fixtures/strikethrough.html
MacDownTests/Fixtures/syntax-highlighting-aliases.html
MacDownTests/Fixtures/syntax-highlighting-languages.html
MacDownTests/Fixtures/syntax-highlighting-mixed.html
MacDownTests/Fixtures/tables.html
MacDownTests/Fixtures/task-lists.html
MacDownTests/Fixtures/unicode.html
```

**Optional:** Review a few HTML files to ensure they look correct:

```bash
# Example: Check the unicode output
cat MacDownTests/Fixtures/unicode.html
```

### 6. Run Tests Again (Verification)

With the regeneration flag disabled, run tests again to verify they pass:

```bash
xcodebuild test -scheme "MacDown 3000" -destination 'platform=macOS'
```

**Expected result:** All tests should now pass ✅

### 7. Commit the Updated Golden Files

```bash
git add MacDownTests/Fixtures/*.html
git commit -m "Regenerate golden HTML files with actual renderer output"
```

### 8. Push to GitHub

```bash
git push origin claude/resolve-issue-58-015pvzomykZejWB2WZYkUWpQ
```

This will trigger GitHub Actions CI to run again with the actual golden files.

## Verification

After pushing:

1. Check the PR: https://github.com/schuyler/macdown3000/pull/152
2. Monitor GitHub Actions: https://github.com/schuyler/macdown3000/actions
3. Verify all tests pass in CI ✅

## Troubleshooting

### Tests fail after regeneration

**Possible causes:**
- Regeneration flag still uncommented (check all 3 files)
- Golden files not committed
- Xcode project cache issues

**Solutions:**
```bash
# Clear Xcode build cache
rm -rf ~/Library/Developer/Xcode/DerivedData/MacDown*

# Verify regeneration flag is commented
grep -n "REGENERATE_GOLDEN_FILES" MacDownTests/MP*.m
```

### Golden files not in source directory (Manual method)

**Important:** When using the manual method, golden files are written to DerivedData, not the source directory. You must copy them back:

```bash
# Find the generated files in DerivedData
find ~/Library/Developer/Xcode/DerivedData -name "*.html" -path "*/MacDownTests.xctest/Contents/Resources/Fixtures/*" -mmin -10

# Copy them to source (adjust path as needed)
cp ~/Library/Developer/Xcode/DerivedData/MacDown_3000-*/Build/Products/Debug/MacDown\ 3000.app/Contents/PlugIns/MacDownTests.xctest/Contents/Resources/Fixtures/*.html \
   MacDownTests/Fixtures/
```

**This is handled automatically by the script.**

### Some golden files not updated

**Check that tests actually ran:**
```bash
# Look for test execution in output
xcodebuild test -scheme "MacDown 3000" -destination 'platform=macOS' | grep "Test Case"
```

## Cleanup

After successful verification, this checklist can remain in the repository as documentation for future golden file updates.

---

**Status:** ✅ Completed (2025-11-20)
**Last Updated:** 2025-11-20
