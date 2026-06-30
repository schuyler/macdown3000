---
description: Cut a release candidate from main and invite reporters to validate it
---

# Release Candidate Workflow

Cut a release candidate (RC) using a **release branch**, build/sign/staple it
through the existing pipeline, and post validation invitations to the reporters
of every change it contains.

This is the **cut** half of the every-other-Sunday release train. The **promote**
half — graduating a validated RC into a final release — is the existing
`/release` workflow. See `plans/rc-process.md` for the full model.

## Release Branch Model

RCs operate on a **release branch** (`release/X.Y.Z`), not `main`. This keeps
`main` open for new work while the RC is being validated.

- **rc.1**: create `release/X.Y.Z` from `main` HEAD.
- **rc.N (N>1)**: cherry-pick **only bug fixes and security fixes** from `main`
  onto the existing `release/X.Y.Z`. New features ride the next release target.
  Skip infra, website, CI, and docs-only commits.
- The changelog and RC tag go on the release branch. **Never commit RC
  changelogs to `main`.**
- At graduation, `/release` tags the final release from the branch, cherry-picks
  the graduation commit onto `main`, and deletes the branch.

## Configuration

- **Repository:** https://github.com/schuyler/macdown3000
- **Main Branch:** main

### GitHub access

This workflow performs GitHub operations (reading releases, triggering and
watching workflows, posting validation comments, labelling issues). Run them
through the `gh` CLI when available, or the GitHub MCP tools when running in
Claude Code on the web. Authentication is handled by the environment — no manual
`gh auth login` needed.

## Usage

- `/release-candidate` — interactive: computes the next RC version and confirms.
- `/release-candidate 3000.0.7-rc.2` — direct: uses the provided RC version.
- `/release-candidate v3000.0.7-rc.2` — 'v' prefix accepted (stripped internally).

## Workflow

### Step 0: Create Todo List

Use TodoWrite to track progress:

```
- Determine RC version and run pre-flight checks
- Set up release branch (create or update)
- Identify changes included in this RC
- Write the temporary RC changelog snapshot and commit
- Tag and push the RC (triggers build + notarization)
- Staple and publish the RC pre-release
- Look up reporters and post validation comments
- Apply rc-pending labels and summarize
```

### Step 1: Determine RC Version

**If a version was provided as an argument:** strip any `v` prefix, verify it
matches `^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$`, and use it.

**Otherwise, compute it:**

```bash
# Latest stable (non-prerelease) release
LATEST_STABLE=$(gh release list --repo schuyler/macdown3000 --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName' | sed 's/^v//')
# e.g. 3000.0.6  →  next patch target is 3000.0.7
TARGET=$(echo "$LATEST_STABLE" | awk -F. '{printf "%s.%s.%d", $1, $2, $3+1}')

# Highest existing rc.N for this target (0 if none). Use max(N), NOT count —
# counting collides if a failed/rejected RC was ever deleted (e.g. rc.2 deleted
# leaves rc.1 + rc.3; count=2 → wrongly recomputes rc.3).
LAST_RC=$(gh release list --repo schuyler/macdown3000 --limit 100 --json tagName --jq \
  '[.[] | .tagName | capture("^v'"$TARGET"'-rc\\.(?<n>[0-9]+)$") | .n | tonumber] | max // 0')
RC_NUM=$((LAST_RC + 1))
VERSION="${TARGET}-rc.${RC_NUM}"
RELEASE_BRANCH="release/${TARGET}"
```

Confirm the computed version with the user before proceeding.

### Step 2: Pre-flight Checks

```bash
# Start on main
[[ "$(git branch --show-current)" == "main" ]] || echo "Switch to main first"
# Clean working tree
[[ -z "$(git status --porcelain)" ]] || echo "Commit or stash changes first"
# Up to date
git pull origin main
# Tag must not already exist
git tag -l "v${VERSION}" | grep -q . && echo "Tag exists — pick a new rc number"
```

**Skip-if-empty:** list commits since the previous RC (or last stable if this is
rc.1). If nothing app-facing has merged to `main`, tell the user the cycle is
empty and stop — don't cut a redundant RC.

Derive the previous RC tag explicitly. **Do not** use `gh release list --limit 1`
for this — an express-lane hotfix (a final shipped out-of-band) can make the most
recent release something other than the prior RC, which would corrupt the
"new since previous RC" diff in Step 3.

```bash
# Previous RC for THIS target = the rc just below the one we're cutting.
# If we're cutting rc.1, there is no previous RC → fall back to last stable,
# so EVERY change since the stable is "new" and gets pinged (correct for rc.1).
PREV_RC_NUM=$((RC_NUM - 1))
if [[ "$PREV_RC_NUM" -ge 1 ]]; then
  PREV_TAG="v${TARGET}-rc.${PREV_RC_NUM}"
else
  PREV_TAG="v${LATEST_STABLE}"
fi
# Sanity: LATEST_STABLE must be an ancestor of HEAD (ensures the range is valid).
# Do NOT check PREV_TAG ancestry — under the release branch model, prior RC tags
# live on the release branch and are not ancestors of main.
git merge-base --is-ancestor "v${LATEST_STABLE}" HEAD || echo "WARN: v${LATEST_STABLE} is not an ancestor of HEAD"
git log "${PREV_TAG}..HEAD" --oneline --no-merges
```

### Step 2.5: Set Up the Release Branch

**For rc.1** (no existing release branch):

```bash
git checkout -b "${RELEASE_BRANCH}"
git push -u origin "${RELEASE_BRANCH}"
```

**For rc.N (N>1)** (release branch already exists):

```bash
git checkout "${RELEASE_BRANCH}"
git pull origin "${RELEASE_BRANCH}"
```

Then cherry-pick **only bug fixes and security fixes** from `main` since the
previous RC. New features and enhancements stay on `main` and ride the next
release target — the release branch is for stabilization, not new functionality.

Review the commit list from Step 2 and classify each commit:

- **Cherry-pick**: bug fixes, security fixes, regression fixes, crash fixes
- **Skip**: new features, enhancements, infra, CI, website, docs-only, release
  process, changelog commits

Present the classification to the user for confirmation, then cherry-pick in
chronological order:

```bash
git cherry-pick <commit1> <commit2> ...
```

If a cherry-pick conflicts, resolve it or ask the user.

### Step 3: Identify Included Changes

From the release branch, collect the changes this RC introduces — everything
since the **last stable** release:

```bash
git log "v${LATEST_STABLE}..HEAD" --oneline --no-merges
```

Extract PR numbers (`#1234`) from the commit subjects. For each PR, note whether
it was **newly added since the previous RC** — this determines who gets
validation comments (see Step 7).

Filter out non-app changes (website, CI/release workflow, infra-only) the same
way `/release` does — they ride the train but need no reporter validation.

### Step 4: Write the Temporary RC Changelog Section

Both `release.yml` (the "Verify changelog entry exists" gate) and
`staple-release.yml` **require** a `## [${VERSION}]` section in `CHANGELOG.md`
matching the tag exactly — including the `-rc.N` suffix — and extract that
section's body as the release notes. An RC tag therefore needs its own section,
or CI fails on the first step.

**Do not copy `## [Unreleased]` to build this section.** This project does not
require contributors to update the changelog, so `[Unreleased]` is chronically
incomplete and will **never** match the RC's actual contents. The RC section must
be **generated from the commit range**, exactly the way `/release` builds its
notes.

Build it from `v${LATEST_STABLE}..HEAD` (on the release branch) using the same
attribution process as `/release` Step 2b: categorize entries (Added / Changed /
Fixed / Security / Documentation / Infrastructure) and credit reporters,
contributors, and testers (excluding @schuyler) by looking up each PR's linked
issues across both `schuyler/macdown3000` and `MacDownApp/macdown`. This is the
heavy step — delegating the lookup to a subagent keeps it manageable for large
batches.

**Every entry must reference both the PR and the linked issue(s).** Use the
format `(#ISSUE, PR #NNN)`. If there is no linked issue, the PR number alone is
sufficient: `(PR #NNN)`. If there are multiple linked issues, list them all:
`(#ISSUE1, #ISSUE2, PR #NNN)`.

For rc.N (N>1), replace the existing `<!-- rc-temp -->` block with the updated
section. For rc.1, insert a new block. Either way, leave `[Unreleased]`
untouched:

```markdown
## [Unreleased]

{existing rolling entries — left untouched, NOT used as the source}

<!-- rc-temp -->
## [{VERSION}] - {YYYY-MM-DD}

{section generated from the commit range, with attribution}
<!-- /rc-temp -->

## [3000.0.6] - 2026-04-18
...
```

Commit **on the release branch** (date = the RC cut date, i.e. today):

```bash
git add CHANGELOG.md
git commit -m "Generate changelog for release candidate ${VERSION}"
git push origin "${RELEASE_BRANCH}"
```

> **Do not** touch `README.md`. The `**Version X.Y.Z** - Available Now` line is
> the *stable* pointer; RCs are pre-releases and must not change it.
>
> **Do not commit RC changelogs to `main`.** The changelog lives on the release
> branch. `/release` cherry-picks the graduation commit (final changelog +
> README) onto `main` at release time.
>
> **`[Unreleased]` is not authoritative.** Because contributors don't maintain
> it, both the RC section here and the final section at graduation are generated
> from the commit range — never from `[Unreleased]`. `/release` removes every
> `<!-- rc-temp -->…<!-- /rc-temp -->` block for the target at graduation, so the
> changelog never carries stale RC sections forward.

### Step 5: Tag and Push the RC

Confirm with the user, then create and push the tag **from the release branch**.
This triggers `release.yml`, which auto-detects the `-rc.N` suffix and builds a
**pre-release** DMG (universal, signed, submitted for notarization).

```bash
git tag -a "v${VERSION}" -m "Release candidate ${VERSION}"
git push origin "v${VERSION}"
```

Monitor the build:

```bash
gh run list --repo schuyler/macdown3000 --workflow release.yml --limit 1
gh run watch {RUN_ID} --repo schuyler/macdown3000
```

### Step 6: Staple and Publish the Pre-release

Once the build completes and Apple notarization finishes (5–15 min), staple and
publish using the same workflow finals use:

```bash
gh workflow run staple-release.yml --repo schuyler/macdown3000 -f release_tag="v${VERSION}"
gh run list --repo schuyler/macdown3000 --workflow staple-release.yml --limit 1
gh run watch {RUN_ID} --repo schuyler/macdown3000
```

Capture the published pre-release URL for the validation comments:

```bash
RC_URL=$(gh release view "v${VERSION}" --repo schuyler/macdown3000 --json url --jq '.url')
```

### Step 7: Look Up Reporters and Post Validation Comments

For each **newly-added** PR (from Step 3), identify who to invite. Reuse the
contributor-lookup logic from `/release` Step 2b to find:

1. **Reporter(s)** — author(s) of the issue(s) the PR links (look for `#123` or
   `MacDownApp/macdown#123` in the PR body).
2. **Prior testers** — users who previously commented confirming/testing.

**Only @-mention people who engaged on `schuyler/macdown3000`.** The lookup may
surface authors of upstream `MacDownApp/macdown` issues — they may be fine to
*credit* in a changelog, but they never opted into this fork, so do **not** ping
them with an `@`-mention. Cross-repo is for attribution, not notification.

**Exclude @schuyler.** If a change has no linked issue, no reporter, or the only
associated user is @schuyler, skip the comment (it still gets a label in Step 8).

**Idempotency and re-pinging.** The default rule: before commenting, check
whether this issue already has an `<!-- rc-validation-ping -->` marker and skip
if so. **Exception:** if a reporter found a regression or bug during the
*previous* RC's validation period that produced a fix in *this* RC, they must be
re-pinged — they need to know the follow-up fix is available. In that case, post
a new comment even though a marker exists.

```bash
gh issue view {ISSUE_NUMBER} --repo schuyler/macdown3000 --json comments \
  --jq '.comments[].body' | grep -q 'rc-validation-ping' && echo "already pinged"
```

Compute the planned release date — the next release Sunday, **14 days after the
RC cut**. This skill is meant to run on the cut Sunday; anchor to that explicitly
and produce identical output on GNU (Linux/CI) and BSD (macOS) `date`:

```bash
# CUT_DATE defaults to today (run this on the cut Sunday). Override if needed.
CUT_DATE=${CUT_DATE:-$(date +%Y-%m-%d)}
RELEASE_DATE=$(date -d "${CUT_DATE} + 14 days" +%Y-%m-%d 2>/dev/null \
  || date -j -v+14d -f %Y-%m-%d "${CUT_DATE}" +%Y-%m-%d)
```

Post one comment per issue (or PR if no issue), on the issue the change resolves.
The hidden marker makes the ping idempotent; the Gatekeeper line keeps
non-technical reporters from misreading a quarantine prompt as "still broken":

```bash
gh issue comment {ISSUE_NUMBER} --repo schuyler/macdown3000 --body "$(cat <<'EOF'
<!-- rc-validation-ping -->
👋 A fix for this is available for testing in **MacDown {VERSION}**.

If you have a moment, please download it, confirm the issue is resolved, and
reply here — your confirmation is what graduates the fix into the next stable
release (currently planned for {RELEASE_DATE}).

📦 Download: {RC_URL}

> First launch: if macOS says the app is from an unidentified developer,
> right-click the app and choose **Open**, then confirm. (This is a signed,
> notarized pre-release build.)

No rush — if we don't hear back, the fix ships anyway. Thanks for reporting it!
EOF
)"
```

Tag the reporter(s)/tester(s) by `@`-mentioning them in the comment body. **Post
at most one comment per issue per RC.**

### Step 8: Apply Labels and Summarize

Apply `rc-pending` to every included issue/PR (including the ownerless ones that
got no comment), so release day knows what's aboard the train:

```bash
gh issue edit {ISSUE_NUMBER} --repo schuyler/macdown3000 --add-label rc-pending
```

(If the `rc-*` labels don't exist yet, create them per `plans/rc-process.md`.)

Print a summary:

```
🚂 Release candidate v{VERSION} is live.

- Pre-release: {RC_URL}
- Release branch: {RELEASE_BRANCH}
- Changes aboard: {N} ({M} new this cycle, {K} carried over)
- Reporters invited to validate: {list}
- Labelled rc-pending: {count} issues
- Planned graduation: {RELEASE_DATE} (run /release on the release branch)
```

## Important Reminders

1. **Work on the release branch, not `main`.** The changelog, cherry-picks, and
   tag all go on `release/X.Y.Z`. Never commit RC changelogs to `main`.
2. **Cherry-pick only app-facing commits** for rc.N (N>1). Infra, website, CI,
   and docs-only commits stay on `main`.
3. **RCs never touch README.md.** They add only a temporary, clearly-marked
   (`<!-- rc-temp -->`) CHANGELOG snapshot that `/release` strips at graduation;
   the rolling `[Unreleased]` section and the final entry belong to `/release`.
4. **One comment per issue per RC.** Check for the `<!-- rc-validation-ping -->`
   marker first — but **re-ping reporters who found regressions** during the
   previous RC's validation that are fixed in this RC.
5. **Exclude @schuyler from all credits and tags.**
6. **No 'v' in the VERSION variable**; add it back only for the tag.
7. **No Co-authored-by trailers.** Use "Related to #123", not "Fixes #123".
8. **Assume GitHub works** — no defensive retry loops; surface real errors and
   let the user decide.
9. **Skip empty cycles** — don't cut an RC with nothing app-facing in it.
