# Phase 7: REFLECT

## Objective

Record learnings for continuous improvement.

## Why This Exists

Session reflections identify instruction gaps, reveal project preferences, and enable workflow improvement over time.

## Protocol

1. **Get user approval to proceed to Phase 7**
   - Mark "Get user approval to proceed to Phase 7" as in_progress
   - Ask: "Would you like me to record learnings from this session?"
   - Wait for user confirmation
   - Mark as completed only after user confirms

2. **If approved, read template and create REFLECTION.md**
   - Read `assets/REFLECTION.md` as a guide
   - Write to `docs/sessions/YYYYMMDD-HHMM-<slug>/REFLECTION.md`
   - Use user's current timezone for timestamp

3. **Required sections**
   - **Task Summary**: Brief description of what was accomplished
   - **User Corrections**: Each time user corrected you, explain reasoning and identify gap
   - **Project Preferences Revealed**: Patterns or preferences discovered
   - **Todos Completed**: Which todos were completed during this session
   - **Workflow Observations**: What worked well or needs improvement

4. **Gap types for User Corrections**
   - **coverage**: No instruction existed for this situation
   - **effectiveness**: Instruction exists but failed to prevent issue
   - **clarity**: Instruction was misunderstood or ambiguous
   - **error**: No gap, you simply made an error

5. **Complete Phase 7**
   - Mark "Phase 7: Reflect on implementation" as completed
   - Session complete

## Critical Anti-Patterns

**❌ "Skipping reflection because everything went smoothly"**

Even smooth sessions reveal preferences and patterns worth documenting.

**❌ "Not recording user corrections"**

User corrections are the most valuable data for improving instructions.

## Key Takeaways

- Always suggest recording learnings
- Document user corrections with gap analysis
- Capture project preferences
- Ask about file cleanup
