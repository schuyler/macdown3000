#!/usr/bin/env python3
"""cmark-gfm fidelity evaluation against the golden fixture corpus.

Implements decision D-2 from plans/dependency-overhaul-decisions.md for
issue #77: renders every golden fixture (MacDownTests/Fixtures/*.md) through
the cmark-gfm CLI using the closest available flag mapping, diffs the result
against hoedown's golden HTML (*.html), and emits a categorized report that
scopes the v3000.1.1 parser migration.

The golden files snapshot MPRenderer output: hoedown 3.0.7 plus MacDown's
patched renderer callbacks (hoedown_html_patch.c) plus MPPreprocessMarkdown.
cmark-gfm is fed the *raw* fixture markdown deliberately — after migration
the preprocessor workarounds are expected to be deleted (D-11), so the raw
input is the honest comparison.

Each fixture gets one of four verdicts, from three comparison tiers:

  identical           byte-for-byte equal
  serialization-only  equal after neutralizing cosmetic HTML serialization
                      (entities, void-tag style, whitespace)
  contract-only       equal after ALSO neutralizing MacDown's custom
                      renderer contract (heading id slugs, div-wrapped code
                      blocks, Prism language aliasing, task-list markup) —
                      i.e. the diff is fully explained by the D-10 contract
                      re-implementation, with no parser behavior change
  behavioral          the parsers genuinely disagree about the input;
                      see <fixture>.behavioral.diff in the output directory

Usage:
    python3 scripts/cmark-gfm-fidelity-eval.py [--cmark PATH] [--output DIR]

Requires a cmark-gfm CLI, pinned to PINNED_VERSION (a warning is printed for
any other version). Build it with:

    git clone --depth 1 --branch 0.29.0.gfm.13 \
        https://github.com/github/cmark-gfm.git
    cmake -S cmark-gfm -B cmark-gfm/build \
        -DCMAKE_BUILD_TYPE=Release -DCMARK_TESTS=OFF -DCMARK_SHARED=OFF
    make -C cmark-gfm/build -j4
    # binary at cmark-gfm/build/src/cmark-gfm
"""

import argparse
import difflib
import json
import re
import subprocess
import sys
from pathlib import Path

PINNED_VERSION = "0.29.0.gfm.13"

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURES_DIR = REPO_ROOT / "MacDownTests" / "Fixtures"
ALIASES_JSON = REPO_ROOT / "MacDown" / "Resources" / "syntax_highlighting.json"

# Per-fixture hoedown flag configuration, transcribed from the golden-file
# tests (MPMarkdownRenderingTests.m, MPSyntaxHighlightingTests.m,
# MPMathJaxRenderingTests.m), mapped to the closest cmark-gfm CLI flags:
#
#   HOEDOWN_EXT_TABLES                 -> -e table
#   HOEDOWN_EXT_STRIKETHROUGH          -> -e strikethrough
#   HOEDOWN_EXT_AUTOLINK               -> -e autolink
#   HOEDOWN_HTML_USE_TASK_LIST         -> -e tasklist
#   HOEDOWN_EXT_FENCED_CODE            -> (built into CommonMark)
#   HOEDOWN_HTML_BLOCKCODE_INFORMATION -> no equivalent (data-information gap)
#
# Raw HTML passthrough is hoedown's default and MacDown renders it, so every
# invocation gets --unsafe and tagfilter stays off (decision D-9).
# Smartypants is a separate MacDown post-pass preference, off in all golden
# tests, so --smart is never passed.
FIXTURE_EXTENSIONS = {
    "autolinks": ["autolink"],                       # testAutolinks
    "basic": [],                                     # testBasicHeaders
    "blockquotes": [],                               # testBlockquotes
    "code-fenced": [],                               # testCodeFenced
    "code-inline": [],                               # testCodeInline
    "code-languages": [],                            # testCodeLanguages
    "edge-cases": ["table"],                         # testEdgeCases
    "emphasis": [],                                  # testEmphasis
    "horizontal-rules": [],                          # testHorizontalRules
    "images": [],                                    # testImages
    "links": [],                                     # testLinks
    "lists-nested": [],                              # testListsNested
    "lists-ordered": [],                             # testListsOrdered
    "lists-unordered": [],                           # testListsUnordered
    "mathjax-in-code": [],                           # testMathInCodeBlocksIgnored
    "mathjax-syntax": [],                            # testMathJaxSyntaxComprehensive
    "mixed-complex": ["table", "autolink",           # testMixedComplex
                      "strikethrough", "tasklist"],
    "regression-issue25": [],                        # testRegressionIssue25...
    "regression-issue34": [],                        # testRegressionIssue34...
    "regression-issue36": [],                        # testRegressionIssue36...
    "regression-issue37": [],                        # testRegressionIssue37...
    "strikethrough": ["strikethrough"],              # testStrikethrough
    "syntax-highlighting-aliases": [],               # testLanguageAliases
    "syntax-highlighting-languages": [],             # testLanguageClassGeneration
    "syntax-highlighting-mixed": [],                 # testMixedCodeBlocks
    "tables": ["table"],                             # testTables
    "task-lists": ["tasklist"],                      # testTaskLists
    "unicode": [],                                   # testUnicodeComprehensive
}


def load_language_aliases():
    data = json.loads(ALIASES_JSON.read_text(encoding="utf-8"))
    return data.get("aliases", {})


def normalize_serialization(html):
    """Neutralize cosmetic serialization differences.

    Hoedown and cmark-gfm legitimately differ in trailing whitespace,
    blank-line placement, self-closing-tag style, boolean-attribute style,
    and entity choice for quotes. None of those affect the DOM that
    MacDown's downstream JS/CSS consumes.
    """
    # Entity and quote-encoding equivalences (same DOM text).
    html = html.replace("&#39;", "'").replace("&quot;", '"')
    html = html.replace("&#47;", "/")
    # XHTML-style self-closing vs HTML-style void tags: <br/> vs <br>.
    html = re.sub(r"\s*/>", ">", html)
    # Boolean attribute serialization: checked="" vs checked.
    html = re.sub(r'(checked|disabled)=""', r"\1", html)
    # Trailing whitespace and blank-line runs. Whitespace inside <pre> is
    # real code content, so both transforms apply only outside those blocks.
    html = _outside_pre(html, lambda t: re.sub(r"[ \t]+\n", "\n", t))
    html = _outside_pre(html, lambda t: re.sub(r"\n{2,}", "\n", t))
    return html.strip() + "\n"


def _outside_pre(html, transform):
    """Apply transform(text) to the segments of html outside <pre> blocks."""
    parts = re.split(r"(<pre.*?</pre>)", html, flags=re.DOTALL)
    return "".join(part if part.startswith("<pre") else transform(part)
                   for part in parts)


def normalize_contract(html, aliases):
    """Neutralize MacDown's custom renderer contract (survey §2.3, D-10).

    Everything removed here is a shape hoedown_html_patch.c adds on purpose
    and the migration must re-achieve via cmark-gfm renderer hooks: heading
    id slugs, the <div>-wrapped code blocks with Prism language aliasing and
    accessories, and the task-list checkbox contract. A diff that disappears
    under this normalization is contract work, not a parser disagreement.
    """
    # Heading anchor ids (slugify contract).
    html = re.sub(r"(<h[1-6]) id=\"[^\"]*\"", r"\1", html)
    # Code-block wrapper and accessories.
    html = html.replace("<div><pre", "<pre").replace("</pre></div>", "</pre>")
    html = re.sub(r'(<pre[^>]*) class="line-numbers"', r"\1", html)
    html = re.sub(r'(<pre[^>]*) data-information="[^"]*"', r"\1", html)
    html = html.replace('<code class="language-none">', "<code>")
    # Prism language aliasing (language_addition back-channel).
    html = re.sub(
        r'class="language-([^"]+)"',
        lambda m: f'class="language-{aliases.get(m.group(1), m.group(1))}"',
        html)
    # Hoedown patch trims the trailing newline inside code blocks; cmark
    # keeps it. DOM-visible only as a trailing blank line Prism would strip.
    html = re.sub(r"\n(</code></pre>)", r"\1", html)
    # Task-list markup (tasklist.js contract vs cmark's tasklist extension).
    html = html.replace(' class="task-list-item"', "")
    html = re.sub(r' data-checkbox-index="\d+"', "", html)
    html = re.sub(r'(<input [^>]*?) ?disabled(="")?(?=[ >/])', r"\1", html)
    # Inter-tag newline placement outside <pre> (e.g. hoedown's "text\n</li>"
    # vs cmark's "text</li>", cmark's "<li>\n<p>" vs hoedown's "<li><p>") —
    # whitespace-insignificant in the DOM. Restricted to block-level closing
    # tags: a newline before an inline closer (</em>, </a>, ...) renders as
    # a space and removing it would mask a real difference.
    block_close = (r"\n+(?=</(?:p|li|ul|ol|blockquote|h[1-6]|t[dhr]|thead"
                   r"|tbody|table|div)>)")
    html = _outside_pre(html, lambda t: re.sub(block_close, "", t))
    html = _outside_pre(html, lambda t: re.sub(r"(<li>)\n+(?=<)", r"\1", t))
    return html


def run_cmark(cmark, md_path, extensions):
    cmd = [str(cmark), "--unsafe"]
    for ext in extensions:
        cmd += ["-e", ext]
    cmd.append(str(md_path))
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"cmark-gfm failed on {md_path.name}: {result.stderr}")
    return result.stdout


def unified(golden_text, actual_text, name, label):
    diff = list(difflib.unified_diff(
        golden_text.splitlines(keepends=True),
        actual_text.splitlines(keepends=True),
        fromfile=f"{name}.html (hoedown golden, {label})",
        tofile=f"{name} (cmark-gfm {PINNED_VERSION}, {label})"))
    changed = sum(1 for line in diff[2:] if line.startswith(("+", "-")))
    return diff, changed


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cmark", default="cmark-gfm",
                        help="path to the cmark-gfm CLI (default: from PATH)")
    parser.add_argument("--output", default=None,
                        help="directory for diff artifacts and results.json "
                             "(default: print summary only)")
    args = parser.parse_args()

    try:
        version = subprocess.run([args.cmark, "--version"],
                                 capture_output=True, text=True).stdout.strip()
    except OSError as exc:
        print(f"error: cannot run cmark-gfm CLI at '{args.cmark}' ({exc}); "
              "see the module docstring for build instructions",
              file=sys.stderr)
        return 2
    if PINNED_VERSION not in version:
        print(f"warning: expected cmark-gfm {PINNED_VERSION}, got: {version}",
              file=sys.stderr)

    aliases = load_language_aliases()
    out_dir = Path(args.output) if args.output else None
    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)

    # Guard against silent staleness: every golden pair on disk must have a
    # flag entry transcribed from its test, or the corpus has grown past us.
    on_disk = {p.stem for p in FIXTURES_DIR.glob("*.html")
               if (FIXTURES_DIR / f"{p.stem}.md").exists()}
    unmapped = sorted(on_disk - set(FIXTURE_EXTENSIONS))
    if unmapped:
        print("error: golden fixtures missing from FIXTURE_EXTENSIONS "
              f"(transcribe their test flags): {', '.join(unmapped)}",
              file=sys.stderr)
        return 2

    results = []
    for name, extensions in sorted(FIXTURE_EXTENSIONS.items()):
        md_path = FIXTURES_DIR / f"{name}.md"
        golden_path = FIXTURES_DIR / f"{name}.html"
        if not golden_path.exists() or not md_path.exists():
            continue

        golden = golden_path.read_text(encoding="utf-8")
        actual = run_cmark(args.cmark, md_path, extensions)

        # Contract normalization runs on the raw HTML so its attribute
        # regexes see original quoting, before entity replacement could
        # corrupt attribute-value boundaries.
        ser_golden = normalize_serialization(golden)
        ser_actual = normalize_serialization(actual)
        con_golden = normalize_serialization(
            normalize_contract(golden, aliases))
        con_actual = normalize_serialization(
            normalize_contract(actual, aliases))

        if actual == golden:
            verdict = "identical"
        elif ser_actual == ser_golden:
            verdict = "serialization-only"
        elif con_actual == con_golden:
            verdict = "contract-only"
        else:
            verdict = "behavioral"

        _, raw_changed = unified(ser_golden, ser_actual, name, "normalized")
        behavioral_diff, behavioral_changed = unified(
            con_golden, con_actual, name, "contract-normalized")

        results.append({
            "fixture": name,
            "extensions": extensions,
            "verdict": verdict,
            "changed_lines_serialization_normalized": raw_changed,
            "changed_lines_contract_normalized": behavioral_changed,
        })

        if out_dir:
            (out_dir / f"{name}.cmark.html").write_text(actual,
                                                        encoding="utf-8")
            if behavioral_diff:
                (out_dir / f"{name}.behavioral.diff").write_text(
                    "".join(behavioral_diff), encoding="utf-8")

    if not results:
        print("error: no golden fixture pairs found under "
              f"{FIXTURES_DIR}", file=sys.stderr)
        return 2

    width = max(len(r["fixture"]) for r in results)
    counts = {}
    for r in results:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
        print(f"{r['fixture']:<{width}}  {r['verdict']:<18}  "
              f"raw:{r['changed_lines_serialization_normalized']:>4}  "
              f"behavioral:{r['changed_lines_contract_normalized']:>4}  "
              f"(ext: {','.join(r['extensions']) or '-'})")
    print()
    total = len(results)
    for verdict in ("identical", "serialization-only", "contract-only",
                    "behavioral"):
        print(f"{verdict}: {counts.get(verdict, 0)}/{total}")

    if out_dir:
        (out_dir / "results.json").write_text(
            json.dumps({"cmark_version": version, "results": results},
                       indent=2) + "\n",
            encoding="utf-8")
        print(f"\ndiff artifacts written to {out_dir}/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
