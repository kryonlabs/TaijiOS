/*
 * KRB Widget Renderers
 *
 * Widget-specific rendering implementations.
 */

#include "lib9.h"
#include <draw.h>
#include <stdlib.h>
#include <string.h>
#include "krb_render.h"

/* Render Text widget */
void
krb_render_text(KrbDrawContext *ctx, KrbWidget *widget)
{
    Point text_pos;
    char *text_content;

    if (ctx == nil || widget == nil)
        return;

    /* TODO: Get text content from widget properties */
    /* For now, use id_str as placeholder */
    text_content = widget->id_str;
    if (text_content == nil)
        text_content = "Text";

    /* Calculate text position (centered in bounds) */
    text_pos.x = widget->bounds.min.x + (int)widget->padding[3];
    text_pos.y = widget->bounds.min.y + (int)widget->padding[0];

    /* Draw text */
    krb_draw_text(ctx, text_pos, text_content, widget->foreground,
                  ctx->default_font);
}

/* Render Button widget */
void
krb_render_button(KrbDrawContext *ctx, KrbWidget *widget)
{
    Point text_pos;
    char *button_text;
    Rectangle bounds;
    int text_width, text_height;

    if (ctx == nil || widget == nil)
        return;

    bounds = widget->bounds;

    /* Draw button background */
    krb_draw_rect(ctx, bounds, widget->background);

    /* Draw button border */
    if (widget->border_width > 0) {
        krb_draw_border(ctx, bounds, widget->border_width, widget->border_color);
    }

    /* Get button text */
    button_text = widget->id_str;
    if (button_text == nil)
        button_text = "Button";

    /* Calculate text position (centered) */
    text_width = stringwidth(ctx->default_font, button_text);
    text_height = ctx->default_font->height;

    text_pos.x = bounds.min.x + (Dx(bounds) - text_width) / 2;
    text_pos.y = bounds.min.y + (Dy(bounds) - text_height) / 2;

    /* Draw text */
    krb_draw_text(ctx, text_pos, button_text, widget->foreground,
                  ctx->default_font);
}

/* Render Container widget */
void
krb_render_container(KrbDrawContext *ctx, KrbWidget *widget)
{
    /* Container rendering is handled by krb_render_widget */
    /* This is a placeholder for any container-specific rendering */
    if (ctx == nil || widget == nil)
        return;

    /* Children are rendered by krb_render_widget_tree */
}

/* Render Column widget */
void
krb_render_column(KrbDrawContext *ctx, KrbWidget *widget)
{
    /* Column rendering is handled by krb_render_widget */
    if (ctx == nil || widget == nil)
        return;

    /* Children are rendered by krb_render_widget_tree */
}

/* Render Row widget */
void
krb_render_row(KrbDrawContext *ctx, KrbWidget *widget)
{
    /* Row rendering is handled by krb_render_widget */
    if (ctx == nil || widget == nil)
        return;

    /* Children are rendered by krb_render_widget_tree */
}

/* Render Image widget */
void
krb_render_image(KrbDrawContext *ctx, KrbWidget *widget)
{
    /* TODO: Implement image rendering */
    if (ctx == nil || widget == nil)
        return;

    /* Placeholder: draw a gray rectangle */
    krb_draw_rect(ctx, widget->bounds, 0x808080FF);
}
