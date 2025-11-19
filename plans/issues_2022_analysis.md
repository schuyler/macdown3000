# MacDown Open Issues Analysis (2022-Present)

Comprehensive analysis of all open issues from the MacDownApp/macdown repository since January 2022, identifying legitimate bugs and valuable features worth implementing in macdown3000.

**Total Issues Reviewed:** 35 (from 2022-2025)
**Date Range:** January 2022 - November 2025

---

## CRITICAL PRIORITY - Must Fix/Implement

### 1. Issue #1348 / #1331 - Native Apple Silicon Support ⚠️ CRITICAL
**Created:** June 2025 / December 2023
**Comments:** 7 / 3
**Status:** DUPLICATE ISSUES

**Problem:** MacDown is Intel-only and requires Rosetta 2. Apple announced macOS 27 (Tahoe) will be the last version to support Rosetta 2, and it will be the last release for Intel Macs.

**Impact:** Without native Apple Silicon support, MacDown will become unusable on future macOS versions.

**Recommendation:** ✅ **HIGHEST PRIORITY**
- This is an existential issue for the application
- Already addressed in macdown3000 with PR #4
- Verify complete Apple Silicon compatibility
- **Action:** Ensure our existing Apple Silicon support is comprehensive

---

### 2. Issue #1356 / #1334 - "Open Recent" List Empty/Broken
**Created:** November 2025 / January 2024
**Comments:** 0 / 13
**Status:** DUPLICATE ISSUES, macOS Sonoma compatibility

**Problem:** "Open Recent" menu appears blank or shows broken entries that generate errors. Root cause: newer macOS versions require specific permission keys in Info.plist (NSDocumentsFolderUsageDescription, NSDownloadsFolderUsageDescription, NSDesktopFolderUsageDescription). Without these, the app can't access folders to populate recent files.

**Impact:** Core macOS functionality broken for all Sonoma users.

**Recommendation:** ✅ **CRITICAL - CLONE AS ISSUE**
- Clear diagnosis with known fix
- Affects all macOS Sonoma+ users
- Simple implementation (add Info.plist keys)
- **Issue Title:** "Fix Open Recent menu on macOS Sonoma (add required permissions)"

---

## HIGH PRIORITY - Legitimate Bugs

### 3. Issue #1350 - Code Text Wrapping in PDF Export
**Created:** August 2025
**Comments:** 1

**Problem:** Code renderings don't wrap text; content gets cut off when exported to PDF.

**Recommendation:** ✅ **ALREADY CLONED as Issue #28**
- Duplicate of PR #1349 functionality
- Already in our backlog

---

### 4. Issue #1346 - LaTeX Double Dollar Sign ($$) Rendering Broken
**Created:** April 2025
**Comments:** 0

**Problem:** Double dollar sign ($$) LaTeX expressions have stopped rendering properly. Content that previously displayed correctly now appears misaligned and merges with other lines.

**Recommendation:** ✅ **CLONE AS ISSUE - HIGH PRIORITY**
- LaTeX/math rendering is important for technical documentation
- Regression (previously worked)
- Clear bug report
- **Issue Title:** "Fix LaTeX double dollar sign ($$) rendering"

---

### 5. Issue #1344 - Lists After Colons Render as Single Row
**Created:** April 2025
**Comments:** 0
**Status:** ✅ **COMPLETED** (macdown3000 #34)

**Problem:** Lists immediately following colons don't render as multi-line lists. Text becomes concatenated into single lines unless a blank line separates the colon from the list.

**Resolution:** Implemented via `MPMarkdownPreprocessor` class that inserts blank lines before list markers when they follow non-blank lines. Handles edge cases including fenced code blocks, blockquotes, and Windows line endings.

---

### 6. Issue #1343 - Mermaid Flow Charts Don't Render
**Created:** February 2025
**Comments:** 1

**Problem:** Flowchart diagrams using Mermaid syntax fail to render, despite flowcharts being supported since Mermaid's inception in 2014. Version v0.8.0d71 doesn't render them properly.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM-HIGH**
- Core functionality for diagrams
- Related to Mermaid library version/configuration
- **Issue Title:** "Fix Mermaid flowchart rendering"

---

### 7. Issue #1333 - Code Blocks Not Formatted Properly Without Space
**Created:** January 2024
**Comments:** 0

**Problem:** Code blocks immediately following text (without blank line) render on single line instead of preserving line breaks. GitHub renders same markdown correctly.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- Markdown parsing compatibility issue
- GitHub renders correctly, so this is a MacDown bug
- **Issue Title:** "Fix code block formatting when no blank line before block"

---

### 8. Issue #1332 - Code Block Rendering Bug for Square Brackets
**Created:** January 2024
**Comments:** 1

**Problem:** Code blocks with square brackets render incorrectly. Example TypeScript interface with `[key: string]` syntax displays improperly.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- Specific rendering bug affecting code
- TypeScript/programming use case
- **Issue Title:** "Fix code block rendering with square brackets"

---

### 9. Issue #1328 - 100% CPU Usage on macOS Sonoma 14.2
**Created:** November 2023
**Comments:** 5

**Problem:** On macOS Sonoma 14.2 beta 3, Intel systems experience 100% CPU usage. Also mentions "Open Recent" issues.

**Recommendation:** ⚠️ **MONITOR BUT DON'T CLONE YET**
- Might be beta-specific issue
- Could be related to performance optimization needed
- Monitor if this affects stable Sonoma releases
- If persistent, combine with general performance optimization

---

### 10. Issue #1326 - Shell Support Not Working in macOS Sonoma
**Created:** September 2023
**Comments:** 1

**Problem:** Terminal preferences "Install" button unresponsive in macOS Sonoma RC.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- macOS compatibility issue
- Clear bug report
- **Issue Title:** "Fix shell utility installation on macOS Sonoma"

---

### 11. Issue #1323 - Preview Pane Doesn't Line Up on Long Pages
**Created:** May 2023
**Comments:** 0

**Problem:** On long pages with extensive media, preview pane inconsistently positions itself, often resetting to page top on refresh.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- Scrolling sync issue (common complaint)
- Affects user experience on large documents
- **Issue Title:** "Fix preview pane scroll position on long documents"

---

### 12. Issue #1317 - Markdown Preferences Show No Detail Settings (Korean)
**Created:** January 2023
**Comments:** 0

**Problem:** On M1 MacBook Pro with Korean system language, Markdown preferences display only section headers without configurable options.

**Recommendation:** ⚠️ **CONSIDER - LOCALIZATION BUG**
- Language-specific UI bug
- Could affect other non-English users
- If we plan i18n support, clone this
- **Issue Title:** "Fix Markdown preferences display for non-English locales"

---

## MEDIUM PRIORITY - Good Feature Ideas

### 13. Issue #1341 - Update Mermaid to Version 11
**Created:** September 2024
**Comments:** 0

**Feature:** Update Mermaid library from version 10 to 11 to support new features like namespaces in class diagrams.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- Dependency update with new features
- Improves diagram capabilities
- **Issue Title:** "Update Mermaid library to v11"

---

### 14. Issue #1340 - TextBundle Standard Support
**Created:** August 2024
**Comments:** 0

**Feature:** Implement TextBundle standard support for import/export functionality. TextBundle is a standard format for markdown files with assets.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- Industry standard format
- Better asset management
- Already discussed in original repo (issue #135 from 2014)
- **Issue Title:** "Implement TextBundle import/export support"

---

### 15. Issue #1339 - Render Whitespace Option
**Created:** June 2024
**Comments:** 0

**Feature:** Option to toggle whitespace visibility in editor pane. User notes this feature previously existed but may have been removed.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- Useful for editing, especially code
- Similar to most code editors
- **Issue Title:** "Add option to show/hide whitespace characters"

---

### 16. Issue #1337 - Set Column Width to 80
**Created:** May 2024
**Comments:** 0

**Feature:** Ability to set column wrapping at 80 characters for markdown files per development team requirements.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- Common development standard
- Useful for teams with style guides
- **Issue Title:** "Add configurable column width/wrapping option"

---

### 17. Issue #1336 - Open Folders Feature
**Created:** March 2024
**Comments:** 0

**Feature:** Open entire folders in MacDown with sidebar listing .md files for easy navigation between files.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM-LOW**
- Useful for documentation projects
- Significant feature (like Sublime Text file tree)
- Already requested in issue #141 from 2014
- **Issue Title:** "Add folder browser with sidebar for multi-file projects"

---

### 18. Issue #1329 - Support Double $$ Delimiters for Math
**Created:** November 2023
**Comments:** 0

**Feature:** Request for double dollar sign delimiter support for MathML deployment.

**Recommendation:** ⚠️ **VERIFY FIRST**
- Need to check if this already works
- Related to issue #1346 (LaTeX $$ broken)
- Might be duplicate or related issue
- Don't clone separately

---

### 19. Issue #1324 - Support Strikethrough (~~text~~)
**Created:** May 2023
**Comments:** 2

**Feature:** Extended markdown supports `~~text~~` for strikethrough. Request MacDown implement this GitHub-compatible feature.

**Recommendation:** ✅ **CLONE AS ISSUE - MEDIUM**
- GitHub Flavored Markdown standard
- Simple to implement
- Commonly used feature
- **Issue Title:** "Add support for strikethrough syntax (~~text~~)"

---

## LOW PRIORITY - Consider Later

### 20. Issue #1345 - Localization Folders Blocking Language Access
**Created:** April 2025
**Comments:** 0

**Problem:** German macOS shows English because empty country-specific folders (de-DE.lproj) block access to working folders (de.lproj).

**Recommendation:** ⏭️ **LOW PRIORITY**
- Affects non-English users only
- Easy fix (remove empty folders)
- Clone if we prioritize i18n

---

### 21. Issue #1342 - Use net.daringfireball.markdown UTType
**Created:** February 2025
**Comments:** 0

**Feature:** When copying content, use the official Markdown UTI (net.daringfireball.markdown) instead of plain text.

**Recommendation:** ⏭️ **LOW PRIORITY - TECHNICAL DEBT**
- Technically correct but low user impact
- Nice-to-have for proper macOS integration
- Clone if doing clipboard work anyway

---

## SKIP - Not Worth Implementing

### 22. Issue #1351 - Tab Automatic Line Break (Chinese)
**Problem:** Unclear issue about tab behavior
**Recommendation:** ❌ **SKIP** - Too vague, possibly user-specific or translation issue

---

### 23. Issue #1338 - Some Styles Missing
**Problem:** Screenshots show missing styles
**Recommendation:** ❌ **SKIP** - Too vague, no clear description

---

### 24. Issue #1335 - Project Status Inquiry
**Type:** Meta discussion about project abandonment
**Recommendation:** ❌ **SKIP** - Not applicable (we're building successor)

---

### 25. Issue #1330 - Forced to Desktop When Opening/Closing
**Problem:** Multi-monitor desktop switching behavior
**Recommendation:** ❌ **SKIP** - Possibly user-specific macOS behavior

---

### 26. Issue #1318 - App Won't Update to Latest Version
**Problem:** Update mechanism issue
**Recommendation:** ❌ **SKIP** - We'll have our own update mechanism

---

## Summary & Recommendations

### Issues to Clone Immediately (14 total):

**CRITICAL (2):**
1. Fix "Open Recent" menu on macOS Sonoma (#1356/#1334)
2. [Already done] Native Apple Silicon support (#1348)

**HIGH PRIORITY BUGS (7):**
3. [Already cloned] Code text wrapping in PDF (#1350)
4. Fix LaTeX double dollar sign rendering (#1346)
5. [Completed] Fix list rendering after colons (#1344 → macdown3000 #34)
6. Fix Mermaid flowchart rendering (#1343)
7. Fix code block formatting without blank line (#1333)
8. Fix code block rendering with square brackets (#1332)
9. Fix shell utility installation on Sonoma (#1326)

**MEDIUM PRIORITY BUGS (2):**
10. Fix preview pane scroll position on long documents (#1323)
11. Fix Markdown preferences for non-English locales (#1317)

**FEATURES (5):**
12. Update Mermaid library to v11 (#1341)
13. Implement TextBundle import/export (#1340)
14. Add show/hide whitespace option (#1339)
15. Add configurable column width (#1337)
16. Add strikethrough support ~~text~~ (#1324)

**CONSIDER LATER (2):**
17. Add folder browser feature (#1336) - Bigger feature
18. Fix German/localization folders (#1345) - If doing i18n

### Total Impact:
- **8 legitimate bugs** to fix (including 2 critical macOS compatibility issues)
- **1 bug completed** (list rendering after colons)
- **5 valuable features** to implement
- **2 larger features** to consider for later

All recommended issues represent real problems affecting multiple users or valuable features that enhance the application's utility.
