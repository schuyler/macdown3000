# Phase 3: IMPLEMENT

## Objective

Execute plan step-by-step with reviewable increments.

## Why This Exists

Step-by-step prevents: context overload, no course correction opportunity, overwhelming changes, "while I'm here" scope creep.

## Step Boundaries

- One step = one logical unit (function, model, endpoint, file section, config change)
- Maximum 50 lines per step
- No "while I'm here" additions
- Break down plan before starting

## Step Execution Protocol with TodoWrite

**MANDATORY for every step:**

1. **Create step todos** from the plan
   - Add todos for each implementation step
   - Use descriptive names (no step numbers)
   - Keep max 50 lines per step
2. **Mark current step in_progress**
3. **Perform ONLY that step's work** (no extras, no unrelated fixes)
4. **Mark step completed**
5. **User can confirm or request changes** before next step

Never write entire files in one response unless explicitly instructed.

## Granularity Examples

**❌ BAD - Too coarse:**
```
Step 1: Implement the authentication system
```

**✅ GOOD - Right granularity:**
```
Step 1: Create User model with email/password fields (~25 lines)
Step 2: Add password hashing function using bcrypt (~30 lines)
Step 3: Add password comparison function (~20 lines)
Step 4: Create login endpoint that validates credentials (~35 lines)
Step 5: Add JWT token generation function (~40 lines)
```

## After All Steps Complete

1. **Read template and create IMPLEMENTATION.md**
   - Read `assets/IMPLEMENTATION.md` as a guide
   - Write implementation summary to `docs/sessions/YYYYMMDD-HHMM-<slug>/IMPLEMENTATION.md`
   - Include: Completed steps, files changed, code comments status, deviations from plan

2. **Offer to add code comments** (if appropriate)

3. **Do NOT run tests (Phase 5) or update docs (Phase 6)**

4. **Complete Phase 3**
   - Mark "Phase 3: Implement" as completed
   - Mark "Get user approval to consult Chico" as in_progress
   - Ask: "May I consult Chico to review this implementation?"
   - Wait for user confirmation

## Critical Anti-Patterns

**❌ "Batching multiple steps"**

One step at a time. ONLY batch if user explicitly instructs: "Do all remaining steps without asking."

**❌ "While I'm here" additions**

Stay focused on current step. If you notice something else, propose it as a separate step.

## Key Takeaways

- One step = one logical unit (max 50 lines)
- Always mark in_progress, perform, mark completed, wait for confirmation
- No "while I'm here" additions
- Break down plan before starting
- Phase boundaries: code only, no testing or docs
