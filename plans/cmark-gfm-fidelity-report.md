# cmark-gfm Fidelity Report (Issue #77, Decision D-2)

Measured comparison of hoedown 3.0.7 (MacDown's production pipeline) against
**cmark-gfm 0.29.0.gfm.13** across the 28 golden fixture pairs in
`MacDownTests/Fixtures/`. This implements decision D-2 from
`plans/dependency-overhaul-decisions.md`: it converts issue #77's risk table
from opinion to data ahead of the v3000.1.1 parser migration.

Generated with `scripts/cmark-gfm-fidelity-eval.py` (see its docstring for
the cmark-gfm build recipe and re-run instructions). Evaluation date:
2026-07-05.

> **Status note:** this report is a point-in-time comparison against the
> *hoedown* golden files. The migration has since landed (same branch): the
> goldens were re-baselined to the new mdmark/cmark-gfm pipeline per the
> per-category review below, so re-running the script against today's
> fixtures compares plain cmark-gfm output against mdmark-contract output
> instead — the hoedown baseline this report measured no longer exists in
> the tree.

## Method

Each fixture's `.md` is rendered through the cmark-gfm CLI with the closest
flag mapping to the hoedown flags its golden test uses (`--unsafe` always,
plus `-e table/strikethrough/autolink/tasklist` where the test enables the
equivalent hoedown extension), then compared against the golden `.html` in
three tiers:

1. **byte-identical**
2. **serialization-normalized** — neutralizes entity choice, void-tag style,
   boolean-attribute style, and DOM-insignificant whitespace
3. **contract-normalized** — additionally neutralizes MacDown's custom
   renderer contract from `hoedown_html_patch.c` (heading `id` slugs,
   `<div>`-wrapped code blocks, Prism language aliasing, `language-none`,
   trailing-newline trim, task-list checkbox markup)

A fixture that matches at tier 3 (**contract-only**) diverges *only* in
shapes the migration must re-implement anyway via cmark-gfm renderer hooks
(decision D-10) — the parsers agree about the input. A **behavioral**
fixture means the parsers genuinely disagree.

Caveats:

- The goldens snapshot the full production pipeline: hoedown *plus*
  `MPPreprocessMarkdown` workarounds. cmark-gfm gets the raw markdown, since
  post-migration the preprocessor is expected to shrink to CRLF
  normalization (D-11). That asymmetry is deliberate and it surfaced real
  findings (see #37 below).
- The corpus does not exercise hoedown's `EXT_MATH`, `EXT_HIGHLIGHT`,
  `EXT_SUPERSCRIPT`, `EXT_UNDERLINE`, or `EXT_QUOTE` (no golden test enables
  them), so **this report measures nothing about those feature gaps** — they
  remain open items for the D-3 corpus extension.

## Headline result

| Verdict | Count |
|---|---|
| identical | 0 / 28 |
| serialization-only | 0 / 28 |
| **contract-only** (parser agrees; diff is D-10 contract work) | **15 / 28** |
| **behavioral** (parsers disagree) | **13 / 28** |

Zero fixtures are byte-identical because the renderer contract touches
every fixture (every heading gets an `id` slug; every code block gets the
`<div>` wrapper). That confirms the survey's framing: **the D-10 contract
re-implementation is the bulk of the migration**, and it is fully
enumerable. The 13 behavioral fixtures decompose into the categories below;
none of them is an unexplained surprise, and one (tilde fences) is a
genuine document-compatibility hazard.

## Per-fixture verdicts

| Fixture | Verdict | Behavioral changed lines | Notes |
|---|---|---|---|
| autolinks | contract-only | 0 | |
| basic | contract-only | 0 | |
| blockquotes | behavioral | 3 | adjacent-blockquote merge (bug fix) |
| code-fenced | contract-only | 0 | |
| code-inline | contract-only | 0 | |
| code-languages | behavioral | 3 | hoedown spurious leading blank line (bug fix) |
| edge-cases | behavioral | 25 | header/emphasis/entity/tab spec differences |
| emphasis | behavioral | 6 | `***x***` nesting order; nested emphasis fix |
| horizontal-rules | contract-only | 0 | |
| images | behavioral | 2 | alt-text markup stripping (spec fix) |
| links | contract-only | 0 | |
| lists-nested | behavioral | 13 | deep-nesting indentation rules (spec) |
| lists-ordered | behavioral | 2 | `start` attribute honored (bug fix, #26 class) |
| lists-unordered | contract-only | 0 | |
| mathjax-in-code | contract-only | 0 | |
| mathjax-syntax | behavioral | 2 | intra-word `_` no longer mangles formulas |
| mixed-complex | behavioral | 30 | table alignment attr + loose/tight lists |
| regression-issue25 | contract-only | 0 | preprocessor workaround unneeded |
| regression-issue34 | contract-only | 0 | lists-after-colon native (issue #77's driver) |
| regression-issue36 | contract-only | 0 | preprocessor workaround unneeded |
| regression-issue37 | behavioral | 10 | golden contains leaked U+200B (see below) |
| strikethrough | behavioral | 24 | **`~~~` opens a tilde code fence (hazard)** |
| syntax-highlighting-aliases | contract-only | 0 | |
| syntax-highlighting-languages | contract-only | 0 | |
| syntax-highlighting-mixed | contract-only | 0 | |
| tables | behavioral | 40 | `align=` vs `style=`; minimal tables now parse |
| task-lists | behavioral | 8 | loose/tight rendering of invalid-marker items |
| unicode | contract-only | 0 | |

## Findings by category

### A. Expected bug fixes (hoedown defects the corpus froze)

These diffs are cmark-gfm doing the *right* thing where the goldens
snapshot a hoedown bug. Per D-1, the re-baseline should accept these
deliberately:

- **Ordered lists honor the start number** (`lists-ordered`, `edge-cases`):
  `5. Fifth item` renders `<ol start="5">`; hoedown always restarts at 1
  (the #26 class of bug).
- **Adjacent blockquotes are no longer merged** (`blockquotes`): a `<ul>`
  and `<ol>` quoted with a blank line between them become two blockquotes;
  hoedown fuses them (#27 class).
- **Minimal tables parse** (`tables`): a `| - | - |` single-dash separator
  row is a valid GFM table; hoedown renders the whole table as a paragraph
  of pipes.
- **Image alt text is plain text** (`images`): `![Alt text with **bold**]`
  yields `alt="Alt text with bold"` per spec; hoedown leaves the literal
  asterisks in the attribute.
- **Nested emphasis parses** (`emphasis`): `*italic with **bold inside**...*`
  renders; hoedown gives up and leaves literal `*`.
- **Spurious blank line in code blocks** (`code-languages`): hoedown emits a
  leading newline inside one fenced block; cmark-gfm does not.

### B. The preprocessor workarounds are confirmed deletable — and one is actively corrupting output today

The four `MPPreprocessMarkdown` regex workarounds (#25, #254, #36, #37 —
with #34, lists after colons, being the symptom the #254 regex addresses)
all exist to patch hoedown parse bugs. cmark-gfm needs none of them:

- `regression-issue25`, `regression-issue34`, `regression-issue36` are all
  **contract-only**: raw markdown through cmark-gfm matches what
  hoedown-plus-preprocessor produces. The workarounds become dead code
  (D-11 requires deleting them for sourcepos correctness anyway).
- `regression-issue37` is the significant one: the golden file **contains
  U+200B ZERO WIDTH SPACE characters in the rendered code output** — the
  #37 workaround injects them before `]:` sequences inside fences to defeat
  hoedown's `is_ref()`, and they leak into the visible `<code>` text (and
  the clipboard, when a user copies the snippet). cmark-gfm renders the
  same input byte-clean with no preprocessing. This is a user-visible
  defect of the current pipeline that the migration fixes for free.

Issue #34 — the original driver of #77 — is confirmed resolved natively:
lists interrupt paragraphs after colons with no preprocessing.

### C. Spec-driven behavior changes (release-note items)

Real divergences long-time users could notice, each a candidate for the
v3000.1.1 release notes rather than compatibility shims:

- **ATX headings require a space after `#`**: `#No space` and `#1 hashtag
  number` become paragraphs (CommonMark rule; hoedown made them headings).
  Also `##Multiple##Hashes##` stays a paragraph, and a bare `##` line
  becomes an *empty* `<h2>` instead of literal text.
- **`***bold italic***`** nests as `<em><strong>` instead of hoedown's
  `<strong><em>` — visually identical, but DOM-order-sensitive CSS or JS
  would notice (none of MacDown's bundled assets key on that order).
- **Consecutive delimiter runs** resolve differently:
  `**Bold****More bold**` and `*Italic**Mixed bold*` produce different
  (spec-defined) groupings than hoedown's.
- **Table alignment** is emitted as `align="left|center|right"` attributes
  instead of hoedown's inline `style="text-align: …"`. Rendering is
  equivalent in practice, but bundled themes and user CSS that target
  `td[style]` would need the D-10 renderer hook to pick one shape (or emit
  hoedown's) — flag for the CSS-theme audit.
- **Loose/tight list rendering** follows spec: several list items the
  goldens wrap in `<p>` render tight (or vice versa), changing visual
  spacing (`lists-*`, `task-lists`, `mixed-complex`).
- **Deep nesting rules differ** (`lists-nested`): at 4-space indents
  cmark-gfm nests sublists where hoedown flattened them to siblings.
- **Tabs are preserved** in paragraph text instead of expanded to spaces;
  **named entities** (`&copy;`) are resolved to literal characters
  (DOM-equivalent).
- **Intra-word underscores**: with the golden tests' flags, hoedown turns
  `( \frac{x_1 + x_2}{2} )` into `x<em>1 + x</em>2`; cmark-gfm leaves it
  alone. This *improves* MathJax fidelity, and the app's shipping default
  already disables intra-word emphasis (preferences migration v3), so the
  practical delta is smaller than the fixture suggests.
- **Raw angle-bracket text is reclassified as an HTML block**: both parsers
  pass `<Text in angle brackets>` through unescaped, but hoedown wraps it
  in `<p>` (inline raw HTML) while cmark-gfm under `--unsafe` emits it as a
  bare raw-HTML block — the paragraph wrapper and its styling disappear.
  Interacts with the D-9 `CMARK_OPT_UNSAFE` decision — the D-3
  hostile-HTML fixtures should pin raw-HTML handling before re-baseline.

### D. The one genuine hazard: `~~~` opens a tilde code fence

In the `strikethrough` fixture, the line `~~~Too many tildes~~~` — which
hoedown renders as `~<del>Too many tildes</del>~` — is a **tilde code fence
opener** in CommonMark (with info string `Too`). cmark-gfm swallowed the
entire remainder of the fixture into a `<pre>` block. Any user document
using three-plus tildes as decoration around text will break dramatically,
not subtly. This is spec-correct and should ship, but it is the single
highest-visibility compatibility break found; the release notes must call
it out explicitly, and it is a good candidate for a one-time "scan your
documents" note or an opt-in lint in the editor.

### E. What this corpus does NOT measure

- The five hoedown extensions with no cmark-gfm equivalent (`==highlight==`,
  `^superscript`, `_underline_`-as-`<u>`, `"quote"`-as-`<q>`, and
  `$…$`/`$$…$$` math protection) have **zero fixture coverage**, so their
  absence produced zero diffs here. The math gap in particular remains the
  highest-risk parity item (survey §2.2, D-9) and needs D-3 fixtures plus a
  custom-extension decision before v3000.1.1.
- `data-information` code-block accessories (`BLOCKCODE_INFORMATION`):
  several golden tests enable the flag, but no fixture uses the `lang:info`
  fence syntax, so the goldens contain no `data-information` or
  `line-numbers` attributes and this comparison exercises neither.
  cmark-gfm keeps the full fence info string in the AST, so the accessory
  is implementable in a renderer hook, but nothing here proves it.
- Smartypants is a MacDown post-pass over rendered HTML, off in all golden
  tests; it is parser-independent and unaffected by this comparison.

## What this means for v3000.1.1 (scoping)

1. **The migration is tractable.** 15/28 fixtures need only the D-10
   renderer-contract hooks (slugs, code-block wrapper + aliasing, task-list
   markup) — all enumerable, all already speced in survey §2.12.
2. **The behavioral fold is mostly wins**: the #26/#27-class bug fixes and
   all four preprocessor workarounds are confirmed deletable, with the #37
   ZWSP leak as concrete evidence the current pipeline corrupts output.
3. **Release-note ledger** (category C) is short and specific; only the
   tilde-fence change (category D) needs prominent user communication.
4. **Before re-baselining the corpus** (D-1), land the D-3 coverage
   extension for the unmeasured feature gaps — math above all — so the gap
   decisions are also data-driven.

## Reproducing

```sh
# Build the pinned CLI (see script docstring), then:
python3 scripts/cmark-gfm-fidelity-eval.py \
    --cmark /path/to/cmark-gfm/build/src/cmark-gfm \
    --output /tmp/cmark-eval
```

Per-fixture `*.behavioral.diff` artifacts (contract-normalized unified
diffs) and `results.json` land in the output directory.
