/*
 * KRB Runtime - Public API
 *
 * Manages widget tree, styles, themes, and state for KRB applications.
 */

#ifndef KRB_RUNTIME_H
#define KRB_RUNTIME_H

#include <stdint.h>
#include <stddef.h>
#include "krb.h"

/* Forward declarations */
typedef struct KrbWidget KrbWidget;
typedef struct KrbRuntime KrbRuntime;

/* Widget structure */
struct KrbWidget {
    uint32_t id;
    uint32_t type_id;         /* 0x0001=Column, 0x0400=Text, etc. */
    char *id_str;             /* Widget ID string */
    char *type_name;          /* Type name from definition */

    KrbWidget *parent;
    KrbWidget **children;
    uint16_t child_count;

    /* Layout */
    Rectangle bounds;         /* x, y, width, height */

    /* Style properties */
    uint32_t background;      /* 0xAABBGGRR format */
    uint32_t foreground;      /* 0xAABBGGRR format */
    double padding[4];        /* top, right, bottom, left */
    double margin[4];
    double font_size;
    int border_width;
    uint32_t border_color;
    int visible;
    int enabled;

    /* Layout properties */
    double width;
    double height;
    double flex;
    int expand;

    /* Event handlers (references to script sections) */
    struct {
        char *onClick;
        char *onChange;
        char *onHover;
        char *onFocus;
        char *onBlur;
        char *onKeyPress;
    } events;

    /* State */
    void *state;
    int needs_layout;
    int needs_render;
    void *user_data;          /* Application-specific data */
};

/* Runtime structure */
struct KrbRuntime {
    KrbFile *krb_file;        /* Parsed KRB file */
    KrbWidget *root;          /* Root widget */
    KrbWidget **widgets;      /* Flat array of all widgets */
    uint32_t widget_count;

    /* Theme */
    char *current_theme;
    void *theme_variables;

    /* Event state */
    KrbWidget *hovered;
    KrbWidget *focused;
    struct {
        Point pos;
        int buttons;
    } mouse;

    /* Callbacks */
    void (*on_widget_click)(KrbRuntime *runtime, KrbWidget *widget);
    void (*on_widget_change)(KrbRuntime *runtime, KrbWidget *widget);
    void (*on_theme_change)(KrbRuntime *runtime, const char *theme);

    /* Script execution */
    void *shell_runtime;       /* KrbShellRuntime* (opaque) */
    void *shell_context;       /* KrbShellContext* (opaque) */
    void **script_functions;   /* KryonScriptFunction** array */
    uint32_t script_function_count;
};

/*
 * Runtime lifecycle
 */

/* Initialize runtime from KRB file */
KrbRuntime* krb_runtime_init(KrbFile *file);

/* Cleanup runtime */
void krb_runtime_cleanup(KrbRuntime *runtime);

/* Update runtime (process events, recalculate layout) */
void krb_runtime_update(KrbRuntime *runtime);

/*
 * Widget tree management
 */

/* Get widget by ID */
KrbWidget* krb_runtime_find_widget(KrbRuntime *runtime, uint32_t id);

/* Get widget by ID string */
KrbWidget* krb_runtime_find_widget_by_str(KrbRuntime *runtime, const char *id_str);

/* Add child widget */
int krb_runtime_add_child(KrbRuntime *runtime, KrbWidget *parent, KrbWidget *child);

/* Remove widget */
int krb_runtime_remove_widget(KrbRuntime *runtime, KrbWidget *widget);

/* Get widget at position (hit testing) */
KrbWidget* krb_runtime_widget_at(KrbRuntime *runtime, Point pos);

/*
 * Style management
 */

/* Resolve style for widget */
int krb_runtime_resolve_style(KrbRuntime *runtime, KrbWidget *widget);

/* Apply style to widget */
int krb_runtime_apply_style(KrbRuntime *runtime, KrbWidget *widget,
                            uint32_t style_id);

/*
 * Theme management
 */

/* Set active theme */
int krb_runtime_set_theme(KrbRuntime *runtime, const char *theme_name);

/* Resolve theme variable */
const char* krb_runtime_resolve_theme_var(KrbRuntime *runtime,
                                          const char *group,
                                          const char *variable);

/*
 * Property resolution
 */

/* Resolve color from value (supports hex, rgb(), theme vars) */
uint32_t krb_resolve_color(KrbRuntime *runtime, const char *value);

/* Resolve dimension (supports px, %, theme vars) */
double krb_resolve_dimension(KrbRuntime *runtime, const char *value,
                            double parent_size);

/*
 * Layout
 */

/* Calculate layout for entire tree */
int krb_runtime_calculate_layout(KrbRuntime *runtime,
                                 int available_width,
                                 int available_height);

/* Calculate layout for specific widget */
int krb_runtime_layout_widget(KrbRuntime *runtime, KrbWidget *widget,
                              Rectangle available);

/*
 * Event handling
 */

/* Trigger event on widget */
int krb_runtime_trigger_event(KrbRuntime *runtime, KrbWidget *widget,
                              const char *event_type, void *event_data);

/* Set focus to widget */
int krb_runtime_set_focus(KrbRuntime *runtime, KrbWidget *widget);

/* Clear focus */
void krb_runtime_clear_focus(KrbRuntime *runtime);

/*
 * Widget state
 */

/* Get widget state */
void* krb_widget_get_state(KrbWidget *widget);

/* Set widget state */
void krb_widget_set_state(KrbWidget *widget, void *state);

/* Get widget property */
int krb_widget_get_property(KrbWidget *widget, const char *name,
                            void *value_out, size_t value_size);

/* Set widget property */
int krb_widget_set_property(KrbWidget *widget, const char *name,
                            const void *value, size_t value_size);

#endif /* KRB_RUNTIME_H */
