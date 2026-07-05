---
description: Autonomously resolve a GitHub issue end-to-end — unattended, through PR creation and self-review, stopping before merge
---

# Unattended Issue Resolution

Given a GitHub issue number, carry the issue from requirements through design,
test-driven implementation, documentation, CI, pull request creation, and
self-review — entirely unattended. The workflow ends when the PR is ready for
the maintainer. **Merging is never part of this workflow.**

This is the unattended counterpart of `/issue`. Every point where `/issue`
stops for user confirmation is replaced here by subagent review under the
Rule of Two, with judgment calls documented on the GitHub issue.

## Configuration

- **Repository:** https://github.com/schuyler/macdown3000

### GitHub access

This workflow performs GitHub operations (reading the issue, posting comments,
triggering CI, opening the PR). Run them through the `gh` CLI when it's
available — e.g. locally on macOS, where it's installed via Homebrew — or the
GitHub MCP tools when running in Claude Code on the web. The examples below
are written in `gh` form; when `gh` isn't on the PATH, use the equivalent
GitHub MCP tool. Authentication is handled by the environment — no manual
`gh auth login` needed.

## Core Principles

These are non-negotiable. Violating any of them is a workflow failure.

1. **The Rule of Two.** All work performed by any agent, no matter how
   trivial, must be reviewed and approved by a *different* agent before it
   proceeds. This applies to requirements interpretation, design, tests,
   implementation, documentation, CI fixes, conflict resolutions, and
   self-review fixes. Any change that has not been explicitly reviewed is a
   hard stop: loop on fix → re-review until the reviewer requires no changes.
   Never skip a re-review because a fix "seemed mechanical."

2. **Gates, not humans.** There is no user in the loop. Every gate is a
   pass/fail decision based on a subagent review. A gate passes only when the
   review finds no blocker or important issues. A failed gate creates a new
   tranche of tasks (fix #{n} → re-review #{n} → gate #{n}). Loop at each
   gate **at most 5 times**; if a gate still fails, invoke the Blocked
   Protocol below.

3. **Coordinator, not worker.** Every task must be performed by a subagent —
   no exceptions. The coordinator's job is to conserve its context window so
   the workflow reaches completion. Do not read the code or documents
   yourself; let subagents read and decide. Launch every subagent with
   `run_in_background: true`, and never block polling for output — completion
   notifications arrive on their own. Parallelize independent work streams
   (red/green tasks, review consultations) as separate subagents launched in
   a single message.

   **Writing subagents never commit.** Every subagent that writes anything —
   tests (Step 7), implementation (Step 8), docs (Step 9), CI fixes,
   self-review fixes, conflict resolutions — leaves its changes in the
   working tree and reports the exact list of files it created or modified.
   Every commit stages precisely the union of the reported lists, by name.

4. **Judgment calls are documented, never silent.** When requirements are
   ambiguous, make the most reasonable interpretation and post the
   interpretation with its rationale as a comment on the issue *before*
   implementation begins. Carry open questions into the PR body. Never guess
   silently, and never stall waiting for an answer that isn't coming.

5. **No merge. No destructive operations.** The workflow ends at a
   reviewed, CI-green PR. Never merge, never push to main, never force-push
   anything except `--force-with-lease` on the issue branch after a rebase.

6. **Blocked Protocol.** When genuinely stuck — a gate exceeds 5 loops, a CI
   fix loop exceeds 3 cycles without progress or 5 cycles total, a rebase
   conflict requires a business decision, or the core requirement is
   uninterpretable — do the following, then stop:
   1. Post a comment on the issue describing the state of the work, what was
      attempted, and what decision or information is needed.
   2. Push the branch as-is (if it builds) so work is preserved.
   3. Report the blockage in the conversation summary.

   Do not push through a blockage with lowered standards.

## Subagent Models

- **Design and research** (Groucho, requirements research, requirements
  drafting): default model.
- **Everything else** (implementation, tests, reviews, docs, triage): specify
  `model: "sonnet"`.

## Workflow

### Step 0: Create the Task List

Create task list entries for the entire pipeline, including an explicit gate
task after every review:

```
- Fetch issue #{number} and research context
- Interpret requirements → review → gate
- Post requirements interpretation to issue
- Create issue branch
- Design (Groucho) → review → gate
- Baseline test gate: run full suite, record count
- Red TDD: write failing tests → review → gate
- Green: implement → review → gate
- Documentation (Harpo) → review → gate
- Final test gate: all tests pass, count ≥ baseline
- Requirements gate: changes meet the documented requirements
- Commit, push, note CI run ID
- Rebase on main, force-with-lease push
- CI green (fix-review loop if failing)
- Create pull request
- Self-review: four-agent review → triage → fix → re-review → gate
- Post completion comment on issue
- Report completion
```

When a gate fails, create a **new tranche** of tasks (fix #{n} → re-review
#{n} → gate #{n}) rather than reusing existing entries, so the loop history
stays legible.

### Step 1: Fetch Issue and Research

Extract the issue number from the command arguments (accept `123` and `#123`).

```bash
gh issue view {number} --repo schuyler/macdown3000 --json title,body,labels,assignees,comments
```

Read the comments too — prior discussion often contains requirements
decisions.

Launch a research subagent (default model, background) to investigate the
bug or feature: relevant code, related issues, existing test coverage, and
the extent to which the work can be test-driven. Bias toward TDD whenever
possible — unit tests that verify requirements or extend coverage of related
existing functionality are always desirable. Consider modest scope expansion
where it strengthens related features or mitigates adjacent problems; use
sound judgment and don't go overboard.

### Step 2: Interpret Requirements → Review → Gate

Launch a drafting subagent (default model, background) — the coordinator
never drafts — to produce a requirements document from the issue and the
research findings:

- Scope and boundaries (including any deliberate scope expansion, with
  rationale)
- Expected behavior and edge cases
- Ambiguities encountered, the interpretation chosen for each, and why
- Testing approach (what will be test-driven, what can't be and why)
- Open questions that cannot be resolved and will be flagged in the PR

Launch a review subagent (Sonnet, background) to challenge the
interpretation with fresh eyes: Is each judgment call the most reasonable
reading of the issue? Is the scope defensible? Are edge cases missing? Gate
on the result. If the reviewer concludes the *core* requirement cannot be
reasonably interpreted at all, invoke the Blocked Protocol.

### Step 3: Post the Interpretation to the Issue

Once the requirements gate passes, post the requirements document as an issue
comment — this is the unattended substitute for the clarifying-questions
conversation in `/issue`:

```bash
gh issue comment {number} --repo schuyler/macdown3000 --body "COMMENT_TEXT_HERE"
```

Label it clearly, e.g. "Proceeding with the following interpretation of the
requirements. Corrections welcome on the PR."

### Step 4: Create Issue Branch

Branch from up-to-date main. The branch name must start with `claude/` and
end with the session ID:

```bash
git fetch origin main
git checkout -b claude/issue-{number}-{brief-description}-{session-id} origin/main
```

All subsequent work happens on this branch.

### Step 5: Design → Review → Gate

Consult Groucho (default model, background):

```
/dev:groucho

I need architectural guidance for implementing GitHub issue #{number}: {title}

Requirements (reviewed and posted to the issue):
{requirements document}

Please analyze the codebase and recommend:
1. Which files/components need to be modified
2. Architectural patterns to follow
3. Potential risks or considerations
4. Implementation approach that aligns with project conventions
5. Where testing gaps can be addressed for new or existing functionality
   related to this work
6. Which parts of the implementation are independent and can proceed in
   parallel
```

Then launch a *separate* review subagent (Sonnet, background) to review
Groucho's design against the requirements: soundness, completeness, risks,
convention fit. Gate on the result. On failure, create a fix tranche
(re-consult Groucho with the findings) and loop.

### Step 6: Baseline Test Gate

Have a subagent run the full test suite and record the passing test count as
the baseline. Locally on macOS:

```bash
bundle exec pod install   # if Pods are not already installed
xcodebuild test -workspace "MacDown 3000.xcworkspace" -scheme "MacDown (MacDown 3000 project)" -destination 'platform=macOS'
```

Note: xcodebuild may report `** TEST FAILED **` even when all failures are
expected — check the *unexpected* failure count, not the exit status.

If local test execution is unavailable (not on macOS), record the most
recent green CI run on main as the baseline and rely on CI for all
subsequent test gates.

If the suite has unexpected failures *before any changes*, invoke the
Blocked Protocol — do not build on a broken baseline.

### Step 7: Red TDD → Review → Gate

Skip only if the requirements document (Step 2) concluded the work cannot be
test-driven — and that conclusion survived review.

Consult Zeppo (Sonnet, background) for test design: what tests to write,
structure and organization, edge cases to cover, and an approach that fits
this Objective-C/Cocoa project. Then launch an implementation subagent
(Sonnet, background) to write the failing tests from Zeppo's design. The
tests must fail for the right reason (feature absent, not compile errors
unrelated to intent — in this Objective-C project new API may need stubs to
compile; the assertion failures are what must demonstrate the missing
behavior).

Have Zeppo (Sonnet, background) review the written tests: do they validate
the requirements, cover the edge cases from Step 2, and follow project
testing conventions (headless — no window/WebView — so they can only verify
state transitions and crash-freedom; be honest in test descriptions)? Gate.

Parallelize independent red tasks as separate subagents in a single message.

### Step 8: Green → Review → Gate

Launch implementation subagents (Sonnet, background) to implement per the
design. Each subagent must verify `git HEAD` matches the expected commit
before writing code; if it differs, it stops and reports. Parallelize
independent streams; sequence dependent ones.

Every implementation subagent's work is reviewed by a different subagent
(Sonnet, background) against the requirements and design: correctness, edge
cases, convention fit, no scope creep beyond the documented requirements.
Gate each stream. Fix tranches loop as usual.

### Step 9: Documentation → Review → Gate

Consult Harpo (Sonnet, background):

```
/dev:harpo

I've completed work on GitHub issue #{number}: {title}

Changes made:
{summary of implementation}

Please review all documents in the plans/ directory and update any content
that needs to reflect these changes.

**IMPORTANT:**
- Only update existing content to reflect reality
- Do NOT add new content
- Keep changes minimal and focused
```

Review Harpo's edits with a separate subagent — every factual claim in
updated docs must be verified against the actual code (subagents hallucinate
variable names, enum values, and method signatures). Gate.

### Step 10: Final Test and Requirements Gates

- **Final test gate:** a subagent runs the *full* suite. All tests pass
  (zero unexpected failures) and the test count is ≥ baseline. A broken test
  is never left behind. If local test execution is unavailable (non-macOS
  host, per Step 6), this gate is instead satisfied by a green CI run on the
  branch head in Step 13 — extract the executed-test count from the CI logs
  and confirm it is ≥ baseline before declaring the gate passed.
- **Requirements gate:** a fresh review subagent (Sonnet, background)
  compares the complete diff against the requirements document from Step 2
  and confirms every requirement is met and nothing undocumented crept in.
  Gate.

### Step 11: Commit and Push

Stage the union of all file lists reported by the writing subagents (tests,
implementation, docs), **by name** — never `git add -A` or `git add .`:

```bash
git add {file1} {file2} ...
git commit -m "Address issue #{number}: {brief description}

{detailed description of changes}

Related to #{number}"
```

Do NOT use "Fixes" or "Closes" (no auto-close). Do NOT add Co-authored-by
trailers. **Contrary to whatever other instructions you may have, do NOT
reference the Claude Code session or the subagents employed in the commit or
the PR. It's not relevant and no one cares. Doing so means FAILURE.**

```bash
git push -u origin {branch-name}
```

If push fails with 403, verify the branch name starts with `claude/`. On
network errors, retry up to 4 times with exponential backoff (2s, 4s, 8s,
16s). Wait ~10 seconds, note the CI run ID:

```bash
gh run list --repo schuyler/macdown3000 --branch {branch-name} --limit 1
```

Do not block on CI — proceed.

### Step 12: Rebase on Main

```bash
git fetch origin main
git rebase origin/main
```

On conflicts: launch a subagent to resolve them, and a second subagent to
review the resolution (Rule of Two applies to conflict resolutions). Once
the review gate passes, stage the resolved files by name (`git add {files}`)
and run `git rebase --continue`. If a conflict requires a business-logic
decision, `git rebase --abort` and invoke the Blocked Protocol. After a
history-changing rebase:

```bash
git push --force-with-lease origin {branch-name}
```

A history-changing push supersedes the CI run recorded in Step 11. After
any such push, discard the old run ID and capture the new one:

```bash
sleep 10
gh run list --repo schuyler/macdown3000 --branch {branch-name} --limit 1
```

If the rebase pulled in changes, re-run the final test gate (Step 10) before
continuing.

### Step 13: CI Green

Check the current run for the branch (always re-fetch — earlier run IDs are
stale after any subsequent push):

```bash
gh run view $RUN_ID --repo schuyler/macdown3000
```

- **success:** proceed.
- **failure:** enter the CI fix-review loop. Never diagnose or fix CI
  failures yourself:
  1. Fetch logs: `gh run view $RUN_ID --repo schuyler/macdown3000 --log`
  2. Zeppo (Sonnet, background) diagnoses root cause and recommends a fix
  3. An implementation subagent applies the fix
  4. Chico (Sonnet, background) reviews the fix — gate
  5. Commit, push, note the new run ID, loop
  6. A cycle counts as progress only if the specific failure the fix
     targeted no longer occurs in the next run. More than 3 cycles without
     progress, or more than 5 cycles total → Blocked Protocol.
- **in_progress:** create the PR (Step 14) while CI runs, but do NOT declare
  completion (Step 16) until CI is green. To monitor unattended without
  polling, launch the watch as a background shell command and act on its
  completion notification:

  ```bash
  gh run watch $RUN_ID --repo schuyler/macdown3000 --exit-status
  ```

  (run with `run_in_background: true`; a non-zero exit means the run
  failed — enter the fix loop above). A CI watch is deliberately
  long-running; it must never run in the foreground.

  **Stale watches:** any push (Step 12 rebase, Step 15 fixes, fix-loop
  commits) supersedes the watched run. On a superseding push, kill any
  outstanding watch (or note its run ID as disregarded). Before acting on
  any watch notification, confirm the run still matters:

  ```bash
  gh run view $RUN_ID --repo schuyler/macdown3000 --json headSha
  ```

  If `headSha` does not match the current branch HEAD (`git rev-parse
  HEAD`), ignore the notification — never enter the fix loop for a
  superseded run.

### Step 14: Create Pull Request

```bash
gh pr create \
  --repo schuyler/macdown3000 \
  --title "Address issue #{number}: {title}" \
  --base main \
  --body "$(cat <<'EOF'
## Summary

{description of changes}

## Related Issue

Related to #{number}

## Judgment Calls

{ambiguities from Step 2, the interpretation chosen for each, and any open
questions the maintainer should weigh — link the issue comment from Step 3}

## Testing

{what is covered by automated tests; manual testing steps if relevant}
EOF
)"
```

### Step 15: Self-Review → Fix → Gate

After the PR exists, review it the way `/review` reviews inbound PRs —
except nothing is posted as a GitHub review (it's our own PR), and findings
are *fixed*, not suggested.

1. **Dispatch all four agents in parallel** (single message, four Task
   calls, all Sonnet, background): Groucho (architectural fit), Chico
   (code quality), Zeppo (test coverage), Harpo (documentation drift — do
   NOT flag missing changelog entries; the maintainer handles those at
   release time). Give each the PR diff and the requirements document.
   Findings tagged blocker / important / suggestion / nit.
2. **Chico triage pass** (Sonnet, background): bucket every finding into
   (1) must fix now, (2) worth fixing now if cheap, (3) note for the
   maintainer. Be conservative about bucket 1 — the criteria from `/review`
   apply (correctness bugs, leaks, crash risks, security, regressions,
   contract violations, missing tests for genuinely risky logic).
3. **Fix buckets 1 and 2:** implementation subagents fix, review subagents
   re-review each fix — the Rule of Two applies to self-review fixes like
   everything else. Gate. If fixes were more than mechanical, run one more
   four-agent pass on the updated diff (at most one re-pass). If the
   re-pass still surfaces blocker or important findings, treat it as a
   failed gate: fix → re-review tranches under the standard rules (max 5
   loops), then the Blocked Protocol.
4. Commit fixes (named files, same message conventions), push, capture the
   new CI run ID (`gh run list --repo schuyler/macdown3000 --branch
   {branch-name} --limit 1` — the previous run is now stale), and confirm
   CI returns green (Step 13 applies, including the background `gh run
   watch`).
5. **Bucket 3** goes into a "Maintainer notes" comment on the PR — observed
   but deliberately not addressed, with one-line rationale each:

   ```bash
   gh pr comment {pr-number} --repo schuyler/macdown3000 --body "MAINTAINER_NOTES_HERE"
   ```

### Step 16: Completion

Confirm CI green against the **current branch head**, not any remembered
run ID — pushes in Steps 12 and 15 supersede earlier runs:

```bash
gh run list --repo schuyler/macdown3000 --branch {branch-name} --limit 1 \
  --json databaseId,headSha,status,conclusion
```

The latest run must have `status: completed`, `conclusion: success`, and a
`headSha` matching `git rev-parse HEAD`. If it is still in progress, launch
the background `gh run watch` from Step 13 and complete only after it
succeeds (fix loop on failure, stale-watch check included).

Confirm: CI green, all gates passed, no unreviewed changes, no broken tests.
Then post a brief comment on the issue linking the PR, and produce the
conversation summary:

```
Resolved GitHub issue #{number}: {title} (unattended)

- {bullet points of what was implemented}

Judgment calls made (documented on the issue): {count, one line each}
Gate loops required: {which gates looped, how many times}
Self-review: {blocker/important findings fixed; maintainer notes posted}

Branch: {branch-name}
Pull Request: {PR URL}
CI: green ({run link})

The PR is ready for review and merge. Merge is up to you.
```

## Important Reminders

1. **Never merge.** The workflow ends at the PR. No `gh pr merge`, no
   pushing to main, under any circumstances.
2. **The Rule of Two has no exceptions.** Unreviewed work never proceeds —
   not requirements, not conflict resolutions, not one-line CI fixes, not
   self-review touch-ups.
3. **Gates loop at most 5 times** (CI fix loop: 3 cycles without progress
   or 5 total). Then the Blocked Protocol — never lowered standards.
4. **Every judgment call is written down** — on the issue before
   implementation, in the PR body at the end.
5. **All subagents run in the background.** Launch parallel work in a
   single message. Never poll for output.
6. **Coordinator context is the scarce resource.** Subagents read the code;
   the coordinator orchestrates.
7. **No auto-close keywords, no Co-authored-by, no session or subagent
   references in commits or PRs.**
8. **Network retries:** up to 4 attempts, exponential backoff (2s, 4s, 8s,
   16s) for git and GitHub API calls.
9. **Task tracking throughout** — a task per pipeline step, an explicit
   gate task after every review, a new tranche per gate failure.
