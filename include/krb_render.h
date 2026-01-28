/*
 * KRB Renderer - Public API
 *
 * Renders KRB widgets using TaijiOS draw library.
 */

#ifndef KRB_RENDER_H
#define KRB_RENDER_H

#include <stdint.h>
#include <stddef.h>
#include "krb_runtime.h"

/* Draw context */
typedef struct {
    Display *display;
    Screen *screen;
    Image *window_image;      /* Our drawing surface */
    Font *default_font;

    KrbRuntime *runtime;

    /* Caching */
    Image *color_cache[256];
} KrbDrawContext;

/*
 * Initialization
 */

/* Initialize renderer with WM-provided image */
KrbDrawContext* krb_render_init(Display *display, Screen *screen,
                                Image *window_image);

/* Cleanup renderer */
void krb_render_cleanup(KrbDrawContext *ctx);

/*
 * Rendering
 */

/* Render widget tree */
void krb_render_widget_tree(KrbDrawContext *ctx, KrbWidget *root);

/* Render single widget */
void krb_render_widget(KrbDrawContext *ctx, KrbWidget *widget);

/*
 * Primitive drawing
 */

/* Draw rectangle */
void krb_draw_rect(KrbDrawContext *ctx, Rectangle rect, uint32_t color);

/* Draw text */
void krb_draw_text(KrbDrawContext *ctx, Point pos, const char *text,
                  uint32_t color, Font *font);

/* Draw border */
void krb_draw_border(KrbDrawContext *ctx, Rectangle rect,
                    int width, uint32_t color);

/*
 * Widget-specific renderers
 */

/* Render Text widget */
void krb_render_text(KrbDrawContext *ctx, KrbWidget *widget);

/* Render Button widget */
void krb_render_button(KrbDrawContext *ctx, KrbWidget *widget);

/* Render Container widget */
void krb_render_container(KrbDrawContext *ctx, KrbWidget *widget);

/* Render Column widget */
void krb_render_column(KrbDrawContext *ctx, KrbWidget *widget);

/* Render Row widget */
void krb_render_row(KrbDrawContext *ctx, KrbWidget *widget);

/* Render Image widget */
void krb_render_image(KrbDrawContext *ctx, KrbWidget *widget);

/*
 * Color utilities
 */

/* Convert KRB color to draw format */
int krb_color_to_draw(uint32_t color);

/* Get cached image for solid color */
Image* krb_get_color_image(KrbDrawContext *ctx, uint32_t color);

#endif /* KRB_RENDER_H */
