# MacDown 3000 - Manual Testing Plan for Release 3000.0.4

This document provides a comprehensive manual testing plan for all changes since version 3000.0.3.

## Summary of Changes

| PR | Issue | Description |
|----|-------|-------------|
| #289 | #285 | Fix smart quote substitution causing unwanted characters |
| #288 | #282 | Fix editor jumping when typing at end of long documents |
| #286 | — | Fix new document windows opening at bottom-left |
| #280 | #277 | Fix Graphviz and Mermaid button positioning in Compilation Settings |
| #275 | #25 | Fix adjacent shortcut-style links not rendering correctly |

---

## Test Environment Setup

- **macOS Version:** 10.14 or later
- **Build:** Fresh build from the release branch
- **Clean State:** Consider testing with `defaults delete app.macdown.macdown3000` for window position tests

---

## 1. Smart Quote Substitution Fix (#289)

**Related Issue:** #285

### Setup
1. Launch MacDown 3000
2. Enable smart quotes: **Edit → Substitutions → Smart Quotes**
3. Create a new document

### Test Cases

| # | Scenario | Steps | Expected Result | Pass/Fail |
|---|----------|-------|-----------------|-----------|
| 1.1 | Basic smart quotes | Type `"hello"` | Opening (`"`) and closing (`"`) typographic quotes appear, no extra characters | ☐ |
| 1.2 | Undo behavior | Type `"test"`, then press Cmd+Z repeatedly | Clean undo with no character corruption | ☐ |
| 1.3 | Multiple quote pairs | Type `She said "hello" and "goodbye"` | All quote pairs render correctly | ☐ |
| 1.4 | Single quotes / apostrophes | Type `It's a 'test'` | Apostrophes and single quotes handled correctly | ☐ |
| 1.5 | Smart quotes OFF | Disable smart quotes, type `"` | Matching pair `""` inserted with cursor between | ☐ |
| 1.6 | Brackets still work | With smart quotes ON, type `(`, `[`, `{` | Matching pairs still inserted correctly | ☐ |
| 1.7 | Quote at document start | Start new document, immediately type `"` | Works correctly, no extra characters | ☐ |
| 1.8 | Quote at end of line | Type text, then `"` at end | Works correctly | ☐ |
| 1.9 | Rapid quote typing | Quickly type `"""` multiple times | No corruption or crashes | ☐ |

---

## 2. Editor Jumping Fix (#288)

**Related Issue:** #282

### Setup
1. Create or open a document with 100+ headers (or any long document)
2. Scroll to the very end of the document

### Test Cases

| # | Scenario | Steps | Expected Result | Pass/Fail |
|---|----------|-------|-----------------|-----------|
| 2.1 | Typing at end of long document | Scroll to end, type rapidly for 10+ seconds | Editor does NOT jump; cursor stays at end; preview syncs after ~200ms pause | ☐ |
| 2.2 | Continuous typing | Type continuously for 5-10 seconds in a long document | No scroll sync during typing; smooth sync after stopping | ☐ |
| 2.3 | Document close during editing | Start typing rapidly, then immediately close with Cmd+W (within 200ms) | No crash; document closes cleanly | ☐ |
| 2.4 | Live scroll still works | Drag the editor scrollbar rapidly up and down | Preview follows editor scroll position normally | ☐ |
| 2.5 | Scroll sync disabled | Disable scroll sync in **Preferences → Editor**, then type in long document | No behavioral changes, no errors | ☐ |
| 2.6 | Rapid typing then scrolling | Type rapidly, then immediately scroll | Transitions smoothly, no jumping | ☐ |
| 2.7 | Copy-paste at document end | Copy large text block, paste at end | No jumping, preview syncs after paste | ☐ |
| 2.8 | Find/Replace operations | Use Find & Replace in a long document | No jumping during replacements | ☐ |
| 2.9 | Undo/Redo operations | Type, then Cmd+Z and Cmd+Shift+Z | No unexpected jumping | ☐ |
| 2.10 | Multiple documents | Open 3+ long documents, type in each | Each document behaves correctly | ☐ |

---

## 3. Window Position Fix (#286)

### Setup
1. Clear saved window positions (optional for full test):
   ```bash
   defaults delete app.macdown.macdown3000 "NSWindow Frame Untitled"
   ```

### Test Cases

| # | Scenario | Steps | Expected Result | Pass/Fail |
|---|----------|-------|-----------------|-----------|
| 3.1 | New document after clearing defaults | Run the defaults delete command above, create new document | Window opens centered on screen (not bottom-left) | ☐ |
| 3.2 | Existing document restoration | Open a saved document, move window, close, reopen | Window restores to last saved position | ☐ |
| 3.3 | New document position memory | Create new document, move window to corner, close, create another new document | Window opens at the remembered position | ☐ |
| 3.4 | Multiple monitors | Connect external monitor, test new document creation | Window centers on appropriate screen | ☐ |
| 3.5 | First launch experience | Fresh install or cleared preferences | First new document is centered, not bottom-left | ☐ |

---

## 4. Compilation Settings Button Positioning (#280)

**Related Issue:** #277

### Setup
1. Open **MacDown → Preferences** (or **Settings**)
2. Navigate to the **Markdown** tab
3. Click **Compilation Settings** button to open HTML Preferences window

### Test Cases

| # | Scenario | Steps | Expected Result | Pass/Fail |
|---|----------|-------|-----------------|-----------|
| 4.1 | Normal state | Open Compilation Settings | "Show line numbers", "Graphviz", and "Mermaid" checkboxes visible in a row with ~8pt spacing | ☐ |
| 4.2 | Vertical alignment | Inspect the three checkboxes | All three are vertically centered on the same line | ☐ |
| 4.3 | Window resize - smaller | Drag window edge to make it narrower | Buttons maintain relative positions, no jumping or snapping | ☐ |
| 4.4 | Window resize - larger | Drag window edge to make it wider | Buttons expand/shift appropriately | ☐ |
| 4.5 | Checkbox functionality | Click each checkbox to toggle | Layout remains correct after toggling | ☐ |
| 4.6 | Enable/disable binding | Uncheck "Syntax highlighted code block" | All three buttons become disabled; layout doesn't break | ☐ |
| 4.7 | Re-enable binding | Check "Syntax highlighted code block" again | All three buttons become enabled; layout intact | ☐ |
| 4.8 | Minimum window size | Resize window to minimum allowed | Buttons remain visible and properly positioned | ☐ |
| 4.9 | Maximum window size | Resize window to maximum/fullscreen | Buttons don't have excessive gaps | ☐ |

---

## 5. Adjacent Shortcut-Style Links Fix (#275)

**Related Issue:** #25

### Setup
1. Create a new document in MacDown

### Test Cases

| # | Scenario | Steps | Expected Result | Pass/Fail |
|---|----------|-------|-----------------|-----------|
| 5.1 | Adjacent shortcut links | Enter the markdown below and check preview | Both `[foo]` and `[bar]` render as clickable links | ☐ |
| 5.2 | Reference-style links still work | Test `[text][ref]` syntax | Reference links render correctly | ☐ |
| 5.3 | Mixed link styles | Combine shortcut, reference, and inline links | All link types render correctly | ☐ |
| 5.4 | Images not affected | Test `![alt][ref]` image syntax | Images render correctly | ☐ |

**Test Markdown for 5.1:**
```markdown
[foo] [bar][baz]

[foo]: https://example.com/foo
[bar]: https://example.com/bar
[baz]: https://example.com/baz
```

**Test Markdown for 5.2-5.4:**
```markdown
This is a [reference link][ref] and a [shortcut link] and an [inline link](https://example.com).

Here's an image: ![Alt text][img]

[ref]: https://example.com/ref
[shortcut link]: https://example.com/shortcut
[img]: https://example.com/image.png
```

---

## 6. Regression Testing

Verify that existing functionality still works correctly.

### General Editor Operations

| # | Scenario | Steps | Expected Result | Pass/Fail |
|---|----------|-------|-----------------|-----------|
| 6.1 | Open existing document | File → Open, select a .md file | Document opens and renders correctly | ☐ |
| 6.2 | Save document | Create new doc, add content, Cmd+S | File saves successfully | ☐ |
| 6.3 | Export to HTML | File → Export → HTML | HTML file exports correctly | ☐ |
| 6.4 | Export to PDF | File → Export → PDF | PDF file exports correctly | ☐ |
| 6.5 | Print | File → Print | Print dialog works, preview correct | ☐ |

### Markdown Rendering

| # | Scenario | Steps | Expected Result | Pass/Fail |
|---|----------|-------|-----------------|-----------|
| 6.6 | Headers | Type `# H1` through `###### H6` | All header levels render | ☐ |
| 6.7 | Bold/Italic | Type `**bold**` and `*italic*` | Formatting renders correctly | ☐ |
| 6.8 | Code blocks | Type fenced code block with language | Syntax highlighting works | ☐ |
| 6.9 | Lists | Create ordered and unordered lists | Lists render correctly | ☐ |
| 6.10 | Tables | Create a markdown table | Table renders correctly | ☐ |
| 6.11 | Block quotes | Type `> quote text` | Block quote renders | ☐ |
| 6.12 | Horizontal rules | Type `---` or `***` | Horizontal rule appears | ☐ |

### Preferences

| # | Scenario | Steps | Expected Result | Pass/Fail |
|---|----------|-------|-----------------|-----------|
| 6.13 | Preferences window | Open Preferences, navigate all tabs | All tabs load without errors | ☐ |
| 6.14 | Theme changes | Change editor theme | Theme applies immediately | ☐ |
| 6.15 | Font changes | Change editor font/size | Font applies correctly | ☐ |

---

## Test Completion Checklist

- [ ] All Section 1 tests passed (Smart Quote Fix)
- [ ] All Section 2 tests passed (Editor Jumping Fix)
- [ ] All Section 3 tests passed (Window Position Fix)
- [ ] All Section 4 tests passed (Compilation Settings Fix)
- [ ] All Section 5 tests passed (Adjacent Links Fix)
- [ ] All Section 6 regression tests passed

**Tested By:** _________________________

**Date:** _________________________

**Build Version:** _________________________

**macOS Version:** _________________________

**Notes:**
