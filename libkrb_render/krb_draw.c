/*
 * KRB Draw - Main Drawing Interface
 *
 * Provides drawing context and primitive drawing operations.
 */

#include "lib9.h"
#include <draw.h>
#include <stdlib.h>
#include <string.h>
#include "krb_render.h"

KrbDrawContext*
krb_render_init(Display *display, Screen *screen, Image *window_image)
{
    KrbDrawContext *ctx;

    ctx = mallocz(sizeof(KrbDrawContext), 1);
    if (ctx == nil)
        return nil;

    ctx->display = display;
    ctx->screen = screen;
    ctx->window_image = window_image;

    /* Load default font */
    ctx->default_font = openfont(display, "*default*");
    if (ctx->default_font == nil) {
        /* Fallback to built-in font */
        ctx->default_font = getdefont(display);
    }

    /* Initialize color cache */
    memset(ctx->color_cache, 0, sizeof(ctx->color_cache));

    return ctx;
}

void
krb_render_cleanup(KrbDrawContext *ctx)
{
    int i;

    if (ctx == nil)
        return;

    /* Free color cache */
    for (i = 0; i < 256; i++) {
        if (ctx->color_cache[i] != nil) {
            freeimage(ctx->color_cache[i]);
        }
    }

    free(ctx);
}

/* Convert KRB color (0xAABBGGRR) to draw format */
int
krb_color_to_draw(uint32_t color)
{
    int r, g, b, a;

    a = (color >> 24) & 0xFF;
    r = (color >> 16) & 0xFF;
    g = (color >> 8) & 0xFF;
    b = color & 0xFF;

    return (a << 24) | (r << 16) | (g << 8) | b;
}

/* Get cached image for solid color */
Image*
krb_get_color_image(KrbDrawContext *ctx, uint32_t color)
{
    int cache_idx;
    Image *img;
    int draw_color;

    if (ctx == nil)
        return nil;

    /* Use lower 8 bits as cache index */
    cache_idx = color & 0xFF;

    if (ctx->color_cache[cache_idx] != nil)
        return ctx->color_cache[cache_idx];

    /* Create new color image */
    draw_color = krb_color_to_draw(color);
    img = allocimage(ctx->display, Rect(0, 0, 1, 1),
                     ctx->display->chan, 1, draw_color);
    if (img == nil)
        return nil;

    ctx->color_cache[cache_idx] = img;
    return img;
}

/* Draw rectangle */
void
krb_draw_rect(KrbDrawContext *ctx, Rectangle rect, uint32_t color)
{
    Image *color_img;

    if (ctx == nil || ctx->window_image == nil)
        return;

    color_img = krb_get_color_image(ctx, color);
    if (color_img == nil)
        return;

    draw(ctx->window_image, rect, color_img, nil, ZP);
}

/* Draw text */
void
krb_draw_text(KrbDrawContext *ctx, Point pos, const char *text,
              uint32_t color, Font *font)
{
    Image *color_img;
    int draw_color;

    if (ctx == nil || ctx->window_image == nil || text == nil)
        return;

    if (font == nil)
        font = ctx->default_font;

    draw_color = krb_color_to_draw(color);
    color_img = krb_get_color_image(ctx, draw_color);
    if (color_img == nil)
        return;

    string(ctx->window_image, pos, color_img, ZP, font, (char*)text);
}

/* Draw border */
void
krb_draw_border(KrbDrawContext *ctx, Rectangle rect,
                int width, uint32_t color)
{
    int i;
    Image *color_img;

    if (ctx == nil || ctx->window_image == nil || width <= 0)
        return;

    color_img = krb_get_color_image(ctx, color);
    if (color_img == nil)
        return;

    /* Draw border by drawing lines along edges */
    for (i = 0; i < width; i++) {
        /* Top edge */
        draw(ctx->window_image,
             Rect(rect.min.x + i, rect.min.y + i,
                  rect.max.x - i, rect.min.y + i + 1),
             color_img, nil, ZP);

        /* Bottom edge */
        draw(ctx->window_image,
             Rect(rect.min.x + i, rect.max.y - i - 1,
                  rect.max.x - i, rect.max.y - i),
             color_img, nil, ZP);

        /* Left edge */
        draw(ctx->window_image,
             Rect(rect.min.x + i, rect.min.y + i,
                  rect.min.x + i + 1, rect.max.y - i),
             color_img, nil, ZP);

        /* Right edge */
        draw(ctx->window_image,
             Rect(rect.max.x - i - 1, rect.min.y + i,
                  rect.max.x - i, rect.max.y - i),
             color_img, nil, ZP);
    }
}

/* Render widget tree */
void
krb_render_widget_tree(KrbDrawContext *ctx, KrbWidget *root)
{
    int i;

    if (ctx == nil || root == nil)
        return;

    /* Render this widget */
    krb_render_widget(ctx, root);

    /* Render children */
    for (i = 0; i < root->child_count; i++) {
        if (root->children[i] != nil && root->children[i]->visible) {
            krb_render_widget_tree(ctx, root->children[i]);
        }
    }
}

/* Render single widget */
void
krb_render_widget(KrbDrawContext *ctx, KrbWidget *widget)
{
    if (ctx == nil || widget == nil || !widget->visible)
        return;

    /* Draw background */
    if (widget->background != 0x00000000) {  /* Not transparent */
        krb_draw_rect(ctx, widget->bounds, widget->background);
    }

    /* Draw border */
    if (widget->border_width > 0) {
        krb_draw_border(ctx, widget->bounds,
                       widget->border_width, widget->border_color);
    }

    /* Type-specific rendering */
    if (widget->type_name != nil) {
        if (strcmp(widget->type_name, "Text") == 0) {
            krb_render_text(ctx, widget);
        } else if (strcmp(widget->type_name, "Button") == 0) {
            krb_render_button(ctx, widget);
        }
    }
}
