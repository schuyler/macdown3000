# Comment for Issue #34

## Decision to Revert the Preprocessor Fix

After careful analysis, I've decided to **revert the preprocessor solution** introduced in PR #70. Here's why:

### The Core Problem

The "issue" reported here isn't actually a bug in MacDown—it's how **hoedown 3.0.7 intentionally works by design**. Hoedown deliberately requires blank lines before lists that follow paragraphs, differing from CommonMark's more permissive approach.

### Key Findings from Code Review

1. **Original MacDown doesn't have this problem**
   - The upstream MacDownApp/macdown repository uses the same hoedown 3.0.7
   - It has **no preprocessor** and has worked successfully for years
   - Zero instances of `MPMarkdownPreprocessor` exist in the original codebase
   - If this were truly a "HIGH priority" issue, the active upstream community would have addressed it

2. **Hoedown's behavior is intentional, not a defect**
   - Hoedown inherited from Sundown, which had a `LAX_SPACING` flag for relaxed list spacing
   - Hoedown deliberately **removed this flag** for stricter spec compliance
   - This prevents ambiguous list detection in hard-wrapped paragraphs with numbers
   - It's a conscious design decision, not something that needs "fixing"

3. **The preprocessor solution has significant downsides**
   - Adds 200+ lines of complex state-tracking code
   - **Modifies user input invisibly** by inserting blank lines before parsing
   - Duplicates parsing logic already in hoedown (fenced code, blockquotes, etc.)
   - Creates maintenance burden and potential for subtle bugs
   - Deviates from original MacDown behavior without clear user benefit

4. **Architecture concerns**
   - Working around a parser's intentional behavior is a code smell
   - The proper fix is to use a parser that matches your desired behavior
   - Preprocessing markdown is fragile and can have unexpected edge cases

### The Right Solution

For true CommonMark compliance, we should **upgrade to a CommonMark-compliant parser** rather than working around hoedown's design. I'm creating a separate issue to track modernizing our markdown parser infrastructure.

### What This Means for Users

Users who want lists immediately after colons should add a blank line manually. This is actually **good markdown practice** that:
- Works across all markdown processors
- Makes document structure clearer
- Is the same behavior as the original MacDown
- Matches what thousands of MacDown users already do

### Next Steps

1. ✅ Reverted the preprocessor in commit 142d070
2. 🔄 Creating new issue for parser modernization
3. 📝 Documenting this decision for future reference

I'm keeping this issue open to track the parser upgrade discussion, but the preprocessor workaround has been removed.

---

**Related:** See the new parser modernization issue #[TBD] for discussion about upgrading to a modern CommonMark-compliant parser.
