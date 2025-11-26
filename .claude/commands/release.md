---
description: Semi-automated release workflow from changelog to stapling
---

# Release Workflow

Create a new MacDown release with interactive changelog editing and automated monitoring.

## Configuration

- **Repository:** https://github.com/schuyler/macdown3000
- **Main Branch:** main

### GitHub CLI

The `gh` CLI is automatically installed via SessionStart hook on Linux. It uses the `GH_TOKEN` environment variable automatically—no manual authentication needed.

## Usage

Extract version from command arguments:
- `/release` - Interactive mode: prompts for version
- `/release 3000.0.0-beta.2` - Direct mode: uses provided version
- `/release v3000.0.0-beta.2` - Also accepts 'v' prefix (will be stripped)

## Workflow

### Step 0: Create Todo List

Use TodoWrite to create a todo list for tracking progress:

```
- Validate version and run pre-flight checks
- Build and commit changelog
- Create and push git tag
- Monitor build and notarization
- Complete release workflow
```

Update todo status as you progress through the workflow.

### Step 1: Version Input & Validation

**Get version:**
- If provided as argument: Strip 'v' prefix and use it
- If not provided: Get latest release (`gh release list`), suggest incremented version, prompt user

**Validate format:**
```bash
# Check semantic versioning: X.Y.Z or X.Y.Z-{beta,alpha,rc}.N
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-((beta|alpha|rc)\.[0-9]+))?$'; then
  echo "Error: Invalid version format"
  exit 1
fi

# Detect pre-release type
if echo "$VERSION" | grep -qE '-(beta|alpha|rc)\.'; then
  IS_PRERELEASE=true
else
  IS_PRERELEASE=false
fi
```

**Confirm with user:**
Display version and type, ask for confirmation. If declined, re-prompt.

**Pre-flight checks:**

Verify on main branch:
```bash
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" != "main" ]]; then
  # Offer to checkout main
fi
```

Verify clean working directory:
```bash
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: Working directory has uncommitted changes"
  exit 1
fi
```

Verify tag doesn't exist:
```bash
if git tag -l "v${VERSION}" | grep -q "v${VERSION}"; then
  # Offer to delete tag and retry, or use different version
fi
```


### Step 2: Interactive Changelog Building


#### 2a. Fetch Recent Changes

**Get commits since last release:**
```bash
LAST_TAG=$(gh release list --repo schuyler/macdown3000 --limit 1 --json tagName --jq '.[0].tagName')
git log ${LAST_TAG}..HEAD --oneline --no-merges
```

**Get merged PRs since last release:**
```bash
gh pr list --repo schuyler/macdown3000 --state merged --limit 30 --json number,title,mergedAt --jq '.[] | select(.mergedAt > "{LAST_RELEASE_DATE}") | "#\(.number): \(.title)"'
```

(Note: Get LAST_RELEASE_DATE from `gh release view $LAST_TAG`)

#### 2b. Display Recent Changes to User

Present the recent commits and PRs to the user:
```
📋 Recent commits since {LAST_TAG}:

{list of recent commit messages with PR numbers}

Should we include these in the changelog for version {VERSION}?
```

#### 2c. Ask User to Confirm or Exclude

Use AskUserQuestion to ask which commits to include:

**Question:** "Which commits should we include in the changelog?"

**Options:**
- "Include all of them" - Use all commits shown
- "Exclude some" - I'll specify which to exclude
- "Customize" - Let me review and write custom entries

If "Exclude some": Ask the user which PR numbers or commit hashes to exclude.

If "Customize": Ask user to provide changelog entries manually for each category (Fixed, Added, Changed, Removed, Infrastructure, Known Issues).

Otherwise, use all shown commits and auto-categorize them as "Fixed" if they mention bug fixes, or group them as general improvements.

#### 2d. Build Changelog Entry

Construct the changelog entry with a brief summary:
```markdown
## [{VERSION}] - {YYYY-MM-DD}

{1-4 sentence summary of the release}

{For each non-empty category:}
### {Category Name}
{user-provided entries}
```

**Summary example:**
"This release focuses on bug fixes and stability improvements. Several fixes address Markdown parsing edge cases, platform-specific issues, and user-reported bugs with HTML exports."

#### 2e. Display and Confirm Changelog

Show the complete changelog entry to the user:
```
📝 Changelog entry for version {VERSION}:

---
{generated changelog entry}
---

Does this look correct?

Options:
- ✅ Approve - Use this changelog entry
- ✏️  Edit - Let me make changes
- ❌ Cancel - Abort the release
```

Use AskUserQuestion with these options.

**If Edit selected:**
- Ask user which section to edit
- Re-prompt for that section
- Rebuild and re-display
- Ask for confirmation again

**If Cancel selected:**
- Stop the workflow
- Inform user no changes were made

**If Approve selected:**
- Proceed to step 2f


#### 2f. Update CHANGELOG.md

Read the current CHANGELOG.md:
```bash
Read CHANGELOG.md
```

Insert the new entry at the top (after the `# Changelog` title):
```markdown
# Changelog

{NEW ENTRY}

{existing content}
```

Use Edit tool to make the change.

Verify the change was applied correctly by reading CHANGELOG.md again.


#### 2g. Commit and Push Changelog

Create a commit with the changelog update:
```bash
git add CHANGELOG.md
git commit -m "Update CHANGELOG for version {VERSION}"
```

Push the changelog commit to the remote repository:
```bash
git push origin main
```

On error, display the git error message. On 403, suggest checking GH_TOKEN permissions at https://github.com/settings/tokens

### Step 3: Git Tag Creation & Push

#### 3a. Final Confirmation Before Tagging

Display summary and ask for final confirmation:
```
🚀 Ready to create release v{VERSION}

Changes staged:
- ✅ CHANGELOG.md updated with release notes
- ✅ Commit created: "Update CHANGELOG for version {VERSION}"

Next steps:
1. Create tag v{VERSION}
2. Push tag to trigger automated build workflow
3. Monitor build and notarization

This will trigger the automated release workflow. Proceed?
```

Use AskUserQuestion for confirmation.

If user declines, offer to:
- Undo the commit: `git reset --soft HEAD~1`
- Keep the commit but stop: Do nothing, let user handle it

#### 3b. Create Annotated Tag

Create the tag from the current commit:
```bash
git tag -a "v{VERSION}" -m "Release version {VERSION}"
```

Verify tag was created:
```bash
git tag -l "v{VERSION}"
```

#### 3c. Push Tag

Push the tag to trigger the release workflow:
```bash
git push origin "v{VERSION}"
```

If successful, the tag is now on GitHub and the release workflow will start within 1-2 minutes.


### Step 4: Monitor Build Workflow

The release workflow has been triggered and is now running. This typically takes 10-15 minutes for:
- Build and sign MacDown
- Create DMG installer
- Sign DMG
- Submit for notarization

**Monitor the workflow:**
- Workflow page: https://github.com/schuyler/macdown3000/actions/workflows/release.yml
- Or use: `gh run list --repo schuyler/macdown3000 --workflow release.yml --limit 1`
- Watch live: `gh run watch {RUN_ID} --repo schuyler/macdown3000`

When the build completes successfully, look for the notarization submission ID in the workflow logs under the "Submit DMG for notarization" step. Search for `Submission ID: {UUID}`.


### Step 5: Notarization Tracking

Once the build workflow completes successfully, Apple will notarize the DMG. You will receive an email from Apple with the subject "Your Mac software was successfully notarized".

**Typical wait:** 5-45 minutes (usually 10-15 minutes)

**When you receive the notarization email:**

1. Get the release URL:
```bash
gh release view "v3000.0.0-{VERSION}" --repo schuyler/macdown3000 --json url
```

2. Trigger the stapling workflow to finalize the release:
```bash
gh workflow run staple-release.yml --repo schuyler/macdown3000 -f release_tag=v{VERSION}
```

3. Monitor the stapling workflow:
```bash
gh run list --repo schuyler/macdown3000 --workflow staple-release.yml --limit 1
gh run watch {RUN_ID} --repo schuyler/macdown3000
```

4. After stapling completes, publish the release by going to the release URL and clicking "Publish release"

The website will update automatically after publishing.


### Step 6: Completion Summary

**Release v{VERSION} workflow initiated:**

Summary:
- ✅ CHANGELOG.md updated and committed
- ✅ Tag v{VERSION} created and pushed
- ✅ Build workflow triggered

**What happens next:**
1. Build workflow runs (~10-15 minutes)
2. Apple notarization email arrives (~5-45 minutes)
3. You trigger stapling workflow when email arrives
4. You publish the release to make it public

**Resources:**
- Build workflow: https://github.com/schuyler/macdown3000/actions/workflows/release.yml
- Draft release: https://github.com/schuyler/macdown3000/releases/tag/v{VERSION}

See Step 5 above for next steps when notarization completes.



## Important Reminders

1. **Assume GitHub works** - Don't add retry logic or complex defensive code. Trust that git/gh commands work on first try.
2. **Use TodoWrite** - Track progress through the workflow steps
3. **No 'v' prefix in VERSION variable** - Strip it if provided, add it back for tags (e.g., user provides `v3000.0.0-beta.2`, store as `3000.0.0-beta.2`)
4. **Confirm before destructive operations** - Get explicit user approval before:
   - Creating the tag
   - Pushing the tag
5. **No Co-authored-by trailers** - Never add "Co-authored-by:" to commits
6. **Clear error messages** - When things fail, show the actual error and let the user decide next steps
