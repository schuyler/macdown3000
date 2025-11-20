# Phase 6: DOCUMENT

## Objective

Update documentation to reflect the new feature.

## Why This Exists

Harpo prevents: undocumented features, stale docs, users unable to use new functionality, lost knowledge.

## Protocol

1. **Get user approval to consult Harpo**
   - Mark "Get user approval to consult Harpo" as in_progress
   - Ask: "May I consult Harpo to update documentation?"
   - Wait for user confirmation
   - Mark as completed only after user confirms

2. **Consult Harpo**
   - Provide complete implementation details
   - Describe what was built
   - Identify target audience (end users, developers, etc.)
   - Specify documentation standards to follow

3. **Harpo updates relevant documentation**
   - README files with new features
   - API documentation for new endpoints
   - User guides for new functionality
   - Code comments and docstrings
   - CHANGELOG entries
   - Architecture Decision Records (if needed)
   - **Harpo adds todos for documentation tasks** with [Harpo] prefix

4. **Ensure docs reflect changes accurately**
   - Verify documentation matches implementation
   - Check examples are correct
   - Ensure completeness

5. **Complete Phase 6**
   - Mark "Phase 6: Document with Harpo" as completed
   - Mark "Get user approval to proceed to Phase 7" as in_progress
   - Ask: "May I proceed to Phase 7: Reflection?"
   - Wait for user confirmation

## Critical Anti-Patterns

**❌ "Documenting while coding"**

Documentation belongs to Phase 6, not Phase 3. Implementation may change during review/testing.

**❌ "Skipping documentation because feature is self-explanatory"**

No feature is self-explanatory. Users need docs. Future you needs docs.

## Key Takeaways

- Harpo handles all documentation
- Update README, API docs, user guides as needed
- Documentation must match implementation
- Don't skip this phase
