# Phase 5: VERIFY

## Objective

Ensure implementation works correctly through testing.

## Why This Exists

Zeppo prevents: shipping untested code, missing edge cases, undiscovered bugs, no verification strategy.

## Protocol

1. **Get user approval to consult Zeppo**
   - Mark "Get user approval to consult Zeppo" as in_progress
   - Ask: "May I consult Zeppo to create a testing strategy?"
   - Wait for user confirmation
   - Mark as completed only after user confirms

2. **Consult Zeppo**
   - Provide complete implementation from Phase 3
   - Reference to REQUIREMENTS.md
   - Any specific concerns about functionality

3. **Receive Zeppo's testing strategy**
   - Automated tests to write/run
   - Manual verification steps
   - Edge cases to test
   - Performance considerations
   - **Zeppo adds todos for test tasks** with [Zeppo] prefix

4. **Read template and create TESTING.md**
   - Read `assets/TESTING.md` as a guide
   - Write verification plan to `docs/sessions/YYYYMMDD-HHMM-<slug>/TESTING.md`
   - Include: Test strategy, automated tests, manual verification steps, edge cases, test results

5. **Execute tests**
   - Run automated tests
   - Perform manual verification
   - Check edge cases
   - Validate against requirements

6. **Do not close task until tests pass**
   - All tests must pass
   - Address issues discovered
   - Ask if user wants to update TESTING.md with results

7. **Complete Phase 5**
   - Mark "Phase 5: Verify with Zeppo" as completed
   - Mark "Get user approval to consult Harpo" as in_progress
   - Ask: "May I consult Harpo for documentation?"
   - Wait for user confirmation

## Critical Anti-Patterns

**❌ "Skipping Zeppo because tests seem obvious"**

Even "obvious" testing benefits from systematic approach. Zeppo identifies edge cases you miss.

**❌ "Proceeding with failing tests"**

All tests must pass before moving to documentation. Don't leave broken functionality.

## Key Takeaways

- Zeppo creates comprehensive test strategy
- Write test plan to TESTING.md
- Execute all tests (automated and manual)
- Don't proceed until all tests pass
