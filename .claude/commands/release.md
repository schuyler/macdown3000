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

Present the commits and PRs to the user:
```
📋 Changes since {LAST_TAG}:

Recent commits:
{list of commit messages}

Merged PRs:
{list of PR titles with numbers}

I'll help you build the changelog entry for version {VERSION}.

**IMPORTANT:** Only include user-visible changes to the MacDown application.
Do NOT include:
- Website updates
- Release automation/workflow changes
- CI/CD pipeline updates
- Internal tooling changes

DO include:
- Bug fixes users will notice
- New features or capabilities
- Changes to existing behavior
- Performance improvements
- Infrastructure changes that affect users (e.g., new system requirements)
```

#### 2c. Interactive Categorization

For each category, ask the user to provide entries. Use multiple rounds of questions:

**Fixed (Bug Fixes):**
```
What bug fixes should be included in the changelog for this release?

Examples from recent changes:
- {relevant commits/PRs that look like bug fixes}

Please list each fix on a new line, in the format:
- Description (#issue or #PR)

Leave blank if none.
```

Repeat for each category:
- **Fixed** - Bug fixes
- **Added** - New features
- **Changed** - Enhancements to existing features
- **Removed** - Removed features
- **Infrastructure** - CI/CD, tooling changes
- **Known Issues** - Known issues to document (optional)

**IMPORTANT:** Skip categories that the user leaves blank.

#### 2d. Build Changelog Entry

Construct the changelog entry:
```markdown
## [{VERSION}] - {YYYY-MM-DD}

{For each non-empty category:}
### {Category Name}
{user-provided entries}
```

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

Push the changelog commit to the remote repository with retry logic (up to 4 attempts, exponential backoff: 2s, 4s, 8s, 16s):
```bash
git push origin main
```

On network errors, retry automatically. On 403 error:
```
Error: Push failed with 403 Forbidden.
Check your GH_TOKEN permissions at: https://github.com/settings/tokens
```

Verify commit appears on remote:
```bash
git fetch origin main
REMOTE_SHA=$(git rev-parse origin/main)
LOCAL_SHA=$(git rev-parse HEAD)

if [[ "$REMOTE_SHA" != "$LOCAL_SHA" ]]; then
  echo "Error: Local commit does not match remote main"
  exit 1
fi
```

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

Use retry logic on network errors (same pattern as Step 2g): up to 4 attempts with exponential backoff (2s, 4s, 8s, 16s).

On 403 error, verify GH_TOKEN has push permissions.

Wait 10 seconds, then verify tag on GitHub:
```bash
sleep 10
gh api repos/schuyler/macdown3000/git/refs/tags/v{VERSION}
```


### Step 4: Monitor Build Workflow


#### 4a. Find Workflow Run

Wait for the workflow to start (tag-triggered runs take a few seconds):
```bash
echo "Waiting for workflow to start..."
sleep 10

# Get the commit SHA that the tag points to
TAG_SHA=$(git rev-parse "v{VERSION}")

# Find the workflow run matching this commit SHA
RUN_ID=$(gh run list --repo schuyler/macdown3000 --workflow release.yml --limit 5 --json databaseId,headSha --jq --arg sha "$TAG_SHA" '.[] | select(.headSha == $sha) | .databaseId' | head -1)
```

If no run found:
```
⚠️  Workflow run not found yet. This can happen if GitHub Actions is slow to start.

You can manually check the workflow at:
https://github.com/schuyler/macdown3000/actions/workflows/release.yml

Continue monitoring?
```

Ask user if they want to wait longer or skip monitoring.

#### 4b. Monitor Workflow with Live Updates

Inform user that monitoring has started:
```
🔄 Monitoring release workflow for v{VERSION}...

This typically takes 10-15 minutes for:
- Build and sign MacDown
- Create DMG installer
- Sign DMG
- Submit for notarization

You can view the workflow at:
https://github.com/schuyler/macdown3000/actions/runs/{RUN_ID}
```

Start monitoring:
```bash
gh run watch {RUN_ID} --repo schuyler/macdown3000 --exit-status
```

This command will stream logs and wait for completion.

#### 4c. Check Workflow Result

After the workflow completes, check the status:
```bash
gh run view {RUN_ID} --repo schuyler/macdown3000 --json conclusion --jq '.conclusion'
```

**If `success`:**
- Proceed to step 4d (extract notarization ID)

**If `failure`:**
```
❌ Release workflow failed.

Viewing error logs...
```

Get the logs:
```bash
gh run view {RUN_ID} --repo schuyler/macdown3000 --log-failed
```

Display relevant error sections to the user.

Offer options:
```
Options:
1. Delete tag and retry (will undo the release attempt)
2. View full logs in browser
3. Stop and let me handle it manually

What would you like to do?
```

Handle user's choice:
- **Delete and retry:** Run `git push origin :refs/tags/v{VERSION}` and `git tag -d v{VERSION}`, then return to step 3a
- **View in browser:** Open `https://github.com/schuyler/macdown3000/actions/runs/{RUN_ID}`
- **Stop:** End the workflow

**If `cancelled` or `skipped`:**
```
⚠️  Workflow was {conclusion}.

This is unexpected. Please check:
https://github.com/schuyler/macdown3000/actions/runs/{RUN_ID}
```

#### 4d. Extract Notarization ID

Parse the workflow logs to find the notarization submission ID:
```bash
gh run view {RUN_ID} --repo schuyler/macdown3000 --log | grep "Submission ID:" | tail -1
```

Expected format: `Submission ID: {UUID}`

Extract the UUID and save to `NOTARIZATION_ID` variable.

If not found:
```
⚠️  Could not extract notarization ID from workflow logs.

You can find it manually in the workflow logs:
https://github.com/schuyler/macdown3000/actions/runs/{RUN_ID}

Look for "Submission ID:" in the "Submit DMG for notarization" step.
```


### Step 5: Notarization Tracking

#### 5a. Get Release URL

Fetch the draft release URL:
```bash
gh release view "v{VERSION}" --repo schuyler/macdown3000 --json url --jq '.url'
```

Save to `RELEASE_URL` variable.

#### 5b. Inform User of Notarization Status

Display the notarization information:
```
✅ Release workflow completed successfully!

📋 Notarization Details:
- Submission ID: {NOTARIZATION_ID}
- Typical wait time: 5-45 minutes (usually 10-15 minutes)
- You will receive an email: "Your Mac software was successfully notarized"

🔗 Draft Release:
{RELEASE_URL}

📧 Waiting for Apple notarization email...
```


#### 5c. Ask About Monitoring

Use AskUserQuestion:
```
What would you like me to do next?

Options:
1. Wait and monitor notarization (I'll poll every 60 seconds)
2. I'll handle the stapling workflow manually when I get the email
3. Show me the next steps and finish
```

Handle user's choice:

**Option 1: Auto-monitor**
- Proceed to step 5d

**Option 2: Manual**
- Skip to step 6 (completion summary)
- Include stapling instructions in summary

**Option 3: Show steps and finish**
- Skip to step 6 (completion summary)
- Include detailed next steps

#### 5d. Poll Notarization Status (Optional)

If user chose auto-monitor, first verify Apple credentials are available:

```bash
if [[ -z "${APPLE_ID}" ]] || [[ -z "${APPLE_APP_PASSWORD}" ]] || [[ -z "${APPLE_TEAM_ID}" ]]; then
  echo "⚠️ Apple credentials not available in environment variables"
  echo "Required: APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID"
  echo "Skipping automatic polling - will provide manual instructions instead"
  # Skip to Step 6
fi
```

**If credentials are available, poll the notarization status:**
```
🔄 Polling notarization status every 60 seconds...
Press Ctrl+C to stop monitoring.
```

Loop every 60 seconds (maximum 45 minutes):
```bash
MAX_POLLS=45
POLL_COUNT=0

while [[ $POLL_COUNT -lt $MAX_POLLS ]]; do
  STATUS=$(xcrun notarytool info ${NOTARIZATION_ID} \
    --apple-id ${APPLE_ID} \
    --password ${APPLE_APP_PASSWORD} \
    --team-id ${APPLE_TEAM_ID} \
    --output-format json | jq -r '.status')

  if [[ "$STATUS" == "Accepted" ]]; then
    echo "✅ Notarization approved!"
    # Proceed to 5e
    break
  elif [[ "$STATUS" == "Invalid" ]]; then
    echo "❌ Notarization rejected"
    # Show error and stop
    exit 1
  fi

  POLL_COUNT=$((POLL_COUNT + 1))
  sleep 60
done

if [[ $POLL_COUNT -eq $MAX_POLLS ]]; then
  echo "⚠️ Notarization polling timeout after 45 minutes"
  echo "Check manually: https://github.com/schuyler/macdown3000/actions"
fi
```

#### 5e. Trigger Stapling Workflow (If Approved)

If notarization was approved (either detected automatically or user confirms):

```bash
gh workflow run staple-release.yml --repo schuyler/macdown3000 -f release_tag=v{VERSION}
```

Wait 10 seconds, then find the workflow run:
```bash
sleep 10

# Find the most recent stapling workflow run
# Note: This assumes no concurrent stapling workflows are running
STAPLE_RUN_ID=$(gh run list --repo schuyler/macdown3000 --workflow staple-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')

if [[ -z "$STAPLE_RUN_ID" ]]; then
  echo "⚠️ Stapling workflow not found"
  echo "Find it manually at: https://github.com/schuyler/macdown3000/actions"
fi
```

Monitor the stapling workflow:
```bash
gh run watch {STAPLE_RUN_ID} --repo schuyler/macdown3000 --exit-status
```

If successful:
```
✅ DMG stapled successfully!

The website will update automatically via the update-website workflow.
```

Proceed to step 6.


### Step 6: Completion Summary

Provide a comprehensive summary based on what was accomplished:

**If monitoring completed through stapling:**
```
✅ Release v{VERSION} is complete!

Summary:
- ✅ CHANGELOG.md updated with release notes
- ✅ Tag v{VERSION} created and pushed
- ✅ Build workflow completed successfully
- ✅ DMG submitted for notarization
- ✅ Notarization approved (ID: {NOTARIZATION_ID})
- ✅ DMG stapled
- ✅ Website will update automatically

🔗 Release URL: {RELEASE_URL}

Final steps:
1. Review the release notes at the URL above
2. Click "Publish release" to make it public
3. Wait ~2 minutes for the website to update

Done!
```

**If stopped before stapling (manual mode):**
```
✅ Release v{VERSION} workflow in progress

Status:
- ✅ CHANGELOG.md updated and committed
- ✅ Tag v{VERSION} created and pushed
- ✅ Build workflow completed successfully
- ✅ DMG submitted for notarization (ID: {NOTARIZATION_ID})
- ⏳ Awaiting Apple notarization approval

🔗 Draft Release: {RELEASE_URL}

Next steps:
1. Watch for Apple email: "Your Mac software was successfully notarized"
   - Subject line: "Your Mac software was successfully notarized"
   - Typical wait: 5-45 minutes (usually 10-15 minutes)

2. When you receive the email, trigger the stapling workflow:
   gh workflow run staple-release.yml --repo schuyler/macdown3000 -f release_tag=v{VERSION}

3. Monitor the stapling workflow:
   gh run list --repo schuyler/macdown3000 --workflow staple-release.yml --limit 1
   gh run watch {RUN_ID} --repo schuyler/macdown3000

4. After stapling completes, publish the release:
   - Go to: {RELEASE_URL}
   - Review the release notes
   - Click "Publish release"

5. Website updates automatically after publishing

Questions? See: plans/release-process.md
```



## Important Reminders

1. **Use TodoWrite** - Track progress through the workflow steps
2. **No 'v' prefix in VERSION variable** - Strip it if provided, add it back for tags
3. **Retry network operations** - Git push and gh commands may fail due to network issues
4. **Fresh eyes at each step** - Verify user input and confirm before destructive operations
5. **Clear error messages** - Provide actionable guidance when things fail
6. **No Co-authored-by** - Never add "Co-authored-by:" trailers to commits
7. **Stop for confirmation** - Get explicit user approval before:
   - Creating the tag
   - Pushing the tag
   - Deleting and retrying after failures
