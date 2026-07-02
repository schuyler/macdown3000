//
//  hoedown_html_patch.c
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 14/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#include <string.h>
#include <hoedown/escape.h>
#include <hoedown/document.h>
#include <hoedown/html.h>
#include "hoedown_html_patch.h"

#define USE_XHTML(opt) (opt->flags & HOEDOWN_HTML_USE_XHTML)
#define USE_BLOCKCODE_INFORMATION(opt) \
    (opt->flags & HOEDOWN_HTML_BLOCKCODE_INFORMATION)
#define USE_TASK_LIST(opt) (opt->flags & HOEDOWN_HTML_USE_TASK_LIST)

// Global checkbox index counter for interactive checkbox support.
// NOTE: This counter is NOT thread-safe. Markdown rendering must be serialized
// on a single thread (which MacDown does via the main thread).
// Related to GitHub issue #269.
static int g_checkbox_index = 0;

void hoedown_patch_reset_checkbox_index(void)
{
    g_checkbox_index = 0;
}

// hoedown_buffer_new() stores its argument as the buffer's growth "unit", and
// hoedown_buffer_grow() asserts that unit is non-zero. Passing a size hint of 0
// (e.g. when a heading or code-fence info string is empty) therefore produces a
// buffer that aborts the process the first time anything is written to it. Clamp
// the hint so a derived buffer is always growable. Related to GitHub issue #479.
static hoedown_buffer *new_growable_buffer(size_t size_hint)
{
    return hoedown_buffer_new(size_hint ? size_hint : 16);
}

int hoedown_patch_get_checkbox_index(void)
{
    return g_checkbox_index;
}

// rndr_blockcode from HEAD. The "language-" prefix in class in needed to make
// the HTML compatible with Prism.
void hoedown_patch_render_blockcode(
    hoedown_buffer *ob, const hoedown_buffer *text, const hoedown_buffer *lang,
    const hoedown_renderer_data *data)
{
	if (ob->size) hoedown_buffer_putc(ob, '\n');

    hoedown_html_renderer_state *state = data->opaque;
    hoedown_html_renderer_state_extra *extra = state->opaque;

    hoedown_buffer *front = NULL;
    hoedown_buffer *back = NULL;
    if (lang && USE_BLOCKCODE_INFORMATION(state))
    {
        front = new_growable_buffer(lang->size);
        back = new_growable_buffer(lang->size);

        hoedown_buffer *current = front;
        for (size_t i = 0; i < lang->size; i++)
        {
            uint8_t c = lang->data[i];
            if (current == front && c == ':')
                current = back;
            else
                hoedown_buffer_putc(current, c);
        }
        lang = front;
    }

    hoedown_buffer *mapped = NULL;
    if (lang && extra->language_addition)
    {
        mapped = extra->language_addition(lang, extra->owner);
        if (mapped)
            lang = mapped;
    }

    HOEDOWN_BUFPUTSL(ob, "<div><pre");
    if (state->flags & HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS)
        HOEDOWN_BUFPUTSL(ob, " class=\"line-numbers\"");
    if (back && back->size)
    {
        HOEDOWN_BUFPUTSL(ob, " data-information=\"");
        hoedown_buffer_put(ob, back->data, back->size);
        HOEDOWN_BUFPUTSL(ob, "\"");
    }
    HOEDOWN_BUFPUTSL(ob, "><code class=\"language-");
    if (lang && lang->size)
        hoedown_escape_html(ob, lang->data, lang->size, 0);
    else
        HOEDOWN_BUFPUTSL(ob, "none");
    HOEDOWN_BUFPUTSL(ob, "\">");

	if (text)
    {
        // Remove last newline to prevent prism from adding a blank line at the
        // end of code blocks.
        size_t size = text->size;
        if (size > 0 && text->data[size - 1] == '\n')
            size--;
        hoedown_escape_html(ob, text->data, size, 0);
    }

	HOEDOWN_BUFPUTSL(ob, "</code></pre></div>\n");

    hoedown_buffer_free(mapped);
    hoedown_buffer_free(front);
    hoedown_buffer_free(back);
}

// Supports task list syntax if HOEDOWN_HTML_USE_TASK_LIST is on.
// Implementation based on hoextdown, with interactive checkbox support.
// Related to GitHub issue #269.
void hoedown_patch_render_listitem(
    hoedown_buffer *ob, const hoedown_buffer *text, hoedown_list_flags flags,
    const hoedown_renderer_data *data)
{
	if (text)
    {
        hoedown_html_renderer_state *state = data->opaque;
        size_t offset = 0;
        if (flags & HOEDOWN_LI_BLOCK)
            offset = 3;

        // Do task list checkbox ([x], [X], or [ ]).
        if (USE_TASK_LIST(state) && text->size >= 3)
        {
            if (strncmp((char *)(text->data + offset), "[ ]", 3) == 0)
            {
                HOEDOWN_BUFPUTSL(ob, "<li class=\"task-list-item\">");
                hoedown_buffer_put(ob, text->data, offset);
                // Include data-checkbox-index for interactive checkbox support
                hoedown_buffer_printf(ob,
                    "<input type=\"checkbox\" data-checkbox-index=\"%d\">",
                    g_checkbox_index++);
				offset += 3;
            }
            else if (strncmp((char *)(text->data + offset), "[x]", 3) == 0 ||
                     strncmp((char *)(text->data + offset), "[X]", 3) == 0)
            {
                HOEDOWN_BUFPUTSL(ob, "<li class=\"task-list-item\">");
                hoedown_buffer_put(ob, text->data, offset);
                // Include data-checkbox-index for interactive checkbox support
                hoedown_buffer_printf(ob,
                    "<input type=\"checkbox\" checked data-checkbox-index=\"%d\">",
                    g_checkbox_index++);
				offset += 3;
            }
            else
            {
                HOEDOWN_BUFPUTSL(ob, "<li>");
                offset = 0;
            }
        }
        else
        {
            HOEDOWN_BUFPUTSL(ob, "<li>");
            offset = 0;
        }
		size_t size = text->size;
		while (size && text->data[size - offset - 1] == '\n')
			size--;

		hoedown_buffer_put(ob, text->data + offset, size - offset);
	}
	HOEDOWN_BUFPUTSL(ob, "</li>\n");
}

// Decode the UTF-8 codepoint starting at data[i] (i < size). Returns the
// number of bytes consumed (1-4) and stores the codepoint in *codepoint, or
// returns 0 if the sequence is malformed / truncated, in which case the
// caller should pass the raw byte through unchanged.
static size_t decode_utf8_codepoint(const uint8_t *data, size_t size, size_t i,
                                     uint32_t *codepoint)
{
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

    for (size_t k = 1; k < len; k++)
    {
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
static void encode_utf8_2byte(uint32_t cp, uint8_t out[2])
{
    out[0] = (uint8_t)(0xC0 | (cp >> 6));
    out[1] = (uint8_t)(0x80 | (cp & 0x3F));
}

// Build a stable text-derived slug from a heading's HTML content, matching
// GitHub's heading-anchor slug algorithm (github-slugger semantics) so
// [text](#slug) links copied from GitHub-rendered Markdown keep working.
// Strips HTML tags and skips HTML entities (&amp; / &lt; / &#39; ...), then
// trims leading/trailing whitespace from the heading text. ASCII letters are
// lowercased; digits, '_' and literal '-' are kept as-is; each remaining
// ASCII space/tab maps to exactly one hyphen (runs are NOT collapsed, e.g.
// "Foo --- Bar" -> "foo-----bar"); other ASCII punctuation is dropped.
// Non-ASCII text is decoded as UTF-8: Latin-1 uppercase letters
// (U+00C0-U+00DE, excluding the multiplication sign U+00D7) are lowercased
// and re-encoded; the Latin-1 punctuation/symbol block (U+00A1-U+00BF), the
// multiplication/division signs (U+00D7, U+00F7), and the General
// Punctuation block (U+2000-U+206F, which covers em/en dashes, curly quotes,
// ellipsis, ...) are dropped entirely; every other codepoint passes through
// unchanged as raw UTF-8 bytes (e.g. "Introducción" -> "introducción").
// Malformed UTF-8 bytes are passed through unchanged rather than dropped.
// Anchors keep their raw UTF-8 bytes (no percent-encoding): browsers match
// the URL fragment against the id literally, so encoding would break
// navigation.
static void slugify(hoedown_buffer *out, const hoedown_buffer *content)
{
    if (!content || !content->size)
        return;

    size_t start = 0, end = content->size;
    while (start < end && (content->data[start] == ' ' ||
                            content->data[start] == '\t' ||
                            content->data[start] == '\n' ||
                            content->data[start] == '\r'))
        start++;
    while (end > start && (content->data[end - 1] == ' ' ||
                            content->data[end - 1] == '\t' ||
                            content->data[end - 1] == '\n' ||
                            content->data[end - 1] == '\r'))
        end--;

    int in_tag = 0;

    for (size_t i = start; i < end; i++)
    {
        uint8_t c = content->data[i];

        if (in_tag)
        {
            if (c == '>') in_tag = 0;
            continue;
        }
        if (c == '<')
        {
            in_tag = 1;
            continue;
        }
        if (c == '&')
        {            // skip an HTML entity like &amp; / &lt; / &#39;
            while (i + 1 < end && content->data[i + 1] != ';')
                i++;
            i++;                    // consume the ';'
            continue;
        }

        if (c >= 0x80)
        {
            uint32_t cp;
            size_t len = decode_utf8_codepoint(content->data, end, i, &cp);

            if (len == 0)
            {
                // Malformed / truncated sequence: pass the raw byte through.
                hoedown_buffer_putc(out, c);
                continue;
            }

            if ((cp >= 0x00A1 && cp <= 0x00BF) || cp == 0x00D7 ||
                cp == 0x00F7 || (cp >= 0x2000 && cp <= 0x206F))
            {
                // Dropped punctuation/symbol codepoint: emit nothing.
            }
            else if (cp >= 0x00C0 && cp <= 0x00DE && cp != 0x00D7)
            {
                uint8_t enc[2];
                encode_utf8_2byte(cp + 0x20, enc);
                hoedown_buffer_put(out, enc, 2);
            }
            else
            {
                hoedown_buffer_put(out, content->data + i, len);
            }

            i += len - 1;
            continue;
        }

        if (c >= 'A' && c <= 'Z')
            c += 32;

        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            c == '_' || c == '-')
        {
            hoedown_buffer_putc(out, c);
        }
        else if (c == ' ' || c == '\t')
        {
            hoedown_buffer_putc(out, '-');
        }
    }
}

// rndr_header replacement that always emits a text-derived id, independent
// of the TOC nesting level. Enables [link](#section-name) navigation.
void hoedown_patch_render_header(
    hoedown_buffer *ob, const hoedown_buffer *content, int level,
    const hoedown_renderer_data *data)
{
    (void)data;
    if (ob->size) hoedown_buffer_putc(ob, '\n');

    hoedown_buffer *slug = new_growable_buffer(content ? content->size : 16);
    slugify(slug, content);
    if (slug->size == 0)
        HOEDOWN_BUFPUTSL(slug, "section");

    hoedown_buffer_printf(ob, "<h%d id=\"", level);
    hoedown_buffer_put(ob, slug->data, slug->size);
    HOEDOWN_BUFPUTSL(ob, "\">");
    if (content) hoedown_buffer_put(ob, content->data, content->size);
    hoedown_buffer_printf(ob, "</h%d>\n", level);

    hoedown_buffer_free(slug);
}

// Adds a "toc" class to the outmost UL element to support TOC styling.
void hoedown_patch_render_toc_header(
    hoedown_buffer *ob, const hoedown_buffer *content, int level,
    const hoedown_renderer_data *data)
{
    hoedown_html_renderer_state *state = data->opaque;

    if (level <= state->toc_data.nesting_level) {
        /* set the level offset if this is the first header
         * we're parsing for the document */
        if (state->toc_data.current_level == 0)
            state->toc_data.level_offset = level - 1;

        level -= state->toc_data.level_offset;

        if (level > state->toc_data.current_level) {
            while (level > state->toc_data.current_level) {
                if (state->toc_data.current_level == 0)
                    HOEDOWN_BUFPUTSL(ob, "<ul class=\"toc\">\n<li>\n");
                else
                    HOEDOWN_BUFPUTSL(ob, "<ul>\n<li>\n");
                state->toc_data.current_level++;
            }
        } else if (level < state->toc_data.current_level) {
            HOEDOWN_BUFPUTSL(ob, "</li>\n");
            while (level < state->toc_data.current_level) {
                HOEDOWN_BUFPUTSL(ob, "</ul>\n</li>\n");
                state->toc_data.current_level--;
            }
            HOEDOWN_BUFPUTSL(ob,"<li>\n");
        } else {
            HOEDOWN_BUFPUTSL(ob,"</li>\n<li>\n");
        }

        hoedown_buffer *slug = new_growable_buffer(content ? content->size : 16);
        slugify(slug, content);
        if (slug->size == 0)
            HOEDOWN_BUFPUTSL(slug, "section");
        HOEDOWN_BUFPUTSL(ob, "<a href=\"#");
        hoedown_buffer_put(ob, slug->data, slug->size);
        HOEDOWN_BUFPUTSL(ob, "\">");
        hoedown_buffer_free(slug);
        state->toc_data.header_count++;
        if (content) hoedown_buffer_put(ob, content->data, content->size);
        HOEDOWN_BUFPUTSL(ob, "</a>\n");
    }
}
