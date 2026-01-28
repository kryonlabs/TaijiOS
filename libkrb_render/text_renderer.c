/*
 * KRB Text Renderer
 *
 * Text rendering utilities for KRB widgets.
 */

#include "lib9.h"
#include <draw.h>
#include <stdlib.h>
#include <string.h>
#include "krb_render.h"

/* Measure text */
Point
krb_measure_text(KrbDrawContext *ctx, const char *text, Font *font)
{
    Point size;

    if (ctx == nil || text == nil)
        return Pt(0, 0);

    if (font == nil)
        font = ctx->default_font;

    size.x = stringwidth(font, text);
    size.y = font->height;

    return size;
}

/* Wrap text to fit width */
int
krb_wrap_text(KrbDrawContext *ctx, char *text, int max_width,
              char **lines, int *line_count, Font *font)
{
    int count, pos, last_space, i;
    char *p;

    if (ctx == nil || text == nil || max_width <= 0)
        return -1;

    if (font == nil)
        font = ctx->default_font;

    /* Simple word wrapping */
    count = 0;
    pos = 0;
    p = text;

    /* TODO: Implement proper text wrapping */
    /* For now, just count lines based on newlines */
    while (*p != '\0') {
        if (*p == '\n')
            count++;
        p++;
    }

    if (count == 0)
        count = 1;

    return count;
}

/* Draw multi-line text */
void
krb_draw_text_multiline(KrbDrawContext *ctx, Point pos, const char *text,
                        uint32_t color, Font *font, int line_height)
{
    char *copy, *line, *free_p;
    int y;

    if (ctx == nil || text == nil)
        return;

    if (font == nil)
        font = ctx->default_font;

    /* Make a copy we can modify */
    copy = strdup(text);
    if (copy == nil)
        return;

    free_p = copy;
    y = pos.y;
    line = strtok(copy, "\n");

    while (line != nil) {
        krb_draw_text(ctx, Pt(pos.x, y), line, color, font);
        y += line_height;
        line = strtok(nil, "\n");
    }

    free(free_p);
}

/* Truncate text to fit width with ellipsis */
void
krb_draw_text_ellipsis(KrbDrawContext *ctx, Point pos, const char *text,
                      int max_width, uint32_t color, Font *font)
{
    char buffer[256];
    int len, i;
    int width;

    if (ctx == nil || text == nil)
        return;

    if (font == nil)
        font = ctx->default_font;

    /* Check if text fits */
    width = stringwidth(font, text);
    if (width <= max_width) {
        krb_draw_text(ctx, pos, text, color, font);
        return;
    }

    /* Truncate with ellipsis */
    len = strlen(text);
    if (len > sizeof(buffer) - 4)
        len = sizeof(buffer) - 4;

    strncpy(buffer, text, len);
    strcpy(buffer + len, "...");

    /* Binary search for fitting length */
    for (i = len; i > 0; i--) {
        buffer[i] = '\0';
        strcat(buffer + i, "...");
        width = stringwidth(font, buffer);
        if (width <= max_width) {
            krb_draw_text(ctx, pos, buffer, color, font);
            return;
        }
    }

    /* If even "..." doesn't fit, draw nothing */
}
