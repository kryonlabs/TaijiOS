/*
 * krbview_renderer - Rendering Wrapper
 *
 * Wrapper around libkrb_render.a for rendering KRB content.
 */

#ifndef KRBVIEW_RENDERER_H
#define KRBVIEW_RENDERER_H

#include "krb_render.h"
#include "krb_runtime.h"

/*
 * Initialize renderer for application
 *
 * Creates draw context and sets up rendering pipeline.
 * Returns: KrbDrawContext pointer on success, NULL on error
 */
KrbDrawContext* krbview_renderer_init(KrbRuntime *runtime,
                                     Display *display,
                                     Screen *screen,
                                     Image *window_image);

/*
 * Cleanup renderer
 */
void krbview_renderer_cleanup(KrbDrawContext *ctx);

/*
 * Render KRB content to window
 *
 * Renders the entire widget tree to the window image.
 */
void krbview_renderer_render(KrbDrawContext *ctx, KrbWidget *root);

/*
 * Mark region as dirty (needs redraw)
 *
 * For optimization - only redraw specified region.
 */
void krbview_renderer_invalidate(KrbDrawContext *ctx, Rectangle rect);

/*
 * Clear window with background color
 */
void krbview_renderer_clear(KrbDrawContext *ctx, uint32_t color);

#endif /* KRBVIEW_RENDERER_H */
