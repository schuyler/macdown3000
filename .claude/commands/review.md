---
description: Review a GitHub pull request with parallel agent collaboration; require approval before posting
---

# GitHub Pull Request Review

Review an inbound pull request by gathering perspectives from all four Marx Brothers subagents in parallel, having Chico triage which findings are worth asking the submitter to change, and posting a respectful review **only after explicit user approval**.

## Configuration

- **Repository:** https://github.com/schuyler/macdown3000

### GitHub CLI

The `gh` CLI is automatically installed via SessionStart hook on Linux. It uses the `GH_TOKEN` environment variable automatically — no manual authentication needed.

## Core Principles

These two rules are non-negotiable. Violating either is a workflow failure.

1. **Approval before posting.** Never call `gh pr review` (or any command that posts to GitHub) until the user has explicitly chosen an "Approve and post" option in Step 7. Drafts live locally until then.

2. **PR submitters are volunteers.** Every posted review opens by cordially thanking the submitter by handle. All commentary is constructive and respectful. No dismissive language ("obviously", "just", "simply", "you should have", "why didn't you"). Suggestions are framed as suggestions, not commands.

## Usage

Extract the PR number from the command arguments. Accept both `123` and `#123` formats.

## Workflow

### Step 0: Create Workflow Todos

Use TodoWrite to track progress:

```
- Fetch PR metadata and diff
- Fetch linked issue context (if any)
- Dispatch four agents in parallel for review
- Combine raw findings
- Run Chico triage pass
- Build draft review
- Get user approval (REQUIRED gate)
- Post review (or skip per user choice)
- Report completion
```

### Step 1: Fetch PR Metadata

Strip any leading `#` from the argument.

```bash
/tmp/gh/bin/gh pr view {number} --repo schuyler/macdown3000 \
  --json number,title,body,author,baseRefName,headRefName,state,isDraft,labels,files,additions,deletions,url
```

If the PR is closed, merged, or draft, ask the user whether to proceed before continuing. Otherwise, present a short summary (title, author, +N/-N, file count) so the user knows which PR is being reviewed.

### Step 2: Fetch Diff and Linked Issues

Get the full diff:

```bash
/tmp/gh/bin/gh pr diff {number} --repo schuyler/macdown3000
```

Scan the PR body for linked issue references (`#NNN` or `MacDownApp/macdown#NNN`). For each, fetch the issue for requirements context:

```bash
/tmp/gh/bin/gh issue view {issue_number} --repo schuyler/macdown3000 --json title,body,author
# If no match, also try the upstream:
/tmp/gh/bin/gh issue view {issue_number} --repo MacDownApp/macdown --json title,body,author
```

### Step 3: Dispatch ALL FOUR Agents IN PARALLEL (Sonnet)

**CRITICAL:** Send a single message containing four Task tool calls. Each call must specify `model="sonnet"`. All four agents always run — no conditional skipping.

Every agent prompt MUST begin with this tone guideline (verbatim):

> **Tone guideline:** the PR author is a volunteer contributing their time. Frame all feedback constructively and respectfully. Tag each finding with severity: **blocker / important / suggestion / nit**. Never dismissive.

Per-agent prompt focus:

#### 3a. Groucho — Architectural Review

```
/dev:groucho

{tone guideline}

Please review pull request #{number} for architectural fit.

PR: {title} by @{author}
Linked issues: {summary}
Diff:
{full diff}

Assess:
1. Does this change align with the existing project structure and patterns?
2. Are there design risks (coupling, abstraction breakage, layering issues)?
3. Are there architectural concerns the maintainer should weigh before merging?

Return findings tagged blocker / important / suggestion / nit.
```

#### 3b. Chico — Code Review

```
/dev:chico

{tone guideline}

Please review pull request #{number} for code quality.

PR: {title} by @{author}
Linked issues: {summary}
Diff:
{full diff}

Assess:
1. Correctness — does the code do what it claims?
2. Project conventions — does it match the surrounding Objective-C/Cocoa style?
3. Bugs, edge cases, security concerns
4. Readability and maintainability

Return findings tagged blocker / important / suggestion / nit.
```

#### 3c. Zeppo — Test Coverage Review

```
/dev:zeppo

{tone guideline}

Please review pull request #{number} from a testing perspective.

PR: {title} by @{author}
Linked issues: {summary}
Diff:
{full diff}

Assess:
1. Test coverage gaps in the changed code
2. Missing edge cases that should be tested
3. Whether new tests are warranted (and roughly what they should cover)
4. Quality of any tests included in the PR

Return findings tagged blocker / important / suggestion / nit.
```

#### 3d. Harpo — Documentation Drift Review

```
/dev:harpo

{tone guideline}

Please review pull request #{number} for documentation drift.

PR: {title} by @{author}
Linked issues: {summary}
Diff:
{full diff}

Assess:
1. Do any documents in the plans/ directory need updates to reflect this change?
2. Are there user-facing docs (README, CHANGELOG, in-repo guides) that drift if this merges?
3. Are code comments / docstrings touched by the PR accurate?

Return findings tagged blocker / important / suggestion / nit.
```

Collect all four agents' raw outputs verbatim before continuing.

### Step 4: Combine Raw Findings

Locally (no agent call), merge the four reports into a single structured document grouped by source agent and severity. Keep substance unchanged — this step only organizes. Example shape:

```
## Groucho (architecture)
- [important] ...
- [suggestion] ...

## Chico (code quality)
- [blocker] ...
- [nit] ...

## Zeppo (testing)
- ...

## Harpo (docs)
- ...
```

This combined document is the input to Step 5.

### Step 5: Chico Triage Pass (Sonnet)

Make a second Task call to Chico, on Sonnet:

```
/dev:chico

You previously contributed to a four-agent review of pull request #{number}. Below are the combined findings from all four agents (Groucho, Chico, Zeppo, Harpo).

The PR submitter is a volunteer. Be judicious about what is actually worth asking them to change versus what we should handle ourselves or simply note.

Triage every item into exactly one of three buckets, using the criteria and examples below.

**Bucket 1 — Must-fix before merge** (genuine blockers; be conservative)
Examples of what belongs here:
- Correctness bugs the user will hit (off-by-one, wrong condition, NULL deref)
- Memory leaks or retain cycles in the new code
- Crash risks (force unwraps, missing nil checks on inputs that can be nil)
- Security issues (injection, unsafe URL handling, leaked secrets/tokens)
- Regressions in existing behavior covered by tests
- Public API or documented contract violations
- Missing tests for genuinely risky new logic (not just "we'd like more tests")
- Wrong layering or breaks a structural rule the project actually enforces

**Bucket 2 — Worth raising as suggestions** (helpful but non-blocking)
Improvements the submitter can reasonably address, framed as suggestions not commands. Things like a clearer error message, an obvious edge case worth handling, a small naming improvement that aids readability of the changed code itself, or a missing test that's quick to add.

**Bucket 3 — Drop or note for our own follow-up** (NOT posted to the PR)
Examples of what belongs here:
- Stylistic preferences ("I'd name this differently", "extract this helper")
- Refactor opportunities the maintainer can do post-merge
- Pre-existing tech debt the PR happens to touch but didn't introduce
- "Would be nice if you also added X" feature creep
- Minor perf nits where perf isn't a concern
- Comment phrasing, blank lines, import ordering
- Documentation polish the maintainer can handle in a follow-up

When in doubt between bucket 2 and bucket 3, choose bucket 3. The submitter's time is finite; only ask for changes that genuinely improve the PR.

Combined findings:
{combined document from Step 4}

Return three clearly-labeled buckets. For each item, include a short rationale for the bucket choice.
```

Chico's bucket assignments are authoritative for what appears in the posted review.

### Step 6: Build the Draft Review

Construct the Markdown review from Chico's bucket 1 and bucket 2 only. Use this template:

```markdown
Thanks for this contribution, @{author}! Really appreciate you taking the time to {brief, specific acknowledgment of what the PR does}.

{Optional: 1-sentence overall assessment}

## Must-fix before merge

{Chico bucket 1, or "None — nice work." if empty}

## Suggestions

{Chico bucket 2, framed as suggestions, not commands}

---

{Closing line thanking them again and stating recommended disposition}
```

Bucket 3 items are NOT included in the posted review. They become an internal follow-up note shown only to the user in Step 7.

**Tone enforcement checklist** — verify before showing the draft:

- [ ] Opens with sincere thanks naming the author by handle
- [ ] No dismissive language ("obviously", "just", "simply", "you should have", "why didn't you")
- [ ] Suggestions phrased as suggestions, not commands
- [ ] Closes warmly
- [ ] Posted review contains nothing from bucket 3

If any box is unchecked, revise the draft before proceeding.

### Step 7: Approval Gate (REQUIRED — never skip)

Show the user:

1. The full draft review (exactly as it would appear on GitHub)
2. The bucket-3 internal-only follow-up items (for maintainer awareness, not for posting)

Then use `AskUserQuestion` with these options:

- **Approve and post as comment-only** (recommended default — safest)
- **Approve and post as "request changes"** (only offer if bucket 1 is non-empty)
- **Approve and post as "approve"** (only offer if bucket 1 is empty and the PR is genuinely ready to merge)
- **Edit before posting** — loop: ask the user what to change, regenerate the draft, re-run the tone checklist, then re-prompt
- **Cancel — don't post**

**CRITICAL:** Do NOT call `gh pr review` until the user picks one of the "Approve and post" options. If they cancel, the draft remains in the conversation only — proceed to Step 9 with disposition "draft only, not posted".

### Step 8: Post the Review

Based on the user's chosen disposition, run one of:

```bash
# Comment-only review:
/tmp/gh/bin/gh pr review {number} --repo schuyler/macdown3000 \
  --comment --body "$(cat <<'EOF'
{draft}
EOF
)"

# Request changes:
/tmp/gh/bin/gh pr review {number} --repo schuyler/macdown3000 \
  --request-changes --body "$(cat <<'EOF'
{draft}
EOF
)"

# Approve:
/tmp/gh/bin/gh pr review {number} --repo schuyler/macdown3000 \
  --approve --body "$(cat <<'EOF'
{draft}
EOF
)"
```

Always pass the body via heredoc to preserve formatting. If the network call fails, retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s).

### Step 9: Report Completion

Print a concise summary to the user:

```
Review for PR #{number}: {title}

Agents consulted (parallel, Sonnet): Groucho, Chico, Zeppo, Harpo
Triage pass: Chico

Disposition: {posted as comment-only / request-changes / approve, OR "draft only, not posted"}
PR: {url}
{If posted: link to the posted review}

Internal follow-up items (NOT posted to the submitter):
{bucket 3 items, or "None."}
```

## Important Reminders

1. **Approval is mandatory.** Never call `gh pr review` without an explicit user choice from Step 7. This is the most important rule in this workflow.
2. **Thank the author first.** Every posted review's first line cordially thanks the submitter by handle.
3. **Volunteer-respectful tone.** Run the tone checklist in Step 6 before showing any draft.
4. **All four agents always run, in parallel, on Sonnet.** No conditional skipping. Single message with four Task calls.
5. **Chico is invoked twice** — once in Step 3 as a peer reviewer alongside the others, once in Step 5 as the triage judge.
6. **Bucket 3 stays internal.** Items Chico judges as not-the-submitter's-burden are shown to the user but never posted to GitHub.
7. **No Co-authored-by trailers** (matches project convention).
8. **Don't reference Claude Code or the subagents in the posted review.** No one cares, and it's not relevant to the submitter.
9. **Use TodoWrite throughout** — update status as each step completes.
