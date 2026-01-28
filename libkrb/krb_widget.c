/*
 * KRB Widget Tree Builder
 *
 * Constructs the widget tree from parsed KRB file data.
 */

#include "lib9.h"
#include "krb.h"
#include "krb_types.h"

/* Get property for a widget instance */
KrbProperty*
krb_get_widget_property(KrbFile *file, KrbWidgetInstance *widget,
                        const char *property_name)
{
    uint32_t i, prop_offset, prop_count;
    uint32_t name_offset;
    char *name;

    if (file == nil || widget == nil || property_name == nil)
        return nil;

    uintptr_t widget_offset = (uintptr_t)widget - (uintptr_t)file->data;

    /* Get property count and offset */
    prop_count = read_u16_le(file->data, widget_offset + 14);
    prop_offset = read_u32_le(file->data, widget_offset + 28);

    for (i = 0; i < prop_count; i++) {
        /* Read property index from properties array */
        uint32_t prop_index = read_u32_le(file->data,
            file->header.properties_offset + prop_offset + i * 4);

        if (prop_index >= file->property_count)
            continue;

        KrbProperty *prop = &file->properties[prop_index];
        uintptr_t prop_offset_abs = (uintptr_t)prop - (uintptr_t)file->data;

        name_offset = read_u32_le(file->data, prop_offset_abs + 4);
        name = krb_get_string(file, name_offset);

        if (name && strcmp(name, property_name) == 0) {
            return prop;
        }
    }

    return nil;
}

/* Get event handler for a widget */
KrbEvent*
krb_get_widget_event(KrbFile *file, KrbWidgetInstance *widget,
                     const char *event_type)
{
    uint32_t i, event_offset, event_count;
    uint32_t type_offset;
    char *type;

    if (file == nil || widget == nil || event_type == nil)
        return nil;

    uintptr_t widget_offset = (uintptr_t)widget - (uintptr_t)file->data;

    /* Get event count and offset */
    event_count = read_u16_le(file->data, widget_offset + 18);
    event_offset = read_u32_le(file->data, widget_offset + 36);

    for (i = 0; i < event_count; i++) {
        /* Read event index from events array */
        uint32_t event_index = read_u32_le(file->data,
            file->header.events_offset + event_offset + i * 4);

        if (event_index >= file->event_count)
            continue;

        KrbEvent *event = &file->events[event_index];
        uintptr_t event_offset_abs = (uintptr_t)event - (uintptr_t)file->data;

        type_offset = read_u32_le(file->data, event_offset_abs + 4);
        type = krb_get_string(file, type_offset);

        if (type && strcmp(type, event_type) == 0) {
            return event;
        }
    }

    return nil;
}

/* Get children of a widget */
int
krb_get_widget_children(KrbFile *file, KrbWidgetInstance *widget,
                        uint32_t **children_out, uint32_t *count_out)
{
    uint32_t child_count, child_offset;
    uint32_t *children;
    uint32_t i;

    if (file == nil || widget == nil || children_out == nil || count_out == nil)
        return -1;

    uintptr_t widget_offset = (uintptr_t)widget - (uintptr_t)file->data;

    child_count = read_u16_le(file->data, widget_offset + 16);
    child_offset = read_u32_le(file->data, widget_offset + 32);

    if (child_count == 0) {
        *children_out = nil;
        *count_out = 0;
        return 0;
    }

    children = mallocz(child_count * sizeof(uint32_t), 1);
    if (children == nil)
        return -1;

    for (i = 0; i < child_count; i++) {
        children[i] = read_u32_le(file->data,
            file->header.widget_instances_offset + child_offset + i * 4);
    }

    *children_out = children;
    *count_out = child_count;

    return 0;
}

/* Find parent of a widget */
KrbWidgetInstance*
krb_find_widget_parent(KrbFile *file, KrbWidgetInstance *widget)
{
    uint32_t parent_id;

    if (file == nil || widget == nil)
        return nil;

    uintptr_t widget_offset = (uintptr_t)widget - (uintptr_t)file->data;
    parent_id = read_u32_le(file->data, widget_offset + 8);

    if (parent_id == 0)
        return nil;  /* Root widget */

    return krb_find_widget_instance(file, parent_id);
}

/* Get root widget of the tree */
KrbWidgetInstance*
krb_get_root_widget(KrbFile *file)
{
    uint32_t i;

    if (file == nil || file->widget_instances == nil)
        return nil;

    for (i = 0; i < file->widget_instance_count; i++) {
        KrbWidgetInstance *widget = &file->widget_instances[i];
        uintptr_t offset = (uintptr_t)widget - (uintptr_t)file->data;
        uint32_t parent_id = read_u32_le(file->data, offset + 8);

        if (parent_id == 0)  /* No parent = root */
            return widget;
    }

    return nil;
}

/* Count total widgets in tree (recursive) */
static uint32_t
count_widgets_recursive(KrbFile *file, KrbWidgetInstance *widget)
{
    uint32_t *children;
    uint32_t child_count, i;
    uint32_t total = 1;  /* Count self */

    if (krb_get_widget_children(file, widget, &children, &child_count) == 0) {
        for (i = 0; i < child_count; i++) {
            KrbWidgetInstance *child = krb_find_widget_instance(file, children[i]);
            if (child != nil) {
                total += count_widgets_recursive(file, child);
            }
        }
        free(children);
    }

    return total;
}

/* Validate widget tree (check for cycles, etc.) */
int
krb_validate_widget_tree(KrbFile *file)
{
    KrbWidgetInstance *root;
    uint32_t widget_count;

    if (file == nil)
        return -1;

    root = krb_get_root_widget(file);
    if (root == nil) {
        /* No root widget found */
        return -1;
    }

    /* Count widgets and verify against header */
    widget_count = count_widgets_recursive(file, root);

    if (widget_count != file->widget_instance_count) {
        /* Tree structure mismatch */
        return -1;
    }

    return 0;
}

/* Get widget depth in tree (for debugging) */
int
krb_get_widget_depth(KrbFile *file, KrbWidgetInstance *widget)
{
    KrbWidgetInstance *parent;
    int depth = 0;

    while ((parent = krb_find_widget_parent(file, widget)) != nil) {
        depth++;
        widget = parent;
    }

    return depth;
}

/* Iterate over all widgets in tree (pre-order traversal) */
int
krb_traverse_widgets(KrbFile *file, KrbWidgetInstance *root,
                     int (*callback)(KrbFile*, KrbWidgetInstance*, void*),
                     void *userdata)
{
    uint32_t *children;
    uint32_t child_count, i;
    int result;

    if (file == nil || root == nil || callback == nil)
        return -1;

    /* Visit this widget */
    result = callback(file, root, userdata);
    if (result != 0)
        return result;

    /* Visit children */
    if (krb_get_widget_children(file, root, &children, &child_count) == 0) {
        for (i = 0; i < child_count; i++) {
            KrbWidgetInstance *child = krb_find_widget_instance(file, children[i]);
            if (child != nil) {
                result = krb_traverse_widgets(file, child, callback, userdata);
                if (result != 0)
                    break;
            }
        }
        free(children);
    }

    return result;
}
