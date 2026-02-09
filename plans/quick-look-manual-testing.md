# Quick Look Extension Manual Testing Plan

**Issue:** #284
**Component:** MacDownQuickLook.appex
**Tester:** _______________
**Date:** _______________
**MacDown Version:** _______________
**macOS Version:** _______________

---

## Prerequisites

Before testing, ensure:
- [ ] MacDown 3000 is installed in `/Applications`
- [ ] The app has been launched at least once (to register the Quick Look extension)
- [ ] System Preferences > Extensions > Quick Look shows "MacDown Quick Look" enabled

---

## 1. Installation Verification Tests

### 1.1 Extension Registration
- [ ] Open System Preferences > Extensions > Quick Look
- [ ] Verify "MacDown Quick Look" appears in the list
- [ ] Verify the extension checkbox is enabled
- [ ] If disabled, enable it and verify it stays enabled after closing System Preferences

### 1.2 Bundle Verification
- [ ] Navigate to `/Applications/MacDown 3000.app/Contents/PlugIns/`
- [ ] Verify `MacDownQuickLook.appex` exists
- [ ] Right-click > Show Package Contents > Contents
- [ ] Verify `Info.plist` exists and lists supported extensions

### 1.3 Extension Activation
- [ ] Run: `pluginkit -m -v -p com.apple.quicklook.preview | grep -i macdown`
- [ ] Verify MacDownQuickLook appears in the output
- [ ] If not listed, try: `qlmanage -r` to reset Quick Look, then recheck

---

## 2. Basic Functionality Tests

### 2.1 Quick Look Preview (Spacebar)
- [ ] Select a `.md` file in Finder
- [ ] Press Spacebar to invoke Quick Look
- [ ] **EXPECTED:** Preview window opens showing rendered markdown (not raw text)
- [ ] Verify the preview uses a styled appearance (not plain HTML)
- [ ] Close the preview (press Spacebar or Esc)

### 2.2 Finder Column View Preview
- [ ] Open Finder in Column View (Cmd+3)
- [ ] Navigate to a folder containing `.md` files
- [ ] Select a markdown file
- [ ] **EXPECTED:** Preview pane on the right shows rendered markdown

### 2.3 Finder Gallery View Preview
- [ ] Open Finder in Gallery View (Cmd+4)
- [ ] Navigate to a folder containing `.md` files
- [ ] Select a markdown file
- [ ] **EXPECTED:** Large preview area shows rendered markdown

### 2.4 Multiple File Quick Look
- [ ] Select multiple `.md` files in Finder (Cmd+click)
- [ ] Press Spacebar
- [ ] **EXPECTED:** Quick Look opens with navigation arrows
- [ ] Use arrow keys to cycle through files
- [ ] **EXPECTED:** Each file renders correctly as you navigate

---

## 3. File Extension Coverage Tests

Test each supported file extension. For each extension:
1. Create a test file with that extension
2. Add basic markdown content: `# Test\n\nHello **world**`
3. Select in Finder and press Spacebar
4. Verify rendered output shows styled heading and bold text

### 3.1 Standard Extensions
- [ ] `.md` - Standard markdown
- [ ] `.markdown` - Full name extension
- [ ] `.mdown` - Alternate extension
- [ ] `.mkd` - Short alternate
- [ ] `.mkdn` - Another alternate

### 3.2 Extension Case Sensitivity
- [ ] `.MD` (uppercase) - Should work
- [ ] `.Markdown` (mixed case) - Should work
- [ ] `.MDOWN` (uppercase) - Should work

---

## 4. Markdown Rendering Tests

### 4.1 Headings
- [ ] H1 heading (`# Heading 1`) renders correctly
- [ ] H2 heading (`## Heading 2`) renders correctly
- [ ] H3 heading (`### Heading 3`) renders correctly
- [ ] H4 heading (`#### Heading 4`) renders correctly
- [ ] H5 heading (`##### Heading 5`) renders correctly
- [ ] H6 heading (`###### Heading 6`) renders correctly

### 4.2 Text Formatting
- [ ] **Bold** text (`**bold**` or `__bold__`) renders correctly
- [ ] *Italic* text (`*italic*` or `_italic_`) renders correctly
- [ ] ***Bold italic*** (`***text***`) renders correctly
- [ ] ~~Strikethrough~~ (`~~text~~`) renders correctly
- [ ] `Inline code` renders in monospace font

### 4.3 Lists
- [ ] Unordered list (`- item`) renders with bullets
- [ ] Ordered list (`1. item`) renders with numbers
- [ ] Nested lists render with proper indentation
- [ ] Mixed ordered/unordered nested lists work

### 4.4 Links and Images
- [ ] `[text](url)` links render as clickable
- [ ] `![alt](image.png)` images render (if image exists)
- [ ] Autolinked URLs (https://example.com) render as links

### 4.5 Blockquotes
- [ ] Single-line blockquote renders with styling
- [ ] Multi-line blockquote renders correctly
- [ ] Nested blockquotes render with proper indentation

### 4.6 Horizontal Rules
- [ ] `---` renders as horizontal line
- [ ] `***` renders as horizontal line
- [ ] `___` renders as horizontal line

### 4.7 Tables
- [ ] Simple table renders with borders/styling
- [ ] Table alignment (left, center, right) works
- [ ] Tables with many columns render correctly

| Left | Center | Right |
|:-----|:------:|------:|
| L    |   C    |     R |

### 4.8 Fenced Code Blocks
- [ ] Code block without language renders in monospace
- [ ] Code block with language hint shows language class

---

## 5. Syntax Highlighting Tests (Prism)

### 5.1 Common Languages
Test that syntax highlighting applies correctly for:

- [ ] Python (```python)
- [ ] JavaScript (```javascript or ```js)
- [ ] Objective-C (```objc)
- [ ] Swift (```swift)
- [ ] Bash/Shell (```bash or ```sh)
- [ ] JSON (```json)
- [ ] HTML (```html)
- [ ] CSS (```css)
- [ ] C (```c)
- [ ] C++ (```cpp)
- [ ] Ruby (```ruby)
- [ ] Go (```go)
- [ ] Rust (```rust)

### 5.2 Syntax Highlighting Quality
- [ ] Keywords are highlighted in a distinct color
- [ ] Strings are highlighted differently from keywords
- [ ] Comments are visually distinct
- [ ] Function names/calls are recognizable

---

## 6. Style/Preferences Tests

### 6.1 CSS Style Inheritance
- [ ] Open MacDown 3000 main app
- [ ] Change Preferences > Rendering > CSS to "GitHub2"
- [ ] Quit MacDown and preview a `.md` file
- [ ] **EXPECTED:** Quick Look uses GitHub2 styling
- [ ] Repeat with "Clearness" style
- [ ] Repeat with "Clearness Dark" style
- [ ] Repeat with custom user style (if available)

### 6.2 Syntax Highlighting Theme
- [ ] Change Preferences > Rendering > Highlight theme to "Tomorrow"
- [ ] Preview a file with code blocks
- [ ] **EXPECTED:** Code uses Tomorrow color scheme
- [ ] Change to "Okaidia" theme and verify
- [ ] Change to "Solarized Light" and verify

### 6.3 Syntax Highlighting Toggle
- [ ] Enable syntax highlighting in MacDown preferences
- [ ] Preview file with code - verify highlighting appears
- [ ] Disable syntax highlighting in MacDown preferences
- [ ] Preview same file - verify code is plain monospace (no colors)

### 6.4 Markdown Extension Settings
- [ ] Enable "Tables" extension - verify tables render
- [ ] Disable "Tables" extension - verify tables show as raw text
- [ ] Enable "Fenced code" - verify ``` blocks work
- [ ] Enable "Autolink" - verify bare URLs become links
- [ ] Enable "Strikethrough" - verify ~~text~~ works

---

## 7. Edge Case Tests

### 7.1 Empty and Minimal Files
- [ ] Empty file (0 bytes) - should show blank preview, no crash
- [ ] File with only whitespace - should show blank preview
- [ ] Single character file - should render that character
- [ ] File with only a heading - renders correctly

### 7.2 Large Files
- [ ] Preview a 100KB markdown file - renders without significant delay
- [ ] Preview a 500KB markdown file - renders (may have slight delay)
- [ ] Preview a 1MB markdown file - renders or shows graceful loading

### 7.3 Special Characters
- [ ] Unicode characters (emoji, CJK, etc.) render correctly
- [ ] Special HTML entities (`&amp;`, `&lt;`, `&gt;`) render correctly
- [ ] Markdown with HTML inline tags renders appropriately
- [ ] File with Windows line endings (CRLF) renders correctly
- [ ] File with classic Mac line endings (CR) renders correctly

### 7.4 File Path Edge Cases
- [ ] File in path with spaces: `/Users/test/My Documents/file.md`
- [ ] File in path with special chars: `/Users/test/a&b/file.md`
- [ ] File with Unicode name: `/Users/test/README-`
- [ ] File in deep nested path (10+ levels)
- [ ] File on external drive
- [ ] File on network share (SMB/AFP)

### 7.5 Encoding
- [ ] UTF-8 file renders correctly
- [ ] UTF-8 with BOM renders correctly
- [ ] File with mixed encodings (best effort rendering)

---

## 8. Excluded Features Tests (Negative)

These features should NOT work in Quick Look (by design):

### 8.1 MathJax (Mathematical Notation)
- [ ] Inline math `$x^2$` shows as literal text `$x^2$`
- [ ] Display math `$$\frac{a}{b}$$` shows as literal text
- [ ] **EXPECTED:** No rendered equations, just raw LaTeX

### 8.2 Mermaid Diagrams
- [ ] Mermaid code block renders as a code block (not a diagram)
```mermaid
graph TD
    A --> B
```
- [ ] **EXPECTED:** Shows code text, not flowchart

### 8.3 Graphviz/DOT
- [ ] DOT code block renders as a code block (not a graph)
```dot
digraph { A -> B }
```
- [ ] **EXPECTED:** Shows code text, not graph visualization

---

## 9. Negative Tests (What Shouldn't Happen)

### 9.1 Crash Resistance
- [ ] Malformed markdown (unclosed code blocks) - no crash
- [ ] Deeply nested lists (20+ levels) - no crash
- [ ] Extremely long single line (10,000+ chars) - no crash
- [ ] Binary file renamed to `.md` - no crash, shows garbled or error
- [ ] File with null bytes - no crash

### 9.2 Security
- [ ] JavaScript in markdown is NOT executed:
  ```html
  <script>alert('XSS')</script>
  ```
  - [ ] No alert dialog appears
- [ ] `onclick` handlers are not executed:
  ```html
  <a onclick="alert('XSS')">click</a>
  ```
  - [ ] Clicking does not show alert

### 9.3 Resource Isolation
- [ ] External CSS links in markdown are NOT loaded
- [ ] External JavaScript links are NOT loaded
- [ ] External images may load (expected behavior)

### 9.4 File Access
- [ ] Quick Look does NOT modify the source file
- [ ] Check file modification date before/after preview - should be unchanged

---

## 10. Performance Tests

### 10.1 Response Time
- [ ] Small file (<10KB): Preview appears in <1 second
- [ ] Medium file (10-100KB): Preview appears in <2 seconds
- [ ] Large file (>100KB): Preview appears in <5 seconds

### 10.2 Memory
- [ ] Preview multiple large files in sequence
- [ ] Activity Monitor shows reasonable memory usage
- [ ] No memory leaks after closing previews

### 10.3 Rapid Preview
- [ ] Quickly select different `.md` files in succession
- [ ] Each preview updates without delay or flickering
- [ ] No crashes during rapid file switching

---

## 11. Integration Tests

### 11.1 Quick Look + Spotlight
- [ ] Search for markdown file content in Spotlight
- [ ] Use Quick Look from Spotlight results
- [ ] Preview renders correctly

### 11.2 Quick Look + Finder Tags
- [ ] Preview markdown file with Finder tags
- [ ] Tags do not interfere with rendering

### 11.3 Quick Look + Time Machine
- [ ] Browse Time Machine backup
- [ ] Preview historical version of markdown file
- [ ] Renders correctly

---

## Test Results Summary

| Category | Pass | Fail | N/A | Notes |
|----------|------|------|-----|-------|
| 1. Installation | | | | |
| 2. Basic Functionality | | | | |
| 3. File Extensions | | | | |
| 4. Markdown Rendering | | | | |
| 5. Syntax Highlighting | | | | |
| 6. Style/Preferences | | | | |
| 7. Edge Cases | | | | |
| 8. Excluded Features | | | | |
| 9. Negative Tests | | | | |
| 10. Performance | | | | |
| 11. Integration | | | | |

---

## Issues Found

| # | Severity | Description | Steps to Reproduce |
|---|----------|-------------|-------------------|
| 1 | | | |
| 2 | | | |
| 3 | | | |

**Severity Levels:**
- **Critical:** Crash, data loss, security issue
- **Major:** Feature doesn't work, significant UX problem
- **Minor:** Cosmetic issue, minor inconvenience
- **Enhancement:** Suggestion for improvement

---

## Sign-off

- [ ] All critical and major issues resolved
- [ ] Testing complete

**Tester Signature:** _______________
**Date:** _______________
