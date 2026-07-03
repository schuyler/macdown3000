# Dependency Overhaul: Ground Survey

Ground-truth inventory of every surface the v3000.0.9 → v3001.x roadmap touches, with
file:line citations, gathered ahead of implementation. Companion document:
`plans/dependency-overhaul-decisions.md` (decision register keyed to milestones).

Survey date: 2026-07-03, at main commit `06dd0a0`.

Sections:

1. [Legacy WebView API surface](#1-legacy-webview-api-surface) — feeds v3000.1.0 (WKWebView)
2. [hoedown parser surface](#2-hoedown-parser-surface) — feeds v3000.1.1 (cmark-gfm)
3. [Preferences system](#3-preferences-system) — feeds v3000.1.2 (PAPreferences replacement)
4. [Dependency & vendored-asset inventory](#4-dependency--vendored-asset-inventory)
5. [MPDocument / MPRenderer structure](#5-mpdocument--mprenderer-structure) — feeds #198 decomposition
6. [Test & CI infrastructure state](#6-test--ci-infrastructure-state) — feeds v3000.0.9 corpus work

---

## 1. Legacy WebView API surface

Scope: the entire legacy-WebKit surface lives in **one target (MacDown)**,
concentrated in `MacDown/Code/Document/MPDocument.m` plus four supporting files.
Key facts:

- **`MacDownQuickLook/PreviewViewController.m` is already fully WKWebView** (async
  `didFinishNavigation:`, `WKWebViewConfiguration`, `decidePolicyForNavigationAction:`
  with `decisionHandler`). It is the in-repo reference for the post-migration shape.
- `macdown-cmd/` and `MacDownCore/` contain **no WebKit at all** — no work there.
- There is exactly **one legacy WebView instance**: the `preview` outlet.

### 1.1 Instance, XIB, view-tree category

| Location | What |
|---|---|
| `MPDocument.m:227` | `@property (weak) IBOutlet WebView *preview;` — the single legacy WebView |
| `Base.lproj/MPDocument.xib:7` | `com.apple.WebKitIBPlugin` plugin dependency |
| `MPDocument.xib:430-439` | the `<webView>` node |
| `MPDocument.xib:433-435` | `<webPreferences defaultFontSize="12" defaultFixedFontSize="12">` — the ONLY WebPreferences config in the project (nib, not code) |
| `MPDocument.xib:437`, `:17` | UIDelegate + `preview` outlet wiring |
| `MPDocument.m:128-135` | `WebView (Shortcut)` category: `-enclosingScrollView` via `mainFrame.frameView.documentView.enclosingScrollView` — **deep dependence on the legacy view tree; no WKWebView equivalent.** Used for scroll geometry at `MPDocument.m:132, 339, 995, 2842, 3237-3240` |

### 1.2 Delegate protocols

Conformance at `MPDocument.m:186-190`; registered `MPDocument.m:618-622`; torn down
`MPDocument.m:775-777`.

| Method | file:line | Function | Migration note |
|---|---|---|---|
| `webView:resource:willSendRequest:…` (ResourceLoad) | `MPDocument.m:1268-1281` | rewrites MathJax CDN requests to the bundled local copy, preserving query items | **no WKWebView per-resource hook** — needs `WKURLSchemeHandler` or config interception |
| `didCommitLoadForFrame:` (FrameLoad) | `:1285-1305` | disables window flushing (anti-flicker); installs `MPMathJaxListener` into `windowScriptObject` | bridge → `WKScriptMessageHandler` |
| `didFinishLoadForFrame:` | `:1307-1333` | fires preview-loaded completion, sets `isPreviewReady`, drains deferred render/print handlers, triggers word count | word count is a sync DOM walk (§1.4) |
| `didFailLoadWithError:forFrame:` | `:1335-1346` | failure = finish; resets render flags | straightforward |
| `decidePolicyForNavigationAction:` (Policy) | `:1351-1417` | intercepts `x-macdown-checkbox://`, same-page/other-file link clicks, enforces `MPURLSecurityPolicy` on `file://` (CVE-2019-12173) | maps cleanly to `WKNavigationDelegate` + `decisionHandler` |
| `webView:doCommandBySelector:` (Editing) | `:1422-1437` | on `copy:`, grabs `selectedDOMRange.markupString` → pasteboard as `public.html` | **WKWebView has no editing delegate / `selectedDOMRange`** — becomes async JS serialization; hard case |
| `dragDestinationActionMask…` (UI) | `:1441-1445` | disables drag-drop into preview | different mechanism needed |
| `contextMenuItemsForElement:` (UI) | `:1447-1469` | rewrites context-menu "Reload" (`WebMenuItemTagReload`) → `-reloadPreview:` | WKUIDelegate menu rework |

### 1.3 JavaScript execution (JS↔native)

MacDown does **not** use `stringByEvaluatingJavaScriptFromString:` — it uses the main
frame's **`JSContext`** (`preview.mainFrame.javaScriptContext`), which WKWebView does
not expose.

| file:line | What | Sync round-trip native depends on? |
|---|---|---|
| `MPDocument.m:1624` | obtain `JSContext` for the DOM-replacement fast path | — |
| `:1625` | `context[@"window"][@"__macdownTempHtml"] = bodyContent` — push body HTML via `JSValue` subscript (avoids string-escaping a huge payload) | native→JS push; must become `evaluateJavaScript:`/message-handler marshaling |
| `:1627-1683` | `[context evaluateScript:updateScript]` — DOM-replacement path: `body.innerHTML` swap, `Prism.highlightAll()`, `macdownInitTaskList()`, MathJax re-typeset, `scrollTo` restore, `MathJaxListener.invokeCallbackForKey_('DOMReplacementDone')` | fire-and-forget (async-safe), completion via bridge |
| **`:2908`** | `JSValue *result = [… evaluateScript:script]` running `updateHeaderLocations.js`; reads `result[@"ys"]`/`result[@"kinds"]` into `webViewHeaderLocations`/`webViewHeaderTypes` | **YES — hardest case.** Scroll sync consumes the JS return synchronously on every scroll and render |
| `MPMathJaxListener.m:42-54` | WebScripting protocol opt-ins (`+isSelectorExcludedFromWebScript:` etc.) | legacy bridge → `WKScriptMessageHandler` |

Independent, migration-safe JSC usage: `MPUtilities.m:163-205`
(`MPGetObjectFromJavaScript` on a standalone `JSGlobalContextCreate`) evaluates
Prism's `components.js` for the language dependency graph (called from
`MPRenderer.m:399`). Not WebView-coupled; leave as-is.

### 1.4 Synchronous DOM API usage (all must become async JS)

| file:line | API | Function |
|---|---|---|
| `MPDocument.m:100-111` (`MPGetWebViewBackgroundColor`) | `mainFrameDocument` → `getComputedStyle` | reads rendered `<body>` background color to tint the split-view divider (`-redrawDivider`, `:2810`) — sync `NSColor` return |
| `:1603-1604` | `mainFrame.DOMDocument` body check | guard before DOM-replacement fast path; async-convertible |
| `:1426` | `selectedDOMRange.markupString` | copy-as-HTML serialization — sync dependency |
| `:2077` | `setSelectedDOMRange:nil` | deselect before Copy HTML; → JS `getSelection().removeAllRanges()` |
| `:3488-3489` (`-updateWordCount`) | `DOMDocument` → `domDoc.textCount` | **full native DOM tree walk** via `DOMNode+Text` |

**`DOMNode+Text` category** (`MacDown/Code/Extension/DOMNode+Text.{h,m}`) — dies with
WKWebView. `MPGetNodeAccumulatedTextCount` (`.m:91-123`) recursively walks by
`nodeType`, skipping `SCRIPT`/`STYLE`/`HEAD`, counting inline `CODE` (not in `PRE`)
as one word; `MPGetStringAccumulatedTextCount` (`.m:43-81`) counts words via
`NSStringEnumerationByWords`. **`MPTextCountForString` (`.m:128-137`) is a pure-string
wrapper used by the editor selection count (`MPDocument.m:1836`, issue #452) — it
survives unchanged.** The DOM walk must be reimplemented as injected JS returning the
three counts asynchronously.

### 1.5 Private API

`MacDown/Code/Extension/WebView+WebViewPrivateHeaders.h` declares two private
methods: `setPageSizeMultiplier:` / `pageSizeMultiplier` (page zoom). One call site:
`MPDocument.m:2848` in `-scaleWebview` (`:2826-2850`) — zooms preview relative to
editor font size; comment flags it "NOT App Store-safe". **WKWebView replacement:
public `pageZoom`.** Getter declared but never called.

### 1.6 Printing / PDF export

| file:line | Function |
|---|---|
| `MPDocument.m:989-998` | `NSPrintOperation` from `preview.mainFrame.frameView printOperationWithPrintInfo:` — no WKWebView analog before macOS 11's `WKWebView.printOperationWithPrintInfo:` (deployment target is 11.0, so available) |
| `:1000-1014` | wraps print in `performAfterRender:` (issue #16); sets `printing = YES` |
| `:1568-1569` | `if (self.printing) return;` — render suppression during print |

HTML export (`copyHtml:` `:2073-2089`, `exportHtml:` `:2091+`) uses
`renderer.currentHtml` — migration-neutral except the `setSelectedDOMRange:` touch.

### 1.7 Loading, base URL, cache

| file:line | Function |
|---|---|
| `MPDocument.m:1720` | `[preview.mainFrame loadHTMLString:html baseURL:]` — the only full-page load; identical signature exists on WKWebView (but WKWebView restricts `file://` subresource access — see decisions doc) |
| `:1573-1576` | base URL = `self.fileURL` or `htmlDefaultDirectoryUrl`, via `previewSafeBaseURL:` |
| `:1758-1773` (`-previewSafeBaseURL:`) | macOS 26 workaround (#405/#431): substitutes a non-existent sentinel `.macdown-preview-base` in the doc's directory so WebKit doesn't blank the load on file-metadata triggers |
| `:2483-2512` (`-invalidateStyleCaches`) | `NSURLCache removeAllCachedResponses` + cache-busting timestamps because legacy WebView serves CSS from a by-URL cache (#318) — may become unnecessary or move to `WKWebsiteDataStore` |

**`MPURLSecurityPolicy`** (`MacDown/Code/Utility/MPURLSecurityPolicy.{h,m}`) — pure
Foundation, survives unchanged. `+isExecutableOrAppBundleAtURL:` (`.m:16-51`, CVE-2019-12173);
`+url:isWithinScopeOfBaseURL:` (`.m:53-82`, CVE-2019-12138, trailing-slash prefix
check). Call sites: `MPDocument.m:1406-1407, 3564-3565, 3589`.

**`MPMathJaxListener`** (`Utility/MPMathJaxListener.{h,m}`) — key→block dictionary
injected via `windowScriptObject setValue:forKey:@"MathJaxListener"`
(`MPDocument.m:1303, 1679`); JS calls `MathJaxListener.invokeCallbackForKey_('End')`
(`MathJax/init.js:10`) and `…('DOMReplacementDone')` (`MPDocument.m:1641`).
Directional JS→native fire-and-forget — clean `WKScriptMessageHandler` conversion.

### 1.8 Injected JS resources

Injection is server-side — the renderer emits `<script>` tags into the generated HTML
(`MPRenderer.m:553-632`), not WebView user-script APIs — so injection itself is
migration-neutral.

| Resource | Purpose |
|---|---|
| `Resources/updateHeaderLocations.js` | scroll sync: returns `{ys, kinds}` (y-coords + kind codes, 0=image, 1–6=header) — consumed synchronously at `MPDocument.m:2908` (hardest case) |
| `Resources/Extensions/tasklist.js` | interactive checkboxes; `window.macdownInitTaskList()`; navigates `x-macdown-checkbox://toggle/<i>?token=…` |
| `Resources/MathJax/init.js` | MathJax config + `StartupHook('End')` → native bridge |
| `Resources/MathJax/MathJax.js` | bundled MathJax 2.x (swapped in for CDN by the resource-load delegate) |
| `Resources/Extensions/mermaid.init.js` | Mermaid 11 init (forest theme, `securityLevel:'antiscript'`), renders `.language-mermaid`, MutationObserver re-render |
| `Resources/Extensions/viz.init.js` | Graphviz via Viz(): renders `code.language-{dot,neato,…}`, `outerHTML` replace, MutationObserver |
| `Resources/Prism/components/*` | prism-core + per-language components + line-numbers/show-language plugins; `Prism.highlightAll()` re-run by DOM-replacement script (`MPDocument.m:1634`) |

### 1.9 Hard-case ranking (sync JS/DOM native depends on inline)

1. `updateHeaderLocations` scroll sync (`MPDocument.m:2908`) — sync JS return arrays on every scroll/render.
2. `updateWordCount` (`:3488` + `DOMNode+Text`) — sync full-DOM walk.
3. Copy-as-HTML (`:1426`, `:2077`) — editing delegate + sync DOM serialization, no WKWebView equivalent.
4. Divider background color (`:100-111`, `:2810`) — sync `getComputedStyle` → `NSColor`.
5. Legacy view-tree geometry (`mainFrame.frameView…enclosingScrollView`) — used by scroll sync and print.
6. Per-resource `willSendRequest` MathJax swap (`:1268`) — needs scheme handler.
7. Direct `JSContext`/`JSValue` access (`:1624-1625`) — WKWebView exposes no JSContext.

Clean conversions: `MPMathJaxListener` → message handler; policy delegate →
`decidePolicyForNavigationAction:decisionHandler:`; private zoom → public `pageZoom`;
`loadHTMLString:baseURL:` (same signature); `MPURLSecurityPolicy`, MPRenderer,
MacDownCore, macdown-cmd untouched.

---

## 2. hoedown parser surface

Parser: CocoaPods **hoedown 3.0.7** (`Podfile:14`), patched via
`MacDown/Code/Extension/hoedown_html_patch.{c,h}`. All rendering is serialized on a
`maxConcurrentOperationCount = 1` queue (`MPRenderer.m:534`) — the checkbox-index
global relies on this.

### 2.1 hoedown API call sites

All parser calls live in `MacDown/Code/Document/MPRenderer.m` (MPDocument.m only
imports the patch header for flag constants).

- **Main render — `MPHTMLFromMarkdown()`**: `hoedown_document_new(htmlRenderer, flags,
  SIZE_MAX)` (`MPRenderer.m:203-204`; nesting `kMPRendererNestingLevel = SIZE_MAX`,
  `.m:32`), `hoedown_buffer_new(64)` (`:205`), `hoedown_document_render` (`:206`),
  `hoedown_buffer_cstr` (`:214`), frees (`:215-216`).
- **TOC second pass** (`MPRenderer.m:218-242`): a second `hoedown_document_new`
  (`:220`) + render (`:223`); TOC HTML spliced by regex-replacing
  `<p...>[TOC]</p>` (`:227-239`).
- **Renderer construction — `MPCreateHTMLRenderer()`** (`MPRenderer.m:419-435`):
  `hoedown_html_renderer_new(rendererFlags, tocLevel)` (`:422`); overrides three
  callbacks — `blockcode`, `listitem`, `header` — with the patch functions
  (`:424-426`); allocates `hoedown_html_renderer_state_extra` (`:428-429`) carrying a
  `language_addition` fn-ptr + `owner` back-pointer into the state's `opaque` slot
  (`:433`).
- **TOC renderer — `MPCreateHTMLTOCRenderer()`** (`:437-443`):
  `hoedown_html_toc_renderer_new(6)` with `header` → `hoedown_patch_render_toc_header`.
- **Free**: `MPFreeHTMLRenderer()` (`:445-452`); TOC renderer freed at `:788`.
- **Driver — `parseMarkdown:`** (`:760-795`): resets checkbox index (`:765`), strips
  front matter (`:773-778`), builds renderers (`:780-783`), renders (`:784`).

### 2.2 Extension/renderer flag → preference matrix

Two bitfields, mapped in category `MPPreferences (Hoedown)` inside MPDocument.m:
`extensionFlags` (`MPDocument.m:139-167`) → `hoedown_document_new`; `rendererFlags`
(`MPDocument.m:169-181`) → `hoedown_html_renderer_new`. Wired through
`rendererExtensions:` (`MPDocument.m:1498-1501`) and `MPDocument.m:1876-1880`.

Extension flags:

| hoedown flag | MPPreferences property | Meaning |
|---|---|---|
| `HOEDOWN_EXT_AUTOLINK` | `extensionAutolink` | linkify bare URLs (`MPDocument.m:143`) |
| `HOEDOWN_EXT_FENCED_CODE` | `extensionFencedCode` | fenced code (`:145`) |
| `HOEDOWN_EXT_FOOTNOTES` | `extensionFootnotes` | `[^n]` footnotes (`:147`) |
| `HOEDOWN_EXT_HIGHLIGHT` | `extensionHighlight` | `==mark==` (`:149`) |
| `HOEDOWN_EXT_NO_INTRA_EMPHASIS` | **`!extensionIntraEmphasis`** (inverted) | (`:150-151`) |
| `HOEDOWN_EXT_QUOTE` | `extensionQuote` | `"..."` → `<q>` (`:153`) |
| `HOEDOWN_EXT_STRIKETHROUGH` | `extensionStrikethough` | `~~del~~` (`:155`) |
| `HOEDOWN_EXT_SUPERSCRIPT` | `extensionSuperscript` | `^super` (`:157`) |
| `HOEDOWN_EXT_TABLES` | `extensionTables` | GFM tables (`:159`) |
| `HOEDOWN_EXT_UNDERLINE` | `extensionUnderline` | `_x_` → `<u>` (`:161`) |
| `HOEDOWN_EXT_MATH` | `htmlMathJax` | `$`/`$$` math parsing (`:163`) |
| `HOEDOWN_EXT_MATH_EXPLICIT` | `htmlMathJaxInlineDollar` | explicit `$` inline (`:165`) |

Renderer/HTML flags — note **three are custom bits defined in the patch header**
(`hoedown_html_patch.h:12-14`), not stock hoedown:

| flag | value | property | meaning |
|---|---|---|---|
| `HOEDOWN_HTML_USE_TASK_LIST` | `1<<4` custom | `htmlTaskList` | task lists (`MPDocument.m:173`) |
| `HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS` | `1<<5` custom | `htmlLineNumbers` | Prism line numbers (`:175`) |
| `HOEDOWN_HTML_HARD_WRAP` | stock | `htmlHardWrap` | newline → `<br>` (`:177`) |
| `HOEDOWN_HTML_BLOCKCODE_INFORMATION` | `1<<6` custom | `htmlCodeBlockAccessory == Custom` | `data-information` on fences (`:178-179`) |

`rendererFlags` is also read directly in MPRenderer.m to select assets
(line-numbers CSS/JS `:561, :589`; tasklist.js `:683`).

### 2.3 `hoedown_html_patch.c` — patched callbacks and exact HTML contracts

Global state: `g_checkbox_index` (`.c:24`, **not thread-safe**; reset via
`hoedown_patch_reset_checkbox_index`, `.c:26-29`). `new_growable_buffer()`
(`.c:36-39`) clamps 0 size-hint to 16 (issue #479 crash fix).

**`hoedown_patch_render_blockcode`** (`.c:48-115`) — the `language-` prefix exists to
satisfy Prism (`.c:46-47`). Info string split on `:` into language + metadata when
`BLOCKCODE_INFORMATION` is on (`.c:59-74`); `language_addition` alias mapping runs at
`.c:76-82`. Emitted shape:

```
<div><pre [class="line-numbers"] [data-information="<meta>"]
><code class="language-<lang-or-'none'>">…escaped, trailing \n stripped…</code></pre></div>\n
```

Empty language → literal `language-none` (`.c:97`); trailing newline trimmed so Prism
doesn't add a blank line (`.c:102-106`).

**`hoedown_patch_render_listitem`** (`.c:120-173`) — task lists (issue #269). Matches
`[ ]`/`[x]`/`[X]` (`.c:132-154`). Emitted shapes:

```
<li class="task-list-item"><input type="checkbox" data-checkbox-index="%d">          (unchecked)
<li class="task-list-item"><input type="checkbox" checked data-checkbox-index="%d">  (checked)
```

`data-checkbox-index` uses the post-increment global.

**`slugify`** (`.c:182-239`) — anchor-ID helper: strips tags, skips entities, passes
UTF-8 ≥0x80 through raw (accents survive, no percent-encoding), lowercases ASCII,
keeps `[a-z0-9_]`, collapses space/tab/`-` runs to single `-`, trims trailing `-`.

**`hoedown_patch_render_header`** (`.c:243-262`) — always emits
`<h%d id="<slug>">…</h%d>` regardless of TOC nesting; empty slug → `section`
(`.c:252-253`).

**`hoedown_patch_render_toc_header`** (`.c:265-310`) — outermost list gets
`<ul class="toc">`; entries are `<a href="#<slug>">`.

### 2.4 Smartypants

Post-pass over rendered HTML (not a parser flag): `hoedown_html_smartypants`
(`MPRenderer.m:207-213`), gated by `rendererHasSmartyPants:` →
`preferences.extensionSmartyPants` (`MPDocument.m:1503-1506`; dirty check
`MPRenderer.m:752`).

### 2.5 YAML front matter

- Strip in `parseMarkdown:` (`MPRenderer.m:773-778`), gated by
  `rendererDetectsFrontMatter:` → `htmlDetectFrontMatter` (`MPDocument.m:1518-1521`).
- `-[NSString frontMatter:]` (`NSString+Lookup.m:55-95`): regex
  `^-{3}[\r\n]+(.*?[\r\n]+)((?:-{3})|(?:\.{3}))` (`:57-58`), parsed via
  `YAMLSerialization` (vendored `Dependency/YAML-framework`) over the LibYAML pod
  with `kYAMLReadOptionStringScalars` (`:88-91`).
- **The parsed YAML object is discarded in the render path** — `parseMarkdown` passes
  `frontMatter:nil` (`MPRenderer.m:784-786`). The only live consumer is title
  extraction: `MPDocument.m:3462-3464` reads `frontMatter[@"title"]`.
- `NSObject+HTMLTabularize` (dict/array → HTML table via handlebars) has **no live
  call site** — historical front-matter-as-table rendering, effectively dead code.

### 2.6 TOC & anchors

Anchors: `<h%d id="slug">` (§2.3). TOC: second render pass + `[TOC]` regex splice
(`MPRenderer.m:230`); gated by `rendererRendersTOC:` → `htmlRendersTOC`
(`MPDocument.m:1508-1511`); levels h1–h6.

### 2.7 Footnotes, math, preprocessing

- Footnotes: stock hoedown output; `GitHub-2020.css:425-461` styles `.footnotes`,
  `[data-footnote-ref]`.
- Math: `HOEDOWN_EXT_MATH` / `HOEDOWN_EXT_MATH_EXPLICIT` (§2.2); hoedown emits
  MathJax-compatible `\(…\)` / `\[…\]`; `MathJax/init.js` sets no `tex2jax` config —
  relies on the CDN default `TeX-AMS-MML_HTMLorMML` (`MPRenderer.m:26-28`). The editor
  highlighter gets `pmh_EXT_MATH` only when `htmlMathJax && htmlMathJaxInlineDollar`
  (`MPDocument.m:2635-2636`).
- **`MPPreprocessMarkdown()`** (`MPRenderer.m:109-193`) runs before every parse:
  CRLF→LF (`:116`); blank line between paragraph and list (#254, `:122`); blank line
  before fence after text (#36, `:134`); shortcut-link conversion (#25, `:160`);
  zero-width-space injection into `]: ` inside fences to defeat hoedown's `is_ref()`
  (#37, `:145`, `:182-191`). Several of these are hoedown-bug workarounds — re-audit
  each against cmark-gfm; most should become deletable.

### 2.8 Templating

handlebars-objc 1.4.5, one template: `MacDown/Resources/Templates/Default.handlebars`.
Rendered in `MPGetHTML()` (`MPRenderer.m:254-303`); context: `title`, `titleTag`,
`headTags` (CSP meta + `macdown-checkbox-token` meta, `:511-519`), `styleTags`,
`body`, `scriptTags`. Template name is dispatch_once-cached from first render
(known wart). Also used by `NSObject+HTMLTabularize`.

### 2.9 HTML shapes downstream JS/CSS depend on (the parser contract)

| Consumer | Depends on |
|---|---|
| `Extensions/tasklist.js` | `.task-list-item` (`:16`), `meta[name="macdown-checkbox-token"]` (`:14`), `data-checkbox-index` (`:27`), navigates `x-macdown-checkbox://toggle/<i>?token=…` (`:30-34`); re-invokable `window.macdownInitTaskList` (`:13,:47`) |
| Prism | `code.language-<lang>`, `pre.line-numbers` |
| `Extensions/show-information.css` | `pre[class*='language-'][data-information]::before { content: attr(data-information) }` (`:4-5`) |
| `Extensions/mermaid.init.js` | `querySelectorAll(".language-mermaid")` (`:39,:93`) |
| `Extensions/viz.init.js` | `querySelectorAll("code.language-" + engine)` (`:12,:46,:78`) |
| `GitHub-2020.css` | `.footnotes`, `[data-footnote-ref]`, `.data-footnote-backref` (`:425-461`) |
| `Resources/updateHeaderLocations.js` | `querySelectorAll('h1…h6')`, `querySelectorAll('img')` (`:25-26`), header level from `tagName[1]` (`:96`) — must stay aligned with the editor-side regex (§2.11) |

### 2.10 PEG Markdown Highlight (editor) integration points

Vendored at `Dependency/peg-markdown-highlight/` (not a pod). All integration in
MPDocument.m: import (`:14`), property (`:231`), instantiation with the editor text
view (`:599-600`), extension flags (`:2632-2637` — base `pmh_EXT_NOTES`, `pmh_EXT_MATH`
conditional), lifecycle calls (`:725-726, :746, :2626, :2680-2688, :2780, :3759`).

### 2.11 Independent Markdown interpretation sites (the "three parsers" problem)

1. `MPPreprocessMarkdown` regexes (`MPRenderer.m:119-164`).
2. `[TOC]` splice regex (`MPRenderer.m:230`).
3. Front-matter regex (`NSString+Lookup.m:57-58`); `titleString` ATX regex
   (`NSString+Lookup.m:97-119`).
4. **Scroll-sync reference detection** (`MPDocument.m:2988-3079+`): setext
   `dashRegex`/`eqRegex`, ATX `^[ ]{0,3}(#+)\s`, `imgRegex`/`imgRefRegex`, `hrRegex`,
   plus hand-written fence state machine (`MPScanFenceMarker`, `insideFence`
   `:3017-3048`); produces `editorHeaderLocations` (`:2955, :3217`) with
   `MPReferenceKind` codes (`:212-219`) paired against `updateHeaderLocations.js`.
5. Checkbox source-toggle regex + fence-exclusion regex (`MPDocument.m:3793-3815+`).
6. `NSTextView+Autocomplete.m`: `kMPListLineHeadPattern` (`:52`), blockquote pattern
   (`:54`), list/blockquote continuation (`:534, :624`), markup-toggle helpers
   (`:59, :295, :325`).
7. Title sanitize regex (`MPDocument.m:3473-3476`).

### 2.12 cmark-gfm migration contract (summary)

The replacement must reproduce: (a) the exact task-list
`<li class="task-list-item"><input … data-checkbox-index>` contract; (b)
`code.language-<lang>` fences with optional `data-information` and `.line-numbers`;
(c) heading `id` slugs matching MacDown's UTF-8-preserving `slugify`; (d) the
`<ul class="toc">` structure and `[TOC]` splice; (e) `$`/`$$` math honoring the
explicit-inline preference; (f) smartypants as a post-pass. The custom flag bits
(`1<<4/5/6`) and the `language_addition` back-channel (Prism alias resolution +
dependency collection, `MPRenderer.m:373-417`) have no cmark-gfm equivalent and need
re-architecting.

---

## 3. Preferences system

**Architecture.** `MPPreferences` subclasses PAPreferences 0.5 (CocoaPods; source not
vendored, only `LICENSE/papreferences.txt`). PAPreferences synthesizes accessors for
`@dynamic` properties at runtime via `+resolveInstanceMethod:` that read/write
`[NSUserDefaults standardUserDefaults]` **using the property name verbatim as the
defaults key** — no prefix, no transformation. This is confirmed independently by
`loadDefaultUserDefaults` and the migration code, which use the same names as string
keys (`MPPreferences.m:429-437`). Singleton: `[MPPreferences sharedInstance]`; `-init`
overridden at `MPPreferences.m:40`.

### 3.1 Canonical defaults-key table (55 `@dynamic` properties)

Declared in `MacDown/Code/Preferences/MPPreferences.h`; `@dynamic` statements at
`MPPreferences.m:218-279`. Defaults key == property name verbatim in every case.
**Any replacement must preserve these keys exactly, including the two misspellings.**

General (`MPPreferences.h:17-21`):

| Property (== defaults key) | Type | Notes |
|---|---|---|
| `firstVersionInstalled` | `NSString *` | fresh-install sentinel (§3.5) |
| `latestVersionInstalled` | `NSString *` | set every launch (`.m:67`) |
| `updateIncludesPreReleases` | `BOOL` | |
| `supressesUntitledDocumentOnLaunch` | `BOOL` | **misspelled ("supresses") — key is load-bearing** |
| `createFileForLinkTarget` | `BOOL` | |

Markdown extension flags (`MPPreferences.h:24-34`):

| Property (== defaults key) | Type | Notes |
|---|---|---|
| `extensionIntraEmphasis` | `BOOL` | |
| `extensionTables` | `BOOL` | |
| `extensionFencedCode` | `BOOL` | |
| `extensionAutolink` | `BOOL` | |
| `extensionStrikethough` | `BOOL` | **misspelled (missing 'r') — key is load-bearing**; QuickLook duplicates the typo (`MacDownCore/MPQuickLookPreferences.m:22`) |
| `extensionUnderline` | `BOOL` | |
| `extensionSuperscript` | `BOOL` | |
| `extensionHighlight` | `BOOL` | |
| `extensionFootnotes` | `BOOL` | |
| `extensionQuote` | `BOOL` | |
| `extensionSmartyPants` | `BOOL` | |

Rendering (`MPPreferences.h:36`): `markdownManualRender` (`BOOL`).

Editor (`MPPreferences.h:38-59`):

| Property (== defaults key) | Type | Notes |
|---|---|---|
| `editorBaseFontInfo` | `NSDictionary *` | composite: sub-keys `"name"`/`"size"` (`.m:26-27`); backing store for computed font accessors (§3.2); "private preference" |
| `editorAutoIncrementNumberedLists` | `BOOL` | |
| `editorConvertTabs` | `BOOL` | |
| `editorInsertPrefixInBlock` | `BOOL` | |
| `editorCompleteMatchingCharacters` | `BOOL` | |
| `editorSyncScrolling` | `BOOL` | |
| `editorSmartHome` | `BOOL` | |
| `editorStyleName` | `NSString *` | |
| `editorHorizontalInset` | `CGFloat` | |
| `editorVerticalInset` | `CGFloat` | |
| `editorLineSpacing` | `CGFloat` | |
| `editorWidthLimited` | `BOOL` | |
| `editorMaximumWidth` | `CGFloat` | |
| `editorOnRight` | `BOOL` | |
| `editorStartInPreviewMode` | `BOOL` | |
| `editorShowWordCount` | `BOOL` | |
| `editorWordCountType` | `NSInteger` | |
| `editorAutoSave` | `BOOL` | |
| `editorScrollsPastEnd` | `BOOL` | |
| `editorEnsuresNewlineAtEndOfFile` | `BOOL` | |
| `editorShowsInvisibleCharacters` | `BOOL` | |
| `editorUnorderedListMarkerType` | `NSInteger` | enum `MPUnorderedListMarkerType` (0=asterisk, 1=plus, 2=minus; `.m:14-19`) |

Preview (`MPPreferences.h:61`): `previewZoomRelativeToBaseFontSize` (`BOOL`).

HTML (`MPPreferences.h:63-77`):

| Property (== defaults key) | Type | Notes |
|---|---|---|
| `htmlTemplateName` | `NSString *` | |
| `htmlStyleName` | `NSString *` | |
| `htmlDetectFrontMatter` | `BOOL` | |
| `htmlTaskList` | `BOOL` | |
| `htmlHardWrap` | `BOOL` | |
| `htmlMathJax` | `BOOL` | |
| `htmlMathJaxInlineDollar` | `BOOL` | |
| `htmlSyntaxHighlighting` | `BOOL` | |
| `htmlHighlightingThemeName` | `NSString *` | |
| `htmlLineNumbers` | `BOOL` | |
| `htmlGraphviz` | `BOOL` | |
| `htmlMermaid` | `BOOL` | |
| `htmlCodeBlockAccessory` | `NSInteger` | |
| `htmlDefaultDirectoryUrl` | `NSURL *` | PAPreferences URL serialization — preserve archival format |
| `htmlRendersTOC` | `BOOL` | |

### 3.2 Non-dynamic properties (NOT defaults keys — keep hand-written)

| Property | Kind | Implementation |
|---|---|---|
| `editorBaseFontName` (`.h:80`) | readonly, computed | reads `editorBaseFontInfo["name"]` (`.m:281`) |
| `editorBaseFontSize` (`.h:81`) | readonly, computed | reads `editorBaseFontInfo["size"]` (`.m:286`) |
| `editorBaseFont` (`.h:82`, `NSFont *`) | computed getter+setter | composes/decomposes `editorBaseFontInfo` (`.m:292-305`) |
| `editorUnorderedListMarker` (`.h:83`) | readonly, computed | switch over marker type → `"* "`/`"+ "`/`"- "` (`.m:307`) |
| `filesToOpen` (`.h:88`, `NSArray *`) | custom accessors | suite store: key `filesToOpenOnNextLaunch` in suite `app.macdown.macdown3000` (`.m:322-333`) |
| `pipedContentFileToOpen` (`.h:89`, `NSString *`) | custom accessors | suite store: key `pipedContentFileToOpenOnNextLaunch` (`.m:335-344`) |

No `@dynamic` property has a custom accessor override or non-obvious key mapping.

### 3.3 Registered defaults / initial values

**No `registerDefaults:` anywhere.** Defaults are imperative:

- `-loadDefaultPreferences` (`MPPreferences.m:395-413`) — fresh install only. Sets
  `extensionIntraEmphasis=NO`, `extensionTables/FencedCode/Footnotes=YES`,
  `editorBaseFontInfo={Menlo-Regular, 14.0}`, `editorStyleName="Tomorrow+"`,
  insets 15/30, `editorLineSpacing=3.0`, `editorSyncScrolling=YES`,
  `htmlStyleName="GitHub2"`, `htmlDefaultDirectoryUrl=<home>`.
- `-loadDefaultUserDefaults` (`MPPreferences.m:426-444`) — every launch, set-if-absent:
  `editorMaximumWidth=1000.0`, `editorAutoIncrementNumberedLists=YES`,
  `editorInsertPrefixInBlock=YES`, `htmlTemplateName="Default"`,
  `extensionStrikethough=YES`, `editorAutoSave=YES`; then `applyPreferencesMigrations`.
- Default constants at `MPPreferences.m:26-35`.

### 3.4 Change observation

No `PAPreferencesDidChangeNotification` usage. Two mechanisms:

- **Fresh-install notification** `MPDidDetectFreshInstallationNotification`
  (declared `MPPreferences.h:12`, defined `.m:23-24`, posted `.m:59-63`); observed by
  `MPMainController.m:229-230` → `showFirstLaunchTips` (`MPMainController.m:355`).
- **KVO directly on `[NSUserDefaults standardUserDefaults]`** — not on the
  MPPreferences object. Registered in `MPDocument windowControllerDidLoadNib:`:
  - `MPDocument.m:606-610`: observes each key in `MPEditorPreferencesToObserve()`
    (`MPDocument.m:69-84`): `editorBaseFontInfo, extensionFootnotes,
    editorHorizontalInset, editorVerticalInset, editorWidthLimited,
    editorMaximumWidth, editorLineSpacing, editorOnRight, editorStyleName,
    editorShowWordCount, editorScrollsPastEnd, editorShowsInvisibleCharacters,
    htmlMathJax, htmlMathJaxInlineDollar`.
  - `MPDocument.m:611-615`: observes the NSTextView itself for
    `MPEditorKeysToObserve()` (`MPDocument.m:51-67` — `automatic*` text-checking
    keys; editor-object keys, not preference keys).
  - Handled in `-observeValueForKeyPath:` (`MPDocument.m:2747`); torn down at
    `MPDocument.m:790-792`; also observes `NSUserDefaultsDidChangeNotification`
    (`MPDocument.m:635`).

**Implication:** a replacement must keep writing through `standardUserDefaults` under
the same keys, or MPDocument's KVO silently stops firing.

### 3.5 Version & migration logic

All in `MPPreferences.m`:

- **Fresh-install detection:** `-init` checks `!self.firstVersionInstalled`
  (`.m:52`) → sets it to CFBundleVersion, calls `loadDefaultPreferences`, posts the
  fresh-install notification (`.m:52-64`). `latestVersionInstalled` updated every
  launch (`.m:67`).
- **Legacy bundle-id migration:** `-migratePreferencesFromLegacyBundleIdentifierIfNeeded`
  (`.m:76-214`), first thing in `-init` (`.m:46`). Migrates from `com.uranusjr.macdown`
  into suite `app.macdown.macdown3000`; guard key `MPDidMigrateFromLegacyBundleIdentifier`;
  2s semaphore timeouts (Sequoia sandbox-hang workaround); skips `NS`/`Apple` keys.
- **Versioned migrations:** `-applyPreferencesMigrations` (`.m:495-556`); current
  version **5**, stored under `MPMigrationVersion`; `-effectiveMigrationVersion`
  (`.m:460-487`) infers version from legacy flags when absent. Steps:
  v1 (#263) force text-substitution keys off + flag `MPDidApplySubstitutionDefaultsFix`;
  v2 (#269) `htmlTaskList=YES` + flag `MPDidApplyTaskListDefaultFix`;
  v3 (#293/#307) `extensionIntraEmphasis=NO`, `htmlDetectFrontMatter=YES`;
  v4 (#309) remove `NSSplitView Subview Frames Untitled`;
  v5 `editorAutoSave=YES`.
- **Autosave cleanup:** `-cleanupObsoleteAutosaveValues` (`.m:349-375`) — removes
  stale `NSSplitView Subview Frames <path>` / `NSWindow Frame <path>` keys.
- Non-property keys in standardUserDefaults: `MPDidMigrateFromLegacyBundleIdentifier`,
  `MPMigrationVersion`, `MPDidApplySubstitutionDefaultsFix`,
  `MPDidApplyTaskListDefaultFix`, plus the eight `editorAutomatic*` /
  `editorSmartInsertDeleteEnabled` keys written by migration v1.

### 3.6 NSUserDefaults+Suite category

`MacDown/Code/Extension/NSUserDefaults+Suite.{h,m}` — thin CFPreferences wrapper for
cross-process sharing (writes land in a specific suite domain immediately, bypassing
the standard-defaults cache):

- `-initWithSuiteNamed:` (`.m:13-20`; note: distinct from Apple's `-initWithSuiteName:`)
- `-objectForKey:inSuiteNamed:` → `CFPreferencesCopyValue` (`.m:22-29`)
- `-setObject:forKey:inSuiteNamed:` → `CFPreferencesSetValue` (`.m:31-38`)

Users: `MPPreferences.m:322-344` (files-to-open accessors), `MPPreferences.m:171-173`
(legacy migration phase 2), `macdown-cmd/main.m:12,29-45`.

### 3.7 MASPreferences window wiring

MASPreferences 1.4.1. `MPMainController.m:10` imports;
`-preferencesWindowController` (`MPMainController.m:177-196`) builds
`MASPreferencesWindowController` with five VCs from `MacDown/Code/Preferences/`:
`MPGeneralPreferencesViewController`, `MPMarkdownPreferencesViewController`,
`MPEditorPreferencesViewController`, `MPHtmlPreferencesViewController`,
`MPTerminalPreferencesViewController`; shared base `MPPreferencesViewController`
exposes the singleton (`MPPreferencesViewController.m:178`); UI binds to MPPreferences
properties. Shown via `-showPreferencesWindow:` (`MPMainController.m:198-201`).

### 3.8 Cross-process consumers (CLI, QuickLook)

No App Group / entitlement container. Sharing is via named CFPreferences suite
**`app.macdown.macdown3000`** (`kMPApplicationSuiteName`, `MPGlobals.h:20`; equals the
release bundle id — DEBUG bundle id differs, `MPGlobals.h:15-17`).

- **macdown-cmd** (`macdown-cmd/main.m`): writes `filesToOpenOnNextLaunch`
  (`kMPFilesToOpenKey`) and `pipedContentFileToOpenOnNextLaunch`
  (`kMPPipedContentFileToOpen`), both defined `MPGlobals.h:28-29`, then launches the
  app by bundle id.
- **QuickLook/MacDownCore** (`MacDownCore/MPQuickLookPreferences.{h,m}`): read-only
  singleton reading via `CFPreferencesCopyValue` against the hardcoded suite
  (`MPQuickLookPreferences.m:13`). Re-declares keys locally (`.m:16-23`) —
  `htmlStyleName`, `htmlHighlightingThemeName`, `htmlSyntaxHighlighting`,
  `extensionTables`, `extensionFencedCode`, `extensionAutolink`,
  `extensionStrikethough` (typo preserved), `htmlTaskList`. Its fallbacks differ
  slightly (style `GitHub2`, theme `tomorrow`); force-disables MathJax/Mermaid/Graphviz.
  `MacDownQuickLook` target has no direct preference access — goes through MacDownCore.

### 3.9 Replacement constraints (summary)

1. Keep all 55 keys in `standardUserDefaults` under exact property names, including
   the typos `supressesUntitledDocumentOnLaunch` and `extensionStrikethough`.
2. Keep the persistence domain aligned with suite `app.macdown.macdown3000` so
   macdown-cmd, legacy migration, and QuickLook's CFPreferences reads keep working.
3. Preserve `NSURL` (`htmlDefaultDirectoryUrl`) and `NSDictionary`
   (`editorBaseFontInfo`) archival formats exactly.
4. Keep the four computed accessors and two suite-based accessors hand-written.
5. Writes must go through `standardUserDefaults` so its KVO keeps firing for
   `MPDocument`'s observers.

---

## 4. Dependency & vendored-asset inventory

### 4.1 CocoaPods

CocoaPods 1.16.2 (Gemfile-pinned, via Bundler). Two spec sources (`Podfile:5-6`):
the **patched** `MacDownApp/cocoapods-specs` fork and cdn.cocoapods.org.

| Pod | Version | Source | Targets |
|---|---|---|---|
| handlebars-objc | 1.4.5 | **patched fork** | MacDown, MacDownCore |
| hoedown | 3.0.7 (`hoedown/standard`) | **patched fork** | MacDown, MacDownTests, MacDownCore |
| LibYAML | 0.1.4 | **patched fork** | MacDown |
| GBCli | 1.1 | trunk | macdown-cmd |
| JJPluralForm | 2.1 | trunk | MacDown |
| M13OrderedDictionary | 1.1.0 | trunk | MacDown |
| MASPreferences | 1.4.1 | trunk | MacDown |
| PAPreferences | 0.5 | trunk | MacDown, MacDownTests |

The lockfile records only checksums, not the fork podspecs' `:git` origins — **the
fork's podspecs are the only authoritative record of what's patched; pull them in
before any upgrade of the three patched pods.** `post_install` forces all pods to
`MACOSX_DEPLOYMENT_TARGET` 11.0; `inhibit_all_warnings!` global.

### 4.2 `Dependency/` directory and submodules

`.gitmodules` declares **one** submodule: `Dependency/prism` →
`https://github.com/PrismJS/prism.git` pinned at commit **`bd479f1d5ff0855b4c50168c1a82c91b2db191f2`**
(~v1.4 era, 2016; not checked out until `setup.sh` runs submodule init).

Vendored source (not submodules):
- `Dependency/peg-markdown-highlight/` — Ali Rantakari's editor-highlight parser,
  frozen at the 2011–2013 upstream state (copyright headers in `pmh_parser.h`,
  `HGMarkdownHighlighter.h`); contains the `.leg` PEG grammar, a `greg/` parser
  generator, `pmh_styleparser`; built by `make` in `setup.sh` step 4 (codegen:
  `pmh_parser.c` from `pmh_grammar.leg` via greg).
- `Dependency/YAML-framework/` — just `YAMLSerialization.{h,m}` (ObjC wrapper over
  the LibYAML pod).
- `Dependency/version/` — helper subproject running `Tools/generate_version_header.sh`.

### 4.3 Vendored JS/web assets

All in `MacDown/Resources/Extensions/` and `MacDown/Resources/MathJax/`; injected by
`MPRenderer.m` as script/style tags in the generated HTML.

- **Prism** — pinned via submodule commit `bd479f1` only (no semver). NOT committed;
  copied into the bundle by two shell build phases in `project.pbxproj` ("Fetch Prism
  Resources", "Copy Styles and Prism Resources" → bundle `Prism/`). Loaded per-document:
  `language_addition()`/`add_to_languages()` read `Prism/components.js` +
  `Resources/syntax_highlighting.json` alias map to pull only the languages present in
  the document's fences plus their `require` chains (`MPRenderer.m:29-31, 553-600`).
  Plugins used: `line-numbers`, `show-language`. All Prism themes ship; selection via
  `MPHtmlPreferencesViewController` (`MPUtilities.m` theme resolution, user-overridable).
- **MathJax** — **2.7.3, split-brain**: local copy at `Resources/MathJax/MathJax.js`
  but the render path hard-codes the CDN
  (`kMPMathJaxCDN = https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.3/MathJax.js`,
  `MPRenderer.m:26`); the WebResourceLoadDelegate swaps in the local copy at runtime
  (`MPDocument.m:1268`, workaround for mathjax/MathJax#548). CSP whitelists
  cdnjs.cloudflare.com + `'unsafe-eval'` (`MPRenderer.m:508`). MathJax 2.x is EOL.
- **Mermaid** — 11.12.1 (`mermaid.min.js`, 2.75 MB) + `mermaid.init.js` +
  `mermaid.forest.css` (`MPRenderer.m:618-633`).
- **viz.js** — 3.75 MB Emscripten Graphviz, **no version banner — completely
  unversioned/unauditable** (`MPRenderer.m:635-649`).
- **tasklist.js** — local, hand-written (issue #269).
- No jQuery, no other third-party JS. Other CSS: `export.css`, `print.css`,
  `show-information.css` (local). `Resources/Data/{data,treats}.map` are binary
  plists (easter-egg data), not JS.

### 4.4 Templates

One handlebars template: `MacDown/Resources/Templates/Default.handlebars`
(full HTML document shell; context assembled in `MPRenderer.m`).

### 4.5 Sparkle (disabled, not removed)

- `Podfile:19-20`: `pod 'Sparkle', '~> 1.18'` commented out — "will upgrade to 2.8.1
  later". Not in Podfile.lock.
- `MPMainController.m:12` import commented; entire `SUUpdaterDelegate` block wrapped
  in `#if 0` (`:259+`) including `feedURLStringForUpdater:`.
- `MacDown-Info.plist:141-152`: `SUFeedURL`
  (`https://macdown.app/sparkle/macdown3000/stable/appcast.xml`), `SUBetaFeedURL`
  (`…/testing/appcast.xml`), `SUPublicDSAKeyFile` — all XML-commented.
- `Resources/dsa_pub.pem` still committed (**DSA — Sparkle 2 requires EdDSA
  migration**).
- Pre-releases checkbox disabled in `MPGeneralPreferencesViewController.m:26`.
- No "Check for Updates…" menu wiring remains.

### 4.6 Build tooling & targets

- Deployment target: uniform **macOS 11.0** (Podfile + all 12 `project.pbxproj`
  entries).
- `Tools/GitHub-style-generator/` — Node/Sass build-time tool (`sass ^1.101.0`,
  `@primer/css ^22.3.0`) generating `Resources/Styles/GitHub-2020.css` via a build
  phase.
- `setup.sh`: submodule init → `bundle install` → `pod install` → `make`
  peg-markdown-highlight. CI mirrors it via `.github/actions/setup-macdown`.
- Targets: **macdown-cmd** links GBCli only (launcher/IPC shim, no rendering);
  **MacDownCore** framework (issue #284) links hoedown + handlebars-objc, shared
  render code for Quick Look; **MacDownQuickLook** has no direct pods (everything via
  the embedded MacDownCore.framework).

### 4.7 Risk flags

1. Prism pinned by bare submodule commit + shell copy phases — brittle.
2. viz.js unversioned — hardest to audit; consider replacing wholesale.
3. MathJax split-brain (local copy + hard-coded CDN + `unsafe-eval` CSP); 2.x EOL.
4. Three pods depend on the external patched-specs fork — single point of failure and
   the only patch record.
5. Sparkle re-enable = Podfile + `#if 0` + Info.plist uncomment + DSA→EdDSA key
   migration.
6. peg-markdown-highlight requires greg codegen at build; frozen upstream.

---

## 5. MPDocument / MPRenderer structure

`MPDocument.m` is 4,061 lines (the Swift-port issue #201 says 2,178 — **it has
nearly doubled since that plan was written**). `MPRenderer.m` 924, `MPRenderer.h` 77.

### 5.1 MPDocument.m region map

| Region | Lines | Responsibility |
|---|---|---|
| Preamble/helpers | 1–427 | categories (`NSURL(Convert)` :116, `WebView(Shortcut)` :128, `MPPreferences(Hoedown)` :138-182 — hoedown flag mapping, belongs with the renderer), private class extension :185-324, `MPGetPreviewLoadingCompletionHandler` :326-380, `MPScanFenceMarker` :390-425 (pure fence scanner) |
| Accessors | 430–544 | computed props bridging prefs/renderer/word-count widget; word-count title formatters :476-529 |
| Lifecycle/NSDocument | 547–798 | `init` :547, `windowControllerDidLoadNib:` :576-716 (**the giant wiring method**: creates renderer + highlighter, registers all observers/KVO, starts file watching), `close` :750-798 |
| File I/O | 799–928 | `writeToURL:` :819, `writeSafelyToURL:` :862 (self-save flag for watcher suppression), `readFromData:` :913 (CRLF normalize) |
| Save panel | 929–977 | `prepareSavePanel:` |
| Printing | 978–1030 | `printOperationWithSettings:` :989 (WebView frameView print), `printDocumentWithSettings:` :1000 |
| Menu validation | 1031–1094 | one big switch over every IBAction selector |
| NSSplitViewDelegate | 1095–1132 | ratio tracking, divider redraw |
| NSTextViewDelegate | 1133–1265 | autocomplete/pairing + "fake" delegate helpers |
| WebView delegates | 1266–1477 | five delegate clusters (§1.2) |
| Renderer DataSource/Delegate | 1478–1774 | 12 one-line preference queries :1496-1552; **`renderer:didProduceHTMLOutput:` :1553-1725 — the single most coupled method** (DOM-replacement vs full reload, MathJax generation counter, resource watchers, scroll sync, word-count scheduling); `rendererBaseURL:` :1726, `previewSafeBaseURL:` :1758 |
| Resource watcher delegate | 1775–1784 | cache-bust + re-render |
| Notification handlers | 1792–2047 | text/selection change, `userDefaultsDidChange:` :1855, sync-scrolling toggle handlers :1894/1916, live-scroll owner transitions :1940-1961, resize/full-screen refresh :1979-2047 |
| KVO | 2048–2070 | editor text-checking pref sync |
| IBActions | 2071–2473 | export/copy :2073-2150, formatting :2151-2418, layout/pane :2426-2467, `render:` :2468 |
| "Private" (six sub-regions) | 2474–3691 | render plumbing :2483-2564 (`performAfterRender:` :2523); pane geometry + `setupEditor:` :2624-2783 (160-line editor config); `scaleWebview` :2826; **scroll sync + header tracking :2891-3452** (`updateHeaderLocations` :2891, pure class methods `editorReferenceKindsForMarkdown:` :2977 and `alignEditorYs:` :3128, `syncScrollers` :3235, `syncScrollersReverse` :3339); word count :3453-3530; link/file open :3531-3691 (`openOrCreateFileForUrl:` :3569) |
| Checkbox support (#269) | 3692–3911 | `handleCheckboxToggle:` :3698; **pure class method `toggleCheckboxAtIndex:inMarkdown:` :3786** |
| File watching (#290) | 3912–4061 | start/stop :3914/3958, external-change prompt/reload :3965-4061 |

### 5.2 Coupling points (private class extension, lines 185–324)

Highest-coupling state:

- **`editor` (:225) — 118 refs; `preview` (:227) — 51 refs** — threaded through
  almost every region.
- **Render-gating triad**: `isPreviewReady` (:237), `alreadyRenderingInWeb` (:250),
  `renderToWebPending` (:251) — shared between frame-load delegate and render path.
- **Scroll cluster** (cohesive, but reached into by the render path):
  `scrollOwner` (:258, 18 refs), `webViewHeaderLocations`/`editorHeaderLocations`
  (:252-253), `webViewHeaderTypes`/`editorHeaderTypes` (:256-257),
  `lastPreviewScrollTop` (:241), `_mathJaxRenderGeneration` (:322).
- Cross-region flags: `printing` (:236, print↔render), `isSelfSaving` (:269,
  I/O↔file-watch), `currentBaseUrl` (:238, render↔policy↔file-open).
- Isolated/low-coupling: `fileWatcher` (3 refs), word-count cluster
  (`totalWords`/menu items/`lastWordCountUpdate`/`showingSelectionCount` — used
  nowhere else), `renderCompletionHandlers` (:283).

### 5.3 The existing document↔renderer seam (MPRenderer.h)

`MPRendererDataSource`: `rendererLoading` (`MPDocument.m:1480` —
`!isPreviewReady || alreadyRenderingInWeb`), `rendererMarkdown:` (:1484 —
`editor.string`), `rendererHTMLTitle:` (:1489).

`MPRendererDelegate`: 11 preference queries (:1498-1548, each a one-line
`self.preferences` read) + `renderer:didProduceHTMLOutput:` (:1553, the heavyweight
sink) + optional `rendererBaseURL:` (:1726). **Every delegate method except the
output sink is a trivially extractable stateless adapter.**

### 5.4 MPRenderer.m pipeline

1. Front-matter strip (`parseMarkdown:` :760, via `NSString+Lookup`).
2. `MPPreprocessMarkdown` :109-193 (§2.7).
3. `MPHTMLFromMarkdown` :195-247 (hoedown + smartypants + TOC splice).
4. `MPGetHTML` :254-303 (template application; template name dispatch_once-cached
   from first render — wart).
5. Asset/style collection :539-705 (`prismStylesheets` :553, `prismScripts` :576,
   `mathjaxScripts` :603, `mermaidScripts` :618, `graphvizScripts` :635).

Entry points: `parseAndRenderWithMaxDelay:` :709 (serial `parseQueue`, background
parse, **spin-wait on `rendererLoading`**), `parseIfPreferencesChanged` :748 /
`renderIfPreferencesChanged` :797 (dirty-flag caches), `render` :820. Cache-busting:
`resourceTimestamps` :340 / `MPApplyCacheBusting` :846 (#110). Export path:
`HTMLForExportWithStyles:highlighting:` :872 (embedded assets).

### 5.5 Existing extracted collaborators

MPRenderer (protocol seam), MPFileWatcher (#290), MPResourceWatcherSet (#110),
MPMathJaxListener, MPAutosaving (protocol), MPDocumentSplitView, MPEditorView,
MPToolbarController, HGMarkdownHighlighter (vendored), MPHTMLResourceURLs,
MPURLSecurityPolicy, MPExportPanelAccessoryViewController.

### 5.6 Extraction seams, ranked (coverage+isolation vs coupling)

- **A. File watching → `MPFileWatchCoordinator`** (3912–4061): blocked only by the
  `isSelfSaving` bridge into `writeSafelyToURL:` (:862). `volumeLocalityChecker` is
  already a test seam. Highest confidence.
- **B. Word count → `MPWordCountController`** (:476-529, :3486-3530, :1846, :1811):
  fully self-contained state cluster; needs only a read-only view of editor text.
- **C. Scroll sync → `MPScrollSyncController`** (2891–3452 + live-scroll handlers
  1940–2047 + completion block 326–380): cohesive state cluster; two pure class
  methods already headless-testable; blocked by the render path directly driving
  `scrollOwner`/`updateHeaderLocations`/`syncScrollers` — needs a render-completion
  event to subscribe to. Largest test file de-risks it (`MPScrollSyncTests.m`, 97 KB).
- **D. Checkbox → `MPCheckboxToggler`** (3692–3911): `toggleCheckboxAtIndex:` is
  already pure + covered; entry is the policy-delegate URL interception (:1351).
- **E. Export/print → `MPDocumentExporter`** (:2073-2150, :989-1030, :3675): HTML side
  already delegates to renderer; blocked by PDF/print borrowing the live preview and
  the cross-region `printing` flag (:1568).
- **F. Preference→renderer adapter** (:1496-1552 + `MPPreferences(Hoedown)` :138-182):
  lowest-risk structural cut — split the renderer delegate into "preference queries"
  (stateless adapter) vs "output sink" (stays with the preview owner).

Recommended order: **A → B → D → F → C → E.** C and E are blocked by the same root:
`renderer:didProduceHTMLOutput:` (:1553-1725) is the true center of the god object
and should be decomposed last.

### 5.7 Test coverage by region (filename level)

Well-covered (safe to extract): rendering path (10 test files incl. golden corpus),
scroll sync (`MPScrollSyncTests.m` 97 KB + `MPMathJaxScrollTests.m`), checkbox
(`MPCheckboxToggleTests.m`), file watching (`MPFileWatcherTests.m`,
`MPResourceWatcherSetTests.m`), export (`MPHTMLExportTests.m`,
`MPImageExportTests.m`), word count (`MPWordCountUpdateTests.m`,
`MPSelectionCountTests.m`), pane/toolbar (`MPPaneToggleTests.m`,
`MPToolbarControllerTests.m`), lifecycle/I-O (`MPDocumentLifecycleTests.m`,
`MPDocumentIOTests.m`). **Thin:** WebView frame/policy delegates and the KVO
editor-preference sync have no dedicated tests (only indirect coverage).

---

## 6. Test & CI infrastructure state

**Headline: the repo is substantially ahead of the roadmap's assumptions.**

### 6.1 Unit tests

`MacDownTests/`: **44 test files, ~1,068 test methods** (plus
`MPRendererTestHelpers.{h,m}` mock infra). Only **3 files** touch a live web view:
`MPPreviewViewControllerTests.m` (WKWebView, Quick Look), `MPScrollSyncTests.m`,
`MPMathJaxScrollTests.m`. Everything else — including the Mermaid/Graphviz/MathJax
"rendering" tests — asserts on `MPRenderer` output strings, never rendering them in
a browser engine. (Full per-file table in the agent survey; headline files:
`MPMarkdownRenderingTests.m` 52 tests golden corpus, `MPScrollSyncTests.m` 174,
`MPRendererEdgeCaseTests.m` 51, `MPQuickLookRendererTests.m` 43.)

### 6.2 Golden corpus — ALREADY EXISTS (contradicts milestone assumption)

`MacDownTests/Fixtures/`: **31 `.md` inputs, 28 golden `.html` outputs** (3
`quicklook-*.md` input-only). Mechanism in `MPMarkdownRenderingTests.m`:
`loadFixture:` (:59), `renderMarkdown:withExtensions:rendererFlags:` (:84 — drives
the real `MPRenderer parseMarkdown:` → `currentHtml` synchronously),
`verifyGoldenFile:` (:107) with `XCTAssertEqualObjects` (:144). Regeneration via
`#define REGENERATE_GOLDEN_FILES` (:15) + `scripts/regenerate-golden-files.sh`.
Three consuming test classes: `MPMarkdownRenderingTests.m`,
`MPSyntaxHighlightingTests.m`, `MPMathJaxRenderingTests.m`.

This is a **string-equality parser-level corpus** — exactly the right layer for the
cmark-gfm swap. What does NOT exist: any rendered-DOM/visual corpus (would be new
work for the WKWebView migration), and corpus annotations distinguishing
"matches-spec" from "known-hoedown-bug" baselines.

### 6.3 XCUITest — ALREADY EXISTS (smoke level)

`MacDownUITests/MacDownUITests.swift` (79 lines): `testAppLaunchesWithWindow`,
`testEditorTextViewExists`, `testCanTypeInEditor`, `testPreviewPaneExists`; uses
accessibility id `"editor-text-view"` and `app.webViews.firstMatch`; dedicated
scheme, dedicated CI job. The larger page-object suite in `plans/xcuitest.md` §3.2
is not implemented; `MacDownUITests/Fixtures/` not created.

### 6.4 CI workflows

- **`test.yml`**: unit tests **gate every push/PR** across a 4-way matrix
  (`macos-14, macos-15, macos-15-intel, macos-26`; `test.yml:13`), plus a 2-minute
  app-launch smoke test (fresh + legacy-prefs migration, #169) and xccov coverage PR
  comments. The `ui-test` job runs `MacDownUITests` on macos-26 only,
  **`continue-on-error: true`** (non-blocking; `test.yml:328-346`).
- `build-release.yml` (Release-config universal-binary check), `markdownlint.yml`,
  `release.yml` (tag-triggered sign/notarize/publish), `staple-release.yml`,
  `update-website.yml`.
- Composite actions: `.github/actions/setup-macdown` (Ruby 3.3, pod install, peg
  build), `.github/actions/build-macdown`.

### 6.5 Issue #476 premise is wrong

**Zero `XCTExpectFailure` usages exist.** Display-dependent tests instead detect
headless at runtime and silently early-return with `NSLog(@"Skipping …")` —
e.g. `MPRenderDeferralTests.m:132,153,232,260`; `MPPaneToggleTests.m:300,341,384,424`;
`MPScrollSyncTests.m:107,297,1891,2030`; `MPDocumentIOTests.m:85,375,551`. On
headless CI these **pass silently** rather than being marked expected-failure. Any
#476 work starts by introducing proper `XCTSkip` semantics, not removing wrappers.

### 6.6 Mermaid/Puppeteer harness — greenfield

No Node test harness exists (no puppeteer/playwright/jest anywhere). The only
`package.json` is the GitHub-style-generator build tool. Mermaid/Graphviz are tested
only via ObjC string assertions plus a manual plan
(`plans/issue-18-mermaid-gantt-testing.md`).

### 6.7 macdown-cmd is NOT a headless renderer

`macdown-cmd/main.m` is a launcher/IPC shim: stashes file paths / piped content into
the shared defaults suite (`:27, :35`) and launches the GUI app (`:117`). It has no
render path (`MPArgumentProcessor.m:45-50` — only `-v`/`-h`). The ready-made headless
rendering primitive is `MPRenderer parseMarkdown:` → `currentHtml` (as used by the
golden tests, `MPMarkdownRenderingTests.m:84-100`); a true CLI renderer would be a
small new subcommand wired to MPRenderer.

### 6.8 Bootstrap

`setup.sh` (submodules → bundler → pods → peg make) mirrors CI's
`setup-macdown` action; local and CI paths are consistent.

