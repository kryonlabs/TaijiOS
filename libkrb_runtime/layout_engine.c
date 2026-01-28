/*
 * KRB Layout Engine
 *
 * Calculates widget layouts for different layout types (Column, Row, Container, Flex).
 */

#include "lib9.h"
#include <draw.h>
#include <stdlib.h>
#include <string.h>
#include "krb_runtime.h"

/* Layout a container widget (default: stack children) */
static int
layout_container(KrbRuntime *runtime, KrbWidget *widget, Rectangle available)
{
    int i;
    int x, y;

    if (widget == nil || widget->children == nil)
        return 0;

    x = available.min.x;
    y = available.min.y;

    /* Stack children at top-left */
    for (i = 0; i < widget->child_count; i++) {
        KrbWidget *child = widget->children[i];

        if (child == nil || !child->visible)
            continue;

        /* Calculate child size */
        int child_width = Dx(available);
        int child_height = Dy(available);

        if (child->width > 0)
            child_width = (int)child->width;

        if (child->height > 0)
            child_height = (int)child->height;

        /* Set child bounds */
        child->bounds = Rect(x, y, x + child_width, y + child_height);

        /* Recursively layout child */
        krb_runtime_layout_widget(runtime, child, child->bounds);

        /* Mark as laid out */
        child->needs_layout = 0;
    }

    return 0;
}

/* Layout a column (vertical layout) */
static int
layout_column(KrbRuntime *runtime, KrbWidget *widget, Rectangle available)
{
    int i;
    int y;
    int total_flex;
    int flex_height;

    if (widget == nil || widget->children == nil)
        return 0;

    y = available.min.y;

    /* Calculate total flex */
    total_flex = 0;
    for (i = 0; i < widget->child_count; i++) {
        KrbWidget *child = widget->children[i];
        if (child != nil && child->visible && child->expand)
            total_flex += (int)child->flex;
    }

    /* Calculate flexible height */
    flex_height = 0;
    if (total_flex > 0) {
        int fixed_height = 0;
        for (i = 0; i < widget->child_count; i++) {
            KrbWidget *child = widget->children[i];
            if (child != nil && child->visible && !child->expand && child->height > 0)
                fixed_height += (int)child->height;
        }
        flex_height = Dy(available) - fixed_height;
    }

    /* Layout children vertically */
    for (i = 0; i < widget->child_count; i++) {
        KrbWidget *child = widget->children[i];

        if (child == nil || !child->visible)
            continue;

        int child_x = available.min.x;
        int child_y = y;
        int child_width = Dx(available);
        int child_height = Dy(available);

        if (child->width > 0)
            child_width = (int)child->width;

        if (child->height > 0) {
            if (child->expand && total_flex > 0) {
                child_height = (int)((child->flex / total_flex) * flex_height);
            } else {
                child_height = (int)child->height;
            }
        }

        /* Apply margin */
        child_x += (int)child->margin[3];  /* left */
        child_y += (int)child->margin[0];  /* top */

        /* Set child bounds */
        child->bounds = Rect(child_x, child_y,
                            child_x + child_width,
                            child_y + child_height);

        /* Recursively layout child */
        krb_runtime_layout_widget(runtime, child, child->bounds);

        /* Mark as laid out */
        child->needs_layout = 0;

        /* Advance y position */
        y += child_height + (int)child->margin[0] + (int)child->margin[2];
    }

    return 0;
}

/* Layout a row (horizontal layout) */
static int
layout_row(KrbRuntime *runtime, KrbWidget *widget, Rectangle available)
{
    int i;
    int x;
    int total_flex;
    int flex_width;

    if (widget == nil || widget->children == nil)
        return 0;

    x = available.min.x;

    /* Calculate total flex */
    total_flex = 0;
    for (i = 0; i < widget->child_count; i++) {
        KrbWidget *child = widget->children[i];
        if (child != nil && child->visible && child->expand)
            total_flex += (int)child->flex;
    }

    /* Calculate flexible width */
    flex_width = 0;
    if (total_flex > 0) {
        int fixed_width = 0;
        for (i = 0; i < widget->child_count; i++) {
            KrbWidget *child = widget->children[i];
            if (child != nil && child->visible && !child->expand && child->width > 0)
                fixed_width += (int)child->width;
        }
        flex_width = Dx(available) - fixed_width;
    }

    /* Layout children horizontally */
    for (i = 0; i < widget->child_count; i++) {
        KrbWidget *child = widget->children[i];

        if (child == nil || !child->visible)
            continue;

        int child_x = x;
        int child_y = available.min.y;
        int child_width = Dx(available);
        int child_height = Dy(available);

        if (child->width > 0) {
            if (child->expand && total_flex > 0) {
                child_width = (int)((child->flex / total_flex) * flex_width);
            } else {
                child_width = (int)child->width;
            }
        }

        if (child->height > 0)
            child_height = (int)child->height;

        /* Apply margin */
        child_x += (int)child->margin[3];  /* left */
        child_y += (int)child->margin[0];  /* top */

        /* Set child bounds */
        child->bounds = Rect(child_x, child_y,
                            child_x + child_width,
                            child_y + child_height);

        /* Recursively layout child */
        krb_runtime_layout_widget(runtime, child, child->bounds);

        /* Mark as laid out */
        child->needs_layout = 0;

        /* Advance x position */
        x += child_width + (int)child->margin[1] + (int)child->margin[3];
    }

    return 0;
}

/* Layout a specific widget */
int
krb_runtime_layout_widget(KrbRuntime *runtime, KrbWidget *widget,
                          Rectangle available)
{
    if (runtime == nil || widget == nil)
        return -1;

    /* Set widget bounds */
    widget->bounds = available;

    /* Layout based on widget type */
    if (widget->type_name != nil) {
        if (strcmp(widget->type_name, "Column") == 0) {
            return layout_column(runtime, widget, available);
        } else if (strcmp(widget->type_name, "Row") == 0) {
            return layout_row(runtime, widget, available);
        } else if (strcmp(widget->type_name, "Container") == 0) {
            return layout_container(runtime, widget, available);
        }
    }

    /* Default: layout as container */
    return layout_container(runtime, widget, available);
}

/* Calculate layout for entire tree */
int
krb_runtime_calculate_layout(KrbRuntime *runtime,
                             int available_width,
                             int available_height)
{
    Rectangle bounds;

    if (runtime == nil || runtime->root == nil)
        return -1;

    /* Calculate layout from root */
    bounds = Rect(0, 0, available_width, available_height);

    return krb_runtime_layout_widget(runtime, runtime->root, bounds);
}
