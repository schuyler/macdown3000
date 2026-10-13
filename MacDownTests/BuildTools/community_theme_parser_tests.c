/* Exercise the same PEG style parser consumed by HGMarkdownHighlighter. */
#include <stdio.h>
#include <stdlib.h>
#include "pmh_styleparser.h"

static void report_error(char *message, int line, void *context)
{
    (*(int *)context)++;
    fprintf(stderr, "style parse error at %d: %s\n", line, message);
}

int main(int argc, char **argv)
{
    int failures = 0;
    if (argc < 2) return 2;
    for (int i = 1; i < argc; i++) {
        FILE *file = fopen(argv[i], "rb");
        if (!file || fseek(file, 0, SEEK_END) != 0) return 2;
        long length = ftell(file);
        if (length < 0 || length > 65536 || fseek(file, 0, SEEK_SET) != 0) return 2;
        char *text = calloc((size_t)length + 1, 1);
        if (!text || fread(text, 1, (size_t)length, file) != (size_t)length) return 2;
        fclose(file);
        int errors = 0;
        pmh_style_collection *styles = pmh_parse_styles(text, report_error, &errors);
        if (!styles || !styles->editor_styles || !styles->editor_selection_styles)
            errors++;
        if (styles) {
            for (int heading = pmh_H1; heading <= pmh_H6; heading++)
                if (!styles->element_styles[heading]) errors++;
            pmh_free_style_collection(styles);
        }
        free(text);
        failures += errors;
        printf("%s %s\n", errors ? "FAIL" : "PASS", argv[i]);
    }
    return failures ? 1 : 0;
}
