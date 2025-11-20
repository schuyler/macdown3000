# Session Resumption

## Objective

Resume interrupted sessions by detecting completed phases and loading context.

## Why This Exists

Users may need to pause and resume feature work. File existence indicates phase completion, enabling precise resumption point detection.

## Resumption Detection Protocol

### 1. Detect resumption request

User provides session slug without "implement" verb:
- ✓ "Continue session-resumption"
- ✓ "Resume auth-flow"
- ✗ "Implement user-login" (fresh start)

### 2. Locate matching sessions

```bash
find docs/sessions -type d -name "*-<slug>" | sort -r
```

Multiple matches → Ask user which to use (show timestamps).

### 3. Map file existence to completed phases

Check session directory for phase files:

| File exists | Phase completed | Resume at |
|-------------|-----------------|-----------|
| None | Nothing | Phase 1 (fresh start) |
| REQUIREMENTS.md | Phase 1 | Phase 2 (PLAN) |
| PLAN.md | Phase 2 | Phase 3 (IMPLEMENT) |
| IMPLEMENTATION.md | Phase 3 | Infer: Phase 4 or 5 |
| TESTING.md | Phase 5 | Infer: Phase 6 or 7 |
| REFLECTION.md | Phase 7 | Session complete |

**Progressive disclosure**: Files created when entering each phase, not at initialization.

**Phase 4 and 6 inference**: These phases (REVIEW, DOCUMENT) don't create files. When ambiguous:
- If IMPLEMENTATION.md exists but TESTING.md doesn't → Ask user: "Resume at Phase 4 (REVIEW) or Phase 5 (VERIFY)?"
- If TESTING.md exists but REFLECTION.md doesn't → Ask user: "Resume at Phase 6 (DOCUMENT) or Phase 7 (REFLECT)?"

### 4. Load context from existing files

Read ALL existing phase files in session directory:
- REQUIREMENTS.md → requirements, constraints, success criteria
- PLAN.md → implementation approach, files to modify, architectural decisions
- IMPLEMENTATION.md → what was implemented, how it works
- TESTING.md → test strategy, verification results
- REFLECTION.md → learnings, corrections

### 5. Present resumption summary to user

**Example 1: Clear resumption point**
```
"Found session: docs/sessions/20251020-2342-session-resumption

Completed phases:
✓ Phase 1: GATHER REQUIREMENTS
✓ Phase 2: PLAN

Context loaded:
- Requirements: Session resumption with progressive disclosure
- Plan: File-based phase detection using existence markers

Next: Phase 3 (IMPLEMENT)

Proceed with Phase 3?"
```

**Example 2: Ambiguous resumption point (requires user clarification)**
```
"Found session: docs/sessions/20251020-2342-add-metrics

Completed phases:
✓ Phase 1: GATHER REQUIREMENTS
✓ Phase 2: PLAN
✓ Phase 3: IMPLEMENT

Context loaded:
- Requirements: Add usage metrics tracking and export
- Plan: Create metrics collection system with CSV/JSON export
- Implementation: Metrics service and export handlers created

IMPLEMENTATION.md exists but TESTING.md does not.

Resume at Phase 4 (REVIEW) or Phase 5 (VERIFY)?"
```

### 6. Resume at next phase

Load appropriate phase reference and continue workflow.

## Multiple Session Handling

When multiple sessions match slug:

```
"Multiple sessions found for 'session-resumption':

1. docs/sessions/20251020-2342-session-resumption (Oct 20, 11:42pm)
   - Last phase: IMPLEMENT

2. docs/sessions/20251019-1056-session-resumption (Oct 19, 10:56am)
   - Last phase: PLAN

Which session should I resume?"
```

Wait for user selection.

## Critical Anti-Patterns

**❌ "Resuming without reading context"**

Always read ALL existing phase files. Context is critical for continuity.

**❌ "Assuming IMPLEMENTATION.md means implementation is done"**

IMPLEMENTATION.md created at end of Phase 3 (before REVIEW). Phase 3 complete, but Phase 4 still needed.

## Key Takeaways

- File existence = phase completion marker
- Progressive disclosure prevents false positives
- Always load complete context before resuming
- Multiple matches require user selection
