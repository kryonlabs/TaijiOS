/*
 * KRB Shell - Inferno Shell Integration for Kryon
 *
 * Provides script execution capabilities using the Inferno shell.
 */

#ifndef KRB_SHELL_H
#define KRB_SHELL_H

#include <stdint.h>

/* Forward declarations to avoid circular dependencies */
typedef struct KrbRuntime KrbRuntime;
typedef struct KrbShellRuntime KrbShellRuntime;
typedef struct KrbShellContext KrbShellContext;

/*
 * Script function structure
 * Stores parsed function information from KRB file
 */
typedef struct KryonScriptFunction {
	char *name;               /* Function name */
	char *language;           /* "inferno-sh", "sh", "limbo", etc. */
	char *code;               /* Source code */
	char **parameters;        /* Parameter names */
	uint32_t param_count;     /* Number of parameters */
	uint32_t script_id;       /* ID from KRB file */
} KryonScriptFunction;

/*
 * Shell Runtime
 * Manages the Dis VM and shell module instance
 */
struct KrbShellRuntime {
	void *sh_module;          /* Module* - loaded /dis/sh.dis */
	void *sh_modlink;         /* Modlink* - module instance */
	void *sh_context_ref;     /* ref Sh->Context */
	int initialized;
};

/*
 * Shell Context
 * Execution context for a single runtime
 */
struct KrbShellContext {
	KrbShellRuntime *runtime;
	void *prog;               /* Prog* - Dis program context */
	KrbRuntime *krb_runtime;  /* Back-reference to Kryon runtime */
};

/*
 * Initialize shell runtime (loads sh.dis)
 * Returns: KrbShellRuntime pointer on success, NULL on error
 */
KrbShellRuntime* krb_shell_init(void);

/*
 * Create execution context for runtime
 * Returns: KrbShellContext pointer on success, NULL on error
 */
KrbShellContext* krb_shell_create_context(KrbShellRuntime *sh, KrbRuntime *rt);

/*
 * Execute shell function by name
 * Returns: 0 on success, -1 on error
 */
int krb_shell_execute_function(KrbShellContext *ctx, const char *func_name,
                                void *event_data);

/*
 * Variable synchronization
 */

/* Sync Kryon variables to shell environment (before execution) */
int krb_shell_sync_vars_to_env(KrbShellContext *ctx, KrbRuntime *rt);

/* Sync shell environment to Kryon variables (after execution) */
int krb_shell_sync_env_to_vars(KrbShellContext *ctx, KrbRuntime *rt);

/* Set individual variable in shell environment */
int krb_shell_set_var(KrbShellContext *ctx, const char *name, const char *value);

/* Get individual variable from shell environment */
char* krb_shell_get_var(KrbShellContext *ctx, const char *name);

/*
 * Cleanup
 */
void krb_shell_destroy_context(KrbShellContext *ctx);
void krb_shell_cleanup(KrbShellRuntime *sh);

#endif /* KRB_SHELL_H */
