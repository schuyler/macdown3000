# Design: Sparkle appcast generation (#554), phase 1 — the script

Implementation guide for `Tools/update_appcast.py` and a documented manual publishing step.
Tests and prose documentation are the implementer's to write.

---

## 1. What gets built

- **`Tools/update_appcast.py`** — Python. Renders one `<item>` into
  `docs/sparkle/macdown3000/stable/appcast.xml`, creating the file if absent. Signs the DMG
  itself, taking the EdDSA key on stdin. Release mode (§3.6) derives every per-release input
  from the version and the state of the repo; the explicit flags remain as the recovery
  escape hatch. The render/splice/validate core is stdlib-only; release mode adds `git` (for
  the tag→bundle-version count and to enumerate the tag), `stapler` (already required for
  building), and one HTTP GET for the DMG.
- **`plans/release-checklist.md` "Step 4: Publish the Appcast"** rewritten from the
  explicit-mode invocation it currently carries to the release-mode command in §4, plus
  the commit that publishes it.
- **Two edits to `plans/rc-process.md`**: reconcile the `--channel ""` reference at
  `:252` and the `--channel beta` reference at `:277` to the release-mode form, since
  `--channel` is refused alongside `--release` (§3.2). Step 5's RC-item-deletion line is
  already in place (§4).

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
  `SUPublicEDKey` in shipped builds. See D3.

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
holds the real key (`MacDown-Info.plist:151-152`).

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

`LSMinimumSystemVersion` in the source plist is the literal string
`${MACOSX_DEPLOYMENT_TARGET}`; Xcode resolves it at build time. §3.6 step 4 reads the
value from `project.pbxproj` instead.

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
update_appcast.py --release VERSION [--appcast PATH] [--sign-update PATH] [--dry-run]

update_appcast.py --dmg PATH --url URL --description-file PATH
                  --bundle-version V --short-version V --minimum-system-version V
                  [--appcast PATH] [--channel {"",beta}] [--sign-update PATH] [--dry-run]
```

The first form is release mode (§3.6); the second is explicit mode, the recovery escape
hatch. `--release` combined with `--dmg`, `--url`, `--description-file`, `--bundle-version`,
`--short-version`, `--minimum-system-version`, or `--channel` is an error — a partial
override is exactly the transcription hazard release mode removes. In particular, a local
DMG passed with `--dmg` is not the DMG users will download: `create-dmg` output is not
reproducible and stapling mutates the file in place (§4), so `--dmg` alongside `--release`
would sign bytes different from the enclosure URL's, and every client's signature check
would fail silently. Release mode owns the DMG source; explicit mode is where the operator
supplies one.

Signing is the only mode: the key is read from **stdin** and `length` is the DMG's size on
disk. No precomputed-signature path — nothing in phase 1 needs one.

| Flag | Rule |
|---|---|
| `--release` | the version of a published GitHub release, accepted with or without the leading `v`; the tag is `v` + version |
| `--appcast` | defaults to `docs/sparkle/macdown3000/stable/appcast.xml` in both modes (D8) |
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
4. **Validate the result, once.** Parse the resulting bytes with `ElementTree`; count the
   items whose `<sparkle:version>` equals the incoming one. Exit 1 unless the document
   parses and that count is exactly 1. On failure with an existing appcast, the error
   message must note the existing file may already have been malformed — the script cannot
   tell the two apart and the operator can. This one pass catches a malformed existing
   file, a control character in the description, an unescaped `&` in the URL, a corrupt
   splice, a re-publish of a version already in the feed, and a pre-existing duplicate.
   Do not reimplement these as separate checks.
5. **Write atomically** — temp file beside the target, then `os.replace()`. Leave no temp
   file on any error path.

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

### 3.6 Release mode

`--release VERSION` derives every per-release input; the operator supplies the version and
the key. Derivations, in order, all before signing:

1. **Shape** — VERSION must fullmatch `\d+(\.\d+)+(-(rc|beta)\.\d+)?`; anything else
   (`-alpha.1`, `-preview.N`, `-rc-1`, `-rc.1-hotfix`, bare `3000`, trailing garbage) is
   an error naming the offending value. Fail-closed: an unrecognized shape does not
   silently classify as stable, because "wrong channel on a pre-release offers it to
   every user" (§5) is exactly the failure mode release mode is supposed to eliminate.
   Deliberately narrower than `release.yml:148`'s `-(beta|alpha|rc)` pre-release
   detection: an `-alpha.N` tag would build in CI but be un-publishable via release mode.
   The project doesn't use alphas; if that changes, widen this regex explicitly.
2. **Tag** = `v` + VERSION, and **channel** = `beta` if the pre-release group is
   present, `""` otherwise. If `git rev-parse TAG` fails, error naming
   `git fetch --tags` — RC tags are cut on release branches a clean `main` may not have.
3. **Bundle version** = `git rev-list --count TAG`. Same commit count
   `Tools/utils.sh:get_bundle_version()` produced at build time — the CI checkout puts
   the tag at HEAD, so the numbers agree.
4. **Minimum system version** — extract `MACOSX_DEPLOYMENT_TARGET` from
   `MacDown 3000.xcodeproj/project.pbxproj` with a regex; the source plist holds only the
   literal `${MACOSX_DEPLOYMENT_TARGET}` placeholder that Xcode resolves at build time.
   The pbxproj currently carries the setting at 12 sites, all agreeing on `11.0`; the
   script asserts one distinct value across all matches and errors naming the drift if
   not. No new dependency — this is a stdlib file read.
5. **Description** — `git show TAG:CHANGELOG.md`, then extract the section whose heading
   line begins with `## [VERSION]` — the closing bracket is part of the match, so
   `## [3000.0.7]` and `## [3000.0.7-rc.1]` never collide; what follows on the same line
   (`- YYYY-MM-DD`, per `CHANGELOG.md`'s convention) is ignored. Take everything up to
   the next `## [` heading or EOF, stripping the heading line itself and any
   `<!-- rc-temp -->` / `<!-- /rc-temp -->` fence lines. The result is validated by the
   same rules as `--description-file` (UTF-8, non-empty, no `]]>`). Missing heading,
   empty section, or an invalid body → error naming the tag. Reading from the tag rather
   than the working tree is what makes this work for RC publishes: `plans/rc-process.md`
   puts each RC's `## [X.Y.Z-rc.N]` block in a `rc-temp` fence on the release branch,
   stripped at graduation, so the entry never lives on `main` — but it always lives on
   the tag.
6. **DMG bytes** — HTTP GET
   `https://github.com/schuyler/macdown3000/releases/download/TAG/MacDown-VERSION.dmg`
   into a private temp file (`tempfile.NamedTemporaryFile` with `delete=False`, mode
   `0600`). Non-200 → error naming the URL. The temp file is unlinked on every exit
   path — success, any error after the download, and `--dry-run` alike — via a `finally`
   block or equivalent. The enclosure URL is the canonical release URL, matching the
   bytes we downloaded and signed.
7. **Stapling check** — `xcrun stapler validate DMG` must exit 0. `stapler` ships with Xcode
   command-line tools (already required for building); the `xcrun` prefix matches
   `staple-release.yml:208,225`. This is the one guard release mode
   adds beyond what §3.3 already does, and it closes the specific failure of running the
   script before `staple-release.yml` finishes: `release.yml` uploads an unstapled DMG that
   the stapler workflow replaces in place, so an early download signs bytes users will
   never see. If not stapled → error telling the operator to wait for the workflow and
   check https://github.com/schuyler/macdown3000/actions.
8. **Sign** — `sign_update -p --ed-key-file - DMG`, key on stdin, as in explicit mode. The
   §3.3 guards against `sign_update`'s XML-embedding mode still apply.

From there the flow is §3.3 unchanged: render, splice, single validating parse, write
atomically. `--dry-run` runs the full derivation, download, stapling check and signing —
its purpose is a real pre-flight — but writes no file. The stdin TTY check and the key
path are identical in both modes.

Release mode runs on macOS (needs `stapler`) with network access. Explicit mode keeps
working with just Python and `sign_update`, which is what makes it the recovery path.

---

## 4. Publishing a release

Documented in `plans/release-checklist.md`. After the release is published **and the
`staple-release.yml` workflow has finished** (check
https://github.com/schuyler/macdown3000/actions), from any checkout that has the tag
locally and `bundle exec pod install` done:

1. Dry-run and read the output — the bytes the real run will write:

```bash
op read "op://Personal/MacDown Sparkle EdDSA/password" \
  | python3 Tools/update_appcast.py --release 3000.1.0 --dry-run
```

2. Run the same command without `--dry-run`.
3. `git commit -am "Publish 3000.1.0 appcast" && git push`. GitHub Pages serves the feed at
   `SUFeedURL`.
4. Confirm the feed is live once Pages rebuilds: fetch `SUFeedURL` and check it parses.

Everything per-release — which DMG, which versions, which channel, which changelog section —
is derived by release mode (§3.6). The one prerequisite is timing: **wait for
`staple-release.yml` to succeed** on https://github.com/schuyler/macdown3000/actions
before running step 1. If you run before it does, `stapler validate` on the downloaded
DMG will refuse, and release mode won't accept `--dmg` as a workaround (§3.2).

The first published item should be a pre-release, so any residual mistake reaches only
opted-in users. The download and stapling check that release mode does exist because the
released asset is the only correct input: stapling mutates the DMG in place
(`staple-release.yml:221`) and re-uploads it with `--clobber` (`:347-350`), so a local
`build/` DMG has different bytes from what users fetch, and a signature over the wrong bytes
is rejected by every client while looking valid in every parse. Explicit mode still relies
on the operator for all of this; use it only for incident recovery.

### An item's lifetime matches its GitHub Release's

`plans/rc-process.md:252-256` deletes the `vX.Y.Z-rc.*` Releases at graduation (tags stay;
downloads go). An RC's enclosure URL dies the moment the final ships, and this script does
not remove items. So when an RC graduates, **delete its `<item>` block from
`docs/sparkle/macdown3000/stable/appcast.xml` in the same commit that deletes the RC
Releases** — `plans/rc-process.md` step 5 carries that instruction. Otherwise beta-channel
users are offered a download that 404s until the final publishes. Stable items are never
deleted; stable releases never are.

---

## 5. What can go wrong

Almost everything fails closed: any error exits 1 with the file byte-identical, `os.replace()`
means the live feed is never half-written, and `--dry-run` before every publish makes the rest
of it unreachable. That is the point of doing this by hand first.

**Signing the pre-stapled DMG.** `release.yml` uploads before notarization; the signature
would be over bytes users never see. §3.6 step 7's `xcrun stapler validate` catches this.

**A wrong signing key** publishes an update every client rejects. Neither mode verifies key
identity (D3); the first-publish-is-pre-release rule bounds the blast radius.

**A wrong channel on a pre-release** offers it to every user. Release mode's strict-shape
regex (§3.6 step 2) either derives the right channel or errors — it never guesses. Explicit
mode doesn't validate; recovery is to delete the item block and re-run.

---

## 6. Decisions

- **D1 — Splice, never re-emit.** The script renders one item and inserts it; existing bytes
  are never rewritten, and a single parse of the result (§3.3 step 4) is the entire validation
  story. **This is the decision the rest of the design depends on.**
- **D2 — Phase the work.** Script first, workflow automation deferred. Publishing by hand
  costs a few minutes per release and buys real evidence before anything unattended runs.
- **D3 — Neither mode verifies the signing key's identity.** The operator holds the key and
  runs the command deliberately, from their own machine, so a stale-secret mixup is unlikely.
  When we're wrong, the failure is bounded by §4's rule that the first publish is a
  pre-release, so only opted-in users see it.
- **D4 — No backfill.** The feed starts with the first release published after merge. Older
  installs reach the newest item by version comparison anyway.
- **D5 — The `stable/` path segment stays.** Beta items live in the same file behind
  `<sparkle:channel>`. Mildly misleading, but baked into every shipped build's `SUFeedURL`.
- **D6 — One script, two modes.** Release mode lives inside `update_appcast.py` rather than a
  wrapper: one entry point, one flag surface, and the derivations sit behind the same guards
  and single validating parse as the explicit inputs.
- **D7 — Release mode adds one guard: `xcrun stapler validate` on the DMG.** It closes the
  specific happy-path failure of running the script before `staple-release.yml` finishes,
  using a tool already required for building.
- **D8 — `--appcast` defaults to the canonical feed path.** There is exactly one feed; the
  flag remains for tests and incident recovery.

---

## 7. Residuals

- **Nobody currently owns verifying the feed is served.** After the first published item,
  someone must confirm `SUFeedURL` returns 200, parses, and drives a real install.
- **#564 will eventually produce a `CFBundleVersion` collision** — the script refuses rather
  than corrupting the feed, but does not fix the underlying problem.
</content>
