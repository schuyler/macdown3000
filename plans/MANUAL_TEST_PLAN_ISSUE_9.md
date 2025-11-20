# Manual Testing Plan: Preview Pane Flickering Fix (Issue #9)

**Issue:** Preview pane flickers when typing/updating
**Fix:** Removed WebCache disabling code that forced WebKit to reload resources on every keystroke
**Branch:** claude/fix-preview-flickering-01NVyLcGHX2Fta677PTVckzg
**Commit:** d54c20a

---

## Pre-Testing Setup

### Build and Launch
1. Open `MacDown 3000.xcworkspace` in Xcode
2. Build the project (Cmd+B)
3. Run the application (Cmd+R)
4. Verify the application launches without errors

### Prepare Test Documents

Create the following test files in a dedicated test folder:

**1. Small Document** (`small.md` - ~50 lines)
```markdown
# Small Test Document

This is a basic Markdown document for testing.

## Features to Test
- Bullet points
- **Bold text**
- *Italic text*
- `inline code`

## Code Block
```javascript
function hello() {
    console.log("Hello, world!");
}
```

## Link
[MacDown](https://macdown.uranusjr.com/)

## Image
![Test Image](./test-image.png)
```

**2. Medium Document** (`medium.md` - ~300 lines)
- Copy the above content and repeat it 6 times
- Add various Markdown elements: tables, blockquotes, nested lists
- Include 5-10 images
- Add math equations if MathJax is enabled: `$E = mc^2$`

**3. Large Document** (`large.md` - 1000+ lines)
- Use an existing large Markdown file (documentation, book chapter, etc.)
- Or generate by repeating the medium document 4 times
- Include at least 20+ images
- Mix of all Markdown syntax types

**4. Images**
- Prepare 3 test images: `test-image.png`, `test-image-2.jpg`, `test-image-3.gif`
- Keep copies for replacement testing

---

## Test Scenarios

### Test 1: Basic Typing - No Flickering

**Objective:** Verify that normal typing does not cause preview flickering

**Steps:**
1. Open `small.md`
2. Ensure preview pane is visible (split view)
3. Position cursor at the end of a paragraph
4. Type a sentence slowly (1-2 characters per second)
5. Observe the preview pane during typing

**Expected Results:**
- Preview updates smoothly as you type
- NO visible flashing or flickering of the entire preview pane
- NO complete re-rendering of the page (images don't flash, styles don't reload)
- Text appears incrementally without the whole page disappearing and reappearing

**Pass/Fail:** [ ]

---

### Test 2: Rapid Typing

**Objective:** Verify smooth preview updates during fast typing

**Steps:**
1. Open `medium.md`
2. Scroll to the middle of the document
3. Type rapidly for 10-15 seconds (normal typing speed or faster)
4. Try typing: "The quick brown fox jumps over the lazy dog" as fast as possible
5. Observe the preview pane

**Expected Results:**
- Preview updates may lag slightly behind typing (acceptable)
- NO flickering or flashing of the preview pane
- Preview eventually catches up and displays all typed text correctly
- Scrolling position in preview remains stable

**Pass/Fail:** [ ]

---

### Test 3: Different Content Types

**Objective:** Verify no flickering when editing various Markdown elements

**For each content type below, make a small edit and observe the preview:**

#### 3a. Plain Text
- Edit a regular paragraph
- Expected: Smooth update, no flicker
- **Pass/Fail:** [ ]

#### 3b. Headers
- Change `## Header` to `### Header`
- Expected: Header resizes smoothly, no flicker
- **Pass/Fail:** [ ]

#### 3c. Bold/Italic
- Add/remove `**` or `*` around text
- Expected: Text style changes smoothly, no flicker
- **Pass/Fail:** [ ]

#### 3d. Code Blocks
- Edit code inside triple backticks
- Add/remove syntax highlighting (change language)
- Expected: Code updates with syntax highlighting, no flicker
- **Pass/Fail:** [ ]

#### 3e. Lists
- Add/remove bullet points
- Indent/unindent list items (change nesting level)
- Expected: List structure updates smoothly, no flicker
- **Pass/Fail:** [ ]

#### 3f. Links
- Edit link text or URL
- Expected: Link updates smoothly, no flicker
- **Pass/Fail:** [ ]

#### 3g. Images (Markdown syntax)
- Edit image alt text: `![New Alt Text](image.png)`
- Expected: Preview updates, no flicker
- Note: Image file changes are NOT expected to update (known regression)
- **Pass/Fail:** [ ]

#### 3h. Blockquotes
- Add/remove `>` prefix
- Edit text inside blockquote
- Expected: Blockquote style changes smoothly, no flicker
- **Pass/Fail:** [ ]

#### 3i. Tables
- Edit cell content
- Add/remove table rows
- Expected: Table updates smoothly, no flicker
- **Pass/Fail:** [ ]

#### 3j. Math Equations (if enabled)
- Edit LaTeX: `$E = mc^2$` to `$E = mc^3$`
- Expected: Equation re-renders, minimal flicker acceptable for MathJax rendering
- **Pass/Fail:** [ ]

---

### Test 4: Document Size Variations

**Objective:** Verify performance across different document sizes

#### 4a. Small Document (~50 lines)
1. Open `small.md`
2. Type continuously for 30 seconds in different locations
3. Observe preview responsiveness
- Expected: Instant updates, zero flicker
- **Pass/Fail:** [ ]

#### 4b. Medium Document (~300 lines)
1. Open `medium.md`
2. Type at the beginning, middle, and end of the document
3. Scroll while typing
- Expected: Smooth updates, no flicker, slight lag acceptable
- **Pass/Fail:** [ ]

#### 4c. Large Document (1000+ lines)
1. Open `large.md`
2. Type at various positions
3. Edit near images and complex elements
- Expected: Updates may be slower, but NO flickering
- Preview may lag 1-2 seconds behind typing (acceptable)
- **Pass/Fail:** [ ]

---

### Test 5: Rapid Editing Patterns

**Objective:** Test scenarios that might trigger flickering

#### 5a. Rapid Deletion
1. Select multiple paragraphs (100+ characters)
2. Press Delete
3. Observe preview
- Expected: Content disappears smoothly, no flicker
- **Pass/Fail:** [ ]

#### 5b. Copy/Paste Large Blocks
1. Copy 50+ lines of Markdown
2. Paste into document
3. Observe preview
- Expected: New content appears smoothly, no flicker
- **Pass/Fail:** [ ]

#### 5c. Find and Replace
1. Use Find/Replace (Cmd+F) to change a common word
2. Replace multiple instances
3. Observe preview during replacements
- Expected: Changes appear smoothly, no flicker
- **Pass/Fail:** [ ]

#### 5d. Undo/Redo Repeatedly
1. Make several edits
2. Press Cmd+Z (undo) repeatedly
3. Press Cmd+Shift+Z (redo) repeatedly
4. Observe preview
- Expected: Preview updates backward/forward smoothly, no flicker
- **Pass/Fail:** [ ]

---

### Test 6: Window and View Manipulation

**Objective:** Verify stable preview during window operations

#### 6a. Resize Window
1. Open any test document
2. Resize the window (drag corners/edges)
3. Observe preview during resize
- Expected: Preview resizes smoothly, no flicker
- **Pass/Fail:** [ ]

#### 6b. Adjust Split View Divider
1. Drag the divider between editor and preview
2. Move it rapidly back and forth
- Expected: Preview resizes smoothly, no content flicker
- **Pass/Fail:** [ ]

#### 6c. Toggle Preview Pane
1. Hide preview pane (menu or shortcut)
2. Show preview pane again
3. Repeat several times
- Expected: Preview appears/disappears smoothly, no flicker when visible
- **Pass/Fail:** [ ]

#### 6d. Full Screen Mode
1. Enter full screen (Cmd+Ctrl+F)
2. Type and edit
3. Exit full screen
- Expected: No flickering in full screen mode, smooth transitions
- **Pass/Fail:** [ ]

---

### Test 7: Scrolling Behavior

**Objective:** Verify preview scrolling is smooth during editing

#### 7a. Edit While Scrolled
1. Open `large.md`
2. Scroll preview to the middle
3. Scroll editor to the middle (different position from preview)
4. Start typing
- Expected: Preview scrolls to match editor position smoothly, no flicker
- **Pass/Fail:** [ ]

#### 7b. Continuous Scrolling
1. Open `medium.md`
2. Scroll through the preview pane continuously
3. While scrolling, make small edits in the editor
- Expected: Scrolling remains smooth, no flicker during scroll
- **Pass/Fail:** [ ]

---

### Test 8: Multiple Windows

**Objective:** Verify behavior with multiple documents open

**Steps:**
1. Open 3 different test documents in separate windows
2. Arrange windows side by side
3. Type in each window alternately
4. Observe each preview pane

**Expected Results:**
- Each preview updates independently
- No flickering in any window
- No cross-window interference

**Pass/Fail:** [ ]

---

### Test 9: Known Regression - Image File Changes

**Objective:** Verify and document the expected regression

**Setup:**
1. Create a document with an image: `![Test](./test-image.png)`
2. Ensure preview shows the image correctly

**Test Steps:**
1. While MacDown is running with the document open
2. Use Finder or terminal to replace `test-image.png` with a different image
3. Observe the preview pane

**Expected Results (REGRESSION - ACCEPTABLE):**
- The preview does NOT update to show the new image
- The old image remains cached
- NO flickering occurs (this is correct)
- User must reload/reopen document to see updated image

**Verification:**
- [ ] Image does NOT update when changed on disk (expected regression)
- [ ] No flickering occurs (correct behavior)
- [ ] Closing and reopening the document shows the new image (workaround works)

**Note:** This regression is acceptable as the previous implementation (reloading cache every keystroke) caused severe flickering. Users rarely change images while editing.

---

### Test 10: Edge Cases

#### 10a. Very Rapid Typing (Stress Test)
1. Open `small.md`
2. Type as fast as possible for 30 seconds
3. Include special characters: `**bold** _italic_ [link](url) ![image](path)`
- Expected: Preview may lag significantly, but NO flickering when it catches up
- **Pass/Fail:** [ ]

#### 10b. Typing While Preview Renders
1. Open `large.md` with many images
2. Immediately start typing before preview finishes loading
- Expected: No flickering, preview completes rendering smoothly
- **Pass/Fail:** [ ]

#### 10c. External File Changes
1. Open a document
2. Edit the file externally (another text editor)
3. Return to MacDown (should detect changes)
4. Reload the file
- Expected: Reload works smoothly, no flickering after reload
- **Pass/Fail:** [ ]

#### 10d. Special Characters and Emoji
1. Type special characters: `<>&"'`
2. Type emoji: 😀🎉✨
3. Observe preview rendering
- Expected: Characters render correctly, no flicker
- **Pass/Fail:** [ ]

---

## Success Criteria

The fix is successful if:

1. ✅ **ZERO preview pane flickering** during normal typing across all test scenarios
2. ✅ **Smooth preview updates** for all Markdown content types
3. ✅ **Acceptable performance** even with large documents (1000+ lines)
4. ✅ **Stable scrolling** and window manipulation
5. ✅ **Known regression is documented** and acceptable (images don't update from disk)

---

## Failure Criteria

Report as a bug if:

1. ❌ Preview pane flickers (entire pane flashes/blinks) during typing
2. ❌ Preview becomes completely unresponsive (freezes)
3. ❌ Application crashes during any test scenario
4. ❌ Preview shows incorrect/corrupted content
5. ❌ Preview fails to update at all (stuck on old content)

---

## Testing Checklist Summary

- [ ] Test 1: Basic Typing - No Flickering
- [ ] Test 2: Rapid Typing
- [ ] Test 3: Different Content Types (10 subtests)
- [ ] Test 4: Document Size Variations (3 sizes)
- [ ] Test 5: Rapid Editing Patterns (4 patterns)
- [ ] Test 6: Window and View Manipulation (4 scenarios)
- [ ] Test 7: Scrolling Behavior (2 scenarios)
- [ ] Test 8: Multiple Windows
- [ ] Test 9: Known Regression - Image File Changes
- [ ] Test 10: Edge Cases (4 cases)

**Total Test Cases:** 30+

---

## Notes for Tester

### What "No Flickering" Means

**BEFORE the fix (flickering):**
- The entire preview pane would flash white/blank
- Images would disappear and reappear on every keystroke
- Page would look like it's reloading completely
- Distracting white flash every time you type

**AFTER the fix (no flickering):**
- Preview updates smoothly and incrementally
- Only the changed content updates
- Images remain stable (don't flash)
- No white flashes or complete page reloads
- Like watching someone type in a word processor

### Performance Expectations

- **Small documents:** Instant, real-time updates
- **Medium documents:** Updates within 100-500ms
- **Large documents:** Updates may lag 1-2 seconds, but should eventually catch up
- **No flickering** is required even if updates are slow

### Recording Results

For each test:
1. Mark **Pass** if behavior matches expected results
2. Mark **Fail** if flickering occurs or behavior differs
3. Note any additional observations
4. Record system info if relevant (macOS version, hardware)

---

## Environment Information

**Please fill in during testing:**

- **macOS Version:** _______________
- **Hardware:** _______________
- **Build Date/Time:** _______________
- **Xcode Version:** _______________
- **Tester Name:** _______________
- **Test Date:** _______________

---

## Additional Testing Recommendations

1. **Performance Monitoring:**
   - Open Activity Monitor while testing
   - Check CPU usage during typing
   - Monitor memory usage with large documents

2. **Comparison Testing:**
   - If possible, test with the old version (before fix) to compare
   - Document the difference in user experience

3. **Real-World Usage:**
   - After formal testing, use MacDown normally for 1-2 hours
   - Write actual content (blog post, documentation, notes)
   - Report any flickering that occurs during real use

---

## Reporting Issues

If any test fails, please report:

1. **Test number and name**
2. **Steps to reproduce**
3. **Observed behavior** (describe the flickering)
4. **Expected behavior**
5. **Screenshots or video** (if possible, capture the flickering)
6. **Document size** when issue occurred
7. **System information**

---

**End of Manual Test Plan**
