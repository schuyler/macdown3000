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
        front = hoedown_buffer_new(lang->size);
        back = hoedown_buffer_new(lang->size);

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

        // Do task list checkbox ([x] or [ ]).
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
            else if (strncmp((char *)(text->data + offset), "[x]", 3) == 0)
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

// Build a stable text-derived slug from a heading's HTML content.
// Strips HTML tags and skips HTML entities (&amp; / &lt; / &#39; ...),
// lowercases ASCII, converts spaces to hyphens, drops ASCII punctuation,
// preserves UTF-8 multi-byte sequences so accented characters survive
// (e.g. "Introducción" -> "introducción"). Anchors keep their raw UTF-8
// bytes (no percent-encoding): browsers match the URL fragment against
// the id literally, so encoding would break navigation.
static void slugify(hoedown_buffer *out, const hoedown_buffer *content)
{
    if (!content || !content->size)
        return;

    int in_tag = 0;
    int last_was_dash = 1;

    for (size_t i = 0; i < content->size; i++)
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
            while (i + 1 < content->size && content->data[i + 1] != ';')
                i++;
            i++;                    // consume the ';'
            continue;
        }

        if (c >= 0x80)
        {
            hoedown_buffer_putc(out, c);
            last_was_dash = 0;
            continue;
        }

        if (c >= 'A' && c <= 'Z')
            c += 32;

        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')
        {
            hoedown_buffer_putc(out, c);
            last_was_dash = 0;
        }
        else if (c == ' ' || c == '\t' || c == '-')
        {
            if (!last_was_dash)
            {
                hoedown_buffer_putc(out, '-');
                last_was_dash = 1;
            }
        }
    }

    while (out->size > 0 && out->data[out->size - 1] == '-')
        out->size--;
}

// rndr_header replacement that always emits a text-derived id, independent
// of the TOC nesting level. Enables [link](#section-name) navigation.
void hoedown_patch_render_header(
    hoedown_buffer *ob, const hoedown_buffer *content, int level,
    const hoedown_renderer_data *data)
{
    (void)data;
    if (ob->size) hoedown_buffer_putc(ob, '\n');

    hoedown_buffer *slug = hoedown_buffer_new(content ? content->size : 16);
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

        hoedown_buffer *slug = hoedown_buffer_new(content ? content->size : 16);
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
