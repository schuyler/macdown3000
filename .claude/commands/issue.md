---
description: Process a GitHub issue end-to-end with agent collaboration
---

# GitHub Issue Processor

Process a GitHub issue from requirements gathering through implementation to pull request creation.

## Configuration

- **Repository:** https://github.com/schuyler/macdown3000
- **Token:** `tvguho_cng_11NNNBO7N0iSCBnoyoHyE5_KAQlrfJKE2lehsWwNSlGG6OcBtD3hAx8e71mQzCkJn0RB44TJDD9C5o2Y2i` (use rot13 to decode)

**IMPORTANT:** The `gh` CLI tool is NOT available in this environment. All GitHub operations must be performed using `curl` with the decoded PAT token as shown in the examples throughout this workflow.

### Decoding and Caching the Token

**CRITICAL:** Decode and cache the token ONCE at the start of the workflow. Do NOT decode it repeatedly in every API call.

**Recommended approach - Cache to file:**
```bash
# Decode and save to temporary file (do this ONCE at the start)
python3 -c "import codecs; print(codecs.decode('tvguho_cng_11NNNBO7N0iSCBnoyoHyE5_KAQlrfJKE2lehsWwNSlGG6OcBtD3hAx8e71mQzCkJn0RB44TJDD9C5o2Y2i', 'rot_13'))" > /tmp/token.txt

# Use in all subsequent API calls
TOKEN=$(cat /tmp/token.txt)
```

**Alternative - Cache to variable (for simple bash scripts):**
```bash
bash << 'EOF'
TOKEN=$(echo "tvguho_cng_11NNNBO7N0iSCBnoyoHyE5_KAQlrfJKE2lehsWwNSlGG6OcBtD3hAx8e71mQzCkJn0RB44TJDD9C5o2Y2i" | tr 'A-Za-z' 'N-ZA-Mn-za-m')
# All your API calls go here
EOF
```

## Workflow

### Step 1: Decode Token and Fetch Issue

Extract the issue number from the command arguments (accept both `123` and `#123` formats).

**First, decode and cache the token** (do this ONCE):
```bash
python3 -c "import codecs; print(codecs.decode('tvguho_cng_11NNNBO7N0iSCBnoyoHyE5_KAQlrfJKE2lehsWwNSlGG6OcBtD3hAx8e71mQzCkJn0RB44TJDD9C5o2Y2i', 'rot_13'))" > /tmp/token.txt
```

Then fetch the issue from GitHub:
```bash
TOKEN=$(cat /tmp/token.txt)
curl -H "Authorization: token $TOKEN" \
  https://api.github.com/repos/schuyler/macdown3000/issues/{number}
```

Present the issue title, body, and any relevant details to the user.

### Step 2: Gather Requirements

Ask the user clarifying questions about:
- Scope and boundaries of the work
- Expected behavior and edge cases
- Design preferences or constraints
- Whether test-driven development should be used

**CRITICAL:** Continue asking questions until you have complete clarity. Do NOT proceed to Step 3 until the user explicitly confirms all requirements are addressed.

### Step 3: Wait for User Confirmation

**STOP HERE** and wait for the user to explicitly confirm that all requirements have been addressed and you can proceed with planning.

### Step 4: Document Requirements on GitHub

Post a comment to the GitHub issue documenting all requirements, clarifications, and decisions made during Step 2.

Use this API call (with decoded token):
```bash
curl -X POST \
  -H "Authorization: token {decoded_token}" \
  -H "Content-Type: application/json" \
  -d '{"body": "COMMENT_TEXT_HERE"}' \
  https://api.github.com/repos/schuyler/macdown3000/issues/{number}/comments
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

Create and switch to the branch:
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

#### 10c. Get Workflow Run ID

Wait 10 seconds for the workflow to start, then fetch the latest workflow run for your branch using the decoded token:

```bash
# URL-encode the branch name (required for branches with special characters like /)
ENCODED_BRANCH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{branch-name}'))")

# Get the workflow run ID with error handling
RUN_ID=$(curl -s -H "Authorization: token {decoded_token}" \
  "https://api.github.com/repos/schuyler/macdown3000/actions/runs?branch=${ENCODED_BRANCH}&event=push&per_page=1" \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    runs = data.get('workflow_runs', [])
    print(runs[0]['id'] if runs else '')
except Exception as e:
    print('', file=sys.stderr)
    sys.exit(0)
")

if [ -z "$RUN_ID" ]; then
  echo "Waiting for workflow to start..."
  sleep 10
  # Try again
  RUN_ID=$(curl -s -H "Authorization: token {decoded_token}" \
    "https://api.github.com/repos/schuyler/macdown3000/actions/runs?branch=${ENCODED_BRANCH}&event=push&per_page=1" \
    | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    runs = data.get('workflow_runs', [])
    print(runs[0]['id'] if runs else '')
except Exception:
    sys.exit(0)
")
fi

if [ -z "$RUN_ID" ]; then
  echo "ERROR: Could not find workflow run for branch {branch-name}"
  echo "Check GitHub Actions: https://github.com/schuyler/macdown3000/actions"
  exit 1
fi

echo "Workflow Run ID: $RUN_ID"
```

#### 10d. Monitor Workflow Status

Poll the workflow status every 30 seconds until it completes. Use the decoded token:

```bash
# Show workflow URL to user
WORKFLOW_URL=$(curl -s -H "Authorization: token {decoded_token}" \
  "https://api.github.com/repos/schuyler/macdown3000/actions/runs/$RUN_ID" \
  | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('html_url', ''))")

echo "Monitoring workflow at: $WORKFLOW_URL"

# Poll until completion with timeout
ELAPSED=0
MAX_WAIT=900  # 15 minutes

while [ $ELAPSED -lt $MAX_WAIT ]; do
  RESPONSE=$(curl -s -H "Authorization: token {decoded_token}" \
    "https://api.github.com/repos/schuyler/macdown3000/actions/runs/$RUN_ID")

  STATUS=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('status', 'unknown'))
except Exception:
    print('error')
")

  CONCLUSION=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('conclusion', 'N/A'))
except Exception:
    print('N/A')
")

  echo "[$(date +%H:%M:%S)] Status: $STATUS, Conclusion: $CONCLUSION"

  if [ "$STATUS" = "completed" ]; then
    break
  fi

  sleep 30
  ELAPSED=$((ELAPSED + 30))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  echo "WARNING: Workflow still running after 15 minutes"
  echo "You can continue monitoring at: $WORKFLOW_URL"
  # Ask user if they want to continue waiting
fi
```

#### 10e. Check Results

Once the workflow completes (status is "completed"), check the conclusion:

- **success**: Tests passed! Proceed to Step 11.
- **failure**: Tests failed. Analyze the logs and fix the issues.
- **cancelled** or **skipped**: Report to user for guidance.

To get detailed job information and logs if tests fail:

```bash
# Get the job ID (prefer failed jobs, fallback to first job)
JOB_ID=$(curl -s -H "Authorization: token {decoded_token}" \
  "https://api.github.com/repos/schuyler/macdown3000/actions/runs/$RUN_ID/jobs" \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    if not jobs:
        print('')
        sys.exit(0)

    # Prefer failed jobs
    failed = [j for j in jobs if j.get('conclusion') == 'failure']
    job = failed[0] if failed else jobs[0]
    print(job.get('id', ''))
except Exception:
    print('')
")

if [ -z "$JOB_ID" ]; then
  echo "ERROR: Could not find job information"
  exit 1
fi

# Get logs for the job (use -L to follow redirects)
echo "Fetching logs for job $JOB_ID..."
curl -sL -H "Authorization: token {decoded_token}" \
  "https://api.github.com/repos/schuyler/macdown3000/actions/jobs/${JOB_ID}/logs"
```

**Important:** The logs endpoint returns a redirect (302) to the actual log file. The `-L` flag makes curl follow redirects.

Analyze the logs to identify which tests failed and why.

#### 10f. Handle Test Failures

If tests fail:
1. Review the job logs from the API response
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

#### 13a. Fetch Latest from Remote

```bash
git fetch origin main
```

#### 13b. Rebase on Main

```bash
git rebase origin/main
```

#### 13c. Handle Conflicts (If Any)

If conflicts occur during rebase:

1. **Attempt to resolve automatically** - Analyze the conflicts and resolve them based on:
   - The requirements and implementation plan
   - Groucho's architectural guidance
   - The nature of the conflicting changes

2. **Only ask the user if:**
   - The conflicts are too complex to resolve confidently
   - The resolution requires business logic decisions
   - You're unsure which changes should take precedence

3. **After resolving conflicts:**
   - Stage the resolved files: `git add <resolved-files>`
   - Continue the rebase: `git rebase --continue`
   - **Return to Step 9** to re-implement or adjust as needed
   - **Re-run all tests** via CI (Step 10)
   - **Consult Chico** (Step 11) to review the conflict resolution
   - **Continue through Steps 12-13** until rebase succeeds without conflicts

4. **Abort if stuck:**
   - If unable to resolve: `git rebase --abort`
   - Inform the user and ask for guidance

### Step 14: Force Push After Rebase

If the rebase modified history (you rebased commits that were already pushed), you'll need to force push:

```bash
git push --force-with-lease origin {branch-name}
```

**IMPORTANT:** Only use force push if you rebased already-pushed commits. If this is the first push or you only added new commits, a regular push is sufficient.

If network errors occur, retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s).

### Step 15: Re-verify Tests After Rebase

After rebasing and pushing, the CI will run again. Monitor the new workflow run:

1. Wait 10 seconds for the workflow to start
2. Get the new workflow run ID (same API call as Step 10c)
3. Monitor status until completion (same as Step 10d)
4. Verify tests pass (same as Step 10e)

If tests fail after rebase, return to Step 9 to fix issues.

### Step 16: Create Pull Request

Use the GitHub API to create a pull request (with decoded token):

```bash
curl -X POST \
  -H "Authorization: token {decoded_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Address issue #{number}: {title}",
    "head": "{branch-name}",
    "base": "main",
    "body": "## Summary\n\n{description of changes}\n\n## Related Issue\n\nRelated to #{number}\n\n## Manual Testing Plan\n\n{include Zeppo'\''s plan if provided, otherwise state \"N/A\"}\n\n## Review Notes\n\n{any relevant notes from agent consultations}"
  }' \
  https://api.github.com/repos/schuyler/macdown3000/pulls
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

Manual Testing: {included/not applicable}

The pull request is ready for your review and manual testing. The issue will remain open for you to close after verification.
```

## Important Reminders

1. **Use TodoWrite extensively** - Track every step, update status as you progress
2. **Fresh eyes at each step** - Challenge assumptions, verify you're on track
3. **Stop for user confirmation** - Don't proceed past Step 3 without explicit approval
4. **Document requirements** - Always post clarifications to GitHub issue
5. **Iterate with agents** - If they have concerns, address them before proceeding
6. **No auto-close** - Never use "Fixes #" or "Closes #" in commits or PR
7. **Run in parallel** - Harpo and Zeppo consultations in Step 12 should run simultaneously
8. **Decode ROT13 token** - Always decode the token before using it in API calls
9. **No co-authored-by** - The project has `includeCoAuthoredBy: false` configured. Do NOT add "Co-authored-by:" trailers to commits or mention co-authorship in PRs
