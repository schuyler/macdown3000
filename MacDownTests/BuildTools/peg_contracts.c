#include "pmh_parser.h"
#include "pmh_styleparser.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    const char *documents[] = {
        "", "# title\n\n**bold** and [label](https://example.invalid/a)\n",
        "> quoted *text*\n\n- list [link](https://example.invalid/b)\n",
        "[ref]: https://example.invalid/path\n\n[ref]\n",
        "😀 *é* and [日本語](https://example.invalid/日本語)\n",
        "$$x+y$$\n\n[^note]: text\n\n[^note]\n"
    };
    for (size_t i = 0; i < sizeof(documents) / sizeof(*documents); ++i) {
        pmh_element **elements = NULL;
        pmh_markdown_to_elements((char *)documents[i], pmh_EXT_NOTES | pmh_EXT_MATH, &elements);
        assert(elements);
        pmh_sort_elements_by_pos(elements);
        for (int type = 0; type < pmh_NUM_LANG_TYPES; ++type) {
            unsigned long previous = 0;
            for (pmh_element *element = elements[type]; element; element = element->next) {
                assert(element->pos >= previous && element->end >= element->pos);
                previous = element->pos;
                if (element->address) assert(strlen(element->address) > 0);
            }
        }
        if (i == 1) {
            assert(elements[pmh_H1] && elements[pmh_STRONG] && elements[pmh_LINK]);
            assert(strcmp(elements[pmh_LINK]->address, "https://example.invalid/a") == 0);
        }
        if (i == 3) {
            assert(elements[pmh_LINK]);
            assert(strcmp(elements[pmh_LINK]->address, "https://example.invalid/path") == 0);
        }
        pmh_free_elements(elements);
    }
    char stylesheet[65536] = "";
    for (int i = 0; i < 1000; ++i)
        strcat(stylesheet, "H1\ncolor: ff0000\nfont-family: \n\n");
    pmh_style_collection *styles = pmh_parse_styles(stylesheet, NULL, NULL);
    int slots = 0, colors = 0, empty_families = 0;
    for (int i = 0; i < pmh_NUM_LANG_TYPES; ++i) {
        if (styles->element_styles[i]) ++slots;
        for (pmh_style_attribute *a = styles->element_styles[i]; a; a = a->next) {
            if (a->type == pmh_attr_type_foreground_color) {
                assert(a->value->argb_color->red == 255);
                ++colors;
            } else if (a->type == pmh_attr_type_font_family) {
                assert(strcmp(a->value->font_family, "") == 0);
                ++empty_families;
            }
        }
    }
    assert(slots == 1 && colors == 1000 && empty_families == 1000);
    pmh_free_style_collection(styles);
    puts("PASS Markdown parse/sort/address/free and repeated stylesheet/empty values");
    return 0;
}
