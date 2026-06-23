---
description: Cut a release candidate from main and invite reporters to validate it
---

# Release Candidate Workflow

Cut a release candidate (RC) from `main`, build/sign/staple it through the
existing pipeline, and post validation invitations to the reporters of every
change it contains.

This is the **cut** half of the every-other-Sunday release train. The **promote**
half — graduating a validated RC into a final release — is the existing
`/release` workflow. See `plans/rc-process.md` for the full model.

## Configuration

- **Repository:** https://github.com/schuyler/macdown3000
- **Main Branch:** main

### GitHub CLI

The `gh` CLI is installed via the SessionStart hook on Linux (`/tmp/gh/bin/gh`)
and assumed present on macOS. It uses `GH_TOKEN` automatically — no manual auth.

## Usage

- `/release-candidate` — interactive: computes the next RC version and confirms.
- `/release-candidate 3000.0.7-rc.2` — direct: uses the provided RC version.
- `/release-candidate v3000.0.7-rc.2` — 'v' prefix accepted (stripped internally).

## Workflow

### Step 0: Create Todo List

Use TodoWrite to track progress:

```
- Determine RC version and run pre-flight checks
- Identify changes included in this RC
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

# Highest existing rc.N for this target (0 if none)
LAST_RC=$(gh release list --repo schuyler/macdown3000 --limit 30 --json tagName --jq \
  '[.[] | select(.tagName | startswith("v'"$TARGET"'-rc."))] | length')
RC_NUM=$((LAST_RC + 1))
VERSION="${TARGET}-rc.${RC_NUM}"
```

Confirm the computed version with the user before proceeding.

### Step 2: Pre-flight Checks

```bash
# On main
[[ "$(git branch --show-current)" == "main" ]] || echo "Switch to main first"
# Clean working tree
[[ -z "$(git status --porcelain)" ]] || echo "Commit or stash changes first"
# Up to date
git pull origin main
# Tag must not already exist
git tag -l "v${VERSION}" | grep -q . && echo "Tag exists — pick a new rc number"
```

**Skip-if-empty:** list commits since the last RC (or last stable if this is
rc.1). If nothing app-facing has merged, tell the user the cycle is empty and
stop — don't cut a redundant RC.

```bash
PREV_TAG=$(gh release list --repo schuyler/macdown3000 --limit 1 --json tagName --jq '.[0].tagName')
git log "${PREV_TAG}..HEAD" --oneline --no-merges
```

### Step 3: Identify Included Changes

Collect the changes this RC introduces — everything on `main` since the **last
stable** release (an RC is always a cumulative superset of the work since the
last final release):

```bash
git log "v${LATEST_STABLE}..HEAD" --oneline --no-merges
```

Extract PR numbers (`#1234`) from the commit subjects. For each PR, note whether
it was **newly added since the previous RC** — only newly-added changes get a
validation comment this cycle (changes carried over from a prior RC were already
pinged; do not re-ping). Determine "new since previous RC" by diffing against
`${PREV_TAG}..HEAD` from Step 2.

Filter out non-app changes (website, CI/release workflow, infra-only) the same
way `/release` does — they ride the train but need no reporter validation.

### Step 4: Tag and Push the RC

Confirm with the user, then create and push the tag. This triggers
`release.yml`, which auto-detects the `-rc.N` suffix and builds a **pre-release**
DMG (universal, signed, submitted for notarization).

```bash
git tag -a "v${VERSION}" -m "Release candidate ${VERSION}"
git push origin "v${VERSION}"
```

> **Do not** update `README.md`. The `**Version X.Y.Z** - Available Now` line is
> the *stable* pointer; RCs are pre-releases and must not change it. Likewise,
> do not finalize a `## [X.Y.Z]` CHANGELOG section for an RC — the changelog is
> written when the train graduates via `/release`.

Monitor the build:

```bash
gh run list --repo schuyler/macdown3000 --workflow release.yml --limit 1
gh run watch {RUN_ID} --repo schuyler/macdown3000
```

### Step 5: Staple and Publish the Pre-release

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

### Step 6: Look Up Reporters and Post Validation Comments

For each **newly-added** PR (from Step 3), identify who to invite. Reuse the
contributor-lookup logic from `/release` Step 2b:

1. **Reporter(s)** — author(s) of the issue(s) the PR links (look for `#123` or
   `MacDownApp/macdown#123` in the PR body). Check both repos.
2. **Prior testers** — users who previously commented confirming/testing.

**Exclude @schuyler.** If a change has no linked issue / no reporter, skip the
comment (it still gets a label in Step 7).

Compute the planned release date — the **second** Sunday from the RC cut:

```bash
RELEASE_DATE=$(date -d "sunday + 2 weeks" +%Y-%m-%d 2>/dev/null || date -v+sun -v+1w +%Y-%m-%d)
```

Post one comment per issue (or PR if no issue), on the issue the change resolves:

```bash
gh issue comment {ISSUE_NUMBER} --repo schuyler/macdown3000 --body "$(cat <<'EOF'
👋 A fix for this is available for testing in **MacDown {VERSION}**.

If you have a moment, please download it, confirm the issue is resolved, and
reply here — your confirmation is what graduates the fix into the next stable
release (currently planned for {RELEASE_DATE}).

📦 Download: {RC_URL}

No rush — if we don't hear back, the fix ships anyway. Thanks for reporting it!
EOF
)"
```

Tag the reporter(s)/tester(s) by `@`-mentioning them in the comment body. **Post
at most one comment per issue per RC.**

### Step 7: Apply Labels and Summarize

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
- Changes aboard: {N} ({M} new this cycle, {K} carried over)
- Reporters invited to validate: {list}
- Labelled rc-pending: {count} issues
- Planned graduation: {RELEASE_DATE} (run /release, then cut the next RC)
```

## Important Reminders

1. **RCs never touch README.md or finalize CHANGELOG sections** — those belong to
   the final release (`/release`).
2. **One comment per issue per RC.** Never re-ping a carried-over change.
3. **Exclude @schuyler from all credits and tags.**
4. **No 'v' in the VERSION variable**; add it back only for the tag.
5. **No Co-authored-by trailers.** Use "Related to #123", not "Fixes #123".
6. **Assume GitHub works** — no defensive retry loops; surface real errors and
   let the user decide.
7. **Skip empty cycles** — don't cut an RC with nothing app-facing in it.
