# MacDown Release Checklist

**Quick reference:** Five manual steps are required to release MacDown:
1. Update the changelog
2. Tag and push the version
3. Staple the DMG (after notarization)
4. Publish the appcast (after the release is published)
5. Triage the milestone's open issues (after publish)

(There's also a one-time auto-update readiness prerequisite before the first update-enabled release — see below.)

See `plans/release-process.md` for detailed instructions.

---

## Prerequisite (One-Time): Auto-Update Readiness

Sparkle 2 auto-updates are wired up in the app but **inert** until the
release-blockers below are cleared, by the maintainer, before the first real
release that should offer auto-updates. Each is resolved once and never
redone — the per-release work they unlock is Step 4.

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

- [x] **Appcast generation and hosting (issue #554).** `Tools/update_appcast.py`
  renders one signed `<item>` per release and splices it into
  `docs/sparkle/macdown3000/stable/appcast.xml`. The tool is the one-time part;
  running it is a per-release step — see Step 4.

  `SUFeedURL` returns 404 until the first item is published. That is harmless,
  since no shipped build polls the feed yet, and it is not to be "fixed" with a
  hand-written placeholder, which would be served live.

**The private key is never committed.** It belongs in 1Password, which is where
Step 4 reads it from at publish time. It has no place in this repository, and
the export written by `generate_keys -x` is as sensitive as the key itself —
delete it once it is stored. Publishing is manual, so nothing in CI needs the
key; don't put it in a GitHub secret until something reads it from there.

**Signing without the Keychain.** The key is read from standard input, so no
machine needs Keychain access at publish time. Step 4 pipes it in with the
1Password CLI (`brew install --cask 1password-cli`); without it, copy the key
from 1Password and substitute `pbpaste |` for `op read …|`.

**Use `Tools/update_appcast.py`, never `generate_appcast`.** Sparkle's
`generate_appcast` regenerates the whole feed from a directory of DMGs: it
reserializes the file, destroying the CDATA release notes, comments and
processing instructions in items already published, and drops any item whose
DMG is not in that directory. `update_appcast.py` renders one item and splices
it in as text, so published items are never rewritten.

For the same reason, never point `sign_update` at the appcast. Handed an XML
file it embeds the signature *inside* it, rewriting the file in place, then
exits 0 printing nothing. `update_appcast.py` refuses a `--dmg` that resolves
to the appcast, but a hand-run `sign_update` has no such guard.

`sign_update` takes `--ed-key-file -`. Do not use `-s <key>`: it is deprecated
in Sparkle 2.9.5 and unsupported for newly generated keys.

**On the appcast:** GitHub Pages serves macdown.app from `docs/` on `main`, so
publishing the feed is a commit to `docs/sparkle/macdown3000/stable/appcast.xml`
— not SSH, not separate hosting. Jekyll copies a file starting `<?xml …?>`
byte-for-byte, so the appcast must never be given YAML front matter.

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

## Step 4: Publish the Appcast

Installed copies only learn about a release when an `<item>` for it appears in
`docs/sparkle/macdown3000/stable/appcast.xml`. Run this from a clean `main`
with `bundle exec pod install` done, after the release is published.

The rest of this step assumes:

```bash
VERSION=3000.1.0                        # the release, without the leading v
DMG=~/Downloads/MacDown-${VERSION}.dmg
```

- [ ] **Download the DMG from the GitHub release — never sign a local build.**
  Stapling rewrites the DMG in place and re-uploads it, and `create-dmg` output
  is not reproducible, so any local `build/` DMG has different bytes from the
  one users download. Signing the wrong file yields a signature and a `length`
  describing bytes nobody fetches; every client rejects the update, and nothing
  catches it — the dry run below produces the same wrong signature. Verify the
  download against `MacDown-${VERSION}.dmg.sha256`, uploaded alongside it.
  Download both, then verify from the directory holding them, since the
  checksum file names the DMG without a path:
  ```bash
  (cd "$(dirname "$DMG")" && shasum -a 256 -c "MacDown-${VERSION}.dmg.sha256")
  ```

- [ ] **Read the versions out of the app inside the DMG**, so they describe the
  build being advertised rather than the working tree:
  ```bash
  MOUNT=/tmp/macdown-appcast-dmg
  hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
  PLIST="$MOUNT/MacDown 3000.app/Contents/Info.plist"
  plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }

  BUNDLE_VERSION=$(plist_value CFBundleVersion)
  SHORT_VERSION=$(plist_value CFBundleShortVersionString)
  MIN_SYSTEM=$(plist_value LSMinimumSystemVersion)

  printf 'CFBundleVersion            %s\n' "$BUNDLE_VERSION"
  printf 'CFBundleShortVersionString %s\n' "$SHORT_VERSION"
  printf 'LSMinimumSystemVersion     %s\n' "$MIN_SYSTEM"
  printf 'SUPublicEDKey              %s\n' "$(plist_value SUPublicEDKey)"

  hdiutil detach "$MOUNT"
  ```
  Keep these in the shell rather than copying them by hand — the publish
  command below uses them directly.

  Mount at an explicit path rather than letting it land in `/Volumes`. Every
  MacDown DMG carries the volume name `MacDown 3000`, so if one is already
  mounted — an earlier release opened in Finder, or this one double-clicked to
  look inside — macOS attaches this one as `/Volumes/MacDown 3000 1`, and
  reading `/Volumes/MacDown 3000` would report a different build's versions
  against this release's URL. Nothing downstream would catch that. If anything
  aborts between `attach` and `detach`, the retry fails with `Resource busy` —
  run `hdiutil detach "$MOUNT"` first.

  **Stop if `SUPublicEDKey` is missing, or is the placeholder**
  `AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=`. A build with no key carries
  no updater at all, and an item for it would advertise, to every installed
  copy, an update that silently removes their ability to receive the next one.
  A build carrying the placeholder can never verify any signature, and users
  who dismiss the broken update with **Skip This Version** are never re-offered
  it even after a corrected item is published. Check this here for every
  release: `/release` compares against the placeholder only for non-prereleases
  (`.claude/commands/release.md` → Step 1), and a pre-release is exactly what
  gets published to this feed first.

- [ ] **Extract this release's changelog section at the tag**, not from `main`.
  The two legitimately differ: `plans/rc-process.md` documents an RC-only block
  that lives on the release branch and never reaches `main`.
  ```bash
  git fetch --tags
  git show "v${VERSION}:CHANGELOG.md" > /tmp/changelog-at-tag.md
  ```
  Fetch first: RC tags are cut on `release/*` branches, so a clean `main`
  may not have them and `git show` would fail on an unknown object.
  Copy this version's section into `/tmp/section.md`, dropping the
  `<!-- rc-temp -->` and `<!-- /rc-temp -->` fence lines. They are invisible
  under `sparkle:format="markdown"` on macOS 12+, but macOS 11 falls back to
  plain text and shows them literally.

- [ ] **Dry run first.** Append `--dry-run` to the command below and read the
  document it prints — the bytes the real run will write, down to the
  signature and the `length`, with only `<pubDate>` regenerated. It signs for
  real, so pipe the key in the same way; a bad key or a missing
  `sign_update` surfaces here rather than after the fact.

- [ ] **Publish.**
  ```bash
  op read "op://Personal/MacDown Sparkle EdDSA/password" \
    | python3 Tools/update_appcast.py \
        --appcast docs/sparkle/macdown3000/stable/appcast.xml \
        --dmg "$DMG" \
        --url "https://github.com/schuyler/macdown3000/releases/download/v${VERSION}/MacDown-${VERSION}.dmg" \
        --bundle-version "$BUNDLE_VERSION" \
        --short-version "$SHORT_VERSION" \
        --minimum-system-version "$MIN_SYSTEM" \
        --description-file /tmp/section.md \
        --channel ""
  ```
  Nothing may follow the last flag on its line. The dry run appends
  `--dry-run` to this command, and a trailing comment would swallow it,
  turning the intended pre-flight into a real publish.

  **Pre-release tags take `--channel beta`; stable tags take `--channel ""`.**
  Getting this wrong on a pre-release offers it to every user. Nothing
  validates the flag against the tag, because the script never sees the tag.

  A version already in the feed is a hard error with no override — it means
  either a re-run of a publish that already succeeded, or a `CFBundleVersion`
  collision between release branches (#564). To recover from a genuinely bad
  item, delete that `<item>` block by hand and re-run.

- [ ] **Commit the one file to `main` and push.** GitHub Pages then serves it
  at `SUFeedURL`.

- [ ] **Confirm the feed is live** once Pages has rebuilt:
  ```bash
  curl -sSf https://macdown.app/sparkle/macdown3000/stable/appcast.xml \
    | xmllint --noout -
  ```

---

## Step 5: Triage the Milestone's Open Issues

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

Your job is just updating the changelog, tagging, stapling, publishing the appcast, and triaging the milestone afterward.

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

**Last updated:** 2026-08-04
**Philosophy:** Only actual manual steps are in this checklist. Everything else is automated.
