---
description: Process a GitHub issue end-to-end with agent collaboration
---

# GitHub Issue Processor

Process a GitHub issue from requirements gathering through implementation to pull request creation.

## Configuration

- **Repository:** https://github.com/schuyler/macdown3000

### GitHub CLI

The `gh` CLI is automatically installed via SessionStart hook on Linux. It uses the `GH_TOKEN` environment variable automatically—no manual authentication needed.

## Workflow

### Step 1: Fetch Issue

Extract the issue number from the command arguments (accept both `123` and `#123` formats).

```bash
/tmp/gh/bin/gh issue view {number} --repo schuyler/macdown3000 --json title,body,labels,assignees
```

Present the issue title, body, and any relevant details to the user.

### Step 2: Gather Requirements

Once you have read and understood the issue, thoroughly research the bug or feature described in the issue. Make sure you understand the context before proceeding. Do NOT attempt to solve the problem yet -- we are just gathering requirements.

Once you have educated yourself on the problem, ask the user clarifying questions about:
- Scope and boundaries of the work
- Expected behavior and edge cases
- Design preferences or constraints
- Whether test-driven development should be used

**CRITICAL:** Continue asking questions until you have complete clarity. Do NOT proceed to Step 3 until the user explicitly confirms all requirements are addressed.

### Step 3: Wait for User Confirmation

**STOP HERE** and wait for the user to explicitly confirm that all requirements have been addressed and you can proceed with planning.

### Step 4: Document Requirements on GitHub

Post a comment to the GitHub issue documenting all requirements, clarifications, and decisions made during Step 2.

```bash
/tmp/gh/bin/gh issue comment {number} --repo schuyler/macdown3000 --body "COMMENT_TEXT_HERE"
```

### Step 5: Create Workflow Todos

Use TodoWrite to create detailed todo items for the entire workflow:
- Create issue branch
- Consult Groucho for architectural plan
- Present implementation plan and get user confirmation
- (If TDD) Consult Zeppo for test design
- (If TDD) Write failing tests
- (If TDD) Validate tests with Zeppo
- Implement the feature
- Commit changes and push to trigger CI
- Monitor GitHub Actions workflow until completion
- Verify tests pass in CI
- Consult Chico for code review
- (In parallel) Consult Harpo for documentation updates
- (In parallel) Consult Zeppo for manual testing plan
- Fetch latest and rebase on main
- Force push after rebase (if needed)
- Re-verify tests pass after rebase
- Create pull request
- Report completion

### Step 6: Create Issue Branch

Generate a branch name based on the issue (e.g., `issue-{number}-{brief-description}` or `fix/issue-{number}`).

```bash
git checkout -b {branch-name}
```

All subsequent work will be done on this branch.

### Step 7: Consult Groucho (Architect)

Use the Task tool to launch the Groucho agent:

```
/dev:groucho

I need architectural guidance for implementing GitHub issue #{number}: {title}

Requirements:
{summarize all requirements from Step 2}

Please analyze the codebase and recommend:
1. Which files/components need to be modified
2. Architectural patterns to follow
3. Any potential risks or considerations
4. Implementation approach that aligns with project conventions
```

**Review Groucho's response with FRESH EYES:**
- Does the plan make sense given the requirements?
- Are there any assumptions that need clarification?
- Do you have new questions for the user?

**If you have new questions:** Return to Step 2, ask the user, and when answered, return here to re-consult Groucho.

**If everything is clear:** Proceed to Step 7b to present the plan to the user.

### Step 7b: Present Implementation Plan and Request Confirmation

**STOP HERE** and present the implementation plan to the user for approval.

Provide a clear summary including:

1. **Overview:** Brief description of the implementation approach
2. **Files to be Modified:** List all files that will be changed with a brief description of changes
3. **Implementation Steps:** High-level outline of what will be done (from Groucho's guidance)
4. **Testing Approach:** Whether TDD will be used and what will be tested
5. **Potential Risks:** Any concerns or edge cases identified by Groucho

**Format your summary clearly and ask:**
> "Does this implementation plan look good to you? Should I proceed with [TDD/implementation]?"

**CRITICAL:** Do NOT proceed until the user explicitly confirms approval. Wait for their response.

**After user confirmation:** Proceed to Step 8.

### Step 8: Test-Driven Development (If Applicable)

**Only proceed with this step if:**
- The user confirmed TDD should be used, OR
- The user said to consult Zeppo about testing

#### 8a. Consult Zeppo for Test Design

```
/dev:zeppo

I need to design tests for GitHub issue #{number}: {title}

Requirements:
{summarize requirements}

Implementation plan (from Groucho):
{summarize Groucho's recommendations}

Please recommend:
1. What tests should be written
2. Test structure and organization
3. Edge cases to cover
4. Testing approach that fits this Objective-C/Cocoa project
```

#### 8b. Write Failing Tests

Implement the tests that Zeppo recommended. Ensure they fail (since the feature isn't implemented yet).

Run the tests and verify they fail as expected.

#### 8c. Validate Tests with Zeppo

```
/dev:zeppo

I've written the tests you recommended. Please review:

{describe what tests were written and how they failed}

Do these tests:
1. Correctly validate the requirements?
2. Cover the important edge cases?
3. Follow project testing conventions?

Any feedback or improvements needed?
```

**Iterate:** If Zeppo has feedback, update the tests and re-consult until Zeppo confirms the tests are good.

### Step 9: Implement the Feature

Following Groucho's architectural guidance, implement the feature.

**Review with FRESH EYES at each stage:**
- Am I following the plan?
- Are there edge cases I'm missing?
- Is the code consistent with project conventions?
- Does this fully address the requirements?

If tests exist, run them frequently during implementation.

### Step 10: Commit and Verify Tests via GitHub Actions

Since this is a macOS project and tests can only run on macOS, we'll push to GitHub and let CI run the tests.

#### 10a. Commit Changes

Stage all changes:
```bash
git add .
```

Create a descriptive commit message that references the issue but does NOT auto-close it:
```bash
git commit -m "Address issue #{number}: {brief description}

{detailed description of changes}

Related to #{number}"
```

#### 10b. Push to Trigger CI

Push the branch to remote to trigger GitHub Actions:
```bash
git push -u origin {branch-name}
```

**IMPORTANT:** If push fails with 403, verify the branch name starts with `claude/` and ends with the session ID.

If network errors occur, retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s).

#### 10c. Monitor Workflow Run

Wait 10 seconds for the workflow to start, then monitor it:

```bash
sleep 10

# List recent workflow runs for this branch
/tmp/gh/bin/gh run list --repo schuyler/macdown3000 --branch {branch-name} --limit 1
```

#### 10d. Monitor Workflow Status

Use `gh run watch` to monitor the workflow run until completion:

```bash
/tmp/gh/bin/gh run watch $RUN_ID --repo schuyler/macdown3000 --exit-status
```

This command will automatically poll the workflow status and display updates until it completes or fails.

#### 10e. Check Results

Once the workflow completes, check the conclusion:

- **success**: Tests passed! Proceed to Step 11.
- **failure**: Tests failed. Analyze the logs and fix the issues.
- **cancelled** or **skipped**: Report to user for guidance.

To get logs if tests fail:

```bash
/tmp/gh/bin/gh run view $RUN_ID --repo schuyler/macdown3000 --log
```

#### 10f. Handle Test Failures

If tests fail:
1. Review the job logs
2. Identify the specific test failures
3. Return to Step 9 to fix the issues
4. Commit the fixes
5. Push again (which triggers a new workflow run)
6. Return to 10c to monitor the new run

Iterate until all tests pass.

### Step 11: Consult Chico (Code Reviewer)

```
/dev:chico

I've implemented GitHub issue #{number}: {title}

Requirements:
{summarize requirements}

Changes made:
{summarize all file changes and implementation approach}

Please review:
1. Does the implementation meet all requirements?
2. Are there any bugs or issues?
3. Does it follow project conventions?
4. Any improvements needed?

Focus on critical issues that would prevent this from being merged.
```

**Evaluate Chico's feedback:**
- If there are critical or important issues: Return to Step 9, address them, re-run tests (Step 10), and re-consult Chico
- If only minor suggestions: Note them but proceed
- If no issues: Proceed to Step 12

### Step 12: Documentation and Testing Review (IN PARALLEL)

**IMPORTANT:** Launch both consultations in parallel using multiple Task tool calls in a single message.

#### 12a. Consult Harpo for Documentation Updates

```
/dev:harpo

I've completed work on GitHub issue #{number}: {title}

Changes made:
{summarize implementation}

Please review all documents in the plans/ directory and update any content that needs to reflect these changes.

**IMPORTANT:**
- Only update existing content to reflect reality
- Do NOT add new content
- Keep changes minimal and focused
```

#### 12b. Consult Zeppo for Manual Testing Plan (If Relevant)

```
/dev:zeppo

I've completed GitHub issue #{number}: {title}

Implementation:
{summarize what was built}

If manual testing would be valuable for this change, please provide a detailed manual testing plan that covers:
1. Setup steps
2. Test scenarios
3. Expected results
4. Edge cases to verify

If manual testing is not relevant for this change, please say so.
```

**Wait for both agents to complete**, then:
- Apply any documentation updates from Harpo
- Save Zeppo's manual testing plan (if provided) to include in the PR

### Step 13: Fetch Latest and Rebase on Main

Before the final push, ensure your branch is up-to-date with the main branch.

```bash
git fetch origin main
git rebase origin/main
```

If conflicts occur during rebase:

1. **Attempt to resolve automatically** - Analyze the conflicts and resolve them
2. **Only ask the user if:** conflicts are too complex or require business logic decisions
3. **After resolving:** `git add <files>` then `git rebase --continue`
4. **Abort if stuck:** `git rebase --abort` and ask for guidance

### Step 14: Force Push After Rebase

If the rebase modified history:

```bash
git push --force-with-lease origin {branch-name}
```

If network errors occur, retry up to 4 times with exponential backoff.

### Step 15: Re-verify Tests After Rebase

After rebasing and pushing, monitor the new workflow run and verify tests pass.

### Step 16: Create Pull Request

```bash
/tmp/gh/bin/gh pr create \
  --repo schuyler/macdown3000 \
  --title "Address issue #{number}: {title}" \
  --base main \
  --body "$(cat <<'EOF'
## Summary

{description of changes}

## Related Issue

Related to #{number}

## Manual Testing Plan

{include Zeppo's plan if provided, otherwise state "N/A"}

## Review Notes

{any relevant notes from agent consultations}
EOF
)"
```

**Note:** Do NOT use "Fixes" or "Closes" keywords to avoid auto-closing the issue.

### Step 17: Report Completion

Provide a summary to the user:

```
✅ Completed GitHub Issue #{number}: {title}

Summary:
- {bullet points of what was implemented}

Agent Consultations:
- Groucho: {brief summary of architectural guidance}
- Zeppo: {summary of testing approach/plan}
- Chico: {summary of review outcome}
- Harpo: {summary of documentation updates}

Branch: {branch-name}
Pull Request: {PR URL}

The pull request is ready for your review.
```

## Important Reminders

1. **Use TodoWrite extensively** - Track every step, update status as you progress
2. **Fresh eyes at each step** - Challenge assumptions, verify you're on track
3. **Stop for user confirmation** - Don't proceed past Step 3 without explicit approval
4. **Document requirements** - Always post clarifications to GitHub issue
5. **Iterate with agents** - If they have concerns, address them before proceeding
6. **No auto-close** - Never use "Fixes #" or "Closes #" in commits or PR
7. **Run in parallel** - Harpo and Zeppo consultations in Step 12 should run simultaneously
8. **No co-authored-by** - Do NOT add "Co-authored-by:" trailers to commits
