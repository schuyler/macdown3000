# PDF Export Test Files for Issue #28

These test files help verify the code block overflow fix in PDF exports.

## Quick Start

1. **Open MacDown** (with your changes applied)
2. **Open any test file** from this directory
3. **Try different themes**: GitHub, GitHub 2, Solarized Light/Dark, Clearness, Clearness Dark
4. **Export to PDF**: File → Print → Save as PDF (or Command+P)
5. **Verify the results** match the expected behaviors

## Test Files

### 00-comprehensive-test.md
**Recommended for quick testing**
- Combines all test scenarios in one file
- Good for testing all themes quickly
- Covers all major edge cases

### 01-long-single-line.md
Tests a single very long code line that would normally overflow.

### 02-multiple-long-lines.md
Tests Python code with multiple long lines and proper indentation.

### 03-inline-code.md
Tests inline code elements within paragraphs and long URLs.

### 04-mixed-content-tables.md
Tests tables with long code in cells and code blocks after tables.

### 05-edge-cases.md
Tests worst-case scenarios:
- Very long URLs
- Code without spaces
- Mixed tabs/spaces
- Empty code blocks
- Repeated characters

## What to Look For

### ✅ Success Indicators
- [ ] No text is cut off or hidden
- [ ] No horizontal scrollbars in the PDF
- [ ] Wrapping occurs at reasonable points (spaces, hyphens when possible)
- [ ] Monospace font preserved for code
- [ ] Syntax highlighting still works (if applicable)
- [ ] Background colors for code blocks look correct
- [ ] Overall document layout is professional
- [ ] No CSS artifacts or rendering glitches

### ❌ Problems to Watch For
- Text cut off at page edge
- Horizontal overflow
- Code breaking mid-word at random positions
- Lost indentation
- Layout breakage
- Missing content

## Testing Each Theme

Test at least the comprehensive file (`00-comprehensive-test.md`) with all 6 themes:

1. **GitHub** - Classic GitHub styling
2. **GitHub 2** - Enhanced GitHub styling
3. **Clearness** - Light minimalist theme
4. **Clearness Dark** - Dark minimalist theme
5. **Solarized (Light)** - Solarized light palette
6. **Solarized (Dark)** - Solarized dark palette

## Estimated Time

- **Quick test** (comprehensive file + 2-3 themes): 10-15 minutes
- **Thorough test** (all files + all themes): 30-45 minutes

## Expected Results

With the fix applied:
- Long code lines **wrap** to multiple lines
- All content is **visible and readable**
- Wrapping respects **word boundaries** when possible
- For text without spaces, breaks at **container edge** (uses `overflow-wrap: break-word`)
- **No horizontal overflow** in any scenario

## Comparison

If you want to compare before/after:
1. Checkout the commit **before** the fix
2. Export a test file to PDF
3. Checkout the commit **with** the fix (current)
4. Export the same file to PDF
5. Compare the two PDFs side-by-side

The "before" PDF should have cut-off text, while the "after" PDF should have wrapped text.
