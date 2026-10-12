# Fix: keep MathJax's TeX fonts local (stop the raster fallback)

## Problem (root cause, confirmed by instrumentation)

Preview math renders as **bitmap image fonts** — pixelated on zoom — instead of
crisp vector text. Commit `472e2a1` set the HTML-CSS output jax's
`availableFonts: []` / `preferredFont: null` (init.js) to stop it typesetting in
macOS's system STIX faces, forcing MathJax's own **TeX web fonts**. But the app
ships *no* fonts: `Resources/MathJax/` holds only the 63 KB `MathJax.js` loader
and `init.js`. So the TeX woff fonts are fetched from the CDN at render time, and
when they don't arrive in time (web-font timeout, cold cache, slow/offline link)
HTML-CSS falls back to bitmap image fonts.

A resource-load probe on a live render confirmed it. Of the requests the preview
issues, `MathJax.js` is already served from the bundle (the existing redirect in
`-webView:resource:willSendRequest:…`, `MPDocument.m:1796`), while these come from
`https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.3/…` at runtime:

```
config/TeX-AMS-MML_HTMLorMML.js
jax/output/HTML-CSS/jax.js
jax/output/HTML-CSS/fonts/TeX/fontdata.js
fonts/HTML-CSS/TeX/woff/MathJax_Main-Regular.woff     ← the fonts
fonts/HTML-CSS/TeX/woff/MathJax_Math-Italic.woff        (fetched on demand,
fonts/HTML-CSS/TeX/woff/MathJax_Size1-Regular.woff       per glyphs used)
fonts/HTML-CSS/TeX/woff/MathJax_Size2-Regular.woff
```

Two facts from the probe drive the fix: **the `.woff` requests pass through the
resource-load delegate** (so they can be redirected exactly as `MathJax.js` is),
and **they target the CDN** (so keeping them local removes the render-time
dependency).

## Requirement (outcome)

- **F1.** Wherever preview math renders, it renders in **vector** TeX faces at any
  zoom — no bitmap image-font fallback — including the very first render on a cold
  cache, while staying HTML-CSS output so the math remains selectable, searchable
  and copy-pasteable (SVG/image output is explicitly rejected for that reason).
  Local woff fonts load synchronously from `file:`, so the HTML-CSS web-font
  timeout that triggers the image-font fallback never fires.

Non-goals: **fully offline math.** The `config`, output `jax.js` and `fontdata.js`
still load from the CDN (and are cached), so with no network the math does not
render at all — unchanged from today, and not what was reported. This fix keeps
the *fonts* local, per the request; bundling the remaining MathJax resources for
true offline rendering is a separate, larger change. Also out of scope: changing
the output jax away from HTML-CSS.

Why fonts-only still fixes the reported bug: the image-font fallback is a property
of the woff `@font-face` load, which local fonts make instant; it only occurs
after `fontdata.js` has loaded, i.e. exactly when math renders. So local fonts
remove the fallback in every case where math renders, cold cache included.

## Design

### 1. Bundle the TeX woff fonts

Add the complete MathJax 2.7.3 HTML-CSS **TeX woff** font set to
`MacDown/Resources/MathJax/fonts/HTML-CSS/TeX/woff/` (the on-demand fetch only
pulls the glyphs a document uses, so the *whole* set must be bundled for any
document to be covered). `Resources/MathJax` is a **folder reference**
(`project.pbxproj:356`, `lastKnownFileType = folder`), so the files are bundled
with no project edit. woff is what modern WebKit uses for `@font-face`; the otf
set is not bundled unless testing shows WebKit1 needs it.

### 2. Serve bundled MathJax resources locally (generalise the redirect)

Replace the `MathJax.js`-only special case in
`-webView:resource:willSendRequest:…` with a general rule: for a request to the
MathJax CDN, map its path below `…/mathjax/<version>/` to
`Resources/MathJax/<subpath>`; if that file exists in the bundle, redirect the
request to the local `file:` URL; otherwise pass the request through to the CDN
unchanged.

- This subsumes today's `MathJax.js` redirect (still bundled → still local) and
  adds the woff fonts (now bundled → local), while `config`, `jax.js` and
  `fontdata.js` (not bundled) keep going to the CDN and stay cached — behaviour
  for those is unchanged.
- The mapping keys off the URL **path**. The local `file:` URL is built from the
  path only — the `?V=2.7.3` query is dropped, since a `file:///…woff?V=2.7.3`
  may not resolve and would fail the load back into the image fallback. Query
  preservation stays limited to `MathJax.js` (which needs `?config=…`), exactly
  as today.
- Fonts loaded from `file:` are already permitted: `font-src` includes `file:`
  (`MPPreviewContentSecurityPolicy`). The CDN entry in `font-src`/`script-src`
  stays as a fallback for the still-remote resources.

### 3. Form as implemented

The `MathJax.js` redirect is kept **verbatim** (early return, `URLForResource` +
`setQueryItems`) and the font redirect is added as a second branch. This was
chosen over folding `MathJax.js` into the general rule because the general
path-mapping builds the local URL with `resourceURL/URLByAppendingPathComponent`,
and re-attaching `MathJax.js`'s `?config=` query to *that* `file:` URL via
`NSURLComponents` yielded a non-`file:` URL — the loader would not load from the
bundle. The original `URLForResource`-based construction re-attaches the query
correctly and is already proven in production, so the working path is left
untouched. The two branches share nothing but intent; the font branch carries no
query, so there is no query-handling duplication to drift.
- **Point MathJax's font path at the bundle via init.js config:** more fragile —
  it depends on MathJax's root/path resolution, which the redirect already
  side-steps. The redirect is the mechanism the app already trusts for `MathJax.js`.

## Tests

- **`MPMathJaxLocalFontsTests`** (new). Every redirect assertion calls the real
  delegate method — `[doc webView:nil resource:nil willSendRequest:req
  redirectResponse:nil fromDataSource:nil]` — never a reimplemented mapping, so a
  test fails if the actual delegate logic changes.
  - A CDN woff URL
    (`…/2.7.3/fonts/HTML-CSS/TeX/woff/MathJax_Main-Regular.woff?V=2.7.3`) is
    rewritten to the bundled `file:` URL, that URL carries **no query**, and the
    bundled file exists on disk.
  - A CDN resource that is **not** bundled (e.g. `…/jax/output/HTML-CSS/jax.js`)
    passes through unchanged (the returned request's URL is still the CDN URL).
  - `MathJax.js` still redirects to the bundle with `?config=…` preserved
    (regression guard for the existing behaviour the generalisation replaces).
  - Every file in an **authoritative, hard-coded list** of the MathJax 2.7.3
    HTML-CSS TeX woff filenames is present in the bundle. The list is a fixed copy
    of the real 2.7.3 `fonts/HTML-CSS/TeX/woff/` directory checked into the test —
    **not** enumerated from the bundle's own contents, which could never fail on an
    incomplete drop. Guards the failure mode where a missing family (e.g. omitting
    `MathJax_AMS-Regular.woff`, so `$$\mathbb{R}\subseteq\mathbb{C}$$` still fetches
    AMS remotely and pixelates) slips through.
- A live-WebView font-mode assertion (image vs web fonts) is not attempted here:
  it needs a windowed WebView and network, and the existing MathJax tests are
  string/JS-level. The redirect + presence tests are the guard; manual
  verification (below) covers the rendered result.

Manual: open a math document offline (or with the CDN blocked) on a cold cache —
math renders vector, not pixelated, and stays selectable.

## Risk

- **Font set completeness.** Missing a woff family leaves some glyphs fetching
  remotely (and pixelating). The presence test enumerates the expected set.
- **WebKit1 woff support.** The probe shows WebKit1 already requests woff for
  MathJax; serving the same bytes from `file:` is a strictly smaller change than
  the remote fetch it replaces. If WebKit1 turns out to need otf, bundle otf too.
- **Redirect generality.** The new rule only ever redirects to a file that exists
  in the bundle; anything else is passed through, so it cannot break loads for
  un-bundled resources.
- **Version coupling.** The rule maps paths under `…/mathjax/<version>/`, and the
  bundled woff are 2.7.3 bytes. Bumping `kMPMathJaxCDN` without refreshing the
  bundled fonts would map a new version's font path to stale local bytes. This is
  the pre-existing hazard already noted at `MPRenderer.m:22` (the bundled
  `MathJax.js` has the same coupling); the fix widens it from one file to the font
  set. Mitigation: the authoritative-list presence test is version-specific, so a
  version bump that moves paths surfaces as a test to update.
