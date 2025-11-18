# MacDown Open Pull Requests Analysis (2023-Present)

Analysis of open pull requests from MacDownApp/macdown to identify features/fixes worth implementing in macdown3000.

---

## HIGH PRIORITY - Recommended to Clone as Issues

### 1. PR #1349 - Printing code with overflow (Aug 5, 2025)
**Author:** falkorichter
**Problem:** Code blocks with long lines get cut off when printing to PDF
**Solution:** Improved overflow handling for code blocks in PDF exports

**Recommendation:** ✅ **CLONE AS ISSUE**
- **Priority:** HIGH
- **Rationale:** This is a practical fix for a real usability problem. PDF export is important for documentation and sharing, and truncated code is a major issue.
- **Implementation:** Review the CSS/print styling changes needed for proper code block overflow handling
- **Issue Title:** "Improve code block rendering in PDF exports (handle overflow)"

---

### 2. PR #1321 - Preview Mode on Launch (Feb 20, 2023)
**Author:** muyexi
**Problem:** No option to launch MacDown directly in preview mode
**Solution:** Added preference option for "Preview Mode on launch"

**Recommendation:** ✅ **CLONE AS ISSUE**
- **Priority:** MEDIUM-HIGH
- **Rationale:** This expands MacDown's use case as a Markdown viewer, not just an editor. Simple feature with clear user value.
- **Implementation:** Add preference setting to MPPreferences to control initial view mode
- **Issue Title:** "Add preference option: Launch in Preview Mode"

---

### 3. PR #1320 / #1319 - Line Breaking in HTML Export (Feb 3, 2023)
**Author:** radicm (duplicate PRs)
**Problem:** Long lines don't wrap properly when exporting to HTML
**Solution:** Add `word-break: break-word;` CSS property to paragraphs

**Recommendation:** ✅ **CLONE AS ISSUE**
- **Priority:** MEDIUM
- **Rationale:** HTML export is a key feature, and proper text wrapping is essential for readability. Simple CSS fix with clear before/after demonstration.
- **Implementation:** Update HTML export templates with proper word-breaking CSS
- **Issue Title:** "Fix line breaking in HTML exports"
- **Note:** PRs #1319 and #1320 appear to be duplicates - only need one issue

---

## MEDIUM PRIORITY - Consider for Later

### 4. PR #1355 - Updated App Icon to macOS Liquid Glass Style (Oct 31, 2025)
**Author:** fisher158163
**Problem:** App icon may look dated compared to modern macOS design language
**Solution:** Updated icon to "macOS 26 Liquid Glass style"

**Recommendation:** ⚠️ **CONSIDER, BUT LOW PRIORITY**
- **Priority:** LOW-MEDIUM
- **Rationale:** Modern icon design is nice-to-have but not critical. Need to see actual icon design before committing. May be dated terminology ("macOS 26" isn't a real version).
- **Next Steps:** Review the actual icon design first, then decide if it fits macdown3000's visual direction
- **Issue Title:** "Update app icon to modern macOS design style"

---

## LOW PRIORITY - Maintenance Tasks

### 5. PR #1325 - Updated Dependencies (Jul 10, 2023)
**Author:** lucy-jane
**Problem:** Dependencies are outdated
**Solution:** Updated dependencies using Dependabot

**Recommendation:** ⏭️ **SKIP - Handle Separately**
- **Priority:** ONGOING MAINTENANCE
- **Rationale:** Dependency updates should be handled as part of regular maintenance, not cloned from old PRs. The specific updates from 2023 are now outdated anyway.
- **Action:** Instead, create a regular dependency update process for macdown3000

---

### 6. PR #1316 - Bump qs Package (Jan 13, 2023)
**Author:** dependabot[bot]
**Problem:** Security vulnerability in qs package
**Solution:** Update qs from 6.5.2 to 6.5.3

**Recommendation:** ⏭️ **SKIP - Handle Separately**
- **Priority:** ONGOING MAINTENANCE
- **Rationale:** This is a 2023 security fix for a specific dependency. Current project should use latest secure versions from the start.
- **Action:** Ensure all dependencies in macdown3000 are current and secure

---

## Summary & Recommendations

### Clone as Issues (3 items):
1. **Improve code block rendering in PDF exports** (from PR #1349) - HIGH PRIORITY
2. **Add preference option: Launch in Preview Mode** (from PR #1321) - MEDIUM-HIGH PRIORITY
3. **Fix line breaking in HTML exports** (from PR #1320) - MEDIUM PRIORITY

### Total Estimated Impact:
These three features/fixes address real user pain points:
- Better PDF export quality
- Expanded use case (viewer mode)
- Improved HTML export formatting

All are relatively straightforward implementations that would enhance macdown3000's usability.

---

## Next Steps

1. Create GitHub issues for the 3 recommended PRs
2. Review actual implementation code from original PRs when implementing
3. Consider the modern icon update after visual review
4. Establish regular dependency update process
