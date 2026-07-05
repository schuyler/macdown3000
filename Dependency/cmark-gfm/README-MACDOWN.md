# Vendored cmark-gfm (MacDown)

Upstream: https://github.com/github/cmark-gfm at tag **0.29.0.gfm.13**
(BSD-2-Clause; see `COPYING`). Vendored for issue #77 — the migration off
the unmaintained hoedown parser.

## Layout

Upstream `src/` and `extensions/` are flattened into `src/` so quoted
includes resolve without CMake. `main.c` (the CLI) is omitted. The
CMake-generated headers `config.h`, `cmark-gfm_export.h` and
`cmark-gfm_version.h` are committed as generated for a static build
(`CMARK_GFM_STATIC_DEFINE`, defined by the podspec).

## MacDown additions (not upstream)

- `src/mdmark.{h,c}` — MacDown's rendering API. The node-render loop is a
  fork of upstream `src/html.c` with three contract changes (heading id
  slugs, the Prism code-block shape, the interactive task-list shape) plus
  the `<ul class="toc">` builder. When bumping upstream, re-diff against
  the new `html.c`.
- `src/mdmark_ext.c` — custom inline syntax extensions: math
  (`$$…$$`/`$…$`/`\(…\)`/`\[…\]` → MathJax delimiters, protecting TeX from
  Markdown processing) and highlight (`==text==` → `<mark>`).

## Local modifications to upstream sources

- `src/inlines.c`, `parse_inline()` `case '\\'`: inline syntax extensions
  are consulted before the core backslash-escape handler so the math
  extension can claim `\(…\)` / `\[…\]`. Extensions that do not register
  `'\'` as a special character are unaffected. Marked with a
  "MacDown patch" comment.

Everything else is byte-identical to upstream.
