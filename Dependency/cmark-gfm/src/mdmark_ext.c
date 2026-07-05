//
//  mdmark_ext.c
//  MacDown 3000
//
//  Custom cmark-gfm syntax extensions replacing hoedown extensions that
//  have no GFM equivalent (issue #77 decision D-9):
//
//  - math: protects TeX math from Markdown inline processing and emits
//    MathJax delimiters, matching hoedown's HOEDOWN_EXT_MATH behavior.
//      $$...$$ and \[...\]  ->  \[...\]   (display)
//      \(...\)              ->  \(...\)   (inline)
//      $...$                ->  \(...\)   (inline; only when the explicit
//                                          single-dollar mode is on, i.e.
//                                          HOEDOWN_EXT_MATH_EXPLICIT)
//    The \(...\) / \[...\] forms rely on the MacDown patch to inlines.c
//    that lets extensions claim '\\' before the core backslash-escape
//    handler (see README-MACDOWN.md).
//
//  - highlight: ==text== -> <mark>text</mark>, matching
//    HOEDOWN_EXT_HIGHLIGHT. Modeled on the bundled strikethrough
//    extension's delimiter handling so inline nesting works.
//

#include <string.h>
#include "cmark-gfm.h"
#include "cmark-gfm-extension_api.h"
#include "parser.h"
#include "render.h"
#include "html.h"
#include "chunk.h"
#include "houdini.h"
#include "mdmark.h"

cmark_syntax_extension *mdmark_create_math_extension(void);
cmark_syntax_extension *mdmark_create_highlight_extension(void);
void mdmark_math_set_explicit_dollar(int explicit_dollar);

#pragma mark - Math

static cmark_node_type CMARK_NODE_MATH_INLINE;
static cmark_node_type CMARK_NODE_MATH_DISPLAY;

// Whether $...$ (single dollar) is parsed as inline math. Set per render
// from MDMARK_EXT_MATH_EXPLICIT; rendering is serialized, so a file-static
// mirrors the existing checkbox-counter convention.
static int g_math_explicit_dollar = 0;

void mdmark_math_set_explicit_dollar(int explicit_dollar) {
  g_math_explicit_dollar = explicit_dollar;
}

static const char *math_get_type_string(cmark_syntax_extension *extension,
                                        cmark_node *node) {
  if (node->type == CMARK_NODE_MATH_INLINE)
    return "math_inline";
  if (node->type == CMARK_NODE_MATH_DISPLAY)
    return "math_display";
  return "<unknown>";
}

static int math_can_contain(cmark_syntax_extension *extension,
                            cmark_node *node, cmark_node_type child_type) {
  if (node->type != CMARK_NODE_MATH_INLINE &&
      node->type != CMARK_NODE_MATH_DISPLAY)
    return false;
  return child_type == CMARK_NODE_TEXT;
}

static cmark_node *math_make_node(cmark_syntax_extension *self,
                                  cmark_parser *parser,
                                  cmark_inline_parser *inline_parser,
                                  int display, const unsigned char *content,
                                  int content_len, int delims) {
  cmark_node *math = cmark_node_new_with_mem(
      display ? CMARK_NODE_MATH_DISPLAY : CMARK_NODE_MATH_INLINE,
      parser->mem);
  cmark_node_set_syntax_extension(math, self);
  math->start_line = math->end_line =
      cmark_inline_parser_get_line(inline_parser);
  math->start_column = cmark_inline_parser_get_column(inline_parser) - delims;

  cmark_node *text = cmark_node_new_with_mem(CMARK_NODE_TEXT, parser->mem);
  cmark_chunk chunk = cmark_chunk_dup(
      &(cmark_chunk){(unsigned char *)content, (bufsize_t)content_len, 0},
      0, content_len);
  text->as.literal = chunk;
  text->start_line = text->end_line = math->start_line;
  cmark_node_append_child(math, text);
  return math;
}

// $...$ / $$...$$ handler. `offset` sits on the first '$'.
static cmark_node *math_match_dollar(cmark_syntax_extension *self,
                                     cmark_parser *parser,
                                     cmark_inline_parser *inline_parser) {
  cmark_chunk *chunk = cmark_inline_parser_get_chunk(inline_parser);
  const unsigned char *data = chunk->data;
  int len = chunk->len;
  int offset = cmark_inline_parser_get_offset(inline_parser);

  int delims = 1;
  if (offset + 1 < len && data[offset + 1] == '$')
    delims = 2;

  if (delims == 1 && !g_math_explicit_dollar)
    return NULL;

  int start = offset + delims;
  int i = start;
  int close = -1;
  while (i < len) {
    if (data[i] == '\\' && i + 1 < len) {
      i += 2;
      continue;
    }
    if (data[i] == '$' &&
        (delims == 1 || (i + 1 < len && data[i + 1] == '$'))) {
      close = i;
      break;
    }
    i++;
  }

  if (close < 0 || close == start)
    return NULL;

  cmark_inline_parser_set_offset(inline_parser, close + delims);
  return math_make_node(self, parser, inline_parser, delims == 2,
                        data + start, close - start, delims);
}

// \(...\) / \[...\] handler. `offset` sits on the backslash.
static cmark_node *math_match_backslash(cmark_syntax_extension *self,
                                        cmark_parser *parser,
                                        cmark_inline_parser *inline_parser) {
  cmark_chunk *chunk = cmark_inline_parser_get_chunk(inline_parser);
  const unsigned char *data = chunk->data;
  int len = chunk->len;
  int offset = cmark_inline_parser_get_offset(inline_parser);

  if (offset + 1 >= len)
    return NULL;

  unsigned char open = data[offset + 1];
  if (open != '(' && open != '[')
    return NULL;
  unsigned char close_char = (open == '(') ? ')' : ']';

  int start = offset + 2;
  int i = start;
  int close = -1;
  while (i + 1 < len) {
    if (data[i] == '\\' && data[i + 1] == close_char) {
      close = i;
      break;
    }
    i++;
  }

  if (close < 0 || close == start)
    return NULL;

  cmark_inline_parser_set_offset(inline_parser, close + 2);
  return math_make_node(self, parser, inline_parser, open == '[',
                        data + start, close - start, 2);
}

static cmark_node *math_match(cmark_syntax_extension *self,
                              cmark_parser *parser, cmark_node *parent,
                              unsigned char character,
                              cmark_inline_parser *inline_parser) {
  if (character == '$')
    return math_match_dollar(self, parser, inline_parser);
  if (character == '\\')
    return math_match_backslash(self, parser, inline_parser);
  return NULL;
}

static void math_html_render(cmark_syntax_extension *extension,
                             cmark_html_renderer *renderer, cmark_node *node,
                             cmark_event_type ev_type, int options) {
  bool entering = (ev_type == CMARK_EVENT_ENTER);
  bool display = (node->type == CMARK_NODE_MATH_DISPLAY);
  if (entering) {
    cmark_strbuf_puts(renderer->html, display ? "\\[" : "\\(");
  } else {
    cmark_strbuf_puts(renderer->html, display ? "\\]" : "\\)");
  }
}

static void math_commonmark_render(cmark_syntax_extension *extension,
                                   cmark_renderer *renderer, cmark_node *node,
                                   cmark_event_type ev_type, int options) {
  bool entering = (ev_type == CMARK_EVENT_ENTER);
  bool display = (node->type == CMARK_NODE_MATH_DISPLAY);
  renderer->out(renderer, node, display ? "$$" : "$", false, LITERAL);
  (void)entering;
}

cmark_syntax_extension *mdmark_create_math_extension(void) {
  cmark_syntax_extension *ext = cmark_syntax_extension_new("mdmark_math");
  cmark_llist *special_chars = NULL;

  cmark_syntax_extension_set_get_type_string_func(ext, math_get_type_string);
  cmark_syntax_extension_set_can_contain_func(ext, math_can_contain);
  cmark_syntax_extension_set_html_render_func(ext, math_html_render);
  cmark_syntax_extension_set_commonmark_render_func(ext,
                                                    math_commonmark_render);
  cmark_syntax_extension_set_plaintext_render_func(ext,
                                                   math_commonmark_render);
  CMARK_NODE_MATH_INLINE = cmark_syntax_extension_add_node(1);
  CMARK_NODE_MATH_DISPLAY = cmark_syntax_extension_add_node(1);

  cmark_syntax_extension_set_match_inline_func(ext, math_match);

  cmark_mem *mem = cmark_get_default_mem_allocator();
  special_chars = cmark_llist_append(mem, special_chars, (void *)'$');
  special_chars = cmark_llist_append(mem, special_chars, (void *)'\\');
  cmark_syntax_extension_set_special_inline_chars(ext, special_chars);

  return ext;
}

#pragma mark - Highlight (==mark==)

static cmark_node_type CMARK_NODE_HIGHLIGHT;

static cmark_node *highlight_match(cmark_syntax_extension *self,
                                   cmark_parser *parser, cmark_node *parent,
                                   unsigned char character,
                                   cmark_inline_parser *inline_parser) {
  cmark_node *res = NULL;
  int left_flanking, right_flanking, punct_before, punct_after, delims;
  char buffer[101];

  if (character != '=')
    return NULL;

  delims = cmark_inline_parser_scan_delimiters(
      inline_parser, sizeof(buffer) - 1, '=',
      &left_flanking,
      &right_flanking, &punct_before, &punct_after);

  memset(buffer, '=', delims);
  buffer[delims] = 0;

  res = cmark_node_new_with_mem(CMARK_NODE_TEXT, parser->mem);
  cmark_node_set_literal(res, buffer);
  res->start_line = res->end_line = cmark_inline_parser_get_line(inline_parser);
  res->start_column = cmark_inline_parser_get_column(inline_parser) - delims;

  if ((left_flanking || right_flanking) && delims == 2) {
    cmark_inline_parser_push_delimiter(inline_parser, character, left_flanking,
                                       right_flanking, res);
  }

  return res;
}

static delimiter *highlight_insert(cmark_syntax_extension *self,
                                   cmark_parser *parser,
                                   cmark_inline_parser *inline_parser,
                                   delimiter *opener, delimiter *closer) {
  cmark_node *highlight;
  cmark_node *tmp, *next;
  delimiter *delim, *tmp_delim;
  delimiter *res = closer->next;

  highlight = opener->inl_text;

  if (opener->inl_text->as.literal.len != closer->inl_text->as.literal.len)
    goto done;

  if (!cmark_node_set_type(highlight, CMARK_NODE_HIGHLIGHT))
    goto done;

  cmark_node_set_syntax_extension(highlight, self);

  tmp = cmark_node_next(opener->inl_text);

  while (tmp) {
    if (tmp == closer->inl_text)
      break;
    next = cmark_node_next(tmp);
    cmark_node_append_child(highlight, tmp);
    tmp = next;
  }

  highlight->end_column = closer->inl_text->start_column + closer->inl_text->as.literal.len - 1;
  cmark_node_free(closer->inl_text);

done:
  delim = closer;
  while (delim != NULL && delim != opener) {
    tmp_delim = delim->previous;
    cmark_inline_parser_remove_delimiter(inline_parser, delim);
    delim = tmp_delim;
  }

  cmark_inline_parser_remove_delimiter(inline_parser, opener);

  return res;
}

static const char *highlight_get_type_string(cmark_syntax_extension *extension,
                                             cmark_node *node) {
  return node->type == CMARK_NODE_HIGHLIGHT ? "highlight" : "<unknown>";
}

static int highlight_can_contain(cmark_syntax_extension *extension,
                                 cmark_node *node, cmark_node_type child_type) {
  if (node->type != CMARK_NODE_HIGHLIGHT)
    return false;

  return CMARK_NODE_TYPE_INLINE_P(child_type);
}

static void highlight_commonmark_render(cmark_syntax_extension *extension,
                                        cmark_renderer *renderer,
                                        cmark_node *node,
                                        cmark_event_type ev_type,
                                        int options) {
  renderer->out(renderer, node, "==", false, LITERAL);
}

static void highlight_html_render(cmark_syntax_extension *extension,
                                  cmark_html_renderer *renderer,
                                  cmark_node *node, cmark_event_type ev_type,
                                  int options) {
  bool entering = (ev_type == CMARK_EVENT_ENTER);
  if (entering) {
    cmark_strbuf_puts(renderer->html, "<mark>");
  } else {
    cmark_strbuf_puts(renderer->html, "</mark>");
  }
}

static void highlight_plaintext_render(cmark_syntax_extension *extension,
                                       cmark_renderer *renderer,
                                       cmark_node *node,
                                       cmark_event_type ev_type,
                                       int options) {
  renderer->out(renderer, node, "==", false, LITERAL);
}

cmark_syntax_extension *mdmark_create_highlight_extension(void) {
  cmark_syntax_extension *ext = cmark_syntax_extension_new("mdmark_highlight");
  cmark_llist *special_chars = NULL;

  cmark_syntax_extension_set_get_type_string_func(ext,
                                                  highlight_get_type_string);
  cmark_syntax_extension_set_can_contain_func(ext, highlight_can_contain);
  cmark_syntax_extension_set_commonmark_render_func(
      ext, highlight_commonmark_render);
  cmark_syntax_extension_set_html_render_func(ext, highlight_html_render);
  cmark_syntax_extension_set_plaintext_render_func(
      ext, highlight_plaintext_render);
  CMARK_NODE_HIGHLIGHT = cmark_syntax_extension_add_node(1);

  cmark_syntax_extension_set_match_inline_func(ext, highlight_match);
  cmark_syntax_extension_set_inline_from_delim_func(ext, highlight_insert);

  cmark_mem *mem = cmark_get_default_mem_allocator();
  special_chars = cmark_llist_append(mem, special_chars, (void *)'=');
  cmark_syntax_extension_set_special_inline_chars(ext, special_chars);

  cmark_syntax_extension_set_emphasis(ext, 1);

  return ext;
}
