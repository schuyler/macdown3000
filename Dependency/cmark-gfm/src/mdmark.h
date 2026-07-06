//
//  mdmark.h
//  MacDown 3000
//
//  MacDown's rendering interface over cmark-gfm. Replaces the hoedown
//  pipeline (hoedown_html_patch.c) while preserving its HTML contract:
//
//  - headings carry github-slugger-compatible id attributes
//  - fenced code blocks render as
//      <div><pre [class="line-numbers"] [data-information="..."]
//      ><code class="language-<lang-or-'none'>">...</code></pre></div>
//    with the trailing newline trimmed and the language optionally rewritten
//    through a caller-supplied callback (Prism alias mapping / collection)
//  - task-list items render as
//      <li class="task-list-item"><input type="checkbox" [checked]
//      data-checkbox-index="N"> ...
//    for the interactive-checkbox bridge (tasklist.js, issue #269)
//  - a table-of-contents renderer emits the <ul class="toc"> shape the
//    [TOC] splice in MPRenderer expects
//
//  Custom syntax beyond GFM:
//  - MDMARK_EXT_MATH protects TeX math from Markdown processing:
//    $$...$$ / \[...\] render as \[...\], \(...\) as \(...\), and, with
//    MDMARK_EXT_MATH_EXPLICIT, $...$ as \(...\) (MathJax delimiters).
//  - MDMARK_EXT_HIGHLIGHT renders ==text== as <mark>text</mark>.
//

#ifndef MDMARK_H
#define MDMARK_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Extension flags (parser behavior). Replaces HOEDOWN_EXT_*.
// Fenced code, which hoedown gated behind HOEDOWN_EXT_FENCED_CODE, is part
// of CommonMark and always on.
typedef enum {
    MDMARK_EXT_TABLES        = 1 << 0,
    MDMARK_EXT_AUTOLINK      = 1 << 1,
    MDMARK_EXT_STRIKETHROUGH = 1 << 2,
    MDMARK_EXT_FOOTNOTES     = 1 << 3,
    MDMARK_EXT_HIGHLIGHT     = 1 << 4,
    MDMARK_EXT_MATH          = 1 << 5,
    MDMARK_EXT_MATH_EXPLICIT = 1 << 6,
    MDMARK_EXT_SMARTYPANTS   = 1 << 7,
} mdmark_extensions;

// HTML renderer flags. Replaces the custom HOEDOWN_HTML_* bits.
typedef enum {
    MDMARK_HTML_USE_TASK_LIST          = 1 << 0,
    MDMARK_HTML_BLOCKCODE_LINE_NUMBERS = 1 << 1,
    MDMARK_HTML_BLOCKCODE_INFORMATION  = 1 << 2,
    MDMARK_HTML_HARD_WRAP              = 1 << 3,
} mdmark_html_flags;

// Optional code-fence language rewrite hook. Receives the fence's language
// token; returns a malloc()ed replacement string (the caller frees it), or
// NULL to keep the original. MacDown uses this for Prism alias resolution
// and per-document language collection.
typedef char *(*mdmark_language_callback)(
    const char *language, size_t length, void *owner);

typedef struct {
    int extensions;      // mdmark_extensions bits
    int html_flags;      // mdmark_html_flags bits
    mdmark_language_callback language_callback;
    void *language_callback_owner;
} mdmark_options;

// Render markdown to an HTML fragment under MacDown's renderer contract.
// Returns a malloc()ed NUL-terminated UTF-8 string; the caller frees it.
char *mdmark_render_html(const char *markdown, size_t length,
                         const mdmark_options *options);

// Render a nested <ul class="toc"> for headings h1..toc_level, matching the
// shape hoedown's patched TOC renderer produced. Returns a malloc()ed
// string (possibly empty); the caller frees it.
char *mdmark_render_toc(const char *markdown, size_t length,
                        const mdmark_options *options, int toc_level);

// The interactive-checkbox index counter is global and NOT thread-safe;
// rendering must stay serialized (MPRenderer uses a serial queue).
void mdmark_reset_checkbox_index(void);
int mdmark_current_checkbox_index(void);

#ifdef __cplusplus
}
#endif

#endif
