# MacDown Release Process

This document describes how to configure and use the automated release workflow for MacDown 3000.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [GitHub Secrets Setup](#github-secrets-setup)
- [Creating a Release](#creating-a-release)
- [Post-Notarization Stapling](#post-notarization-stapling)
- [Troubleshooting](#troubleshooting)

## Overview

The release workflow (`.github/workflows/release.yml`) automates the following steps:

1. ✅ **Build** MacDown in Release configuration (Universal binary - Apple Silicon + Intel)
2. ✅ **Code Sign** with Developer ID Application certificate
3. ✅ **Enable Hardened Runtime** (required for notarization)
4. ✅ **Create DMG** installer with professional layout
5. ✅ **Submit for Notarization** to Apple (without waiting)
6. ✅ **Generate Checksums** (SHA256) for verification
7. ✅ **Create Draft Release** on GitHub with artifacts

The workflow **does not wait** for Apple notarization to complete (this can take 5-45 minutes). After notarization finishes, you'll need to manually staple the ticket and publish the release.

### Important Note on Workflow Changes

The `build-release.yml` workflow has been modified to avoid conflicts with the new `release.yml` workflow:
- `build-release.yml` now only runs on branch pushes (development builds)
- `release.yml` handles all tagged releases
- This prevents duplicate releases when you push a version tag

## Prerequisites

Before using the release workflow, you must have:

- [ ] **Apple Developer Account** ($99/year) with Developer ID privileges
- [ ] **Developer ID Application Certificate** installed in Keychain
- [ ] **App-Specific Password** for notarization
- [ ] **Admin access** to the GitHub repository

### Hardened Runtime

Apple requires **Hardened Runtime** to be enabled for all notarized applications. The workflow automatically enables this with the `ENABLE_HARDENED_RUNTIME=YES` build setting.

**If your app requires runtime exceptions** (e.g., for plugins, JIT compilation, or unsigned code execution), you must:

1. Create an entitlements file (e.g., `MacDown/MacDown.entitlements`) with required exceptions:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <!-- Example: Allow loading of unsigned executable memory -->
       <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
       <true/>
   </dict>
   </plist>
   ```

2. Update the workflow to include the entitlements file:
   - Add `CODE_SIGN_ENTITLEMENTS="MacDown/MacDown.entitlements"` to the xcodebuild command

For most apps (including MacDown), no special entitlements are needed and the default Hardened Runtime settings work fine.

## GitHub Secrets Setup

The release workflow requires 5 secrets to be configured in your GitHub repository.

### Required Secrets

| Secret Name | Description | Where to Find |
|-------------|-------------|---------------|
| `APPLE_TEAM_ID` | Your 10-character Apple Team ID | [developer.apple.com/account](https://developer.apple.com/account) → Membership |
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded .p12 certificate file | Export from Keychain (see below) |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 certificate | Set during export |
| `APPLE_ID` | Your Apple ID email address | Your Apple account email |
| `APPLE_APP_PASSWORD` | App-specific password for notarization | Generate at [appleid.apple.com](https://appleid.apple.com) |

### Step 1: Find Your Apple Team ID

1. Go to [developer.apple.com/account](https://developer.apple.com/account)
2. Sign in with your Apple ID
3. Click on **Membership** in the sidebar
4. Your **Team ID** is displayed (10 characters, e.g., `A1B2C3D4E5`)

### Step 2: Export Your Developer ID Certificate

**Prerequisites:** You must have your Developer ID Application certificate installed in Keychain Access.

1. **Open Keychain Access** (Applications → Utilities → Keychain Access)

2. **Select "login" keychain** in the left sidebar

3. **Select "Certificates"** category

4. **Find your certificate** named:
   ```
   Developer ID Application: Your Name (TEAM_ID)
   ```

5. **Right-click** the certificate → **Export "Developer ID Application: ..."**

6. **Save as:** Choose a location and name (e.g., `DeveloperIDCertificate.p12`)

7. **Set a password** when prompted
   - Choose a strong password
   - **Remember this password** - you'll need it for `APPLE_CERTIFICATE_PASSWORD`

8. **Convert to Base64:**
   ```bash
   base64 -i ~/Desktop/DeveloperIDCertificate.p12 | pbcopy
   ```
   This copies the base64-encoded certificate to your clipboard.

9. **Delete the .p12 file** from your Desktop (security best practice)

### Step 3: Generate App-Specific Password

App-specific passwords allow GitHub Actions to authenticate with Apple without using your main Apple ID password.

1. Go to [appleid.apple.com](https://appleid.apple.com)

2. Sign in with your Apple ID

3. In the **Security** section, find **App-Specific Passwords**

4. Click **Generate an app-specific password**

5. **Label it:** `MacDown Notarization` (or similar)

6. **Copy the generated password** (format: `xxxx-xxxx-xxxx-xxxx`)
   - You won't be able to see this again
   - This is your `APPLE_APP_PASSWORD`

### Step 4: Add Secrets to GitHub

1. Go to your repository on GitHub

2. Navigate to **Settings** → **Secrets and variables** → **Actions**

3. Click **New repository secret**

4. Add each of the 5 secrets:

   **APPLE_TEAM_ID:**
   - Name: `APPLE_TEAM_ID`
   - Value: Your 10-character Team ID (e.g., `A1B2C3D4E5`)

   **APPLE_CERTIFICATE_BASE64:**
   - Name: `APPLE_CERTIFICATE_BASE64`
   - Value: Paste the base64 string from Step 2 (should be very long)

   **APPLE_CERTIFICATE_PASSWORD:**
   - Name: `APPLE_CERTIFICATE_PASSWORD`
   - Value: The password you set when exporting the .p12

   **APPLE_ID:**
   - Name: `APPLE_ID`
   - Value: Your Apple ID email (e.g., `developer@example.com`)

   **APPLE_APP_PASSWORD:**
   - Name: `APPLE_APP_PASSWORD`
   - Value: The app-specific password from Step 3 (format: `xxxx-xxxx-xxxx-xxxx`)

5. **Verify:** You should now have 5 secrets configured

### Security Notes

- ✅ Secrets are encrypted and never exposed in logs
- ✅ Only repository admins can view/edit secrets
- ✅ Secrets are only available to workflows during execution
- ⚠️ Never commit certificates or passwords to git
- ⚠️ Rotate app-specific passwords periodically

## Creating a Release

### Release Version Numbering

MacDown uses [Semantic Versioning](https://semver.org/):

- **Production releases:** `v1.0.0`, `v1.2.3`, `v2.0.0`
- **Pre-releases:** `v1.0.0-beta.1`, `v1.0.0-alpha.1`, `v1.0.0-rc.1`

The workflow automatically detects pre-releases from the version string.

### Release Checklist

Before creating a release:

- [ ] All tests pass on the commit you want to release
- [ ] Version number is decided
- [ ] CHANGELOG is updated (if applicable)
- [ ] All intended changes are merged

### Creating a Release (Tag Method)

The recommended way to trigger a release is by creating and pushing a version tag:

**⚠️ IMPORTANT:** Release tags MUST be created from the `main` branch only. The workflow will fail if you tag a dev branch.

1. **Ensure you're on the correct commit:**
   ```bash
   git checkout main
   git pull origin main
   ```

2. **Create a version tag:**
   ```bash
   # For production release
   git tag v1.0.0

   # For pre-release
   git tag v1.0.0-beta.1
   ```

3. **Push the tag:**
   ```bash
   git push origin v1.0.0
   ```

4. **Monitor the workflow:**
   - Go to **Actions** tab on GitHub
   - Watch the "Release" workflow run
   - Workflow typically takes **10-15 minutes**

5. **Wait for completion:**
   - Workflow will create a **draft release**
   - Check the **Releases** page on GitHub

### Manual Trigger (Alternative)

You can also manually trigger the workflow without creating a tag:

1. Go to **Actions** → **Release** workflow

2. Click **Run workflow**

3. Enter the version number (e.g., `1.0.0` - without the 'v' prefix)

4. Click **Run workflow**

## Post-Notarization Stapling

After the release workflow completes, the DMG has been **submitted** for notarization but is **not yet stapled**. Use the automated stapling workflow to complete the release.

### Why Stapling?

**Stapling** attaches Apple's notarization approval ticket to the DMG file. Without stapling:

- ✅ DMG will work if user has internet connection (macOS can verify online)
- ❌ DMG will show warnings if user is offline
- ❌ Less professional user experience

**With stapling:**

- ✅ DMG works offline
- ✅ No security warnings
- ✅ Professional distribution

### Automated Stapling Process

#### Step 1: Wait for Notarization Email

Apple will send an email to your Apple ID address when notarization completes (typically 5-15 minutes, sometimes up to 45 minutes).

**Email subject:** "Your Mac software was successfully notarized"

#### Step 2: Run the Stapling Workflow

Once you receive the approval email:

1. **Go to GitHub Actions**
   - Navigate to: `Actions` → `Staple and Publish Release`

2. **Run the workflow**
   - Click `Run workflow`
   - Enter the release tag (e.g., `v3000.0.0-beta.1`)
   - Click the green `Run workflow` button

3. **Monitor the workflow**
   - The workflow will:
     - ✅ Verify notarization was accepted
     - ✅ Download the DMG from the release
     - ✅ Staple the notarization ticket
     - ✅ Validate the stapled DMG
     - ✅ Generate updated checksums
     - ✅ Replace the DMG and checksums in the release
     - ✅ Update release notes to indicate it's ready

4. **Workflow completes in ~2-3 minutes**

#### Step 3: Publish the Release

After the stapling workflow succeeds:

1. Go to the release on GitHub
2. Review the updated release notes
3. Click `Publish release`

#### Step 4: Website Updates Automatically

The `update-website.yml` workflow automatically triggers after the stapling workflow completes successfully. It will:

- ✅ Fetch the latest release information
- ✅ Update `docs/_data/latest.json` with download links
- ✅ Commit and push changes to the repository
- ✅ Jekyll regenerates the website with new download links

No manual intervention required for website updates!

### Manual Stapling (If Needed)

If the automated workflow fails or you need to staple manually:

<details>
<summary>Click to expand manual stapling instructions</summary>

1. Download DMG from the GitHub release
2. Staple the ticket:
   ```bash
   xcrun stapler staple MacDown-X.X.X.dmg
   ```
3. Validate:
   ```bash
   xcrun stapler validate MacDown-X.X.X.dmg
   ```
4. Verify:
   ```bash
   spctl -a -vvv -t install MacDown-X.X.X.dmg
   ```
5. Re-upload the stapled DMG to the release
6. Update checksums if needed

</details>

## Troubleshooting

### Workflow Fails: Missing Secrets

**Error:**
```
Missing required GitHub secrets: APPLE_TEAM_ID, APPLE_CERTIFICATE_BASE64
```

**Solution:**
- Follow [GitHub Secrets Setup](#github-secrets-setup) to configure missing secrets
- Ensure secret names match exactly (case-sensitive)
- Re-run the failed workflow after adding secrets

### Workflow Fails: Code Signing Error

**Error:**
```
No signing identity found
```

**Possible causes:**
1. Certificate expired → Renew certificate in Apple Developer account
2. Wrong certificate type → Must be "Developer ID Application" (not "Mac App Distribution")
3. Certificate password incorrect → Regenerate `APPLE_CERTIFICATE_PASSWORD` secret

**Solution:**
1. Verify certificate in Keychain Access
2. Re-export and re-encode to base64
3. Update `APPLE_CERTIFICATE_BASE64` and `APPLE_CERTIFICATE_PASSWORD` secrets

### Notarization Submission Fails

**Error:**
```
Invalid credentials
```

**Possible causes:**
1. Wrong Apple ID → Verify `APPLE_ID` matches your developer account
2. Wrong app-specific password → App-specific passwords expire or can be revoked
3. Wrong Team ID → Verify `APPLE_TEAM_ID` is correct

**Solution:**
1. Generate a **new app-specific password** at [appleid.apple.com](https://appleid.apple.com)
2. Update `APPLE_APP_PASSWORD` secret
3. Re-run the workflow

### Notarization Rejected

**Email:** "Your Mac software was not notarized"

**Common reasons:**
1. **Hardened Runtime not enabled** → Should be automatic in workflow
2. **Unsigned dependencies** → Check for unsigned frameworks/libraries
3. **Invalid entitlements** → Review entitlements in Xcode project

**How to diagnose:**
```bash
xcrun notarytool info <SUBMISSION_ID> \
  --apple-id your-email@example.com \
  --password xxxx-xxxx-xxxx-xxxx \
  --team-id YOUR_TEAM_ID
```

Look for the `statusReason` field for specific issues.

**How to get detailed logs:**
```bash
xcrun notarytool log <SUBMISSION_ID> \
  --apple-id your-email@example.com \
  --password xxxx-xxxx-xxxx-xxxx \
  --team-id YOUR_TEAM_ID \
  developer_log.json
```

Review `developer_log.json` for specific errors.

### Stapler Fails: "Could not validate"

**Error:**
```
CloudKit query for MacDown-1.0.0.dmg (2/....) failed due to "Ticket not found"
```

**Cause:** Trying to staple before notarization completed

**Solution:**
1. Wait for Apple's email confirmation
2. Verify status with `notarytool info` shows "Accepted"
3. Wait 1-2 minutes after acceptance email
4. Try stapling again

### DMG Shows Security Warning on User's Mac

**Symptom:** User sees "MacDown.dmg cannot be opened because it is from an unidentified developer"

**Possible causes:**
1. DMG not stapled → Follow [Post-Notarization Stapling](#post-notarization-stapling)
2. DMG not notarized → Check notarization status
3. User's macOS version too old → Notarization requires macOS 10.9+
4. User's Gatekeeper disabled → Not a MacDown issue

**Solution:**
- Ensure DMG is both **notarized** and **stapled**
- Test on a clean Mac before releasing
- Provide instructions for users with strict security settings

### Build Fails: CocoaPods Error

**Error:**
```
[!] Unable to find a specification for PodName
```

**Cause:** CocoaPods dependencies not installed correctly

**Solution:**
- Should not happen in CI (workflow installs dependencies)
- If testing locally: `bundle exec pod install`
- Check that `Podfile.lock` is committed to git

### Release Tag Already Exists

**Error:**
```
tag 'v1.0.0' already exists
```

**Cause:** Tag was already created (possibly for a failed build)

**Solution to re-release:**

1. **Delete the remote tag:**
   ```bash
   git push origin :refs/tags/v1.0.0
   ```

2. **Delete the local tag:**
   ```bash
   git tag -d v1.0.0
   ```

3. **Delete the draft release** on GitHub (if exists)

4. **Create tag again:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

## Additional Resources

- [Apple Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [GitHub Actions Secrets Documentation](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [Semantic Versioning](https://semver.org/)

## Support

If you encounter issues not covered in this guide:

1. Check the workflow logs in GitHub Actions
2. Review the [Troubleshooting](#troubleshooting) section
3. Open an issue on the GitHub repository with:
   - Workflow run URL
   - Error messages (redact sensitive info)
   - Steps you've already tried

---

**Last updated:** 2025-11-18
