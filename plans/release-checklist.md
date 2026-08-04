# MacDown Release Checklist

**Quick reference:** Four manual steps are required to release MacDown:
1. Update the changelog
2. Tag and push the version
3. Staple the DMG (after notarization)
4. Triage the milestone's open issues (after publish)

(There's also a one-time auto-update readiness prerequisite before the first update-enabled release — see below.)

See `plans/release-process.md` for detailed instructions.

---

## Prerequisite (One-Time): Auto-Update Readiness

Sparkle 2 auto-updates are wired up in the app but **inert** until the
release-blockers below are cleared, by the maintainer, before the first real
release that should offer auto-updates. None of these are per-release steps
— once each is resolved, it never needs to be redone for later releases.

- [x] **The EdDSA signing keypair exists**, generated with the `generate_keys`
  tool Sparkle 2.9.5 vendors at `Pods/Sparkle/bin/generate_keys` (present
  after `bundle exec pod install`). It writes the private key to the login
  Keychain and prints the matching public key.

  Use `generate_keys` rather than deriving a pair with another ed25519 tool.
  A public half that doesn't match the private key yields a `SUPublicEDKey`
  no signature can ever verify — indistinguishable from a working key until an
  update is rejected in the field. (`generate_keys -f` imports a key produced
  elsewhere, if that path is ever needed.)

- [x] **The public key is in `MacDown/MacDown-Info.plist`** as `SUPublicEDKey`.
  Every shipped build carries it, so it cannot be changed without stranding
  existing installs — they reject updates signed by any other key.

- [x] **The private key is backed up in 1Password**, as a Password item titled
  `MacDown Sparkle EdDSA` in the `Personal` vault. This has to stay true before
  any release that ships the public key above: if the private half is lost, no
  existing install can ever be updated again. Nothing in the build or the
  release workflow reads the key out of the Keychain, so it need not stay
  there. To repeat the export — for a second backup, or after rotating:
  ```bash
  ./Pods/Sparkle/bin/generate_keys -x ~/sparkle-eddsa.key
  pbcopy < ~/sparkle-eddsa.key
  rm ~/sparkle-eddsa.key
  ```
  Write the export outside the working tree, as above — a private key sitting
  in the repo root is one careless `git add` away from being published.

  The export is one base64 line: the 32-byte private seed, identical to the
  password on the Keychain's "Private key for signing Sparkle updates" item.
  Paste it from the clipboard into the 1Password item, then clear the
  clipboard. Paste by hand rather than using `op item create`: assignments are
  logged in shell history and visible to other local processes, per 1Password's
  own warning. Piping the file through `pbcopy` keeps the key off the terminal,
  out of shell history, and out of any session transcript.

  There is no secure erase to reach for here — `rm -P` is documented on macOS
  as having no effect. Treat the key as having existed in the clear on that
  disk, and in any snapshot or backup taken while it did.

  Once the key is in 1Password the Keychain item can be deleted; signing then
  works from any machine, including CI.

- [x] **Sparkle's nested components are re-signed for notarization (issue
  #553).** Sparkle ships from CocoaPods ad-hoc signed, and the pod's embed
  phase re-signs only the framework's top level, without hardened runtime or a
  secure timestamp — which notarization rejects for any release that embeds
  Sparkle, not just ones advertising auto-update. `Tools/sign_sparkle.sh`
  re-signs the XPC services, `Autoupdate`, `Updater.app`, and the framework
  inside-out with the release identity, and
  `Tools/verify_sparkle_signature.sh` asserts Developer ID authority, hardened
  runtime, team identifier, and a secure timestamp at three gates. No
  per-release action is required.

- [ ] **Appcast generation and hosting (issue #554).** The remaining blocker.
  Until a signed `appcast.xml` is served at `SUFeedURL`, auto-update stays
  inert no matter what else in this section is checked.

**The private key is never committed.** It belongs in 1Password and in the
GitHub secret that appcast automation will read (issue #554). It has no place
in this repository, and the export written by `generate_keys -x` is as
sensitive as the key itself — delete it once it is stored.

**Signing without the Keychain.** Both signing tools accept the key on
standard input, so no machine needs Keychain access at publish time:

```bash
op read "op://Personal/MacDown Sparkle EdDSA/password" \
  | ./Pods/Sparkle/bin/generate_appcast --ed-key-file - ./release-dmgs/
```

That needs the 1Password CLI (`brew install --cask 1password-cli`). Without
it, copy the key from 1Password and substitute `pbpaste |` for `op read …|`.

`sign_update` takes the same `--ed-key-file -`. Do not use `-s <key>`: it is
deprecated in Sparkle 2.9.5 and unsupported for newly generated keys.

**On the appcast:** no automation in this repo produces or publishes one, and
nothing is served at `SUFeedURL` today. GitHub Pages serves macdown.app from
`docs/` on `main`, so publishing the feed is a commit to
`docs/sparkle/macdown3000/stable/appcast.xml` — see issue #554.

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

- [ ] **Trigger the stapling GitHub Action** (recommended)
  - Go to: Actions → Staple DMG workflow
  - Click "Run workflow"
  - Enter the submission ID from the notarization email
  - Workflow automatically updates the release with the stapled DMG

  *OR manually staple if preferred:*
  - Download DMG from draft release
  - Run: `xcrun stapler staple MacDown-0.9.0.dmg`
  - Re-upload to the release

- [ ] **Publish the release**
  - Go to: Releases → "MacDown 0.9.0" (draft)
  - Uncheck "This is a draft"
  - Click "Publish release"

---

## Step 4: Triage the Milestone's Open Issues

- [ ] **Review open issues in the release's milestone** and close any fully addressed by this release, with a comment citing the fixing PR
  - Don't wait for the original submitter to confirm the fix — the changelog/PR content is sufficient evidence
  - Flag ambiguous cases (unclear PR match, opt-in-only fix, suspected duplicate) for confirmation before closing
  - See `.claude/commands/release.md` → "Step 7: Post-Release Milestone Issue Triage" for the full process

---

## That's It

The workflow handles everything else:
- ✅ Builds the app (universal binary for Apple Silicon + Intel)
- ✅ Code signs with Developer ID
- ✅ Creates the DMG installer
- ✅ Generates checksums
- ✅ Submits for Apple notarization
- ✅ Creates the GitHub release as a draft

Your job is just updating the changelog, tagging, stapling, and triaging the milestone afterward.

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

**Last updated:** 2026-08-03
**Philosophy:** Only actual manual steps are in this checklist. Everything else is automated.
