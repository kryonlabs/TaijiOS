/*
 * KRB Widget Tree Management
 *
 * Functions for managing the widget tree structure.
 */

#include "lib9.h"
#include <draw.h>
#include <stdlib.h>
#include <string.h>
#include "krb_runtime.h"

/* Hit testing - find widget at position */
KrbWidget*
krb_runtime_widget_at(KrbRuntime *runtime, Point pos)
{
    KrbWidget *widget;
    int i;

    if (runtime == nil || runtime->widgets == nil)
        return nil;

    /* Search in reverse order (top-most widgets first) */
    for (i = runtime->widget_count - 1; i >= 0; i--) {
        widget = runtime->widgets[i];

        if (widget == nil || !widget->visible)
            continue;

        /* Check if point is in widget bounds */
        if (ptinrect(pos, widget->bounds))
            return widget;
    }

    return nil;
}

/* Add child widget */
int
krb_runtime_add_child(KrbRuntime *runtime, KrbWidget *parent, KrbWidget *child)
{
    KrbWidget **new_children;
    int new_count;

    if (runtime == nil || parent == nil || child == nil)
        return -1;

    /* Check if child already has a parent */
    if (child->parent != nil)
        return -1;

    /* Allocate new children array */
    new_count = parent->child_count + 1;
    new_children = realloc(parent->children, new_count * sizeof(KrbWidget*));
    if (new_children == nil)
        return -1;

    parent->children = new_children;
    parent->children[new_count - 1] = child;
    parent->child_count = new_count;

    /* Set parent */
    child->parent = parent;

    /* Mark for layout update */
    parent->needs_layout = 1;

    return 0;
}

/* Remove widget from tree */
int
krb_runtime_remove_widget(KrbRuntime *runtime, KrbWidget *widget)
{
    KrbWidget *parent;
    int i, found;
    KrbWidget **new_children;

    if (runtime == nil || widget == nil)
        return -1;

    parent = widget->parent;

    if (parent != nil) {
        /* Remove from parent's children list */
        found = 0;
        for (i = 0; i < parent->child_count; i++) {
            if (parent->children[i] == widget) {
                found = 1;
                break;
            }
        }

        if (found) {
            /* Shift remaining children */
            for (i = i; i < parent->child_count - 1; i++) {
                parent->children[i] = parent->children[i + 1];
            }

            parent->child_count--;

            /* Shrink array */
            if (parent->child_count > 0) {
                new_children = realloc(parent->children,
                                      parent->child_count * sizeof(KrbWidget*));
                if (new_children != nil)
                    parent->children = new_children;
            } else {
                free(parent->children);
                parent->children = nil;
            }

            parent->needs_layout = 1;
        }
    }

    /* Clear parent reference */
    widget->parent = nil;

    return 0;
}

/* Get widget property */
int
krb_widget_get_property(KrbWidget *widget, const char *name,
                        void *value_out, size_t value_size)
{
    if (widget == nil || name == nil || value_out == nil)
        return -1;

    /* Handle common properties */
    if (strcmp(name, "visible") == 0) {
        if (value_size >= sizeof(int)) {
            *(int*)value_out = widget->visible;
            return 0;
        }
    } else if (strcmp(name, "enabled") == 0) {
        if (value_size >= sizeof(int)) {
            *(int*)value_out = widget->enabled;
            return 0;
        }
    } else if (strcmp(name, "background") == 0) {
        if (value_size >= sizeof(uint32_t)) {
            *(uint32_t*)value_out = widget->background;
            return 0;
        }
    } else if (strcmp(name, "foreground") == 0) {
        if (value_size >= sizeof(uint32_t)) {
            *(uint32_t*)value_out = widget->foreground;
            return 0;
        }
    } else if (strcmp(name, "font_size") == 0) {
        if (value_size >= sizeof(double)) {
            *(double*)value_out = widget->font_size;
            return 0;
        }
    } else if (strcmp(name, "width") == 0) {
        if (value_size >= sizeof(double)) {
            *(double*)value_out = widget->width;
            return 0;
        }
    } else if (strcmp(name, "height") == 0) {
        if (value_size >= sizeof(double)) {
            *(double*)value_out = widget->height;
            return 0;
        }
    }

    return -1;
}

/* Set widget property */
int
krb_widget_set_property(KrbWidget *widget, const char *name,
                        const void *value, size_t value_size)
{
    if (widget == nil || name == nil || value == nil)
        return -1;

    /* Handle common properties */
    if (strcmp(name, "visible") == 0) {
        if (value_size >= sizeof(int)) {
            widget->visible = *(int*)value;
            widget->needs_render = 1;
            return 0;
        }
    } else if (strcmp(name, "enabled") == 0) {
        if (value_size >= sizeof(int)) {
            widget->enabled = *(int*)value;
            widget->needs_render = 1;
            return 0;
        }
    } else if (strcmp(name, "background") == 0) {
        if (value_size >= sizeof(uint32_t)) {
            widget->background = *(uint32_t*)value;
            widget->needs_render = 1;
            return 0;
        }
    } else if (strcmp(name, "foreground") == 0) {
        if (value_size >= sizeof(uint32_t)) {
            widget->foreground = *(uint32_t*)value;
            widget->needs_render = 1;
            return 0;
        }
    } else if (strcmp(name, "font_size") == 0) {
        if (value_size >= sizeof(double)) {
            widget->font_size = *(double*)value;
            widget->needs_layout = 1;
            return 0;
        }
    } else if (strcmp(name, "width") == 0) {
        if (value_size >= sizeof(double)) {
            widget->width = *(double*)value;
            widget->needs_layout = 1;
            return 0;
        }
    } else if (strcmp(name, "height") == 0) {
        if (value_size >= sizeof(double)) {
            widget->height = *(double*)value;
            widget->needs_layout = 1;
            return 0;
        }
    }

    return -1;
}
