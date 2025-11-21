# MacDown Release Checklist

**Primary Reference:** See `plans/release-process.md` for detailed instructions on any step marked with 📖.

This checklist ensures nothing is missed during a release. Use it alongside the release process guide for complete, step-by-step instructions.

---

## Phase 1: Pre-Release Preparation (1-2 days before)

### Code Quality & Testing

- [ ] **All tests pass** — Run tests locally and verify GitHub Actions passes
  - GitHub Actions: https://github.com/schuyler/macdown3000/actions
  - Verify "Tests" workflow shows ✅ on main branch

- [ ] **No failing GitHub Actions workflows** — Check all CI/CD pipelines
  - Must pass before creating release tag

- [ ] **Code review completed** (if applicable for your workflow)
  - Any pending PRs merged or deferred

- [ ] **Linter passes with no errors** — If project uses linting
  - No style warnings that would appear in build

- [ ] **Build succeeds locally**
  ```bash
  bundle exec pod install
  make -C Dependency/peg-markdown-highlight
  xcodebuild build -workspace "MacDown 3000.xcworkspace" -scheme MacDown -configuration Debug
  ```

- [ ] **No compiler warnings** (or documented exceptions)
  - Check build log for "warning:" messages
  - If unavoidable, document in release notes

- [ ] **Security audit completed** — Dependencies
  - Run `bundle audit` for Ruby dependencies
  - Verify CocoaPods dependencies are up to date

### Version Management

- [ ] **Semantic version decided** — Determine version number
  - Review latest git tag to determine next version
  - Decide: MAJOR.MINOR.PATCH or pre-release (MAJOR.MINOR.PATCH-prerelease)
  - See 📖 `release-process.md` → "Release Version Numbering" for format

- [ ] **Not a duplicate of existing version**
  ```bash
  git tag | grep "v0.X.X"  # Check if version already exists
  ```

- [ ] **Pre-release version format correct** (if applicable)
  - Valid formats: `0.9.0-alpha.1`, `0.9.0-beta.2`, `0.9.0-rc.1`
  - Use lowercase: `alpha`, `beta`, `rc` (not `Alpha`, `BETA`, etc.)

- [ ] **Understand how version flows through system**
  - Git tags → single source of truth
  - `Tools/utils.sh` → extracts version from git tags
  - `Tools/generate_version_header.sh` → creates version.h
  - Build system embeds version in app binary

### Documentation & Changelog

- [ ] **CHANGELOG.md prepared** with all changes
  - Location: Create or update `CHANGELOG.md` in repo root (if not existing)
  - Include:
    - What's new (new features with descriptions)
    - Bug fixes (specific issues fixed)
    - Known issues (if any remain)
    - Breaking changes (if any) with migration guide
    - Updated dependencies (if any changed versions)
    - Deprecation notices (if any)
  - Format example:
    ```markdown
    ## Version 0.9.0 (2025-11-20)

    ### New Features
    - Added dark mode support (#42)
    - Improved markdown rendering performance

    ### Bug Fixes
    - Fixed export to PDF crash (#38)
    - Fixed search highlighting in preview (#41)

    ### Known Issues
    - None currently known

    ### Breaking Changes
    - None
    ```

- [ ] **Release notes drafted** (for GitHub release)
  - Short summary of what's included
  - Key features highlighted
  - Link to full CHANGELOG
  - Example: See `release-process.md` → "Create GitHub Release" section

- [ ] **Migration guide created** (if breaking changes)
  - Document what changed
  - Provide upgrade path for users
  - Include workarounds if needed

- [ ] **README.md ready for version update**
  - Line 19: Will need to update "Version 3000.0.0 - Coming Soon"
  - Update to actual version after release

- [ ] **API docs updated** (if applicable)
  - Not applicable for MacDown (end-user app)
  - Check if project docs site needs updating

### Git Repository State

- [ ] **All changes committed**
  ```bash
  git status  # Should be clean except for intended changes
  ```

- [ ] **Working directory clean** (no uncommitted changes)
  ```bash
  git status  # No "Changes not staged for commit"
  ```

- [ ] **On main/master branch** (or deployment branch)
  ```bash
  git branch  # Should show "* main" or equivalent
  ```

- [ ] **In sync with origin**
  ```bash
  git pull origin main  # No conflicts, fully up to date
  ```

- [ ] **Branch doesn't conflict with version tag**
  - Example: Don't have branch named "v0.9.0"

### Release Planning & Communication

- [ ] **Announcement plan documented**
  - Where will release be announced? (GitHub, website, email, social media)
  - Who needs to be informed?
  - Timeline for announcements

- [ ] **Target audience identified**
  - Breaking changes affect certain users?
  - New features appeal to specific use case?
  - Document in release notes

- [ ] **Known compatibility issues documented**
  - macOS version limitations?
  - Architecture limitations (Intel vs. Apple Silicon)?
  - Known dependency conflicts?

- [ ] **System requirements verified**
  - Current requirement: macOS 11.0+, Apple Silicon
  - Any changes to requirements documented?

---

## Phase 2: Release Execution

### Pre-Release Git Setup

- [ ] **Verified no tag already exists**
  ```bash
  git tag | grep "^v0.9.0$"  # Should show nothing
  ```

- [ ] **Checked for pre-existing GitHub release**
  - Go to: https://github.com/schuyler/macdown3000/releases
  - Verify version doesn't already exist (as draft or published)

- [ ] **Confirmed workspace is clean**
  ```bash
  xcodebuild clean -workspace "MacDown 3000.xcworkspace" -scheme MacDown
  ```

- [ ] **Latest code pulled**
  ```bash
  git fetch origin
  git pull origin main
  ```

### GitHub Secrets Verification

Before triggering the release workflow, verify all 5 secrets are configured:

- [ ] **APPLE_TEAM_ID** configured
  - Should be 10 characters (e.g., `A1B2C3D4E5`)
  - Location: Settings → Secrets and variables → Actions

- [ ] **APPLE_CERTIFICATE_BASE64** configured
  - Should be a very long string (encoded certificate)
  - Not empty and not corrupted

- [ ] **APPLE_CERTIFICATE_PASSWORD** configured
  - Password for the .p12 certificate
  - Must match the password set during certificate export

- [ ] **APPLE_ID** configured
  - Your Apple ID email address
  - Format: `name@example.com`

- [ ] **APPLE_APP_PASSWORD** configured
  - App-specific password from Apple ID account
  - Format: `xxxx-xxxx-xxxx-xxxx`
  - If expired/revoked, generate new one at: https://appleid.apple.com

📖 **Setup Instructions:** See `release-process.md` → "GitHub Secrets Setup"

### Creating the Release Tag

📖 **Detailed Instructions:** See `release-process.md` → "Creating a Release"

**Option A: Tag Method (Recommended)**
```bash
# Create version tag
git tag v0.9.0

# Push tag to trigger release workflow
git push origin v0.9.0
```

- [ ] **Version tag created** — `git tag v0.9.0`
- [ ] **Tag pushed to origin** — `git push origin v0.9.0`
- [ ] **GitHub Actions triggered**
  - Go to: Actions → Release workflow
  - Should show workflow running within seconds

**Option B: Manual Trigger (Alternative)**
- [ ] **Navigated to Actions → Release workflow**
- [ ] **Clicked "Run workflow"**
- [ ] **Entered version** (e.g., `0.9.0` without 'v')
- [ ] **Clicked "Run workflow"** again

### Build & Code Signing Phase

The release workflow automatically handles these steps (10-15 minutes):

- [ ] **Workflow build phase running**
  - Monitor at: Actions → Release workflow → latest run
  - Watch for: "Build and archive MacDown" step

- [ ] **Code signing successful**
  - Workflow should show: ✅ "Setup code signing keychain"
  - Workflow should show: ✅ "Extract application bundle"
  - Verify signature: Look for "Verified signature: Developer ID Application"

- [ ] **Build logs reviewed** — Check for unexpected warnings
  - Click workflow run → scroll to build steps
  - Look for "warning:" messages (not expected)

- [ ] **DMG created successfully**
  - Workflow should show: ✅ "Create DMG installer"
  - Size should be reasonable (20-100 MB, not bloated)

- [ ] **Checksums generated**
  - Workflow should show: ✅ "Generate checksums"

### Notarization Submission Phase

The release workflow submits to Apple (happens automatically):

- [ ] **Notarization submitted successfully**
  - Workflow should show: ✅ "Submit DMG for notarization"
  - Look for submission ID in logs

- [ ] **Submission ID captured**
  - Note the ID from workflow output (format: `xxxx-xxxx-xxxx-xxxx`)
  - This will be in the GitHub release notes automatically

- [ ] **Draft GitHub release created**
  - Go to: Releases → "MacDown 0.9.0" (should be draft)
  - DMG and checksum files attached

- [ ] **Started monitoring for Apple email**
  - Subject: "Your Mac software was successfully notarized"
  - This typically arrives in 5-15 minutes, sometimes up to 1 hour

---

## Phase 3: Post-Notarization (After Apple Approval)

📖 **Detailed Instructions:** See `release-process.md` → "Post-Notarization Stapling"

### Notarization Verification

- [ ] **Received Apple notarization email**
  - Subject: "Your Mac software was successfully notarized"
  - If rejected instead, see 📖 "Troubleshooting" → "Notarization Rejected"

- [ ] **Notarization status confirmed as "Accepted"**
  ```bash
  xcrun notarytool info SUBMISSION_ID \
    --apple-id your-email@example.com \
    --password xxxx-xxxx-xxxx-xxxx \
    --team-id APPLE_TEAM_ID
  ```
  - Should show: `status: Accepted`
  - If "Invalid" or "Rejected", see troubleshooting section

### Stapling the DMG

📖 **Detailed Steps:** See `release-process.md` → "Post-Notarization Stapling"

- [ ] **Downloaded DMG from GitHub release**
  - Go to: Releases → "MacDown 0.9.0" (draft)
  - Download: `MacDown 3000-0.9.0.dmg`

- [ ] **Stapled the notarization ticket**
  ```bash
  cd ~/Downloads
  xcrun stapler staple MacDown\ 3000-0.9.0.dmg
  ```
  - Should show: "The staple and validate action worked!"

- [ ] **Validated stapling**
  ```bash
  xcrun stapler validate MacDown\ 3000-0.9.0.dmg
  ```
  - Should show: "The validate action worked!"

- [ ] **Verified code signature**
  ```bash
  spctl -a -vvv -t install MacDown\ 3000-0.9.0.dmg
  ```
  - Should show: `accepted` and `source=Notarized Developer ID`

### Updating the Release

- [ ] **Re-uploaded stapled DMG to GitHub release**
  - Go to: Releases → "MacDown 0.9.0" (draft)
  - Delete old un-stapled DMG
  - Upload new stapled DMG

- [ ] **Updated checksums** (if DMG was modified during stapling)
  ```bash
  shasum -a 256 MacDown\ 3000-0.9.0.dmg
  ```
  - If checksum changed, update checksum file in release
  - Usually checksums don't change after stapling

- [ ] **Release notes updated**
  - Remove: "⚠️ Important: This DMG has been submitted for Apple notarization but the ticket is not yet stapled"
  - Add: "✅ Notarized and stapled. Ready for distribution."

- [ ] **Pre-release flag correct**
  - For beta/alpha/rc: ✅ Check "This is a pre-release"
  - For production: ☐ Uncheck "This is a pre-release"

### Publishing the Release

- [ ] **Reviewed release notes one final time**
  - Spelling and grammar correct?
  - All sections complete?
  - Checksums correct?

- [ ] **Converted from draft to published**
  - Go to: Releases → "MacDown 0.9.0" (draft)
  - Uncheck: "This is a draft"
  - Click: "Publish release"

- [ ] **GitHub release is now public**
  - Go to: Releases page
  - Should see "MacDown 0.9.0" as published release
  - Should be downloadable

### Git Repository Update (Post-Release Development)

- [ ] **Updated README.md with new version** (if needed)
  - Line 19: Update version display
  - Keep "Coming Soon" or replace with actual version?
  - Commit and push

**Note:** Version management is now fully automated via git tags. Development builds automatically show as `<version>.post<N>` after a release tag. No manual version updates needed!

---

## Phase 4: Post-Release Verification (2-24 hours)

### Download & Install Testing

- [ ] **Downloaded DMG from public GitHub release**
  - From: https://github.com/schuyler/macdown3000/releases
  - Should be easy to find, properly listed

- [ ] **DMG opens without security warnings**
  - Double-click the DMG
  - No "unverified developer" warnings (stapling worked!)
  - No corruption messages

- [ ] **Application installs cleanly**
  - Drag "MacDown 3000.app" to Applications folder
  - No permission errors
  - No installation prompts

- [ ] **Application launches successfully**
  - Open /Applications/MacDown\ 3000.app
  - No crash on launch
  - No error dialogs

- [ ] **App version displays correctly**
  - Go to: MacDown → About MacDown 3000
  - Version shown should be: 0.9.0
  - Not 0.1 (placeholder), not 0.9.1 (development version)

- [ ] **No security warnings on clean Mac** (if tested)
  - Optional: Test on different Mac if possible
  - Verify no "unidentified developer" warnings appear

### Functionality QA Testing

- [ ] **Basic functionality works**
  - Create new markdown document
  - Type some markdown
  - Preview updates live
  - No crashes

- [ ] **No regressions from previous version**
  - Test features known to be working
  - No new bugs introduced
  - Markdown rendering still correct

- [ ] **No crashes on startup**
  - Launch app multiple times
  - All features accessible
  - Menu items working

- [ ] **All UI elements present**
  - All buttons, menus, preferences visible
  - Not cut off or missing parts

- [ ] **Preferences load correctly**
  - Go to: Preferences
  - Settings persist across launches
  - No corruption of preferences

### Post-Release Announcements

- [ ] **Updated project website**
  - If applicable, update download page
  - Update version number displayed
  - Add link to release notes

- [ ] **Announced on GitHub**
  - Release notes are live
  - Visible on main Releases page

- [ ] **Announced on social media** (if applicable)
  - Twitter/X, Mastodon, etc.
  - Include download link
  - Highlight key features

- [ ] **Announced via email** (if applicable)
  - Mailing list notification
  - Include changelog link

- [ ] **Updated project documentation**
  - Any docs referencing old version updated
  - Installation instructions still correct

---

## Phase 5: Contingency & Rollback

### If Release Fails Before Publishing

**Symptom:** Build or signing failed, or never created a release

**Response:**
- [ ] **Deleted failed tag** (if created)
  ```bash
  git push origin :refs/tags/v0.9.0
  git tag -d v0.9.0
  ```

- [ ] **Deleted draft release in GitHub** (if created)
  - Go to: Releases → (draft release)
  - Click "Delete" button

- [ ] **Investigated root cause**
  - Check GitHub Actions logs: Actions → Release → click failed run
  - Look for error messages in build or signing steps
  - See 📖 `release-process.md` → "Troubleshooting"

- [ ] **Fixed issues in code**
  - Made necessary changes
  - Committed and pushed to main

- [ ] **Retried release process**
  - Delete and recreate tag with bump version
  - Or manually trigger workflow with new version number

### If Release Fails After Publishing

**Symptom:** Release published, but users report critical issues

**Response:**
- [ ] **Assessed severity**
  - Is it a blocking issue or minor problem?
  - Can users work around it?

- [ ] **Created hotfix release immediately** (if blocking)
  - Bump patch version: 0.9.0 → 0.9.1
  - Fix the issue
  - Follow release process again (fast-track)

- [ ] **Updated GitHub release notes**
  - Add note: "⚠️ Critical issue in 0.9.0 → Please download 0.9.1"
  - Link to hotfix release
  - Describe the issue

- [ ] **Communicated clearly to users**
  - Email, social media, GitHub issues
  - Explain the problem and solution
  - Link to hotfix download

- [ ] **Marked problematic release as obsolete** (optional)
  - Go to GitHub release
  - Edit and add note: "⚠️ Superseded by v0.9.1"
  - Consider hiding from view if possible

### If Notarization Fails

**Symptom:** Notarization submission rejected by Apple

**Response:**
- [ ] **Retrieved detailed logs**
  ```bash
  xcrun notarytool log SUBMISSION_ID \
    --apple-id your-email@example.com \
    --password xxxx-xxxx-xxxx-xxxx \
    --team-id APPLE_TEAM_ID
  ```

- [ ] **Investigated issues** in developer_log.json
  - Look for common issues: hardened runtime, entitlements, unsigned dependencies
  - See 📖 `release-process.md` → "Troubleshooting" → "Notarization Rejected"

- [ ] **Fixed code or configuration issues**
  - Update entitlements if needed
  - Ensure all dependencies are signed
  - Rebuild locally and verify signature

- [ ] **Incremented version number** (critical fix)
  - Don't try to release same version again
  - Bump patch: 0.9.0 → 0.9.1
  - Create new git tag with bumped version

- [ ] **Resubmitted for notarization**
  - Delete old draft release
  - Delete and recreate tag with new version
  - Follow release process again

---

## Approval Checklist

**Before publishing release to the public, verify:**

- [ ] ✅ All code quality checks passed
- [ ] ✅ Version number is correct and unique
- [ ] ✅ CHANGELOG is complete and accurate
- [ ] ✅ DMG is notarized and stapled
- [ ] ✅ All files attached to release
- [ ] ✅ Release notes are clear and complete
- [ ] ✅ No known critical bugs in release
- [ ] ✅ All team members notified (if applicable)
- [ ] ✅ Announcement plan ready
- [ ] ✅ Comfortable proceeding with publication

---

## Reference Information

### File Locations

| What | Where |
|------|-------|
| Current version info | Git tags (single source of truth) |
| Build version scripts | `Tools/utils.sh` |
| Version generation | `Tools/generate_version_header.sh` |
| Release process details | `plans/release-process.md` |
| GitHub release action | `.github/workflows/release.yml` |
| Application info | `MacDown/MacDown-Info.plist` |
| Change log | `CHANGELOG.md` (create if needed) |

### Time Estimates

| Phase | Time |
|-------|------|
| Pre-release prep | 1-2 hours |
| Build & sign | 10-15 minutes |
| Notarization wait | 5-45 minutes |
| Stapling & publish | 5-10 minutes |
| Testing & announce | 15-30 minutes |
| **Total** | **30-90 minutes** |

### Release Frequency Recommendations

- **Patch releases (0.X.Z):** As needed (critical bugs)
- **Minor releases (0.Y.0):** Monthly (new features ready)
- **Major releases (X.0.0):** Quarterly or as needed (major changes)
- **Pre-releases:** Mark with `-alpha`, `-beta`, or `-rc` suffix

### Important Notes

⚠️ **Do not commit secrets to Git** — GitHub secrets are configured separately and never committed

⚠️ **Semantic versioning enforced** — Use proper MAJOR.MINOR.PATCH format

⚠️ **Notarization is required** — macOS will warn users of "unidentified developer" if not notarized

⚠️ **Stapling improves UX** — Stapled DMG works offline; un-stapled requires internet for verification

---

**Last updated:** 2025-11-20
**Coordination Status:** ✅ Integrated with `plans/release-process.md`
