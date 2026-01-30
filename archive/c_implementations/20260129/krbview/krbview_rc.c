/*
 * krbview_rc - RC Shell Integration
 *
 * Integrates the native RC shell VM for executing embedded RC scripts.
 */

#define _BSD_SOURCE
#define _DEFAULT_SOURCE
#include <lib9.h>
#include "krbview_rc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * For now, we use the existing KrbShellContext from libkrb_shell.a
 * which provides the Inferno Dis VM integration.
 *
 * TODO: In Phase 3, we'll modify this to use the native RC shell
 * from /home/wao/Projects/TaijiOS/utils/rcsh/ for better performance
 * and tighter integration.
 */

#include "krb_shell.h"

struct KrbviewRCVM {
    KrbShellContext *shell_ctx;
    KrbRuntime *krb_runtime;
    char *output_buffer;
    size_t output_size;
};

/*
 * Initialize RC shell integration
 */
KrbviewRCVM* krbview_rc_init(KrbRuntime *runtime)
{
    KrbviewRCVM *rc_vm;
    KrbShellRuntime *shell_runtime;
    KrbShellContext *shell_ctx;

    if (!runtime) {
        return NULL;
    }

    rc_vm = (KrbviewRCVM*)calloc(1, sizeof(KrbviewRCVM));
    if (!rc_vm) {
        return NULL;
    }

    rc_vm->krb_runtime = runtime;

    /* Get or create shell runtime */
    shell_runtime = (KrbShellRuntime*)runtime->shell_runtime;
    if (!shell_runtime) {
        shell_runtime = krb_shell_init();
        if (!shell_runtime) {
            free(rc_vm);
            return NULL;
        }
        runtime->shell_runtime = shell_runtime;
    }

    /* Create shell context for this runtime */
    shell_ctx = krb_shell_create_context(shell_runtime, runtime);
    if (!shell_ctx) {
        free(rc_vm);
        return NULL;
    }

    rc_vm->shell_ctx = shell_ctx;

    /* Allocate output buffer */
    rc_vm->output_size = 4096;
    rc_vm->output_buffer = (char*)calloc(1, rc_vm->output_size);
    if (!rc_vm->output_buffer) {
        krb_shell_destroy_context(shell_ctx);
        free(rc_vm);
        return NULL;
    }

    return rc_vm;
}

/*
 * Cleanup RC shell integration
 */
void krbview_rc_cleanup(KrbviewRCVM *rc_vm)
{
    if (!rc_vm) {
        return;
    }

    if (rc_vm->shell_ctx) {
        krb_shell_destroy_context(rc_vm->shell_ctx);
    }

    if (rc_vm->output_buffer) {
        free(rc_vm->output_buffer);
    }

    free(rc_vm);
}

/*
 * Execute RC script string
 */
int krbview_rc_execute_string(KrbviewRCVM *rc_vm, const char *code)
{
    /* TODO: Implement direct string execution
     * For now, this is a placeholder that would need:
     * 1. Parse the RC code into an AST
     * 2. Compile to bytecode
     * 3. Execute in the RC VM
     *
     * The native RC shell from /home/wao/Projects/TaijiOS/utils/rcsh/
     * needs to be modified to expose this functionality as a library.
     */

    fprintf(stderr, "Direct string execution not yet implemented\n");
    return -1;
}

/*
 * Execute RC script from KRB file
 */
int krbview_rc_execute_script(KrbviewRCVM *rc_vm, const char *script_name)
{
    if (!rc_vm || !rc_vm->shell_ctx || !script_name) {
        return -1;
    }

    /* Clear output buffer */
    krbview_rc_clear_output(rc_vm);

    /* Use existing shell context to execute function */
    return krb_shell_execute_function(rc_vm->shell_ctx, script_name, NULL);
}

/*
 * Variable synchronization - Widget to RC
 */
void krbview_rc_export_widget_vars(KrbviewRCVM *rc_vm, KrbWidget *widget)
{
    char value_str[256];

    if (!rc_vm || !rc_vm->shell_ctx || !widget) {
        return;
    }

    /* Export widget ID */
    krb_shell_set_var(rc_vm->shell_ctx, "widget_id", widget->id_str);

    /* Export widget type */
    krb_shell_set_var(rc_vm->shell_ctx, "widget_type", widget->type_name);

    /* Export common properties */
    snprintf(value_str, sizeof(value_str), "%d", widget->id);
    krb_shell_set_var(rc_vm->shell_ctx, "widget_numeric_id", value_str);

    /* Export widget position */
    snprintf(value_str, sizeof(value_str), "%d", widget->bounds.min.x);
    krb_shell_set_var(rc_vm->shell_ctx, "widget_x", value_str);

    snprintf(value_str, sizeof(value_str), "%d", widget->bounds.min.y);
    krb_shell_set_var(rc_vm->shell_ctx, "widget_y", value_str);

    snprintf(value_str, sizeof(value_str), "%d",
             widget->bounds.max.x - widget->bounds.min.x);
    krb_shell_set_var(rc_vm->shell_ctx, "widget_width", value_str);

    snprintf(value_str, sizeof(value_str), "%d",
             widget->bounds.max.y - widget->bounds.min.y);
    krb_shell_set_var(rc_vm->shell_ctx, "widget_height", value_str);

    /* Export widget state */
    krb_shell_set_var(rc_vm->shell_ctx, "widget_enabled",
                     widget->enabled ? "1" : "0");
    krb_shell_set_var(rc_vm->shell_ctx, "widget_visible",
                     widget->visible ? "1" : "0");
}

/*
 * Variable synchronization - RC to Widget
 */
void krbview_rc_import_widget_vars(KrbviewRCVM *rc_vm, KrbWidget *widget)
{
    char *value;

    if (!rc_vm || !rc_vm->shell_ctx || !widget) {
        return;
    }

    /* Import and apply text property if changed */
    value = krb_shell_get_var(rc_vm->shell_ctx, "widget_text");
    if (value) {
        /* TODO: Set widget text property */
        /* This would require a property setter API */
        free(value);
    }

    /* Import and apply enabled state */
    value = krb_shell_get_var(rc_vm->shell_ctx, "widget_enabled");
    if (value) {
        widget->enabled = (strcmp(value, "1") == 0);
        free(value);
    }

    /* Import and apply visibility */
    value = krb_shell_get_var(rc_vm->shell_ctx, "widget_visible");
    if (value) {
        widget->visible = (strcmp(value, "1") == 0);
        free(value);
    }
}

/*
 * Set event data for RC scripts
 */
void krbview_rc_set_event_data(KrbviewRCVM *rc_vm,
                              const char *event_type,
                              int mouse_x,
                              int mouse_y,
                              int key,
                              const char *widget_id)
{
    char value_str[64];

    if (!rc_vm || !rc_vm->shell_ctx) {
        return;
    }

    /* Set event type */
    if (event_type) {
        krb_shell_set_var(rc_vm->shell_ctx, "event_type", event_type);
    }

    /* Set mouse position */
    snprintf(value_str, sizeof(value_str), "%d", mouse_x);
    krb_shell_set_var(rc_vm->shell_ctx, "mouse_x", value_str);

    snprintf(value_str, sizeof(value_str), "%d", mouse_y);
    krb_shell_set_var(rc_vm->shell_ctx, "mouse_y", value_str);

    /* Set key */
    snprintf(value_str, sizeof(value_str), "%d", key);
    krb_shell_set_var(rc_vm->shell_ctx, "key", value_str);

    /* Set widget ID */
    if (widget_id) {
        krb_shell_set_var(rc_vm->shell_ctx, "widget_id", widget_id);
    }
}

/*
 * Get RC output
 */
const char* krbview_rc_get_output(KrbviewRCVM *rc_vm)
{
    if (!rc_vm) {
        return "";
    }

    return rc_vm->output_buffer;
}

/*
 * Clear RC output buffer
 */
void krbview_rc_clear_output(KrbviewRCVM *rc_vm)
{
    if (!rc_vm || !rc_vm->output_buffer) {
        return;
    }

    rc_vm->output_buffer[0] = '\0';
}

/*
 * Set variable value in RC environment
 */
int krbview_rc_set_var(KrbviewRCVM *rc_vm, const char *name, const char *value)
{
    if (!rc_vm || !rc_vm->shell_ctx || !name || !value) {
        return -1;
    }

    return krb_shell_set_var(rc_vm->shell_ctx, name, value);
}

/*
 * Get variable value from RC environment
 */
const char* krbview_rc_get_var(KrbviewRCVM *rc_vm, const char *name)
{
    if (!rc_vm || !rc_vm->shell_ctx || !name) {
        return NULL;
    }

    return krb_shell_get_var(rc_vm->shell_ctx, name);
}
