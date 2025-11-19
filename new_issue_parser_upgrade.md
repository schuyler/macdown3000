# New Issue: Upgrade to Modern CommonMark-Compliant Parser

**Title:** Modernize markdown parser: Evaluate migration from hoedown to CommonMark-compliant alternative

**Labels:** enhancement, infrastructure, rendering

---

## Summary

MacDown currently uses **hoedown 3.0.7**, a markdown parser that was last updated in 2016 and is no longer actively maintained. We should evaluate migrating to a modern, actively-maintained, CommonMark-compliant parser.

## Background

This issue stems from #34, where users reported that lists following colons don't render without a blank line separator. While we initially implemented a preprocessor workaround, deeper analysis revealed that hoedown's behavior is **intentional by design**—it diverges from CommonMark by requiring blank lines before lists.

Rather than working around hoedown's design decisions, we should consider switching to a parser that aligns with modern markdown standards.

## Problems with Current Parser (hoedown)

1. **No longer maintained** - Last significant update was 2016
2. **Not CommonMark compliant** - Intentionally differs from the spec in several ways
3. **Missing modern features** - No support for newer markdown extensions
4. **Design decisions diverge from user expectations** - Like requiring blank lines before lists

## Candidate Parsers to Evaluate

### cmark (libcmark)
- ✅ Official CommonMark reference implementation in C
- ✅ Actively maintained by CommonMark project
- ✅ Excellent performance
- ✅ Stable C API suitable for Objective-C integration
- ✅ Well-tested against CommonMark spec
- ❓ Need to evaluate GFM (GitHub Flavored Markdown) support

### cmark-gfm
- ✅ GitHub's fork of cmark with GFM extensions
- ✅ Adds tables, strikethrough, autolinks, task lists
- ✅ Actively maintained
- ✅ Used in production by GitHub
- ❓ Need to verify macOS compatibility

### markdown-it (if considering JavaScript)
- ✅ Highly extensible
- ✅ CommonMark compliant
- ❌ JavaScript-based (integration complexity)

### marked (if considering JavaScript)
- ✅ Fast and lightweight
- ✅ Widely used
- ❌ JavaScript-based (integration complexity)

## Evaluation Criteria

When evaluating parsers, we should assess:

1. **CommonMark Compliance**
   - Full spec compliance
   - Passes CommonMark test suite

2. **GitHub Flavored Markdown (GFM) Support**
   - Tables
   - Strikethrough
   - Autolinks
   - Task lists
   - Syntax highlighting hints

3. **Integration Feasibility**
   - C/Objective-C API availability
   - CocoaPods support
   - Binary size impact

4. **Performance**
   - Parsing speed for large documents
   - Memory usage
   - Real-time preview performance

5. **Maintenance & Stability**
   - Active development
   - Security updates
   - API stability
   - Community support

6. **Feature Parity**
   - All features currently supported by hoedown
   - Math support (for MathJax integration)
   - Footnotes
   - Custom extensions MacDown users expect

## Implementation Approach

### Phase 1: Research & Prototyping (2-3 weeks)
- [ ] Evaluate top 2-3 candidates
- [ ] Create proof-of-concept integrations
- [ ] Performance benchmarking
- [ ] Feature compatibility matrix

### Phase 2: Integration (3-4 weeks)
- [ ] Implement chosen parser
- [ ] Update rendering pipeline
- [ ] Preserve all existing features
- [ ] Update build system

### Phase 3: Testing (2-3 weeks)
- [ ] Comprehensive rendering tests
- [ ] Performance regression testing
- [ ] User acceptance testing
- [ ] Documentation updates

### Phase 4: Migration (1 week)
- [ ] Gradual rollout
- [ ] Monitor for issues
- [ ] Support user feedback

## Success Metrics

- ✅ Full CommonMark compliance
- ✅ All existing MacDown features work
- ✅ No performance regression
- ✅ Issue #34 resolved naturally (lists can interrupt paragraphs)
- ✅ Users report improved markdown compatibility

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing documents | HIGH | Extensive testing, phased rollout |
| Performance degradation | MEDIUM | Benchmark early, optimize if needed |
| Integration complexity | MEDIUM | Prototype early, evaluate alternatives |
| Loss of custom features | HIGH | Document all features, ensure parity |

## Related Issues

- Closes #34 (Lists after colons)
- Related to upstream MacDownApp/macdown#1344

## References

- [CommonMark Spec](https://spec.commonmark.org/)
- [cmark repository](https://github.com/commonmark/cmark)
- [cmark-gfm repository](https://github.com/github/cmark-gfm)
- [Hoedown repository](https://github.com/hoedown/hoedown) (archived/unmaintained)

## Priority

**MEDIUM-HIGH** - This affects core functionality and user expectations, but current hoedown implementation is stable. The main drivers are:
1. CommonMark compliance for better interoperability
2. Long-term maintainability (hoedown is unmaintained)
3. Access to modern markdown features
4. Resolving user confusion about list rendering

---

**Note:** This is a significant architectural change that should be carefully planned and thoroughly tested. Community feedback is welcome!
