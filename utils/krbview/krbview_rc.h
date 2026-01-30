/*
 * krbview_rc - RC Shell Integration
 *
 * Integrates the RC shell VM for executing embedded RC scripts.
 * Provides variable synchronization between KRB widgets and RC environment.
 */

#ifndef KRBVIEW_RC_H
#define KRBVIEW_RC_H

#include "krb_runtime.h"

/*
 * RC VM opaque handle
 */
typedef struct KrbviewRCVM KrbviewRCVM;

/*
 * Initialize RC shell integration
 *
 * Creates and initializes an RC VM for script execution.
 * Returns: RC VM handle on success, NULL on error
 */
KrbviewRCVM* krbview_rc_init(KrbRuntime *runtime);

/*
 * Cleanup RC shell integration
 */
void krbview_rc_cleanup(KrbviewRCVM *rc_vm);

/*
 * Execute RC script string
 *
 * Executes RC code in the VM context.
 * Returns: 0 on success, -1 on error
 */
int krbview_rc_execute_string(KrbviewRCVM *rc_vm, const char *code);

/*
 * Execute RC script from KRB file
 *
 * Executes a named script function from the KRB file.
 * Returns: 0 on success, -1 on error
 */
int krbview_rc_execute_script(KrbviewRCVM *rc_vm, const char *script_name);

/*
 * Variable synchronization - Widget to RC
 *
 * Exports widget properties as RC variables before script execution.
 * Typical pattern: export vars → execute script → import vars
 */
void krbview_rc_export_widget_vars(KrbviewRCVM *rc_vm, KrbWidget *widget);

/*
 * Variable synchronization - RC to Widget
 *
 * Imports RC variables back to widget properties after script execution.
 */
void krbview_rc_import_widget_vars(KrbviewRCVM *rc_vm, KrbWidget *widget);

/*
 * Set event data for RC scripts
 *
 * Sets special RC variables for event data:
 *   $event_type - "click", "change", "keydown", etc.
 *   $mouse_x, $mouse_y - Mouse position
 *   $key - Keyboard input
 *   $widget_id - Source widget ID
 */
void krbview_rc_set_event_data(KrbviewRCVM *rc_vm,
                              const char *event_type,
                              int mouse_x,
                              int mouse_y,
                              int key,
                              const char *widget_id);

/*
 * Get RC output
 *
 * Returns captured stdout from RC script execution.
 * Returns: Output string, or NULL if no output
 */
const char* krbview_rc_get_output(KrbviewRCVM *rc_vm);

/*
 * Clear RC output buffer
 */
void krbview_rc_clear_output(KrbviewRCVM *rc_vm);

/*
 * Set variable value in RC environment
 *
 * Sets or creates a variable in the RC VM.
 * Returns: 0 on success, -1 on error
 */
int krbview_rc_set_var(KrbviewRCVM *rc_vm, const char *name, const char *value);

/*
 * Get variable value from RC environment
 *
 * Returns: Variable value, or NULL if not found
 */
const char* krbview_rc_get_var(KrbviewRCVM *rc_vm, const char *name);

/*
 * Built-in RC functions for widget manipulation
 *
 * These are exposed to RC scripts for manipulating widgets:
 *
 *   get_widget_prop <widget_id> <property>
 *       - Get widget property value
 *
 *   set_widget_prop <widget_id> <property> <value>
 *       - Set widget property value
 *
 *   echo <args...>
 *       - Print to output buffer (shown in status bar)
 */

#endif /* KRBVIEW_RC_H */
