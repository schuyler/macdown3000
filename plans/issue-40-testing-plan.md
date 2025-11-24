# Manual Testing Plan: Korean Localization Fix (Issue #40)

## Overview

This testing plan validates the fix for incomplete Korean localization that caused preference controls to disappear when MacDown was run with Korean system language settings. The fix also includes completeness validation tests for Japanese and Chinese Simplified locales.

**Related Issue**: #40
**Fix Summary**: Completed Korean localization files for all 5 preference view controllers, adding 174+ missing translations

---

## Prerequisites

### Hardware & Software Requirements
- **Device**: Mac with macOS 10.14 or later
- **Build**: MacDown 3000 built from the fix branch `claude/issue-40-01H35XZ33okFBDCQPH7zmKRk`
- **Time Required**: 45-60 minutes for complete test suite
- **Disk Space**: ~500MB free (for language packs)

### Before You Begin
1. Build the application from source or obtain a test build
2. Close all running instances of MacDown
3. Back up your MacDown preferences (optional but recommended):
   ```bash
   cp -r ~/Library/Preferences/com.uranusjr.macdown ~/Desktop/macdown-prefs-backup
   ```

---

## Part 1: System Language Configuration

### How to Change System Language on macOS

#### Method A: Full System Language Change (Most Accurate Test)

1. **Open System Settings/Preferences**
   - macOS Ventura+: Apple menu → System Settings → General → Language & Region
   - macOS Monterey and earlier: Apple menu → System Preferences → Language & Region

2. **Add Test Language**
   - Click the "+" button under "Preferred Languages"
   - Select the test language (Korean, Japanese, or Chinese Simplified)
   - Choose "Use [Language]" when prompted
   - macOS will download language resources (may take 2-5 minutes)

3. **Restart or Re-login**
   - Log out and log back in for changes to take effect
   - Some changes may require a full restart

4. **Verify Language Change**
   ```bash
   defaults read -g AppleLocale
   # Should show: ko_KR, ja_JP, or zh_CN
   ```

#### Method B: Per-Application Language Override (Faster, macOS Catalina+)

1. **Open System Settings/Preferences**
   - Navigate to Language & Region → Apps (or Applications)

2. **Add MacDown Override**
   - Click "+" button
   - Select MacDown from applications list
   - Choose desired language (Korean, Japanese, Chinese Simplified)
   - Restart MacDown

3. **Verify Override**
   ```bash
   defaults read com.uranusjr.macdown AppleLanguages
   # Should show array with selected language code
   ```

**Note**: Method A provides the most accurate test of real-world user experience, but Method B is faster for iterative testing.

---

## Part 2: Core Test Scenarios

### Test Matrix

Test all combinations marked with ✓:

| Locale | Markdown | Terminal | General | HTML | Editor |
|--------|----------|----------|---------|------|--------|
| Korean (ko-KR) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Japanese (ja) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Chinese Simplified (zh-Hans) | ✓ | ✓ | ✓ | ✓ | ✓ |
| English (regression) | ✓ | ✓ | ✓ | ✓ | ✓ |

---

## Part 3: Detailed Test Cases

### Test Suite 1: Korean Locale (ko-KR) - PRIMARY FIX

This is the **critical test suite** as Korean was the reported locale in the original issue.

#### Setup
```bash
# Set system language to Korean using Method A or B above
# Launch MacDown
open /Applications/MacDown.app  # or your build location
```

#### Test 1.1: Markdown Preferences Tab

**Steps:**
1. Open MacDown Preferences (⌘,)
2. Click "Markdown" tab (should show "마크다운" in toolbar)
3. Verify all UI elements are visible and in Korean

**Expected Results:**

**Section: 블록 형식 (Block formatting)**
- ✓ Checkbox: "테이블" (Table)
- ✓ Checkbox: "코드 펜스" (Fenced code block)

**Section: 문서 형식 (Document formatting)**
- ✓ Checkbox: "각주" (Footnote)

**Section: 인라인 형식 (Inline formatting)**
- ✓ Checkbox: "자동링크" (Autolink)
- ✓ Checkbox: "취소선" (Strikethrough)
- ✓ Checkbox: "밑줄" (Underline)
- ✓ Checkbox: "하이라이트" (Highlight)
- ✓ Checkbox: "인용" (Quote)
- ✓ Checkbox: "위첨자" (Superscript)
- ✓ Checkbox: "단어 내 강조" (Intra-word emphasis)
- ✓ Checkbox: "Smartypants"

**Total Elements**: 14 localizable elements
**Pass Criteria**: All checkboxes and section headers visible with Korean text

**Screenshot Required**: Yes - Full Markdown preferences tab

---

#### Test 1.2: Terminal Preferences Tab

**Steps:**
1. Click "Terminal" tab (should show "터미널" in toolbar)
2. Verify shell support section displays correctly

**Expected Results:**
- ✓ Label: "위치:" (Location:)
- ✓ Text field: "<binary location>"
- ✓ Status indicator: "●"
- ✓ Status text: "셸 지원 미설치" (Shell support not installed)
- ✓ Description: "셸 지원을 활성화하면 macdown 유틸리티를 사용하여 셸에서 MacDown과 문서를 열 수 있습니다." (By activating shell support you can use the macdown utility to open MacDown and documents from a shell.)
- ✓ Button: "설치" (Install)

**Total Elements**: 6 localizable elements
**Pass Criteria**: All UI elements visible with proper Korean text, layout not broken

**Screenshot Required**: Yes

---

#### Test 1.3: General Preferences Tab

**Steps:**
1. Click "General" tab (should show "일반" in toolbar)
2. Verify all sections display correctly

**Expected Results:**

**Section: 동작 (Behavior)**
- ✓ Checkbox: "입력할 때 미리보기 자동 업데이트" (Update preview automatically as you type)
- ✓ Checkbox: "에디터 스크롤 시 미리보기도 함께 스크롤" (Sync preview scrollbar when editor scrolls)
- ✓ Checkbox: "에디터를 오른쪽에 배치" (Put editor on the right)
- ✓ Checkbox: "실행 시 문서 열기" (Ensure open document on launch)
- ✓ Checkbox: "링크 대상 파일 자동 생성" (Automatically create files for link targets)
- ✓ Checkbox: "단어수 보기" (Show word count)

**Section: 업데이트 (Update)**
- ✓ Checkbox: "프리릴리스 포함" (Include pre-releases)

**Total Elements**: 9 localizable elements
**Pass Criteria**: All checkboxes visible and functional

**Screenshot Required**: Yes

---

#### Test 1.4: HTML Preferences Tab

**Steps:**
1. Click "HTML" tab
2. Verify all sections and controls display correctly
3. Check dropdown menus expand properly

**Expected Results:**

**Rendering Options:**
- ✓ Checkbox: "TeX 스타일 수식 구문" (TeX-like math syntax)
- ✓ Checkbox: "달러 기호 ($)를 인라인 구분자로 사용" (Use dollar sign ($) as inline delimiter)
- ✓ Label: "수식 지원은 인터넷 연결이 필요합니다." (Math support requires Internet connection.)
- ✓ Checkbox: "Jekyll 머리말 감지" (Detect Jekyll front-matter)
- ✓ Checkbox: "목차 토큰 감지" (Detect table of contents token)
- ✓ Checkbox: "작업 목록 구문" (Task list syntax)
- ✓ Checkbox: "줄바꿈 그대로 렌더링" (Render newline literally)

**Code Block Options:**
- ✓ Checkbox: "코드 블록 구문 강조" (Syntax highlighted code block)
- ✓ Checkbox: "행 번호 보이기" (Show line numbers)
- ✓ Label: "액세서리:" (Accessory:)
- ✓ Dropdown items: "없음" (None), "언어 이름" (Language name), "사용자 정의" (Custom)

**Diagram Support:**
- ✓ Checkbox: "Mermaid"
- ✓ Checkbox: "Graphviz"

**Styling:**
- ✓ Label: "테마:" (Theme:)
- ✓ Label: "CSS:"
- ✓ Label: "기본 경로:" (Default path:)
- ✓ Checkbox: "에디터 폰트 크기에 따라 미리보기 크기 조정" (Scale preview based on editor font size)
- ✓ Segmented control: "표시" / "리로드" (Reveal / Reload)

**Total Elements**: 20 localizable elements
**Pass Criteria**: All controls visible, dropdowns functional, Korean text properly displayed

**Screenshot Required**: Yes - Scroll to capture all sections if needed

---

#### Test 1.5: Editor Preferences Tab

**Steps:**
1. Click "Editor" tab (should show "편집기" in toolbar)
2. Verify all sections display correctly
3. Test dropdown menus

**Expected Results:**

**Section: 동작 (Behavior)**
- ✓ Checkbox: "탭 대신 공백 삽입" (Insert spaces instead of tabs)
- ✓ Checkbox: "일치하는 문자 자동 완성" (Auto-complete matching characters)
- ✓ Checkbox: "현재 블록에 줄 접두사 자동 삽입" (Automatically insert line prefix for the current block)
- ✓ Checkbox: "순서 목록에서 번호 자동 증가" (Auto-increment numbering in ordered lists)
- ✓ Label: "목록 마커:" (List marker:)
- ✓ Dropdown items: "*(별표)" (Asterisk), "+(더하기 기호)" (Plus sign), "-(빼기 기호)" (Minus sign)
- ✓ Checkbox: "⌘← 키로 줄의 첫 번째 공백이 아닌 문자로 이동" (⌘← jumps to first non-whitespace character in line)
- ✓ Checkbox: "끝을 넘어서 스크롤" (Scroll past end)
- ✓ Checkbox: "저장 시 파일 끝에 줄바꿈 확인" (Ensure newline at end of file on save)

**Appearance Options:**
- ✓ Label: "기본 서체:" (Base font:)
- ✓ Button: "변경..." (Change…)
- ✓ Label: "테마:" (Theme:)
- ✓ Segmented control: "표시" / "리로드" (Reveal / Reload)
- ✓ Label: "행 간격:" (Line spacing:)
- ✓ Label: "텍스트 여백:" (Text insets:)
- ✓ Label: "×"
- ✓ Checkbox: "에디터 너비 제한" (Limit editor width to)

**Total Elements**: 20 localizable elements
**Pass Criteria**: All controls visible and properly labeled in Korean

**Screenshot Required**: Yes

---

### Test Suite 2: Japanese Locale (ja) - REGRESSION

**Purpose**: Verify Japanese localization remains complete and functional

#### Setup
```bash
# Change system language to Japanese
# Restart MacDown
```

#### Test 2.1-2.5: All Preference Tabs

Repeat tests 1.1 through 1.5, but verify Japanese translations instead:

**Sample Expected Results (Markdown Tab):**
- Section headers: "ブロック書式", "ドキュメント書式", "インライン書式"
- Checkboxes: "脚注", "引用", "ハイライト", "Smartypants", etc.

**Pass Criteria**:
- All 69 UI elements across 5 tabs display in Japanese
- No English fallbacks for localized strings
- Layout remains consistent with English version

**Screenshot Required**: One screenshot per tab (5 total)

---

### Test Suite 3: Chinese Simplified (zh-Hans) - REGRESSION

**Purpose**: Verify Chinese Simplified localization remains complete

#### Setup
```bash
# Change system language to Chinese Simplified
# Restart MacDown
```

#### Test 3.1-3.5: All Preference Tabs

**Sample Expected Results (Markdown Tab):**
- Section headers: "块格式", "文档格式", "内联格式"
- Checkboxes: "脚注", "引用", "高亮", "Smartypants", etc.

**Pass Criteria**: All 69 UI elements display in Chinese Simplified

**Screenshot Required**: One screenshot per tab (5 total)

---

### Test Suite 4: English Locale - REGRESSION

**Purpose**: Ensure English localization still works correctly

#### Setup
```bash
# Reset system language to English
# Restart MacDown
```

#### Test 4.1-4.5: All Preference Tabs

**Expected Results:**
- All section headers in English (e.g., "Block formatting", "Document formatting")
- All checkboxes in English (e.g., "Footnote", "Quote", "Highlight")
- No placeholder text or missing translations

**Pass Criteria**: Application functions identically to pre-fix behavior

**Screenshot Required**: Optional - only if issues found

---

## Part 4: Edge Cases & Additional Testing

### Test 5: Mixed Language Scenarios

#### Test 5.1: System Language vs. App Language Override

**Setup:**
1. Set system language to Korean
2. Override MacDown to use English (Method B from Part 1)
3. Launch MacDown

**Expected Result**: MacDown UI should be in English, overriding system Korean

**Pass Criteria**: App language override takes precedence

---

#### Test 5.2: Unsupported Locale Fallback

**Setup:**
1. Set system language to a locale MacDown doesn't support (e.g., Hindi, Thai)
2. Launch MacDown

**Expected Result**: Should fall back to English

**Pass Criteria**: All preferences display in English, no broken UI

---

### Test 6: UI Layout & Rendering

#### Test 6.1: Text Truncation Check

**For each locale (Korean, Japanese, Chinese):**

1. Check all preference tabs for text truncation
2. Look for labels that are cut off or "..."
3. Verify all checkbox labels fit within their bounds
4. Check that section headers don't overlap with controls

**Common Problem Areas:**
- Long Korean phrases in narrow columns
- Chinese characters in fixed-width fields
- Japanese text with English technical terms

**Pass Criteria**: No truncated text, all labels fully visible

---

#### Test 6.2: Window Resize Behavior

**Steps:**
1. Set locale to Korean
2. Open Preferences window
3. Resize window to minimum size
4. Resize to maximum size
5. Verify layout adapts correctly

**Expected Result**: UI elements reflow gracefully, no overlapping text

---

#### Test 6.3: RTL Language Compatibility (Arabic)

**Note**: MacDown supports Arabic (ar.lproj exists)

**Steps:**
1. Set system language to Arabic
2. Launch MacDown
3. Check if preference tabs mirror properly (RTL layout)

**Expected Result**: If RTL is implemented, layout should mirror. If not, text should still be readable.

**Pass Criteria**: No broken layout, text readable

---

### Test 7: Functional Verification

#### Test 7.1: Preference Changes Persist (Korean Locale)

**Steps:**
1. Set system language to Korean
2. Open MacDown Preferences
3. Change several settings:
   - Toggle "자동링크" (Autolink) ON
   - Toggle "취소선" (Strikethrough) ON
   - Enable "TeX 스타일 수식 구문" (TeX-like math)
4. Close preferences
5. Restart MacDown
6. Reopen preferences

**Expected Result**: All changed settings remain in their new state

**Pass Criteria**: Preferences persist correctly regardless of locale

---

#### Test 7.2: Preference Functionality (Korean Locale)

**Steps:**
1. In Korean locale, enable "Autolink" (자동링크)
2. Create new document
3. Type: `http://example.com`
4. Preview should show clickable link

**Repeat for other settings** (sample 3-5 preferences)

**Expected Result**: Changing preferences in Korean locale affects rendering behavior identically to English locale

---

### Test 8: Automated Test Verification

#### Test 8.1: Run Localization Tests

**Steps:**
```bash
cd /home/user/macdown3000
xcodebuild test -scheme MacDown -destination 'platform=macOS' \
  -only-testing:MacDownTests/MPLocalizationTests
```

**Expected Output:**
```
Test Suite 'MPLocalizationTests' passed
  ✓ testKoreanMarkdownPreferencesLocalization (0.001 sec)
  ✓ testKoreanTerminalPreferencesLocalization (0.001 sec)
  ✓ testKoreanGeneralPreferencesLocalization (0.001 sec)
  ✓ testKoreanHtmlPreferencesLocalization (0.001 sec)
  ✓ testKoreanEditorPreferencesLocalization (0.001 sec)
  ✓ testJapaneseMarkdownPreferencesLocalization (0.001 sec)
  [... all 15 tests pass]
```

**Pass Criteria**: All 15 localization tests pass

---

## Part 5: Issue Reproduction & Validation

### Test 9: Verify Original Issue Is Resolved

**Purpose**: Confirm the exact scenario reported in issue #40 is fixed

#### Setup
1. Clean MacDown installation (or reset preferences):
   ```bash
   defaults delete com.uranusjr.macdown
   ```
2. Set system language to Korean (ko-KR)
3. Restart Mac or re-login

#### Test 9.1: Reproduce Original Bug (Verification)

**Steps:**
1. Launch MacDown
2. Open Preferences (⌘,)
3. Click "Markdown" tab

**Before Fix** (Expected in unpatched version):
- Section headers visible: "블록 형식", "문서 형식", "인라인 형식"
- Checkboxes MISSING or showing as blank/untranslated
- Only 4 out of 14 elements localized

**After Fix** (Expected with this patch):
- Section headers visible: "블록 형식", "문서 형식", "인라인 형식"
- ALL 14 checkboxes visible with Korean labels
- No blank or English fallback text

**Pass Criteria**: All 14 elements in Markdown tab are visible and in Korean

**Screenshot Required**: YES - This is the critical validation screenshot

---

## Part 6: Performance & Stability

### Test 10: App Stability in Non-English Locales

#### Test 10.1: Launch Stability

**Steps:**
1. For each locale (Korean, Japanese, Chinese):
   - Launch MacDown
   - Wait 30 seconds
   - Verify no crashes or hangs

**Expected Result**: App launches successfully in all locales

---

#### Test 10.2: Preference Window Stability

**Steps:**
1. Set locale to Korean
2. Open Preferences
3. Rapidly switch between all 5 tabs (20 cycles)
4. Monitor for memory leaks or crashes

**Expected Result**: No crashes, smooth tab switching

---

### Test 11: Console Log Analysis

#### Test 11.1: Check for Localization Warnings

**Steps:**
```bash
# Open Console.app
# Filter for "MacDown" process
# Look for warnings like:
#   - "Missing localized string"
#   - "Could not load .strings file"
#   - "Localization key not found"
```

**Expected Result**: No localization-related warnings or errors

**Pass Criteria**: Console is clean of localization issues

---

## Part 7: Documentation & User Experience

### Test 12: Localization Quality Assessment

**Note**: This test requires native or fluent speakers

#### Test 12.1: Translation Accuracy (Korean)

**For each translated string**, verify:
- Grammar is correct
- Technical terms are accurate
- Tone is appropriate (formal/informal consistency)
- No machine translation artifacts

**Common Issues to Check:**
- "Smartypants" - kept untranslated (correct, it's a proper name)
- Technical terms like "Markdown", "CSS", "HTML" - typically kept in English
- UI action verbs - should be imperative form in Korean

**Recommendation**: Have native Korean speaker review translations

---

#### Test 12.2: Context Appropriateness

**Steps:**
1. For each preference, toggle it ON
2. Create test document that exercises the preference
3. Verify the Korean label accurately describes the functionality

**Example:**
- "자동링크" (Autolink) → Verify URLs auto-convert to links
- "취소선" (Strikethrough) → Verify `~~text~~` renders with strikethrough

**Pass Criteria**: Labels accurately reflect functionality

---

## Part 8: Regression Testing Checklist

### Final Validation Checklist

Before closing the issue, confirm:

#### Localization Completeness
- [ ] Korean: All 69 UI elements translated across 5 tabs
- [ ] Japanese: All 69 UI elements remain translated
- [ ] Chinese Simplified: All 69 UI elements remain translated
- [ ] English: All UI elements display correctly (no regressions)

#### Functionality
- [ ] All preferences functional in Korean locale
- [ ] All preferences functional in Japanese locale
- [ ] All preferences functional in Chinese Simplified locale
- [ ] Preferences persist across app restarts in all locales
- [ ] No crashes when switching locales
- [ ] No console errors related to localization

#### Automated Tests
- [ ] All 15 MPLocalizationTests pass
- [ ] Tests validate expected element counts (14, 6, 9, 20, 20)
- [ ] Tests cover Korean, Japanese, and Chinese Simplified locales

#### User Experience
- [ ] No text truncation in any locale
- [ ] Layout adapts to different text lengths
- [ ] No overlapping UI elements
- [ ] Consistent spacing and alignment across locales
- [ ] Toolbar icons display correctly with localized labels

#### Original Issue
- [ ] M1 MacBook Pro with Korean system language scenario verified
- [ ] Markdown preferences tab shows ALL controls (not just headers)
- [ ] Issue #40 reproduction steps no longer reproduce the bug

---

## Part 9: Test Results Documentation

### Results Template

For each test suite, document results using this format:

```markdown
## Test Results - [Locale Name] - [Date]

**Tester**: [Name]
**Build**: MacDown 3000 [version/commit hash]
**macOS Version**: [version]
**Test Duration**: [time]

### Markdown Preferences Tab
- Status: ✅ PASS / ❌ FAIL
- Elements visible: [X/14]
- Issues: [None / Description]
- Screenshot: [Attached / Link]

### Terminal Preferences Tab
- Status: ✅ PASS / ❌ FAIL
- Elements visible: [X/6]
- Issues: [None / Description]
- Screenshot: [Attached / Link]

[... repeat for all tabs ...]

### Overall Assessment
- [ ] Ready for merge
- [ ] Needs revisions (see issues)
- [ ] Requires native speaker review

**Notes**: [Any additional observations]
```

---

## Part 10: Known Limitations & Future Work

### Current Implementation Notes

1. **Translation Quality**:
   - Translations were completed using automated tools
   - Native Korean speaker review recommended before final release
   - Some technical terms intentionally left untranslated (e.g., "Smartypants", "Mermaid")

2. **Test Coverage**:
   - Automated tests validate element counts, not translation accuracy
   - Manual testing required for UI/UX validation
   - Native speaker testing recommended for quality assurance

3. **Other Locales**:
   - This fix focused on Korean, Japanese, and Chinese Simplified
   - Other locales (ar, cs, da, de, es, etc.) may have similar incompleteness issues
   - Consider running completeness audit for all locales in future

### Suggested Follow-up Testing

1. **Extended Locale Testing**: Audit all 25+ supported locales for completeness
2. **Accessibility Testing**: Verify VoiceOver works correctly with localized strings
3. **Load Testing**: Test with extremely long translated strings to verify layout
4. **Professional Translation Review**: Engage native speakers for quality review

---

## Contact & Support

**Issues Found During Testing?**
- Document in issue #40 comments
- Include screenshots and console logs
- Specify macOS version and MacDown build

**Questions About This Test Plan?**
- Consult CLAUDE.md for project context
- Review MPLocalizationTests.m for automated test expectations

---

## Appendix A: Quick Reference

### Translation Counts by File

| Localization File | Korean (ko-KR) | Japanese (ja) | Chinese (zh-Hans) |
|-------------------|----------------|---------------|-------------------|
| MPMarkdownPreferencesViewController | 42 lines (14 elements) | 42 lines | 42 lines |
| MPTerminalPreferencesViewController | 18 lines (6 elements) | 18 lines | 18 lines |
| MPGeneralPreferencesViewController | 27 lines (9 elements) | 27 lines | 27 lines |
| MPHtmlPreferencesViewController | 63 lines (20 elements) | 63 lines | 63 lines |
| MPEditorPreferencesViewController | 63 lines (20 elements) | 63 lines | 63 lines |
| **Total** | **213 lines (69 elements)** | **213 lines** | **213 lines** |

### Key Files Changed

| File | Purpose |
|------|---------|
| `/MacDown/Localization/ko-KR.lproj/MPMarkdownPreferencesViewController.strings` | Korean translations for Markdown tab |
| `/MacDown/Localization/ko-KR.lproj/MPTerminalPreferencesViewController.strings` | Korean translations for Terminal tab |
| `/MacDown/Localization/ko-KR.lproj/MPGeneralPreferencesViewController.strings` | Korean translations for General tab |
| `/MacDown/Localization/ko-KR.lproj/MPHtmlPreferencesViewController.strings` | Korean translations for HTML tab |
| `/MacDown/Localization/ko-KR.lproj/MPEditorPreferencesViewController.strings` | Korean translations for Editor tab |
| `/MacDownTests/MPLocalizationTests.m` | Automated regression tests |

### Command Reference

```bash
# View current system locale
defaults read -g AppleLocale

# View MacDown language override
defaults read com.uranusjr.macdown AppleLanguages

# Reset MacDown preferences
defaults delete com.uranusjr.macdown

# Run localization tests only
xcodebuild test -scheme MacDown -destination 'platform=macOS' \
  -only-testing:MacDownTests/MPLocalizationTests

# Check for localization warnings in Console
log show --predicate 'processImagePath contains "MacDown"' \
  --last 1h | grep -i "locali"
```

---

**End of Manual Testing Plan**

*Last Updated: 2025-11-23*
*Related Issue: #40*
*Test Plan Version: 1.0*
