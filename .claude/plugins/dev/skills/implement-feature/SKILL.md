---
name: implement-feature
description: This skill should be used when implementing non-trivial software features that require planning, review, testing, and documentation. It orchestrates a team of specialized development agents (Groucho, Chico, Zeppo, Harpo) through a rigorous 7-phase workflow to ensure features are properly architected, implemented, reviewed, verified, and documented. Use this skill for multi-file features, new functionality, or any work where quality and thoroughness matter. Do not use for trivial single-line fixes or quick experimental prototypes.
---

# Implement Feature

## Core Principles

**1. Ambiguity means proceed strictly**

When uncertain whether an approval todo applies, that uncertainty is the reason to apply it. The process exists precisely for situations where you're tempted to skip it.

**2. Phase boundaries are strict**

- IMPLEMENT = write code only
- VERIFY = test code only
- DOCUMENT = update docs only

**3. Step-by-step prevents overwhelm**

One logical unit per step (max 50 lines). Wait for confirmation between steps.

## Development Team

- **Groucho** - Architectural advisor (Phase 2). Ensures new code aligns with existing patterns.
- **Chico** - Code reviewer (Phase 4). Verifies implementation meets requirements.
- **Zeppo** - Debugger and tester (Phase 5). Creates testing strategies.
- **Harpo** - Documentation specialist (Phase 6). Updates documentation.

## TodoWrite Management

**Use TodoWrite to track all workflow progress:**

1. **Initialize phase todos at skill start**
   - Create todo for each of the 7 phases
   - Add approval todos between phases
   - Write initial state to TODO.md

2. **Expand phases just-in-time**
   - When entering a phase, add its specific subtasks
   - Use natural list ordering (no step numbers)
   - Insert new todos at appropriate position as work progresses

3. **Exactly ONE todo in_progress at a time**
   - Mark current task as in_progress
   - Complete it before starting next
   - This prevents skipping steps

4. **Approval todos enforce gates**
   - "Get user approval to proceed to Phase X"
   - "Get user approval to consult [Agent]"
   - Mark in_progress when asking
   - Complete only after user confirms

5. **Persist state to TODO.md**
   - Update TODO.md after completing each phase
   - Update TODO.md when agents add todos
   - Enables session resumption with exact state

6. **Agent coordination via shared todo list**

   All agents work on ONE shared todo list for complete visibility:

   - **Agents create todos for their domain** with [AgentName] prefix
     - Chico creates: "[Chico] Review error handling"
     - Zeppo creates: "[Zeppo] Run integration tests"
     - Harpo creates: "[Harpo] Update API documentation"

   - **Agents mark their own todos in_progress/completed**
     - When Chico adds review todos, Chico marks them completed
     - Main agent sees Chico's findings in shared list

   - **Main agent creates and completes implementation todos**
     - No prefix or [Main] for implementation work
     - Main agent fixes issues identified by other agents

   - **Exactly ONE in_progress applies globally**
     - Prevents main agent and subagents from conflicting work
     - Todo list shows who is working on what in real-time

## Session Structure

```
docs/sessions/YYYYMMDD-HHMM-<slug>/
├── TODO.md           (Persistent todo state, updated throughout)
├── REQUIREMENTS.md   (Phase 1)
├── PLAN.md          (Phase 2)
├── IMPLEMENTATION.md (Phase 3)
├── TESTING.md       (Phase 5)
└── REFLECTION.md    (Phase 7)
```

Initialize: `scripts/init_session.sh <feature-slug>`

**TODO.md persistence:**
- Write current todo list state to TODO.md after each phase completes
- Enables session resumption with exact workflow state
- Format: Simple markdown checklist matching TodoWrite state
- Main agent and all subagents update same shared TODO.md

## The 7 Phases

### Phase 1: GATHER REQUIREMENTS
Understand what the user needs.

- Ask clarifying questions
- Confirm understanding
- Create session directory
- Write requirements to REQUIREMENTS.md
- Store documentation links for Groucho

Load `references/phase-1-gather-requirements.md` for details.

---

### Phase 2: PLAN
Create implementation plan aligned with existing patterns.

- Get user approval to consult Groucho
- Provide: requirements, docs from Phase 1, constraints, preferences
- Present complete plan
- Write to PLAN.md
- Get user approval to proceed to Phase 3

Load `references/phase-2-plan.md` for details.

---

### Phase 3: IMPLEMENT
Execute plan step-by-step.

- Create todo for each implementation step
- One step = one logical unit (max 50 lines)
- Complete each todo before starting next
- User can confirm or request changes between steps

Load `references/phase-3-implement.md` for details.

---

### Phase 4: REVIEW
Verify implementation meets requirements.

- Get user approval to consult Chico
- Have Chico review all Phase 3 code
- Chico adds todos for issues found
- Fix issues one at a time
- Ask if Chico should re-review
- Don't claim completion until approved

Load `references/phase-4-review.md` for details.

---

### Phase 5: VERIFY
Ensure implementation works correctly.

- Get user approval to consult Zeppo
- Get testing strategy from Zeppo
- Zeppo adds todos for test tasks
- Write verification plan to TESTING.md
- Execute tests
- Don't close until tests pass

Load `references/phase-5-verify.md` for details.

---

### Phase 6: DOCUMENT
Update documentation.

- Get user approval to consult Harpo
- Have Harpo update relevant docs
- Harpo adds todos for documentation tasks
- Ensure docs reflect changes

Load `references/phase-6-document.md` for details.

---

### Phase 7: REFLECT
Record learnings.

- Get user approval to proceed to Phase 7
- Create REFLECTION.md
- Document: task summary, user corrections, preferences, todos completed
- Ask about cleaning up session files

Load `references/phase-7-reflect.md` for details.

---

## TodoWrite State Recovery

If todo state becomes out of sync:

1. Review current progress honestly
2. Update TodoWrite to reflect actual state
3. Continue from correct position
4. TodoWrite state is the source of truth

## Resources

**scripts/**
- `init_session.sh` - Create session directory

**references/**
- `phase-1-gather-requirements.md`
- `phase-2-plan.md`
- `phase-3-implement.md`
- `phase-4-review.md`
- `phase-5-verify.md`
- `phase-6-document.md`
- `phase-7-reflect.md`
- `session-resumption.md`

**assets/**
- Templates for session phase files

Load phase references only when entering that phase.

## Starting a Task

**If user provides session slug to resume:**
1. Read `docs/sessions/<session-slug>/TODO.md` to reconstruct workflow state
2. Load TodoWrite with state from TODO.md
3. Identify first incomplete todo
4. Mark that todo as in_progress
5. Continue from that point in workflow

**If user requests new feature implementation:**
1. **Do not attempt to solve problems yet**
2. Acknowledge you'll use the 7-phase workflow
3. List all 7 phases
4. **Initialize TodoWrite with phase structure**:
   - Create todo for each of the 7 phases
   - Add approval todos between phases
   - Mark "Phase 1: Gather requirements" as in_progress
   - Write initial state to TODO.md
5. Begin Phase 1
