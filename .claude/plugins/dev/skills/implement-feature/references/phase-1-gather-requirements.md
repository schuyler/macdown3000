# Phase 1: GATHER REQUIREMENTS

## Objective

Understand what the user needs before jumping to solutions.

## Why This Exists

Without clear requirements, you can't build the right thing. This prevents building the wrong feature, missing requirements, and having no success criteria.

## Protocol

1. **Ask clarifying questions** (2-4 at a time)
   - What is the user trying to achieve?
   - What specific functionality is needed?
   - Are there constraints or preferences?
   - What does success look like?

2. **Confirm understanding**
   - Summarize what you've understood
   - Ask: "Is there anything else?" and "Are there edge cases?"

3. **Create session directory**
   ```bash
   scripts/init_session.sh <feature-slug>
   ```
   Use lowercase-with-hyphens (e.g., `user-authentication`)

4. **Read template and create REQUIREMENTS.md**
   - Read `assets/REQUIREMENTS.md` as a guide
   - Write complete requirements to `docs/sessions/YYYYMMDD-HHMM-<slug>/REQUIREMENTS.md`
   - Include: Summary, detailed requirements, constraints, user preferences, success criteria, documentation links (if fetched)

5. **Store documentation links**
   If you fetch API docs or references, include them in REQUIREMENTS.md. These MUST be passed to Groucho in Phase 2.

6. **Complete Phase 1 todos**
   - Mark "Create session directory and REQUIREMENTS.md" as completed
   - Mark "Phase 1: Gather requirements" as completed
   - Mark "Get user approval to consult Groucho" as in_progress
   - Ask user for approval to proceed to Phase 2

## Critical Anti-Patterns

**❌ Assuming requirements are obvious**

Don't assume the approach. User says "add authentication" - ask about method, features, constraints first.

**❌ Incomplete requirements**

"Add CSV export" is too vague. Include specific functionality, constraints, success criteria, edge cases.

## Key Takeaways

- Focus on needs, not solutions
- Ask questions incrementally
- Document everything
- Store documentation links for Groucho
