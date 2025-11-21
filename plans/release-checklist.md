# MacDown Release Checklist

**Quick reference:** Only three manual steps are required to release MacDown:
1. Update the changelog
2. Tag and push the version
3. Staple the DMG (after notarization)

See `plans/release-process.md` for detailed instructions.

---

## Step 1: Update the Changelog

- [ ] **Update CHANGELOG.md** with all changes in this release
  ```markdown
  ## Version 0.9.0 (YYYY-MM-DD)

  ### New Features
  - Feature description (#issue)

  ### Bug Fixes
  - Bug fix description (#issue)

  ### Breaking Changes
  - None (or describe if applicable)
  ```

---

## Step 2: Tag and Push (Triggers Automated Build)

- [ ] **Create and push the version tag**
  ```bash
  git tag v0.9.0
  git push origin v0.9.0
  ```

- [ ] **Monitor GitHub Actions** (10-15 minutes)
  - Workflow automatically builds, signs, creates DMG, and submits for notarization
  - Go to: https://github.com/schuyler/macdown3000/actions
  - Watch for workflow completion

- [ ] **Wait for Apple notarization approval email**
  - Subject: "Your Mac software was successfully notarized"
  - May take 5-45 minutes

---

## Step 3: Staple and Publish

Once you receive the notarization approval email:

- [ ] **Download the DMG from the draft GitHub release**
  - Go to: Releases → "MacDown 0.9.0" (draft status)
  - Download: `MacDown-0.9.0.dmg`

- [ ] **Staple the notarization ticket**
  ```bash
  xcrun stapler staple ~/Downloads/MacDown-0.9.0.dmg
  ```

- [ ] **Re-upload the stapled DMG to GitHub**
  - Delete the old un-stapled DMG from the release
  - Upload the stapled DMG

- [ ] **Publish the release**
  - Go to: Releases → "MacDown 0.9.0" (draft)
  - Uncheck "This is a draft"
  - Click "Publish release"

---

## That's It

The workflow handles everything else:
- ✅ Builds the app (universal binary for Apple Silicon + Intel)
- ✅ Code signs with Developer ID
- ✅ Creates the DMG installer
- ✅ Generates checksums
- ✅ Submits for Apple notarization
- ✅ Creates the GitHub release as a draft

Your job is just updating the changelog, tagging, and stapling.

---

## Troubleshooting

**Notarization failed?**
- Check the Apple email for details
- See `release-process.md` → "Troubleshooting" → "Notarization Rejected"
- Fix issues, bump patch version, and retry

**Want to cancel a release?**
- If before notarization completes: Delete the tag and draft release
- If after publishing: Create a hotfix release (0.9.1) immediately

---

**Last updated:** 2025-11-21
**Philosophy:** Only actual manual steps are in this checklist. Everything else is automated.
