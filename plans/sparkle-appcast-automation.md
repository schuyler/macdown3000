# Design: Sparkle appcast generation (#554), phase 1 — the script

Implementation guide for `Tools/update_appcast.py` and a documented manual publishing step.
Tests and prose documentation are the implementer's to write.

**Two deliberate limits.** Wiring this into `staple-release.yml` is phase 2 (§7) — phase 1
publishes by hand, so the script gets exercised across a few real releases before anything
unattended depends on it. And **the script never rewrites existing feed content**: it renders
one item, splices it in, and validates the result. That constraint removes the round-trip
fixed point, and with it most of what makes this kind of tool hard.

> **Evidence rule.** Sparkle's headers *declare* ObjC API, which the compiler enforces —
> those are trustworthy. They also *describe the appcast XML vocabulary in prose*, which
> nothing enforces, and where they do it they are wrong: `SUAppcastItem.h:167` names an
> attribute Sparkle does not read. Every schema claim below comes from the framework binary
> or from executing the tools.

---

## 1. What gets built

- **`Tools/update_appcast.py`** — stdlib-only Python. Renders one `<item>` into
  `docs/sparkle/macdown3000/stable/appcast.xml`, creating the file if absent. Signs the DMG
  itself, taking the EdDSA key on stdin.
- **A release-checklist step** giving the command an operator runs after a release is
  stapled, plus the commit that publishes it.
- **One line in `plans/rc-process.md` step 5**, deleting the RC's `<item>` when its Release is
  deleted at graduation (§4).

macdown.app is GitHub Pages serving `docs/` from `main`, so publishing is a commit — not
SSH, not separate hosting.

---

## 2. Facts

### 2.1 `sign_update` (Sparkle 2.9.5)

- Invoke as `sign_update -p --ed-key-file - FILE`, key on **stdin**. `-p` prints only the
  base64 signature plus a newline.
- **`-s <key>` is deprecated and does not work for newly generated keys.** Most CI examples
  online use it.
- **The key is a 32-byte seed** (44 base64 chars), what `generate_keys -x` exports. Measured:
  32 accepted, 48 rejected, **64 rejected**, 96 accepted (legacy), 128 rejected. Sparkle's own
  error message claims 64 or 96 are valid. It is wrong.
- Errors exit non-zero. Empty stdin → rc=1, and **no silent Keychain fallback** while
  `--ed-key-file -` is present.
- **There is no public-key input**, so nothing here can confirm the secret matches the
  `SUPublicEDKey` in shipped builds. See D3 and §7.

The operator runs this from `main`, where Sparkle is in the Podfile, so
`./Pods/Sparkle/bin/sign_update` exists after `bundle exec pod install`.

### 2.2 Appcast XML contract

Namespace URI `http://www.andymatuschak.org/xml-namespaces/sparkle` — the only such string in
the binary.

| Sparkle property | XML |
|---|---|
| `versionString` | `<sparkle:version>` — `CFBundleVersion` |
| `displayVersionString` | `<sparkle:shortVersionString>` — `CFBundleShortVersionString` |
| `fileURL` / `contentLength` | enclosure `url` / `length` |
| `itemDescription` | `<description>` CDATA body |
| `itemDescriptionFormat` | **`sparkle:format`** attribute |
| `channel` | `<sparkle:channel>`; absent = stable |
| `minimumSystemVersion` | `<sparkle:minimumSystemVersion>` |
| `dateString` | `<pubDate>`, RFC 5322 |
| `installationType` | inferred from extension; `.dmg` → `application` |

**The attribute is `sparkle:format`, not `sparkle:descriptionFormat`.** The binary contains
`sparkle:format` twice and `descriptionFormat` zero times; a wrong attribute name is silently
ignored, the format falls back to `html`, and raw Markdown rendered as HTML collapses into one
paragraph. **This is the single most important name in the document.** Pin the distinctive
names — `sparkle:format`, `sparkle:version`, `sparkle:shortVersionString`, `sparkle:channel`,
`sparkle:minimumSystemVersion`, `sparkle:edSignature`, and the namespace URI — against the
framework binary, not against our own fixture, which would pass with the wrong name.

`markdown` is a supported value (`_prefersMarkdown`, `org.sparkle-project.markdown-loader`, and
a *"falling back to plain text because markdown support requires macOS 12 or newer"* string in
the binary). The app's floor is macOS 11, so 11 shows readable Markdown source and 12+ renders
it. `guid` has 0 occurrences; omitting it is right.

`email.utils.format_datetime()` emits Sparkle's `pubDate` format exactly, locale-independently.

### 2.3 Hosting

`SUFeedURL` is `https://macdown.app/sparkle/macdown3000/stable/appcast.xml`; `SUPublicEDKey`
holds the real key (`MacDown-Info.plist:142-152`).

Jekyll renders only files beginning with YAML front matter, so a file starting `<?xml …?>` is
copied byte-for-byte; `docs/_config.yml` excludes only `Gemfile`, `Gemfile.lock`, `README.md`,
`vendor`. **The appcast must not be given front matter.**

`docs/sparkle/` does not exist yet and is not gitignored. Until the first published item
`SUFeedURL` returns 404 — harmless, since no shipped build polls the feed today, and not to be
"fixed" with a hand-written placeholder that would be served live.

### 2.4 Versions

`Tools/utils.sh:41-43` — `get_bundle_version()` is `git rev-list --count HEAD`, a commit count,
**not monotonic across release branches** (#564, out of scope). That is why §3.3 refuses on a
duplicate rather than assuming versions are unique per release. `plans/rc-process.md:127,248` —
graduating an RC adds a commit, so an RC and its final never collide.

`LSMinimumSystemVersion` resolves in the built app (`11.0` today). Read it from the app inside
the DMG per build; hardcoding drifts.

**Why the script does not re-emit existing content:** `ElementTree.tostring` does not preserve
CDATA (`<![CDATA[a & b]]>` comes back as `a &amp; b`), silently drops comments and processing
instructions, and parses a DOCTYPE with internal entities without complaint. Round-tripping the
feed would mean defending against all three. Splicing means none of them can reach us.

---

## 3. `Tools/update_appcast.py`

### 3.1 The item it renders

Two-space indent, LF, UTF-8 without BOM. Child order is exactly this:

```xml
    <item>
      <title>MacDown 3000 3000.1.0-rc.1</title>
      <pubDate>Tue, 04 Aug 2026 18:03:12 +0000</pubDate>
      <sparkle:version>4837</sparkle:version>
      <sparkle:shortVersionString>3000.1.0-rc.1</sparkle:shortVersionString>
      <sparkle:channel>beta</sparkle:channel>
      <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
### Added

- Automate Sparkle appcast generation and publishing (#554)
]]></description>
      <enclosure url="https://github.com/schuyler/macdown3000/releases/download/v3000.1.0-rc.1/MacDown-3000.1.0-rc.1.dmg" length="41287316" type="application/octet-stream" sparkle:edSignature="Ov9k2mQ3H1cVYxTn0aQ8pLpQ4bK7dR2sYy1uWw6cJ0nZ8rT5fXhE3mB7oQdA1cV2sYy1uWw6cJ0nZ8rT5fXhEg=="/>
    </item>
```

A stable item is identical minus `<sparkle:channel>`, which is emitted **only for
pre-releases**. That is what `MPMainController.m:299` relies on: `allowedChannelsForUpdater:`
returns `{"beta"}` when the pre-release preference is on and the empty set otherwise, and
Sparkle always allows channel-less items.

`<title>` is `MacDown 3000 {short_version}` — Sparkle composes its own headline and never
displays this; it exists so a human reading the feed sees something. `<pubDate>` is now, UTC.
The CDATA body is bracketed by exactly one newline on each side.

**Deliberately omitted.** Item-level `<link>` — in Sparkle 2 that is `infoURL`, feeding the
informational-update path, not a web link; it puts the item one
`<sparkle:informationalUpdate>` away from being non-downloadable. `<guid>` — absent from the
binary. `sparkle:installationType` — `.dmg` infers `application`. `application/octet-stream`
over the accurate `x-apple-diskimage` because `type` is RSS metadata Sparkle never reads for
dispatch, and it matches `generate_appcast`.

The enclosing document, written only when the file does not exist:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MacDown 3000</title>
    <link>https://macdown.app/</link>
    <description>Updates for MacDown 3000, a Markdown editor for macOS.</description>
    <language>en</language>
    <!-- items here, newest first -->
  </channel>
</rss>
```

### 3.2 CLI

```
update_appcast.py --appcast PATH --dmg PATH --url URL --description-file PATH
                  --bundle-version V --short-version V --minimum-system-version V
                  [--channel {"",beta}] [--sign-update PATH] [--dry-run]
```

Signing is the only mode: the key is read from **stdin** and `length` is the DMG's size on
disk. No precomputed-signature path — nothing in phase 1 needs one.

| Flag | Rule |
|---|---|
| `--dmg` | must exist, be readable, end in `.dmg`, and not resolve to the same path as `--appcast` (§3.3) |
| `--url` | must be `https://` |
| `--channel` | exactly `""` (default) or `beta` |
| `--bundle-version` | `[A-Za-z0-9._-]+` |
| `--description-file` | must exist, non-empty after stripping, and must not contain `]]>` (§3.4) |
| `--sign-update` | defaults to `./Pods/Sparkle/bin/sign_update`; error naming the path if missing or not executable |

Read stdin to EOF for the key. **If stdin is a TTY, error immediately** rather than blocking
forever — that is the failure an operator hits under time pressure.

### 3.3 What it does

1. **Render the item** (§3.1).
2. **If the appcast does not exist** — write the full document with the one item, creating
   parent directories. This is the expected first run.
3. **If it exists** — splice the rendered item in as text, immediately before the first
   `    <item>` line, or before the `  </channel>` line if there are none. **If neither anchor
   is found, exit 1.**
4. **Validate the result, once.** Parse the resulting bytes with `ElementTree`; then count the
   items whose `<sparkle:version>` equals the incoming one. Exit 1 unless the document parses
   and that count is exactly 1.
5. **Write atomically** — temp file beside the target, then `os.replace()`. Leave no temp file
   on any error path.

**Step 4 is the whole safety story, and it is one pass.** A malformed existing file, a
control character in the description, an unescaped `&` in the URL, a corrupt splice, a
re-publish of a version already in the feed, a pre-existing duplicate — every one of them
fails here, before anything is written. Do not reimplement these as separate checks. When it
fails on an existing file, say in the message that the existing file may already have been
malformed, because the script cannot tell the two apart and the operator can.

**The existing file's bytes are never rewritten.** Only an insertion. So no round-trip fixed
point is required, existing items cannot drift, and the ElementTree behaviors in §2.4 cannot
damage anything. Preserve this property; it is why the rest of the design is small.

**Two guards on the signing subprocess**, because `sign_update` has a second mode that would
otherwise defeat all of the above. Given an XML file it *embeds* the signature — its own help
says *"For signing appcast feeds, sign_update will embed the signature inside the XML file"* —
so it rewrites the feed in place, reserializing it and destroying existing items' CDATA, then
exits 0 printing nothing. A copy-paste slip between `--dmg` and `--appcast` in a hand-run
command that already contains both paths is all it takes, and the result is invisible to step 4:
an item carrying `sparkle:edSignature=""` is well-formed, parses, counts 1, and publishes.

1. Validate `--dmg` before launching the subprocess (§3.2) — extension, and not the appcast's
   own path.
2. **Reject a `sign_update -p` result that is not a non-empty base64 string.** Exit code 0 is
   not sufficient evidence that a signature was produced.

### 3.4 Escaping

The description goes into CDATA verbatim, so `&`, `<`, `>`, quotes and non-ASCII need no
handling — the file is UTF-8 and declared as such. Normalize `\r\n` and `\r` to `\n` on ingest
to keep the committed file clean.

`]]>` cannot appear inside a CDATA section, and rather than splitting the section the script
**rejects a description containing it** (§3.2) with a message naming the offending line. A
changelog is unlikely to contain `]]>`, splitting is machinery to maintain and get right, and
the operator can trivially reword. Without this pre-check the failure would still be caught by
step 4, but the message would be an opaque parse error.

Element text is escaped with `saxutils.escape`. **Do not use `saxutils.quoteattr` for attribute
values** — it switches to single-quote delimiters when the value contains a double quote
(`quoteattr('a"b')` → `'a"b'`), which contradicts the fixed layout. Emit attributes as
`'"' + saxutils.escape(v, {'"': '&quot;'}) + '"'` and control the delimiter yourself.

Escaping `"` *before* calling `quoteattr` does not work: `quoteattr` escapes `&` too, so the
value arrives as the literal text `&amp;quot;`.

### 3.5 Output

- Exit **0** printing `appcast updated: <bundle_version> (<short_version>)`.
- Exit **1** on any error, leaving the file byte-identical.
- **`--dry-run`** writes the full resulting document to stdout, touches no file, and returns
  the exit code the real run would have returned. **It signs for real** — it reads the key from
  stdin and runs `sign_update` exactly as a normal run does, so its output is the document that
  would have been written, and a bad key or a missing `sign_update` is caught in the pre-flight
  rather than after it. "Touches no file" means the appcast, not the subprocess. This is the
  pre-flight §4 depends on.

A duplicate version is a hard error with no override. `CFBundleVersion` is a commit count
(§2.4), so it means either a re-run of a publish that already succeeded or a #564 collision
between release branches — where silently replacing `3000.0.7`'s item with `3000.1.0`'s would
push a wrong download URL to every install. Neither should be resolved by a flag. The operator
edits and commits this file by hand anyway, so the recovery for a genuinely bad item is to
delete that `<item>` block and re-run; say so in the error message.

The key never appears in argv, in an environment variable, or in a temp file — stdin to the
script, stdin to the `sign_update` subprocess.

---

## 4. Publishing a release

Documented in `plans/release-checklist.md`. After the stapling workflow finishes, from a clean
`main` with `bundle exec pod install` done:

1. **Download `MacDown-${VERSION}.dmg` from the GitHub release. Never sign a local build.**
   Stapling mutates the DMG in place (`staple-release.yml:221`) and re-uploads it with
   `--clobber` (`:347-350`), so the released asset and any local `build/` DMG have different
   bytes — and `create-dmg` output is not reproducible anyway. Signing the wrong file yields a
   signature and a `length` describing bytes nobody downloads, every client rejects the update,
   and nothing catches it: `--dry-run` produces the same wrong signature, and the parse in
   §3.3 cannot see it. Verify the download against `MacDown-${VERSION}.dmg.sha256`, uploaded
   alongside it.
2. Mount it read-only; read `CFBundleVersion`, `CFBundleShortVersionString` and
   `LSMinimumSystemVersion` from `MacDown 3000.app/Contents/Info.plist` with PlistBuddy.
   **If the app has no `SUPublicEDKey`, stop** — that build carries no updater (Sparkle is
   commented out of the Podfile on release branches cut before this work), and an item for it
   would advertise, to every installed copy, an update that silently removes their ability to
   receive the next one.
3. Extract the release's section from `CHANGELOG.md` **at the tag**, not from `main` — the two
   legitimately differ, and `plans/rc-process.md:100-103` documents an RC-only block present on
   the release branch and not on main. Strip the `<!-- rc-temp -->` / `<!-- /rc-temp -->` fence
   lines: invisible under `sparkle:format="markdown"` on macOS 12+, but macOS 11 falls back to
   plain text and shows them literally.
4. Run the exact command below with `--dry-run` appended, and read the output. It signs for
   real, so it needs the key piped in the same way.
5. Run it again without `--dry-run`:

```bash
op read "op://Personal/MacDown Sparkle EdDSA/password" \
  | python3 Tools/update_appcast.py \
      --appcast docs/sparkle/macdown3000/stable/appcast.xml \
      --dmg ~/Downloads/MacDown-3000.1.0.dmg \
      --url https://github.com/schuyler/macdown3000/releases/download/v3000.1.0/MacDown-3000.1.0.dmg \
      --bundle-version 4837 --short-version 3000.1.0 --minimum-system-version 11.0 \
      --description-file /tmp/section.md \
      --channel ""
```

Use `--channel beta` for a pre-release tag. Nothing may follow the last flag on its line —
step 4 appends `--dry-run` to this command, and a trailing comment would swallow it, turning
the intended pre-flight into a real publish.

6. Commit the one file to `main` and push. GitHub Pages serves it at `SUFeedURL`.

**Pre-release tags take `--channel beta`; stable tags take `--channel ""`.** Getting this wrong
on a pre-release pushes it to every user. The first published item should be a pre-release, so
a mistake reaches only opted-in users.

### An item's lifetime matches its GitHub Release's

`plans/rc-process.md:252-256` **deletes the `vX.Y.Z-rc.*` Releases at graduation** — keeping the
tags, but removing the downloads, because some RCs ship known-buggy DMGs. An RC's enclosure URL
therefore dies the moment the final ships, and nothing in this design removes items.

So when an RC graduates, **delete its `<item>` block from
`docs/sparkle/macdown3000/stable/appcast.xml` in the same commit that deletes the RC Releases**
— `plans/rc-process.md` step 5 gains that line. Otherwise beta-channel users are offered a
download that 404s, in the window between graduation and the final's publish.

This is the general rule, and it is the only case where the operator removes an item by hand
outside of incident recovery: **an appcast item lives exactly as long as the release it points
at.** Stable items are never deleted, because stable releases never are.

---

## 5. What can go wrong

Almost everything fails closed: any error exits 1 with the file byte-identical, `os.replace()`
means the live feed is never half-written, and `--dry-run` before every publish makes the rest
of it unreachable. That is the point of doing this by hand first.

Two failures are not caught by the script.

**A wrong signing key is not detected** (D3). Every client rejects the update with a signature
error. Republishing fixes it — but not for everyone. Users who dismiss the broken update with
**Skip This Version** record it in `SUSkippedVersion` (verified in the binary, with
`SUSkippedMajorVersion` and the menu string), and Sparkle presents that alert *before* download
and signature verification, so it is reachable. Republishing keeps the same
`<sparkle:version>`, so the corrected item is never re-offered to them and they wait for the
following release. Sparkle's escape hatch `sparkle:ignoreSkippedUpgradesBelowVersion` (8
occurrences in the binary) exists; this design does not emit it.

**A wrong `--channel` on a pre-release** offers it to every user. Recovery is to delete the
item block and re-run. Nothing validates the flag against the tag, because the script never
sees the tag.

---

## 6. Decisions

- **D1 — Splice, never re-emit.** The script renders one item and inserts it; existing bytes
  are never rewritten, and a single parse of the result (§3.3 step 4) is the entire validation
  story. This removes the round-trip fixed point and everything hanging off it — a strict
  schema for existing content, CR normalization on read, comment/PI/DOCTYPE detection,
  byte-stability across releases. **This is the decision the rest of the design depends on.**
- **D2 — Phase the work.** Script first, workflow second (§7). Publishing by hand costs about
  ten minutes per release and buys real evidence before anything unattended runs.
- **D3 — Phase 1 does not verify the signing key's identity.** The operator holds the key and
  runs the command deliberately, so a stale-secret mixup is far less likely than in CI. Phase 2
  should verify it — §7 records a mechanism that costs almost nothing.
- **D4 — No backfill.** The feed starts with the first release published after merge.
  Backfilling would require downloading and signing every historical DMG, and older installs
  reach the newest item by version comparison anyway.
- **D5 — The `stable/` path segment stays.** Beta items live in the same file behind
  `<sparkle:channel>`. Mildly misleading, but baked into every shipped build's `SUFeedURL`.

**Cut as unnecessary:** the canonical re-serializer and its fixed point; the strict-schema
parser; `--force` and the field-by-field conflict comparison; monotonicity warnings; the
CDATA `]]>` splitter; `--title`; `--pub-date`; `--length`/`--signature`. Each was machinery
guarding a problem that splicing, or a single validating parse, removes.

---

## 7. Phase 2 — workflow automation, deferred

Not designed here. Findings against an earlier full-automation draft, recorded so phase 2 does
not rediscover them:

- **Step placement.** `staple-release.yml`'s point of no return is "Update release with stapled
  DMG" (`:338`), which uploads with `--clobber`; everything after it is un-re-runnable because
  the already-stapled guard (`:208-212`) validates the DMG downloaded *from the release*. Note
  "Update release notes" is at `:364` — **after** `:338`. The stapled DMG exists locally from
  `:216`, so signing and metadata extraction belong between "Final comprehensive verification"
  (ends `:336`) and `:338`.
- **The tag tree.** After `git checkout "$TAG"` (`:60-66`), every path in the workspace resolves
  against the *tag's* tree, not the workflow's commit. Any new shared script must be staged out
  of the workspace (e.g. into `$RUNNER_TEMP`) before that line, or it will not exist for older
  tags. `staple-release.yml:314` already has this latent bug, harmlessly, because it sits
  before `:338`.
- **Verify the key, cheaply.** The check is *not* deriving the public half from the private key
  — that needs Ed25519 on macOS, which LibreSSL cannot do. It is verifying the signature just
  produced against the `SUPublicEDKey` read out of the app: public inputs only, stock OpenSSL 3
  on ubuntu. Prefix the bare 32-byte key with `302a300506032b6570032100` to make an SPKI DER,
  then `openssl pkeyutl -verify -pubin -inkey pub.pem -rawin -in FILE -sigfile sig.bin`.
  Correct key verifies; wrong key exits 1. This closes the wrong-key failure in §5.
- **Fail closed.** A skip-the-appcast gate must be written on *every* path and asserted to be
  exactly `true` or `false` by its consumer. Gating on `!= 'true'` makes the unset string the
  publishing state, so a typo silently publishes an item for an app with no updater.
- **`update-website.yml`.** Its push retry (`:230-246`) has no `git pull --rebase`, and `:17`
  gates on the whole run's conclusion. Anything committing to `main` during a staple run must
  account for both.
- **Sparkle tooling.** `staple-release.yml` runs no CocoaPods toolchain at all, so a pinned,
  checksum-verified release tarball extracted into a named directory beats adding Bundler and
  CocoaPods to the most safety-critical workflow in the repo.
- **RC item removal.** Automating publication does not automate the deletion in §4 — graduation
  is a separate workflow. Either automate that removal too, or the feed accumulates dead RC
  enclosure URLs. Removing an item means editing existing content, which is the one thing the
  phase 1 script deliberately cannot do.
- **Extraction contract.** If changelog extraction is factored into a script, specify its input
  contract explicitly — the existing awk (`:382-392`) reads a *named file* and takes the version
  via `-v ver=`, so a caller that pipes to it silently reads the wrong changelog rather than
  failing.

## 8. Risks

- **Nothing verifies Sparkle parses the emitted feed correctly** — only that the names appear in
  its binary. Bounded by publishing a pre-release first.
- **Nothing verifies the signing key is the right key** in phase 1 (D3).
- **Publishing is manual and can be forgotten.** Lower-consequence than the automated failure it
  replaces, but it belongs in the release checklist rather than folklore.
- **Nobody currently owns verifying the feed is served.** After the first published item, someone
  must confirm `SUFeedURL` returns 200, parses, and drives a real install.
- **#564 will eventually produce a `CFBundleVersion` collision.** The script refuses rather than
  corrupting the feed. It does not fix the underlying problem.
</content>
