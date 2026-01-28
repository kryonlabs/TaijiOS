/*
 * KRB Runtime - Main Runtime Implementation
 *
 * Manages the widget tree and lifecycle of KRB applications.
 */

#include "lib9.h"
#include <draw.h>
#include <stdlib.h>
#include <string.h>
#include "krb_runtime.h"
#include "krb_shell.h"

/* Helper to read little-endian values */
static uint32_t
read_u32_le(const char *data, size_t offset)
{
    const unsigned char *p = (const unsigned char *)(data + offset);
    return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

static uint16_t
read_u16_le(const char *data, size_t offset)
{
    const unsigned char *p = (const unsigned char *)(data + offset);
    return p[0] | (p[1] << 8);
}

/* Helper function to create a widget from KrbWidgetInstance */
static KrbWidget*
create_widget_from_instance(KrbRuntime *runtime, KrbWidgetInstance *instance)
{
    KrbWidget *widget;
    KrbFile *file;
    uintptr_t offset;

    widget = mallocz(sizeof(KrbWidget), 1);
    if (widget == nil)
        return nil;

    file = runtime->krb_file;
    offset = (uintptr_t)instance - (uintptr_t)file->data;

    /* Basic properties */
    widget->id = read_u32_le(file->data, offset);
    widget->type_id = read_u32_le(file->data, offset + 4);

    /* Get ID string */
    uint32_t id_str_offset = read_u32_le(file->data, offset + 20);
    widget->id_str = krb_get_string(file, id_str_offset);

    /* Get type name */
    widget->type_name = krb_get_widget_type_name(file, instance);

    /* Initialize default values */
    widget->background = 0xFFFFFFFF;  /* White */
    widget->foreground = 0x000000FF;  /* Black */
    widget->font_size = 14.0;
    widget->border_width = 0;
    widget->border_color = 0x000000FF;
    widget->visible = 1;
    widget->enabled = 1;
    widget->flex = 0.0;
    widget->expand = 0;

    /* Initialize padding and margin to 0 */
    int i;
    for (i = 0; i < 4; i++) {
        widget->padding[i] = 0.0;
        widget->margin[i] = 0.0;
    }

    widget->needs_layout = 1;
    widget->needs_render = 1;

    return widget;
}

/* Build widget tree from KRB file */
static int
build_widget_tree(KrbRuntime *runtime)
{
    KrbFile *file;
    KrbWidget *root_widget;
    KrbWidgetInstance *root_instance;
    uint32_t i;

    file = runtime->krb_file;

    /* Find root widget instance */
    root_instance = krb_get_root_widget(file);
    if (root_instance == nil) {
        return -1;  /* No root widget found */
    }

    /* Allocate widget array */
    runtime->widget_count = file->widget_instance_count;
    runtime->widgets = mallocz(runtime->widget_count * sizeof(KrbWidget*), 1);
    if (runtime->widgets == nil) {
        return -1;
    }

    /* Create all widgets */
    for (i = 0; i < runtime->widget_count; i++) {
        KrbWidgetInstance *instance = &file->widget_instances[i];
        KrbWidget *widget = create_widget_from_instance(runtime, instance);

        if (widget == nil) {
            /* Cleanup on error */
            /* TODO: free allocated widgets */
            return -1;
        }

        runtime->widgets[i] = widget;
    }

    /* Build parent-child relationships */
    for (i = 0; i < runtime->widget_count; i++) {
        KrbWidget *widget = runtime->widgets[i];
        KrbWidgetInstance *instance = &file->widget_instances[i];
        uint32_t parent_id;
        uint32_t *child_ids;
        uint32_t child_count, j;

        /* Get parent ID */
        uintptr_t offset = (uintptr_t)instance - (uintptr_t)file->data;
        parent_id = read_u32_le(file->data, offset + 8);

        /* Find parent widget */
        if (parent_id != 0) {
            KrbWidgetInstance *parent_inst = krb_find_widget_instance(file, parent_id);
            if (parent_inst != nil) {
                /* Find index of parent instance */
                uintptr_t parent_offset = (uintptr_t)parent_inst - (uintptr_t)file->data;
                uint32_t parent_index = (parent_offset - file->header.widget_instances_offset) / 48;

                if (parent_index < runtime->widget_count) {
                    widget->parent = runtime->widgets[parent_index];
                }
            }
        }

        /* Get children */
        if (krb_get_widget_children(file, instance, &child_ids, &child_count) == 0) {
            if (child_count > 0) {
                widget->children = mallocz(child_count * sizeof(KrbWidget*), 1);
                widget->child_count = child_count;

                for (j = 0; j < child_count; j++) {
                    KrbWidgetInstance *child_inst = krb_find_widget_instance(file, child_ids[j]);
                    if (child_inst != nil) {
                        uintptr_t child_offset = (uintptr_t)child_inst - (uintptr_t)file->data;
                        uint32_t child_index = (child_offset - file->header.widget_instances_offset) / 48;

                        if (child_index < runtime->widget_count) {
                            widget->children[j] = runtime->widgets[child_index];
                        }
                    }
                }

                free(child_ids);
            }
        }
    }

    /* Set root widget */
    uintptr_t root_offset = (uintptr_t)root_instance - (uintptr_t)file->data;
    uint32_t root_index = (root_offset - file->header.widget_instances_offset) / 48;
    runtime->root = runtime->widgets[root_index];

    return 0;
}

/* Load script functions from KRB file */
static int
load_script_functions(KrbRuntime *runtime)
{
    KrbFile *file;
    uint32_t i;

    if (runtime == nil || runtime->krb_file == nil)
        return -1;

    file = runtime->krb_file;

    /* Allocate script functions array */
    if (file->script_count == 0) {
        runtime->script_functions = nil;
        runtime->script_function_count = 0;
        return 0;
    }

    runtime->script_functions = mallocz(file->script_count * sizeof(void*), 1);
    if (runtime->script_functions == nil)
        return -1;

    runtime->script_function_count = file->script_count;

    /* Load each script function */
    for (i = 0; i < file->script_count; i++) {
        KrbScript *script = &file->scripts[i];
        KryonScriptFunction *func;

        func = mallocz(sizeof(KryonScriptFunction), 1);
        if (func == nil)
            continue;

        /* Get script metadata from KRB file */
        func->script_id = script->id;
        func->language = krb_get_string(file, script->language_offset);
        func->code = krb_get_string(file, script->code_offset);
        func->name = nil;  /* TODO: Extract from metadata */
        func->parameters = nil;
        func->param_count = 0;

        runtime->script_functions[i] = func;
    }

    return 0;
}

KrbRuntime*
krb_runtime_init(KrbFile *file)
{
    KrbRuntime *runtime;

    if (file == nil)
        return nil;

    runtime = mallocz(sizeof(KrbRuntime), 1);
    if (runtime == nil)
        return nil;

    runtime->krb_file = file;
    runtime->current_theme = strdup("light");

    /* Build widget tree */
    if (build_widget_tree(runtime) != 0) {
        free(runtime);
        return nil;
    }

    /* Initialize shell runtime */
    runtime->shell_runtime = krb_shell_init();
    if (runtime->shell_runtime != nil) {
        runtime->shell_context = krb_shell_create_context(
            (KrbShellRuntime*)runtime->shell_runtime, runtime);
    }

    /* Load script functions from KRB file */
    load_script_functions(runtime);

    return runtime;
}

void
krb_runtime_cleanup(KrbRuntime *runtime)
{
    uint32_t i;

    if (runtime == nil)
        return;

    /* Cleanup shell runtime */
    if (runtime->shell_context != nil)
        krb_shell_destroy_context((KrbShellContext*)runtime->shell_context);
    if (runtime->shell_runtime != nil)
        krb_shell_cleanup((KrbShellRuntime*)runtime->shell_runtime);

    /* Free script functions */
    if (runtime->script_functions != nil) {
        for (i = 0; i < runtime->script_function_count; i++) {
            KryonScriptFunction *func = (KryonScriptFunction*)runtime->script_functions[i];
            if (func != nil)
                free(func);
        }
        free(runtime->script_functions);
    }

    /* Free all widgets */
    if (runtime->widgets != nil) {
        for (i = 0; i < runtime->widget_count; i++) {
            KrbWidget *widget = runtime->widgets[i];
            if (widget != nil) {
                if (widget->children != nil)
                    free(widget->children);
                free(widget);
            }
        }
        free(runtime->widgets);
    }

    /* Free theme string */
    if (runtime->current_theme != nil)
        free(runtime->current_theme);

    free(runtime);
}

void
krb_runtime_update(KrbRuntime *runtime)
{
    if (runtime == nil)
        return;

    /* Recalculate layout if needed */
    if (runtime->root != nil && runtime->root->needs_layout) {
        /* Layout will be calculated when bounds are known */
    }
}

KrbWidget*
krb_runtime_find_widget(KrbRuntime *runtime, uint32_t id)
{
    uint32_t i;

    if (runtime == nil || runtime->widgets == nil)
        return nil;

    for (i = 0; i < runtime->widget_count; i++) {
        KrbWidget *widget = runtime->widgets[i];
        if (widget != nil && widget->id == id)
            return widget;
    }

    return nil;
}

KrbWidget*
krb_runtime_find_widget_by_str(KrbRuntime *runtime, const char *id_str)
{
    uint32_t i;

    if (runtime == nil || runtime->widgets == nil || id_str == nil)
        return nil;

    for (i = 0; i < runtime->widget_count; i++) {
        KrbWidget *widget = runtime->widgets[i];
        if (widget != nil && widget->id_str != nil &&
            strcmp(widget->id_str, id_str) == 0)
            return widget;
    }

    return nil;
}

int
krb_runtime_set_focus(KrbRuntime *runtime, KrbWidget *widget)
{
    if (runtime == nil)
        return -1;

    /* Blur previous focused widget */
    if (runtime->focused != nil && runtime->focused != widget) {
        /* Trigger blur event */
        if (runtime->focused->events.onBlur != nil) {
            krb_runtime_trigger_event(runtime, runtime->focused, "onBlur", nil);
        }
    }

    runtime->focused = widget;

    /* Trigger focus event */
    if (widget != nil && widget->events.onFocus != nil) {
        krb_runtime_trigger_event(runtime, widget, "onFocus", nil);
    }

    return 0;
}

void
krb_runtime_clear_focus(KrbRuntime *runtime)
{
    if (runtime == nil || runtime->focused == nil)
        return;

    /* Trigger blur event */
    if (runtime->focused->events.onBlur != nil) {
        krb_runtime_trigger_event(runtime, runtime->focused, "onBlur", nil);
    }

    runtime->focused = nil;
}

void*
krb_widget_get_state(KrbWidget *widget)
{
    if (widget == nil)
        return nil;
    return widget->state;
}

void
krb_widget_set_state(KrbWidget *widget, void *state)
{
    if (widget == nil)
        return;
    widget->state = state;
}

/* Trigger event on widget */
int
krb_runtime_trigger_event(KrbRuntime *runtime, KrbWidget *widget,
                          const char *event_type, void *event_data)
{
    char *handler_name;

    if (runtime == nil || widget == nil || event_type == nil)
        return -1;

    /* Get event handler name from widget */
    handler_name = nil;
    if (strcmp(event_type, "onClick") == 0)
        handler_name = widget->events.onClick;
    else if (strcmp(event_type, "onChange") == 0)
        handler_name = widget->events.onChange;
    else if (strcmp(event_type, "onHover") == 0)
        handler_name = widget->events.onHover;
    else if (strcmp(event_type, "onFocus") == 0)
        handler_name = widget->events.onFocus;
    else if (strcmp(event_type, "onBlur") == 0)
        handler_name = widget->events.onBlur;
    else if (strcmp(event_type, "onKeyPress") == 0)
        handler_name = widget->events.onKeyPress;

    /* Execute script handler if available */
    if (handler_name != nil && runtime->shell_context != nil) {
        int result;
        result = krb_shell_execute_function(
            (KrbShellContext*)runtime->shell_context,
            handler_name,
            event_data);

        if (result == 0) {
            /* Script executed successfully */
            return 0;
        }
        /* If script execution failed, fall through to callbacks */
    }

    /* Trigger callbacks as fallback */
    if (strcmp(event_type, "onClick") == 0) {
        if (runtime->on_widget_click != nil) {
            runtime->on_widget_click(runtime, widget);
        }
    } else if (strcmp(event_type, "onChange") == 0) {
        if (runtime->on_widget_change != nil) {
            runtime->on_widget_change(runtime, widget);
        }
    }

    return 0;
}
