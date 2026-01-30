/*
 * krbview_renderer - Rendering Wrapper
 */

#define _BSD_SOURCE
#define _DEFAULT_SOURCE
#include <lib9.h>
#include "krbview_renderer.h"
#include <stdlib.h>

/*
 * Initialize renderer for application
 */
KrbDrawContext* krbview_renderer_init(KrbRuntime *runtime,
                                     Display *display,
                                     Screen *screen,
                                     Image *window_image)
{
    KrbDrawContext *ctx;

    if (!runtime || !display || !screen || !window_image) {
        return NULL;
    }

    /* Use existing libkrb_render initialization */
    ctx = krb_render_init(display, screen, window_image);
    if (!ctx) {
        return NULL;
    }

    /* Store runtime reference */
    ctx->runtime = runtime;

    return ctx;
}

/*
 * Cleanup renderer
 */
void krbview_renderer_cleanup(KrbDrawContext *ctx)
{
    if (ctx) {
        krb_render_cleanup(ctx);
    }
}

/*
 * Render KRB content to window
 */
void krbview_renderer_render(KrbDrawContext *ctx, KrbWidget *root)
{
    if (!ctx || !root) {
        return;
    }

    /* Use existing widget tree renderer */
    krb_render_widget_tree(ctx, root);
}

/*
 * Mark region as dirty (needs redraw)
 *
 * Note: For now, we just redraw everything. Optimization can come later.
 */
void krbview_renderer_invalidate(KrbDrawContext *ctx, Rectangle rect)
{
    /* TODO: Implement dirty region tracking */
    /* For now, this is a no-op - we redraw the entire tree */
}

/*
 * Clear window with background color
 */
void krbview_renderer_clear(KrbDrawContext *ctx, uint32_t color)
{
    if (!ctx || !ctx->window_image) {
        return;
    }

    Rectangle rect;
    rect.min.x = 0;
    rect.min.y = 0;
    rect.max.x = ctx->window_image->r.max.x - ctx->window_image->r.min.x;
    rect.max.y = ctx->window_image->r.max.y - ctx->window_image->r.min.y;

    /* Use existing draw rect function */
    krb_draw_rect(ctx, rect, color);
}
