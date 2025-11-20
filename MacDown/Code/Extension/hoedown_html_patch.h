//
//  hoedown_html_patch.h
//  MacDown 3000
//
//  Created by Tzu-ping Chung  on 14/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#ifndef MacDown_hoedown_html_patch_h
#define MacDown_hoedown_html_patch_h

#import <CoreGraphics/CoreGraphics.h>

static unsigned int HOEDOWN_HTML_USE_TASK_LIST = (1 << 4);
static unsigned int HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS = (1 << 5);
static unsigned int HOEDOWN_HTML_BLOCKCODE_INFORMATION = (1 << 6);

typedef struct hoedown_buffer hoedown_buffer;

typedef CGSize (*hoedown_image_dimensions_callback)(const hoedown_buffer *link,
                                                     void *owner);

typedef struct hoedown_html_renderer_state_extra {

    /* More extra callbacks */
    hoedown_buffer *(*language_addition)(const hoedown_buffer *language,
                                         void *owner);
    hoedown_image_dimensions_callback image_dimensions;
    void *owner;

} hoedown_html_renderer_state_extra;

void hoedown_patch_render_blockcode(
    hoedown_buffer *ob, const hoedown_buffer *text, const hoedown_buffer *lang,
    const hoedown_renderer_data *data);

void hoedown_patch_render_listitem(
    hoedown_buffer *ob, const hoedown_buffer *text, hoedown_list_flags flags,
    const hoedown_renderer_data *data);

void hoedown_patch_render_image(
    hoedown_buffer *ob, const hoedown_buffer *link, const hoedown_buffer *title,
    const hoedown_buffer *alt, const hoedown_renderer_data *data);

void hoedown_patch_render_toc_header(
     hoedown_buffer *ob, const hoedown_buffer *content, int level,
     const hoedown_renderer_data *data);

#endif
