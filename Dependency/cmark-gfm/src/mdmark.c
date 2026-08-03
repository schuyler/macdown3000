//
//  mdmark.c
//  MacDown 3000
//
//  MacDown's HTML renderer over cmark-gfm. The node loop is forked from
//  upstream src/html.c (0.29.0.gfm.13) with three contract changes, each
//  marked "MacDown:" below — heading id slugs, the code-block shape, and
//  the interactive task-list shape. Everything else must stay in lockstep
//  with upstream so a future cmark-gfm bump is a re-diff of html.c.
//
//  slugify() is ported byte-for-byte from hoedown_html_patch.c so heading
//  anchors survive the parser migration (issue #77); anchor links AND
//  scroll sync depend on identical slugs.
//

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "cmark_ctype.h"
#include "config.h"
#include "cmark-gfm.h"
#include "cmark-gfm-core-extensions.h"
#include "houdini.h"
#include "scanners.h"
#include "syntax_extension.h"
#include "html.h"
#include "render.h"
#include "node.h"
#include "mdmark.h"

// Implemented in mdmark_ext.c.
cmark_syntax_extension *mdmark_create_math_extension(void);
cmark_syntax_extension *mdmark_create_highlight_extension(void);
void mdmark_math_set_explicit_dollar(int explicit_dollar);

// Global checkbox index counter for interactive checkbox support (issue
// #269). NOT thread-safe; rendering is serialized (MPRenderer's queue).
static int g_checkbox_index = 0;

void mdmark_reset_checkbox_index(void) { g_checkbox_index = 0; }
int mdmark_current_checkbox_index(void) { return g_checkbox_index; }

#pragma mark - Heading slug dedup (issue #503)

// Per-render duplicate-slug dedup, matching github-slugger semantics: a
// purpose-built linear (slug,count) list, allocated via the render's
// cmark_mem so it plays nicely with the Linux test harness. Not a global —
// each render (HTML pass and TOC pass alike) owns its own stack-local
// instance, so state resets automatically per render/per pass and no
// mdmark_reset_* export is needed (contrast with g_checkbox_index above,
// whose value must cross the C<->ObjC boundary and therefore has none of
// these options).
typedef struct slug_dedup_entry {
  struct slug_dedup_entry *next;
  char  *slug;   // NUL-terminated copy, owned via d->mem
  size_t len;    // byte length excl NUL
  int    count;  // occurrences[slug]
} slug_dedup_entry;

typedef struct slug_dedup {
  cmark_mem        *mem;
  slug_dedup_entry *head;
} slug_dedup;

static void slug_dedup_init(slug_dedup *d, cmark_mem *mem) {
  d->mem = mem;
  d->head = NULL;
}

static slug_dedup_entry *slug_dedup_find(slug_dedup *d, const char *s,
                                         size_t len) {
  for (slug_dedup_entry *e = d->head; e; e = e->next)
    if (e->len == len && memcmp(e->slug, s, len) == 0)
      return e;
  return NULL;
}

static void slug_dedup_put(slug_dedup *d, const char *s, size_t len,
                           int count) {
  slug_dedup_entry *e = d->mem->calloc(1, sizeof(*e));
  e->slug = d->mem->calloc(1, len + 1);
  memcpy(e->slug, s, len);
  e->len = len;
  e->count = count;
  e->next = d->head;
  d->head = e;
}

static void slug_dedup_free(slug_dedup *d) {
  slug_dedup_entry *e = d->head;
  while (e) {
    slug_dedup_entry *n = e->next;
    d->mem->free(e->slug);
    d->mem->free(e);
    e = n;
  }
  d->head = NULL;
}

// Append the deduped form of base[0..base_len) to out, per github-slugger:
// result = base; while occurrences[result] exists, occurrences[base]++ and
// result = base + "-" + occurrences[base]; then occurrences[result] = 0.
// NULL-tolerant: without a dedup map, just pass the base slug through
// unchanged (used as a defensive fallback; state is never actually NULL on
// the current call paths).
static void slug_dedup_emit(slug_dedup *d, cmark_strbuf *out,
                            const char *base, size_t base_len) {
  if (!d) {
    cmark_strbuf_put(out, (const unsigned char *)base, (bufsize_t)base_len);
    return;
  }

  cmark_strbuf result = CMARK_BUF_INIT(d->mem);
  cmark_strbuf_put(&result, (const unsigned char *)base, (bufsize_t)base_len);

  // `base`/`base_len` are invariant across iterations, so resolve the base
  // entry once up front rather than re-searching on every pass. Entering
  // the loop means the while-condition found `result` (== `base` on the
  // first pass) already registered, so `base` itself is registered too —
  // `b` is guaranteed non-NULL whenever it is dereferenced inside the loop.
  // On a first-occurrence slug the loop never runs, so a NULL `b` (base not
  // yet registered) is never dereferenced.
  slug_dedup_entry *b = slug_dedup_find(d, base, base_len);
  while (slug_dedup_find(d, (const char *)result.ptr, result.size)) {
    int n = ++b->count;
    char suffix[16];
    int slen = snprintf(suffix, sizeof(suffix), "-%d", n);
    cmark_strbuf_clear(&result);
    cmark_strbuf_put(&result, (const unsigned char *)base, (bufsize_t)base_len);
    cmark_strbuf_put(&result, (const unsigned char *)suffix, (bufsize_t)slen);
  }

  slug_dedup_put(d, (const char *)result.ptr, result.size, 0);
  cmark_strbuf_put(out, result.ptr, result.size);
  cmark_strbuf_free(&result);
}

typedef struct {
    const mdmark_options *opts;
    slug_dedup           *dedup;  // per-render dedup state (issue #503)
} mdmark_render_state;

static void escape_html(cmark_strbuf *dest, const unsigned char *source,
                        bufsize_t length) {
  houdini_escape_html0(dest, source, length, 0);
}

#pragma mark - Slug generation

// Decode the UTF-8 codepoint starting at data[i] (i < size). Returns the
// number of bytes consumed (1-4) and stores the codepoint in *codepoint, or
// returns 0 if the sequence is malformed / truncated, in which case the
// caller should pass the raw byte through unchanged.
static size_t decode_utf8_codepoint(const uint8_t *data, size_t size, size_t i,
                                    uint32_t *codepoint) {
  uint8_t c = data[i];
  size_t len;
  uint32_t cp;

  if ((c & 0x80) == 0x00)      { cp = c;        len = 1; }
  else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; len = 2; }
  else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; len = 3; }
  else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; len = 4; }
  else return 0;

  if (i + len > size)
    return 0;

  for (size_t k = 1; k < len; k++) {
    uint8_t cc = data[i + k];
    if ((cc & 0xC0) != 0x80)
      return 0;
    cp = (cp << 6) | (cc & 0x3F);
  }

  *codepoint = cp;
  return len;
}

// Encode a codepoint <= 0x7FF (used only for lowercased Latin-1 letters) as
// two UTF-8 bytes.
static void encode_utf8_2byte(uint32_t cp, uint8_t out[2]) {
  out[0] = (uint8_t)(0xC0 | (cp >> 6));
  out[1] = (uint8_t)(0x80 | (cp & 0x3F));
}

// Build a stable text-derived slug from a heading's HTML content, matching
// GitHub's heading-anchor slug algorithm (github-slugger semantics). Ported
// verbatim from hoedown_html_patch.c (see that file's history for the full
// semantics notes): strips tags, skips entities, lowercases ASCII and
// Latin-1 uppercase, maps each space/tab to one hyphen, drops ASCII and
// selected Unicode punctuation, passes other UTF-8 through raw.
static void mdmark_slugify(cmark_strbuf *out, const unsigned char *data,
                           size_t size) {
  if (!data || !size)
    return;

  size_t start = 0, end = size;
  while (start < end && (data[start] == ' ' || data[start] == '\t' ||
                         data[start] == '\n' || data[start] == '\r'))
    start++;
  while (end > start && (data[end - 1] == ' ' || data[end - 1] == '\t' ||
                         data[end - 1] == '\n' || data[end - 1] == '\r'))
    end--;

  int in_tag = 0;

  for (size_t i = start; i < end; i++) {
    uint8_t c = data[i];

    if (in_tag) {
      if (c == '>') in_tag = 0;
      continue;
    }
    if (c == '<') {
      in_tag = 1;
      continue;
    }
    if (c == '&') {  // skip an HTML entity like &amp; / &lt; / &#39;
      while (i + 1 < end && data[i + 1] != ';')
        i++;
      i++;  // consume the ';'
      continue;
    }

    if (c >= 0x80) {
      uint32_t cp;
      size_t len = decode_utf8_codepoint(data, end, i, &cp);

      if (len == 0) {
        // Malformed / truncated sequence: pass the raw byte through.
        cmark_strbuf_putc(out, c);
        continue;
      }

      if ((cp >= 0x00A1 && cp <= 0x00BF) || cp == 0x00D7 ||
          cp == 0x00F7 || (cp >= 0x2000 && cp <= 0x206F)) {
        // Dropped punctuation/symbol codepoint: emit nothing.
      }
      else if (cp >= 0x00C0 && cp <= 0x00DE && cp != 0x00D7) {
        uint8_t enc[2];
        encode_utf8_2byte(cp + 0x20, enc);
        cmark_strbuf_put(out, enc, 2);
      }
      else {
        cmark_strbuf_put(out, data + i, (bufsize_t)len);
      }

      i += len - 1;
      continue;
    }

    if (c >= 'A' && c <= 'Z')
      c += 32;

    if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
        c == '_' || c == '-') {
      cmark_strbuf_putc(out, c);
    }
    else if (c == ' ' || c == '\t') {
      cmark_strbuf_putc(out, '-');
    }
  }
}

#pragma mark - Heading content helpers

// Render a heading node in isolation with the stock cmark HTML renderer and
// return the malloc()ed result, e.g. "<h2>Some <em>text</em></h2>\n".
// slugify() skips tags, so the wrapping <hN> is harmless for slugs; the TOC
// builder strips it to reuse the inline content.
static char *render_heading_html(cmark_node *heading) {
  return cmark_render_html(heading, CMARK_OPT_UNSAFE, NULL);
}

// Given "<hN ...>inner</hN>\n", locate the inner HTML. Returns a pointer
// into `rendered` and stores the length in *out_len.
static const char *heading_inner_html(const char *rendered, size_t *out_len) {
  const char *start = strchr(rendered, '>');
  if (!start) {
    *out_len = 0;
    return rendered;
  }
  start++;
  const char *end = strrchr(start, '<');  // "</hN>" opener
  if (!end || end < start) {
    *out_len = strlen(start);
    return start;
  }
  *out_len = (size_t)(end - start);
  return start;
}

// Emit the deduped id/href slug for `heading` into `out`. The "section"
// empty-heading fallback is applied to the base slug before dedup (issue
// #503, requirements §2.3), so repeated empty headings dedup as
// "section, section-1, section-2, ..." rather than each claiming "section".
static void put_heading_slug(cmark_strbuf *out, cmark_node *heading,
                             slug_dedup *dedup) {
  char *rendered = render_heading_html(heading);
  cmark_strbuf slug = CMARK_BUF_INIT(cmark_node_mem(heading));
  if (rendered)
    mdmark_slugify(&slug, (const unsigned char *)rendered, strlen(rendered));
  if (slug.size == 0)
    cmark_strbuf_puts(&slug, "section");
  slug_dedup_emit(dedup, out, (const char *)slug.ptr, slug.size);
  cmark_strbuf_free(&slug);
  free(rendered);
}

#pragma mark - HTML renderer (forked from upstream html.c)

static void filter_html_block(cmark_html_renderer *renderer, uint8_t *data, size_t len) {
  cmark_strbuf *html = renderer->html;
  cmark_llist *it;
  cmark_syntax_extension *ext;
  bool filtered;
  uint8_t *match;

  while (len) {
    match = (uint8_t *) memchr(data, '<', len);
    if (!match)
      break;

    if (match != data) {
      cmark_strbuf_put(html, data, (bufsize_t)(match - data));
      len -= (match - data);
      data = match;
    }

    filtered = false;
    for (it = renderer->filter_extensions; it; it = it->next) {
      ext = ((cmark_syntax_extension *) it->data);
      if (!ext->html_filter_func(ext, data, len)) {
        filtered = true;
        break;
      }
    }

    if (!filtered) {
      cmark_strbuf_putc(html, '<');
    } else {
      cmark_strbuf_puts(html, "&lt;");
    }

    ++data;
    --len;
  }

  if (len)
    cmark_strbuf_put(html, data, (bufsize_t)len);
}

static bool S_put_footnote_backref(cmark_html_renderer *renderer, cmark_strbuf *html, cmark_node *node) {
  if (renderer->written_footnote_ix >= renderer->footnote_ix)
    return false;
  renderer->written_footnote_ix = renderer->footnote_ix;
  char m[32];
  snprintf(m, sizeof(m), "%d", renderer->written_footnote_ix);

  cmark_strbuf_puts(html, "<a href=\"#fnref-");
  houdini_escape_href(html, node->as.literal.data, node->as.literal.len);
  cmark_strbuf_puts(html, "\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"");
  cmark_strbuf_puts(html, m);
  cmark_strbuf_puts(html, "\" aria-label=\"Back to reference ");
  cmark_strbuf_puts(html, m);
  cmark_strbuf_puts(html, "\">↩</a>");

  if (node->footnote.def_count > 1)
  {
    for(int i = 2; i <= node->footnote.def_count; i++) {
      char n[32];
      snprintf(n, sizeof(n), "%d", i);

      cmark_strbuf_puts(html, " <a href=\"#fnref-");
      houdini_escape_href(html, node->as.literal.data, node->as.literal.len);
      cmark_strbuf_puts(html, "-");
      cmark_strbuf_puts(html, n);
      cmark_strbuf_puts(html, "\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"");
      cmark_strbuf_puts(html, m);
      cmark_strbuf_puts(html, "-");
      cmark_strbuf_puts(html, n);
      cmark_strbuf_puts(html, "\" aria-label=\"Back to reference ");
      cmark_strbuf_puts(html, m);
      cmark_strbuf_puts(html, "-");
      cmark_strbuf_puts(html, n);
      cmark_strbuf_puts(html, "\">↩<sup class=\"footnote-ref\">");
      cmark_strbuf_puts(html, n);
      cmark_strbuf_puts(html, "</sup></a>");
    }
  }

  return true;
}

// MacDown: true when this list item was claimed by the tasklist extension.
static bool S_is_tasklist_item(cmark_node *node) {
  return node->type == CMARK_NODE_ITEM && node->extension &&
         strcmp(cmark_node_get_type_string(node), "tasklist") == 0;
}

static int S_render_node(cmark_html_renderer *renderer, cmark_node *node,
                         cmark_event_type ev_type, int options) {
  cmark_node *parent;
  cmark_node *grandparent;
  cmark_strbuf *html = renderer->html;
  cmark_llist *it;
  cmark_syntax_extension *ext;
  char start_heading[] = "<h0";
  char end_heading[] = "</h0";
  bool tight;
  bool filtered;
  char buffer[BUFFER_SIZE];
  mdmark_render_state *state = (mdmark_render_state *)renderer->opaque;

  bool entering = (ev_type == CMARK_EVENT_ENTER);

  if (renderer->plain == node) { // back at original node
    renderer->plain = NULL;
  }

  if (renderer->plain != NULL) {
    switch (node->type) {
    case CMARK_NODE_TEXT:
    case CMARK_NODE_CODE:
    case CMARK_NODE_HTML_INLINE:
      escape_html(html, node->as.literal.data, node->as.literal.len);
      break;

    case CMARK_NODE_LINEBREAK:
    case CMARK_NODE_SOFTBREAK:
      cmark_strbuf_putc(html, ' ');
      break;

    default:
      break;
    }
    return 1;
  }

  // MacDown: render task-list items with the interactive-checkbox contract
  // (tasklist.js keys on .task-list-item / data-checkbox-index; issue
  // #269). Intercepted before the generic extension dispatch below, which
  // would otherwise emit cmark's own <li><input disabled> shape.
  if (S_is_tasklist_item(node)) {
    if (entering) {
      cmark_html_render_cr(html);
      cmark_strbuf_puts(html, "<li class=\"task-list-item\"");
      cmark_html_render_sourcepos(node, html, options);
      cmark_strbuf_putc(html, '>');
      if (node->as.list.checked) {
        snprintf(buffer, BUFFER_SIZE,
                 "<input type=\"checkbox\" checked data-checkbox-index=\"%d\"> ",
                 g_checkbox_index++);
      } else {
        snprintf(buffer, BUFFER_SIZE,
                 "<input type=\"checkbox\" data-checkbox-index=\"%d\"> ",
                 g_checkbox_index++);
      }
      cmark_strbuf_puts(html, buffer);
    } else {
      cmark_strbuf_puts(html, "</li>\n");
    }
    return 1;
  }

  if (node->extension && node->extension->html_render_func) {
    node->extension->html_render_func(node->extension, renderer, node, ev_type, options);
    return 1;
  }

  switch (node->type) {
  case CMARK_NODE_DOCUMENT:
    break;

  case CMARK_NODE_BLOCK_QUOTE:
    if (entering) {
      cmark_html_render_cr(html);
      cmark_strbuf_puts(html, "<blockquote");
      cmark_html_render_sourcepos(node, html, options);
      cmark_strbuf_puts(html, ">\n");
    } else {
      cmark_html_render_cr(html);
      cmark_strbuf_puts(html, "</blockquote>\n");
    }
    break;

  case CMARK_NODE_LIST: {
    cmark_list_type list_type = node->as.list.list_type;
    int start = node->as.list.start;

    if (entering) {
      cmark_html_render_cr(html);
      if (list_type == CMARK_BULLET_LIST) {
        cmark_strbuf_puts(html, "<ul");
        cmark_html_render_sourcepos(node, html, options);
        cmark_strbuf_puts(html, ">\n");
      } else if (start == 1) {
        cmark_strbuf_puts(html, "<ol");
        cmark_html_render_sourcepos(node, html, options);
        cmark_strbuf_puts(html, ">\n");
      } else {
        snprintf(buffer, BUFFER_SIZE, "<ol start=\"%d\"", start);
        cmark_strbuf_puts(html, buffer);
        cmark_html_render_sourcepos(node, html, options);
        cmark_strbuf_puts(html, ">\n");
      }
    } else {
      cmark_strbuf_puts(html,
                        list_type == CMARK_BULLET_LIST ? "</ul>\n" : "</ol>\n");
    }
    break;
  }

  case CMARK_NODE_ITEM:
    if (entering) {
      cmark_html_render_cr(html);
      cmark_strbuf_puts(html, "<li");
      cmark_html_render_sourcepos(node, html, options);
      cmark_strbuf_putc(html, '>');
    } else {
      cmark_strbuf_puts(html, "</li>\n");
    }
    break;

  case CMARK_NODE_HEADING:
    if (entering) {
      cmark_html_render_cr(html);
      start_heading[2] = (char)('0' + node->as.heading.level);
      cmark_strbuf_puts(html, start_heading);
      cmark_html_render_sourcepos(node, html, options);
      // MacDown: always emit a text-derived id so [link](#section-name)
      // navigation, TOC anchors and scroll sync work (hoedown_html_patch's
      // rndr_header contract).
      cmark_strbuf_puts(html, " id=\"");
      put_heading_slug(html, node, state->dedup);
      cmark_strbuf_puts(html, "\">");
    } else {
      end_heading[3] = (char)('0' + node->as.heading.level);
      cmark_strbuf_puts(html, end_heading);
      cmark_strbuf_puts(html, ">\n");
    }
    break;

  case CMARK_NODE_CODE_BLOCK: {
    // MacDown: emit the Prism-compatible code-block contract from
    // hoedown_html_patch's rndr_blockcode: a <div> wrapper, optional
    // line-numbers class and data-information accessory (info string split
    // on ':'), a language callback for Prism alias mapping / collection,
    // "language-none" for plain fences, and the trailing newline trimmed
    // so Prism does not add a blank line.
    cmark_html_render_cr(html);

    const unsigned char *info = node->as.code.info.data;
    bufsize_t info_len = node->as.code.info.len;
    const unsigned char *lang = info;
    bufsize_t lang_len = info_len;
    const unsigned char *meta = NULL;
    bufsize_t meta_len = 0;
    int html_flags = state ? state->opts->html_flags : 0;

    if (info_len && (html_flags & MDMARK_HTML_BLOCKCODE_INFORMATION)) {
      for (bufsize_t i = 0; i < info_len; i++) {
        if (info[i] == ':') {
          lang_len = i;
          meta = info + i + 1;
          meta_len = info_len - i - 1;
          break;
        }
      }
    }

    char *mapped = NULL;
    if (lang_len && state && state->opts->language_callback) {
      mapped = state->opts->language_callback(
          (const char *)lang, (size_t)lang_len,
          state->opts->language_callback_owner);
      if (mapped) {
        lang = (const unsigned char *)mapped;
        lang_len = (bufsize_t)strlen(mapped);
      }
    }

    cmark_strbuf_puts(html, "<div><pre");
    if (html_flags & MDMARK_HTML_BLOCKCODE_LINE_NUMBERS)
      cmark_strbuf_puts(html, " class=\"line-numbers\"");
    if (meta_len) {
      cmark_strbuf_puts(html, " data-information=\"");
      escape_html(html, meta, meta_len);
      cmark_strbuf_putc(html, '"');
    }
    cmark_html_render_sourcepos(node, html, options);
    cmark_strbuf_puts(html, "><code class=\"language-");
    if (lang_len)
      escape_html(html, lang, lang_len);
    else
      cmark_strbuf_puts(html, "none");
    cmark_strbuf_puts(html, "\">");

    bufsize_t literal_len = node->as.code.literal.len;
    if (literal_len > 0 && node->as.code.literal.data[literal_len - 1] == '\n')
      literal_len--;
    escape_html(html, node->as.code.literal.data, literal_len);

    cmark_strbuf_puts(html, "</code></pre></div>\n");
    free(mapped);
    break;
  }

  case CMARK_NODE_HTML_BLOCK:
    cmark_html_render_cr(html);
    if (!(options & CMARK_OPT_UNSAFE)) {
      cmark_strbuf_puts(html, "<!-- raw HTML omitted -->");
    } else if (renderer->filter_extensions) {
      filter_html_block(renderer, node->as.literal.data, node->as.literal.len);
    } else {
      cmark_strbuf_put(html, node->as.literal.data, node->as.literal.len);
    }
    cmark_html_render_cr(html);
    break;

  case CMARK_NODE_CUSTOM_BLOCK:
    cmark_html_render_cr(html);
    if (entering) {
      cmark_strbuf_put(html, node->as.custom.on_enter.data,
                       node->as.custom.on_enter.len);
    } else {
      cmark_strbuf_put(html, node->as.custom.on_exit.data,
                       node->as.custom.on_exit.len);
    }
    cmark_html_render_cr(html);
    break;

  case CMARK_NODE_THEMATIC_BREAK:
    cmark_html_render_cr(html);
    cmark_strbuf_puts(html, "<hr");
    cmark_html_render_sourcepos(node, html, options);
    cmark_strbuf_puts(html, " />\n");
    break;

  case CMARK_NODE_PARAGRAPH:
    parent = cmark_node_parent(node);
    grandparent = cmark_node_parent(parent);
    if (grandparent != NULL && grandparent->type == CMARK_NODE_LIST) {
      tight = grandparent->as.list.tight;
    } else {
      tight = false;
    }
    if (!tight) {
      if (entering) {
        cmark_html_render_cr(html);
        cmark_strbuf_puts(html, "<p");
        cmark_html_render_sourcepos(node, html, options);
        cmark_strbuf_putc(html, '>');
      } else {
        if (parent->type == CMARK_NODE_FOOTNOTE_DEFINITION && node->next == NULL) {
          cmark_strbuf_putc(html, ' ');
          S_put_footnote_backref(renderer, html, parent);
        }
        cmark_strbuf_puts(html, "</p>\n");
      }
    }
    break;

  case CMARK_NODE_TEXT:
    escape_html(html, node->as.literal.data, node->as.literal.len);
    break;

  case CMARK_NODE_LINEBREAK:
    cmark_strbuf_puts(html, "<br />\n");
    break;

  case CMARK_NODE_SOFTBREAK:
    if (options & CMARK_OPT_HARDBREAKS) {
      cmark_strbuf_puts(html, "<br />\n");
    } else if (options & CMARK_OPT_NOBREAKS) {
      cmark_strbuf_putc(html, ' ');
    } else {
      cmark_strbuf_putc(html, '\n');
    }
    break;

  case CMARK_NODE_CODE:
    cmark_strbuf_puts(html, "<code>");
    escape_html(html, node->as.literal.data, node->as.literal.len);
    cmark_strbuf_puts(html, "</code>");
    break;

  case CMARK_NODE_HTML_INLINE:
    if (!(options & CMARK_OPT_UNSAFE)) {
      cmark_strbuf_puts(html, "<!-- raw HTML omitted -->");
    } else {
      filtered = false;
      for (it = renderer->filter_extensions; it; it = it->next) {
        ext = (cmark_syntax_extension *) it->data;
        if (!ext->html_filter_func(ext, node->as.literal.data, node->as.literal.len)) {
          filtered = true;
          break;
        }
      }
      if (!filtered) {
        cmark_strbuf_put(html, node->as.literal.data, node->as.literal.len);
      } else {
        cmark_strbuf_puts(html, "&lt;");
        cmark_strbuf_put(html, node->as.literal.data + 1, node->as.literal.len - 1);
      }
    }
    break;

  case CMARK_NODE_CUSTOM_INLINE:
    if (entering) {
      cmark_strbuf_put(html, node->as.custom.on_enter.data,
                       node->as.custom.on_enter.len);
    } else {
      cmark_strbuf_put(html, node->as.custom.on_exit.data,
                       node->as.custom.on_exit.len);
    }
    break;

  case CMARK_NODE_STRONG:
    if (node->parent == NULL || node->parent->type != CMARK_NODE_STRONG) {
      if (entering) {
        cmark_strbuf_puts(html, "<strong>");
      } else {
        cmark_strbuf_puts(html, "</strong>");
      }
    }
    break;

  case CMARK_NODE_EMPH:
    if (entering) {
      cmark_strbuf_puts(html, "<em>");
    } else {
      cmark_strbuf_puts(html, "</em>");
    }
    break;

  case CMARK_NODE_LINK:
    if (entering) {
      cmark_strbuf_puts(html, "<a href=\"");
      if ((options & CMARK_OPT_UNSAFE) ||
            !(scan_dangerous_url(&node->as.link.url, 0))) {
        houdini_escape_href(html, node->as.link.url.data,
                            node->as.link.url.len);
      }
      if (node->as.link.title.len) {
        cmark_strbuf_puts(html, "\" title=\"");
        escape_html(html, node->as.link.title.data, node->as.link.title.len);
      }
      cmark_strbuf_puts(html, "\">");
    } else {
      cmark_strbuf_puts(html, "</a>");
    }
    break;

  case CMARK_NODE_IMAGE:
    if (entering) {
      cmark_strbuf_puts(html, "<img src=\"");
      if ((options & CMARK_OPT_UNSAFE) ||
            !(scan_dangerous_url(&node->as.link.url, 0))) {
        houdini_escape_href(html, node->as.link.url.data,
                            node->as.link.url.len);
      }
      cmark_strbuf_puts(html, "\" alt=\"");
      renderer->plain = node;
    } else {
      if (node->as.link.title.len) {
        cmark_strbuf_puts(html, "\" title=\"");
        escape_html(html, node->as.link.title.data, node->as.link.title.len);
      }

      cmark_strbuf_puts(html, "\" />");
    }
    break;

  case CMARK_NODE_FOOTNOTE_DEFINITION:
    if (entering) {
      if (renderer->footnote_ix == 0) {
        cmark_strbuf_puts(html, "<section class=\"footnotes\" data-footnotes>\n<ol>\n");
      }
      ++renderer->footnote_ix;

      cmark_strbuf_puts(html, "<li id=\"fn-");
      houdini_escape_href(html, node->as.literal.data, node->as.literal.len);
      cmark_strbuf_puts(html, "\">\n");
    } else {
      if (S_put_footnote_backref(renderer, html, node)) {
        cmark_strbuf_putc(html, '\n');
      }
      cmark_strbuf_puts(html, "</li>\n");
    }
    break;

  case CMARK_NODE_FOOTNOTE_REFERENCE:
    if (entering) {
      cmark_strbuf_puts(html, "<sup class=\"footnote-ref\"><a href=\"#fn-");
      houdini_escape_href(html, node->parent_footnote_def->as.literal.data, node->parent_footnote_def->as.literal.len);
      cmark_strbuf_puts(html, "\" id=\"fnref-");
      houdini_escape_href(html, node->parent_footnote_def->as.literal.data, node->parent_footnote_def->as.literal.len);

      if (node->footnote.ref_ix > 1) {
        char n[32];
        snprintf(n, sizeof(n), "%d", node->footnote.ref_ix);
        cmark_strbuf_puts(html, "-");
        cmark_strbuf_puts(html, n);
      }

      cmark_strbuf_puts(html, "\" data-footnote-ref>");
      houdini_escape_href(html, node->as.literal.data, node->as.literal.len);
      cmark_strbuf_puts(html, "</a></sup>");
    }
    break;

  default:
    assert(false);
    break;
  }

  return 1;
}

static char *mdmark_render_html_ast(cmark_node *root, int cmark_options,
                                    const mdmark_options *opts) {
  char *result;
  cmark_mem *mem = cmark_node_mem(root);
  cmark_strbuf html = CMARK_BUF_INIT(mem);
  cmark_event_type ev_type;
  cmark_node *cur;
  slug_dedup dedup;
  slug_dedup_init(&dedup, mem);
  mdmark_render_state state = {opts, &dedup};
  cmark_html_renderer renderer = {&html, NULL, NULL, 0, 0, &state};
  cmark_iter *iter = cmark_iter_new(root);

  while ((ev_type = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    cur = cmark_iter_get_node(iter);
    S_render_node(&renderer, cur, ev_type, cmark_options);
  }

  if (renderer.footnote_ix) {
    cmark_strbuf_puts(&html, "</ol>\n</section>\n");
  }

  result = (char *)cmark_strbuf_detach(&html);

  cmark_llist_free(mem, renderer.filter_extensions);

  cmark_iter_free(iter);
  slug_dedup_free(&dedup);
  return result;
}

#pragma mark - Parsing

static int mdmark_cmark_options(const mdmark_options *opts) {
  // Raw HTML passthrough is MacDown's (and hoedown's) default behavior, so
  // UNSAFE is always on and tagfilter stays off (issue #77 decision D-9).
  int cmark_options = CMARK_OPT_UNSAFE;
  if (opts->extensions & MDMARK_EXT_SMARTYPANTS)
    cmark_options |= CMARK_OPT_SMART;
  if (opts->extensions & MDMARK_EXT_FOOTNOTES)
    cmark_options |= CMARK_OPT_FOOTNOTES;
  if (opts->html_flags & MDMARK_HTML_HARD_WRAP)
    cmark_options |= CMARK_OPT_HARDBREAKS;
  return cmark_options;
}

static void mdmark_attach_core_extension(cmark_parser *parser,
                                         const char *name) {
  cmark_syntax_extension *ext = cmark_find_syntax_extension(name);
  if (ext)
    cmark_parser_attach_syntax_extension(parser, ext);
}

static cmark_parser *mdmark_parser_new(const mdmark_options *opts) {
  cmark_gfm_core_extensions_ensure_registered();

  cmark_parser *parser = cmark_parser_new(mdmark_cmark_options(opts));

  if (opts->extensions & MDMARK_EXT_TABLES)
    mdmark_attach_core_extension(parser, "table");
  if (opts->extensions & MDMARK_EXT_AUTOLINK)
    mdmark_attach_core_extension(parser, "autolink");
  if (opts->extensions & MDMARK_EXT_STRIKETHROUGH)
    mdmark_attach_core_extension(parser, "strikethrough");
  if (opts->html_flags & MDMARK_HTML_USE_TASK_LIST)
    mdmark_attach_core_extension(parser, "tasklist");

  if (opts->extensions & MDMARK_EXT_HIGHLIGHT) {
    static cmark_syntax_extension *highlight = NULL;
    if (!highlight)
      highlight = mdmark_create_highlight_extension();
    cmark_parser_attach_syntax_extension(parser, highlight);
  }
  if (opts->extensions & MDMARK_EXT_MATH) {
    static cmark_syntax_extension *math = NULL;
    if (!math)
      math = mdmark_create_math_extension();
    mdmark_math_set_explicit_dollar(
        (opts->extensions & MDMARK_EXT_MATH_EXPLICIT) != 0);
    cmark_parser_attach_syntax_extension(parser, math);
  }

  return parser;
}

static cmark_node *mdmark_parse(const char *markdown, size_t length,
                                const mdmark_options *opts,
                                cmark_parser **out_parser) {
  cmark_parser *parser = mdmark_parser_new(opts);
  cmark_parser_feed(parser, markdown, length);
  cmark_node *doc = cmark_parser_finish(parser);
  *out_parser = parser;
  return doc;
}

char *mdmark_render_html(const char *markdown, size_t length,
                         const mdmark_options *options) {
  cmark_parser *parser = NULL;
  cmark_node *doc = mdmark_parse(markdown, length, options, &parser);
  char *result = mdmark_render_html_ast(
      doc, mdmark_cmark_options(options), options);
  cmark_node_free(doc);
  cmark_parser_free(parser);
  return result;
}

#pragma mark - Table of contents

// Reproduces hoedown's patched TOC renderer output: the outermost list is
// <ul class="toc">, entries are <a href="#slug">inline content</a>, levels
// are offset so the first heading in the document is level 1, and the
// trailing close-out repeats "</li>\n</ul>\n" (hoedown's toc_finalize).
char *mdmark_render_toc(const char *markdown, size_t length,
                        const mdmark_options *options, int toc_level) {
  cmark_parser *parser = NULL;
  cmark_node *doc = mdmark_parse(markdown, length, options, &parser);

  cmark_mem *mem = cmark_node_mem(doc);
  cmark_strbuf ob = CMARK_BUF_INIT(mem);

  int current_level = 0;
  int level_offset = 0;

  slug_dedup dedup;
  slug_dedup_init(&dedup, mem);

  cmark_iter *iter = cmark_iter_new(doc);
  cmark_event_type ev_type;
  while ((ev_type = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    cmark_node *node = cmark_iter_get_node(iter);
    if (ev_type != CMARK_EVENT_ENTER || node->type != CMARK_NODE_HEADING)
      continue;

    // MacDown: advance the dedup counter for EVERY heading, in document
    // order, before the toc_level filter below -- including headings deeper
    // than toc_level that never make it into the list. GitHub assigns an id
    // to (and dedups across) every heading; if a skipped deep heading isn't
    // counted here, a shallower heading sharing its base slug would get a
    // dedup suffix that disagrees with the id the HTML pass gave it (issue
    // #503).
    cmark_strbuf slug = CMARK_BUF_INIT(mem);
    put_heading_slug(&slug, node, &dedup);

    int level = node->as.heading.level;
    if (level > toc_level) {
      cmark_strbuf_free(&slug);
      continue;
    }

    // Set the level offset if this is the first header of the document.
    if (current_level == 0)
      level_offset = level - 1;
    level -= level_offset;

    if (level > current_level) {
      while (level > current_level) {
        if (current_level == 0)
          cmark_strbuf_puts(&ob, "<ul class=\"toc\">\n<li>\n");
        else
          cmark_strbuf_puts(&ob, "<ul>\n<li>\n");
        current_level++;
      }
    } else if (level < current_level) {
      cmark_strbuf_puts(&ob, "</li>\n");
      while (level < current_level) {
        cmark_strbuf_puts(&ob, "</ul>\n</li>\n");
        current_level--;
      }
      cmark_strbuf_puts(&ob, "<li>\n");
    } else {
      cmark_strbuf_puts(&ob, "</li>\n<li>\n");
    }

    cmark_strbuf_puts(&ob, "<a href=\"#");
    cmark_strbuf_put(&ob, slug.ptr, slug.size);  // reuse the precomputed slug
    cmark_strbuf_puts(&ob, "\">");
    cmark_strbuf_free(&slug);

    char *rendered = render_heading_html(node);
    if (rendered) {
      size_t inner_len = 0;
      const char *inner = heading_inner_html(rendered, &inner_len);
      cmark_strbuf_put(&ob, (const unsigned char *)inner,
                       (bufsize_t)inner_len);
      free(rendered);
    }
    cmark_strbuf_puts(&ob, "</a>\n");
  }
  cmark_iter_free(iter);
  slug_dedup_free(&dedup);

  while (current_level > 0) {
    cmark_strbuf_puts(&ob, "</li>\n</ul>\n");
    current_level--;
  }

  char *result = (char *)cmark_strbuf_detach(&ob);
  cmark_node_free(doc);
  cmark_parser_free(parser);
  return result;
}
