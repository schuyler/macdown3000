# Dependency Overhaul: Decision Register

Companion to `plans/dependency-overhaul-survey.md` (ground-truth inventories with
file:line citations — read it first). This document records the decisions to make at
each milestone, options, recommendations, and sequencing constraints, for the arc:

> v3000.0.9 (foundation) → v3000.1.0 (WKWebView) → v3000.1.1 (cmark-gfm) →
> v3000.1.2 (last ObjC train) → v3001.0.0 (Swift port) → v3001.1.x (post-Swift)

North star: the codebase currently has **three independent understandings of
Markdown** — hoedown (preview), PEG Markdown Highlight (editor), and regexes
(scroll sync, checkbox toggle, autocomplete; survey §2.11). The roadmap is a
convergence plan toward one parser. Every decision below should be tested against
that: does it move toward one source of truth, or invest in a parser we're deleting?

---

## 0. Corrections to roadmap assumptions (survey findings)

These change the shape of planned milestones:

1. **The golden corpus already exists and gates CI** (survey §6.2): 31 fixtures,
   string-equality against `MPRenderer` output, regeneration script, three consuming
   test classes. v3000.0.9's corpus work is **annotation + extension**, not creation.
2. **The XCUITest target already exists** with a smoke suite and a non-blocking CI
   job (survey §6.3-6.4). v3000.1.2's "XCUITest phase" is the page-object expansion,
   not target setup.
3. **Issue #476's premise is wrong** (survey §6.5): there are zero `XCTExpectFailure`
   usages. Display-dependent tests silently early-return on headless CI — they *pass
   without testing anything*. The fix is introducing `XCTSkip` (visible skip counts),
   not removing wrappers.
4. **MPDocument.m has nearly doubled** since the Swift-port plan was written
   (#201 says 2,178 lines; it is 4,061). Decomposition (#198) is more urgent than
   planned, and the file is still growing.
5. **The QuickLook extension is already WKWebView**
   (`MacDownQuickLook/PreviewViewController.m`) — an in-repo reference
   implementation for #111, including `WKNavigationDelegate` shape.
6. **macdown-cmd is not a renderer** (survey §6.7) — it's a launcher/IPC shim. Any
   "headless corpus harness" idea must build on `MPRenderer parseMarkdown:` directly.
7. **Front-matter YAML is parsed and then discarded** except for title extraction
   (survey §2.5). This shrinks the LibYAML-upgrade stakes considerably (D-12).

---

## v3000.0.9 — Foundation

### D-1. Corpus baseline policy (decide before the parser swap)
The corpus faithfully snapshots hoedown's **bugs** (#26 list numbering, #27 merged
blockquotes, #10 code indentation are expected to close as side effects of
cmark-gfm). With plain string equality, the parser swap "fails" tests by fixing bugs.
**Recommendation:** annotate every fixture with a status — `matches-spec` /
`known-hoedown-bug` / `intentional-macdown-deviation` — so v3000.1.1 re-baselining is
a deliberate per-fixture review, not a blind regenerate. Enumerate the third category
now, while the knowledge is fresh. Mechanically: a sidecar manifest
(`Fixtures/manifest.json`) beats renaming files — the loader (`MPMarkdownRenderingTests.m:59`)
stays untouched.

### D-2. Speculative cmark-gfm diff report (converts #77 from opinion to data)
Run all 31 fixtures through cmark-gfm with the closest flag mapping (survey §2.2) and
produce a categorized diff report *in this milestone*. Cheap (a small script against
`cmark-gfm` CLI), and it scopes v3000.1.1 precisely: which diffs are bug-fixes, which
are contract breaks (task lists, slugs, TOC), which are feature gaps (highlight,
superscript, quote).

### D-3. Corpus coverage extension
The corpus should gain fixtures for every surface in the survey's parser contract
(§2.12) that isn't covered: `data-information` accessory, `[TOC]` splice shapes,
slug edge cases (UTF-8, entities, empty→`section`), math explicit/implicit modes,
each `MPPreprocessMarkdown` workaround (#25/#36/#37/#254 — these regexes may become
deletable under cmark-gfm; a fixture each proves it), hostile raw HTML (pins the
UNSAFE/tagfilter decision, D-9).

### D-4. Two corpora, two variables
Keep the parser corpus (exists) and the rendered-DOM corpus (doesn't) separate. The
WKWebView milestone holds the parser constant and varies the renderer; the cmark
milestone holds the renderer constant and varies the parser. Never vary both at once.
A rendered-DOM smoke corpus (post-Prism/tasklist DOM assertions via
`evaluateJavaScript`) is worth building *in v3000.1.0 itself*, not before — it tests
the new machinery.

### D-5. #476 reframed
Convert silent early-returns (survey §6.5 has the file:line list) to `XCTSkip` so CI
reports skipped-not-passed. This also produces the honest baseline for "which tests
actually exercise a web view" (currently: 3 files) before #111 churns that layer.

---

## v3000.1.0 — WKWebView migration (#111)

### D-6. Architecture: push-based page-state channel (the load-bearing decision)
The hard cases are all synchronous reads native code does against the page (survey
§1.9): header locations for scroll sync (`MPDocument.m:2908`), word count DOM walk
(`:3488`), copy-as-HTML (`:1426`), divider color (`:100-111`). Porting each call site
to nested `evaluateJavaScript:` completion handlers invents races (scroll sync
reading mid-DOM-replacement).
**Recommendation:** invert to a push model — one `WKScriptMessageHandler` channel;
injected JS *pushes* page state (header ys/kinds, word counts, selection HTML on
request, body background) on mutation/idle; native caches it and reads the cache
synchronously. The scroll cluster (survey §5.2) then consumes the cache exactly as it
does today. `MPMathJaxListener` folds into the same channel. Design this once;
everything else in the milestone is mechanical.

### D-7. Local file access / resource loading
WKWebView restricts `file://` subresource loading; a Markdown editor's core loop is
"render this doc with images next to it on disk", and users reference
`../../images/foo.png`. Options: (a) `loadFileURL:allowingReadAccessToURL:` scoped to
a directory — but scoped to *what* for out-of-tree references; (b) custom
`WKURLSchemeHandler` proxying reads — full control, and it also replaces two hacks at
once: the MathJax CDN-swap delegate (`MPDocument.m:1268-1281`, since WKWebView has no
per-resource hook anyway) and cache-busting/#110 image invalidation
(`resourceTimestamps`, `MPRenderer.m:846`). Must route through `MPURLSecurityPolicy`
(unchanged, survey §1.7) to preserve the CVE-2019-12138/12173 guards.
**Recommendation:** (b), prototyped FIRST — it's the highest-uncertainty piece and
its design constrains sandboxing (D-19). Also decide whether `previewSafeBaseURL:`
(macOS 26 sentinel workaround, `:1758-1773`) is still needed under WKWebView.

### D-8. Decisions bundled into this milestone (don't rediscover mid-flight)
- **MathJax**: the CDN swap dies with the resource-load delegate. Either serve the
  local copy via the scheme handler (keeps 2.7.3), or take the opportunity to move to
  MathJax 3/4 (kills the `unsafe-eval` CSP carve-out and the EOL dependency, but
  changes the typeset-completion API the sync engine hooks). Recommendation: bundle
  the MathJax 3/4 upgrade here — the completion-hook rewrite is forced either way.
- **PDF export**: print currently goes through the legacy `frameView`
  (`MPDocument.m:989-998`). Deployment target is 11.0, so
  `WKWebView.printOperationWithPrintInfo:` and `createPDF` are available. Decide
  whether to just port the pipeline (keeps #504's broken internal links) or rebuild
  on `createPDF` (may fix #504). Don't accidentally re-implement the broken path.
- **Copy-as-HTML**: no editing delegate / `selectedDOMRange` — becomes an async JS
  selection serialization. Small behavior change (copy completes async); acceptable.
- **Private zoom API** (`setPageSizeMultiplier:`, `:2848`) → public `pageZoom`.
  Delete `WebView+WebViewPrivateHeaders.h`.
- **Scroll geometry**: `WebView(Shortcut).enclosingScrollView` and the legacy view
  tree die; WKWebView scrolling is inside the web process — scroll position moves to
  the JS channel (D-6), which `updateHeaderLocations.js` already half-implements.
- **Discipline**: do NOT fix the editor-side header-detection heuristic (#375) here —
  cmark sourcepos replaces it one train later. Port the mechanism, not the heuristic.

Exit gate: parser corpus untouched (parser didn't change); new rendered-DOM smoke
corpus green; the 3 web-view test files migrated off silent-skip (D-5).

---

## v3000.1.1 — hoedown → cmark-gfm (#77)

### D-9. Flag/feature disposition table (decide per-feature, publish in release notes)
From the survey matrix (§2.2): tables, strikethrough, autolink, footnotes, tasklist
map to cmark-gfm extensions; smartypants → `--smart` equivalent (currently a
post-pass, §2.4); `NO_INTRA_EMPHASIS` inversion needs care (cmark's default emphasis
rules differ). **No cmark-gfm equivalent**: `HOEDOWN_EXT_HIGHLIGHT` (`==mark==`),
`EXT_SUPERSCRIPT`, `EXT_UNDERLINE`, `EXT_QUOTE`, `EXT_MATH`/`MATH_EXPLICIT`, hard
wrap flag differences. Options per feature: custom cmark extension (cmark-gfm's
extension API supports this), post-/pre-processing, or drop with release note.
Recommendation: custom extensions for math (high-value, structured) and highlight
(popular); drop quote/superscript/underline behind a release note unless the
speculative diff (D-2) shows real corpus usage. Raw HTML: MacDown renders it today →
`CMARK_OPT_UNSAFE`, tagfilter off by default; pin with hostile fixtures (D-3).
**GitHub alerts (#291) becomes a natural custom extension here.**

### D-10. Re-implement the renderer contract (survey §2.12 is the checklist)
`hoedown_html_patch.c` must be re-achieved: task-list `<li class="task-list-item">
<input … data-checkbox-index>` (tasklist.js contract), `code.language-<lang>` +
`language-none` + `data-information` + `.line-numbers`, MacDown's UTF-8-preserving
`slugify` for heading ids (anchor links AND scroll sync depend on byte-identical
slugs), `<ul class="toc">` + `[TOC]` splice, trailing-newline trim in code blocks.
cmark-gfm's own tasklist extension and `--sourcepos` don't emit these shapes —
options: custom renderer callbacks (cmark-gfm supports overriding node rendering),
or a post-processing pass over cmark's HTML. Recommendation: custom extensions/
renderer hooks, not post-processing regex — we're trying to *reduce* regex parsing.
The `language_addition` back-channel (Prism language collection,
`MPRenderer.m:373-417`) re-homes naturally: walk the cmark AST for fence info strings
instead of hooking the renderer.

### D-11. sourcepos → scroll sync (the payoff)
`--sourcepos` replaces both the abandoned source-map patching (#466) and the
editor-side regex header scan (#375's root cause; survey §2.11 item 4). Design the
sourcepos→line-map as its own small module with tests — it is also exactly what the
editor highlighter wants in v3001.1.x (D-17). The preprocessing workarounds
(`MPPreprocessMarkdown`, §2.7) should each be re-tested against cmark-gfm and
deleted where obsolete — but note they currently *shift character offsets*, which
interacts with sourcepos; deleting them is not just cleanup, it's a correctness
requirement for the line map.

Exit gate: corpus re-baselined per D-1 annotations (fixture-by-fixture review);
hoedown, `hoedown_html_patch.c`, and the patched-pod dependency removed;
`MPPreprocessMarkdown` reduced to CRLF normalization (or documented remainder).
MacDownCore (Quick Look) migrates in the same train — it links hoedown too
(survey §4.6).

---

## v3000.1.2 — Last ObjC train

### D-12. PAPreferences replacement (#188)
The survey (§3) is the spec. Non-negotiables: 55 keys verbatim **including the typos**
(`supressesUntitledDocumentOnLaunch`, `extensionStrikethough`); writes through
`standardUserDefaults` (MPDocument's KVO observes it by key, §3.4); suite
`app.macdown.macdown3000` behavior preserved (macdown-cmd + QuickLook read it via
CFPreferences, §3.8); `NSURL`/`NSDictionary` archival formats preserved
(`htmlDefaultDirectoryUrl`, `editorBaseFontInfo`); the four computed and two
suite-based accessors stay hand-written; migration machinery (v1–v5 +
legacy-bundle-id, §3.5) carries over untouched.
**Recommendation:** a boring explicit ObjC `NSUserDefaults` wrapper with the same
property surface — deliberately dumb, because it translates mechanically to a Swift
`UserDefaults` wrapper in Phase 2 of the port. Do NOT rebuild runtime magic. Write a
migration test that seeds legacy defaults and asserts every key round-trips (the CI
launch smoke test already covers legacy-prefs migration, §6.4 — extend it).

### D-13. LibYAML upgrade (#134) — recommend DEFER/DROP
The planned 0.1.4→0.2.5 upgrade is double work: Phase 1 of the Swift port replaces
LibYAML with Yams, and Yams *wraps libyaml* — the YAML 1.1→1.2 semantics change
(`yes/no/on/off` stop being booleans) would be relitigated anyway. And the survey
found the parsed front matter is **discarded except for `title`** (§2.5) — the
current YAML surface is one dictionary key. Either (a) pull the Yams swap forward
into this train (it bridges to ObjC), or (b) leave LibYAML 0.1.4 and land the 1.2
behavior change once, with Yams, during the port. Recommendation: (b). Land the
behavior change once, not twice.

### D-14. Prism re-integration (#133)
Treat as re-integration, not upgrade: the pin is a bare 2016 submodule commit copied
by shell build phases (survey §4.3). Decisions: bundling strategy (keep the dynamic
per-document language loading — it's good — but regenerate the
`components.js`-driven dependency walk against 1.30's metadata), theme CSS churn
(all themes ship; users may have overrides in the user data dir), and the
`language-`-class contract (already pinned by corpus fixtures after D-3). Sequencing:
after the cmark swap (fence-class emission is stable) — which the milestone order
already provides. Belongs in the rendered-DOM corpus, not the parser corpus.

### D-15. Swift-port runway items (cheap now, expensive later)
- Nullability: add `NS_ASSUME_NONNULL_BEGIN/END` + targeted `nullable` across
  headers, or every ported file imports as implicitly-unwrapped optionals.
- Soft freeze on MPDocument.m: new subsystems land as new classes along the seam plan
  (survey §5.6, order A → B → D → F → C → E). The decomposition itself (#198) should
  be substantially done by end of this train — it's the port's rate limiter.
- M13OrderedDictionary removal (#187) and JJPluralForm disposition: small, do here.
- Decide CocoaPods → SPM timing (D-20).

---

## v3001.0.0 — Swift port (#201)

### D-16. Port discipline
- **Port, don't improve.** The corpus + 1,068 tests are only a safety net if the port
  is behavior-preserving. "While I'm here" fixes get filed for v3001.1.x.
- Concurrency model decided once, up front: `@MainActor` document/AppKit layer,
  `async` preview-channel API (D-6 built the channel; completion handlers →
  async/await is mechanical). Pick the Swift language mode (5 vs 6 strict
  concurrency) at Phase 1 — retrofitting Sendable mid-port is misery.
- XIB coupling: ported classes keep their ObjC names (`@objc(MPDocument)`) or nib
  class references are updated in the same commit; the XCUITest smoke suite is the
  runtime check for silent unarchive failures.
- Dependency dispositions per #201 stand, with amendments: hoedown is already gone
  (v3000.1.1); LibYAML → Yams here (D-13); handlebars-objc → decide between Stencil
  and plain string composition — the survey found exactly ONE template whose job is
  wrapping head/body tags (§4.4); a template engine may be overkill. Recommendation:
  replace with typed string composition, drop the dependency entirely.
- swift-markdown note: it wraps cmark-gfm, so the Phase 5 "evaluate parser migration"
  becomes a calling-convention change over the same C library — near-free, and
  confirmation that doing cmark in ObjC-era was the right order.

---

## v3001.1.x — Post-Swift

### D-17. Editor highlighting convergence
Replace PEG Markdown Highlight not with tree-sitter-for-its-own-sake but with
**highlighting derived from the same cmark-gfm/swift-markdown parse (sourcepos) that
drives preview and scroll sync** — collapsing three Markdown implementations into
one and structurally eliminating the #375 bug class. Tree-sitter only if incremental
reparse proves necessary for very large documents (benchmark first). This also
retires the greg build-time codegen (survey §4.2) and the 2011-era vendored source.

### D-18. Remaining regex sites
Survey §2.11 items 5–7 (checkbox toggle, autocomplete continuation, title scan)
should migrate to AST/sourcepos queries opportunistically once the parser is shared.

---

## Cross-cutting

### D-19. Sandboxing stance — decide BEFORE v3000.1.0, in writing
Sparkle 2 (XPC model), WKWebView file access (D-7), and
`MPHomebrewSubprocessController` (spawns subprocesses) all interact with the App
Sandbox differently. The scheme-handler design either survives sandboxing or doesn't.
Even if the answer is "not sandboxing, ever," write it down — it's an input to D-7
and the Sparkle work (which also needs DSA→EdDSA key migration, survey §4.5).

### D-20. CocoaPods → SPM
CocoaPods is in maintenance mode, and three pods come from a patched fork whose
podspecs are the only patch record (survey §4.1 — retrieve them into this repo
regardless). The overhaul is what makes SPM possible: the post-overhaul set
(cmark-gfm, Yams, Sparkle 2, swift-markdown) is SPM-native; the current set mostly
isn't. Recommendation: migrate at Swift-port Phase 1; until then, no new pods, and
each milestone that deletes a pod (hoedown at 3000.1.1; PAPreferences at 3000.1.2;
handlebars-objc + LibYAML + MASPreferences during the port) is measured progress.

### D-21. Corpus as the standing exit gate
Every milestone re-runs both corpora with exactly one variable changed:
v3000.1.0 varies the renderer (parser corpus must be byte-identical);
v3000.1.1 varies the parser (rendered-DOM corpus must be visually identical,
parser corpus re-baselined deliberately per D-1);
v3001.x varies the language (both corpora byte-identical). Protect this discipline
when schedule pressure hits — it is the whole safety argument.

### D-22. Unversioned/EOL asset cleanup (opportunistic, any train)
viz.js: unversioned 3.75 MB blob — replace with a current, versioned Graphviz-wasm
build or drop to an optional download. MathJax: resolved by D-8. Mermaid 11.12.1:
current, but 2.75 MB — revisit bundling. These ride along with whichever milestone
touches the asset pipeline first (likely v3000.1.0's scheme handler).
