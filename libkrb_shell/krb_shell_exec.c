/*
 * KRB Shell Execution Engine
 * Executes shell functions from Kryon scripts
 */

#include "lib9.h"
#include <draw.h>
#include <string.h>
#include "interp.h"
#include "krb_shell.h"
#include "krb_runtime.h"

/* Forward declarations from sh.m module interface */
typedef struct Sh Sh;
typedef struct ShContext ShContext;

/*
 * Find a script function by name in the runtime
 */
static KryonScriptFunction*
find_script_function(KrbRuntime *runtime, const char *func_name)
{
	uint32_t i;
	KryonScriptFunction *func;

	if (runtime == nil || func_name == nil)
		return nil;

	/* Access the script functions from runtime */
	KryonScriptFunction **functions = (KryonScriptFunction**)runtime->shell_context;
	if (functions == nil)
		return nil;

	/* Linear search through script functions */
	for (i = 0; i < runtime->widget_count; i++) {
		func = functions[i];
		if (func != nil && func->name != nil) {
			if (strcmp(func->name, func_name) == 0)
				return func;
		}
	}

	return nil;
}

/*
 * Execute a shell command string and return result
 * This is a simplified version - a full implementation would use
 * the Sh->system() function from the shell module
 */
static int
execute_shell_code(KrbShellContext *ctx, const char *code)
{
	Module *sh_mod;
	Modlink *sh_ml;

	if (ctx == nil || ctx->runtime == nil || code == nil)
		return -1;

	sh_mod = (Module*)ctx->runtime->sh_module;
	sh_ml = (Modlink*)ctx->runtime->sh_modlink;

	if (sh_mod == nil || sh_ml == nil)
		return -1;

	/*
	 * TODO: Call Sh->system() to execute the code
	 * This requires:
	 * 1. Getting the Sh module's system() function pointer
	 * 2. Creating a String* from the code
	 * 3. Calling system() and capturing the result
	 * 4. Converting the result back to C string
	 *
	 * For now, we just log that execution was attempted
	 */
	fprint(2, "krb_shell: executing code: %s\n", code);

	return 0;
}

/*
 * Execute a script function by name
 */
int
krb_shell_execute_function(KrbShellContext *ctx, const char *func_name,
                            void *event_data)
{
	KryonScriptFunction *func;
	int result;

	USED(event_data);  /* TODO: Pass event data to shell */

	if (ctx == nil || func_name == nil)
		return -1;

	if (ctx->krb_runtime == nil)
		return -1;

	/* Find the function */
	func = find_script_function(ctx->krb_runtime, func_name);
	if (func == nil) {
		fprint(2, "krb_shell: function not found: %s\n", func_name);
		return -1;
	}

	/* Check language */
	if (func->language != nil) {
		if (strcmp(func->language, "inferno-sh") != 0 &&
		    strcmp(func->language, "sh") != 0) {
			fprint(2, "krb_shell: unsupported language: %s\n",
			       func->language);
			return -1;
		}
	}

	/* Sync variables to shell environment */
	result = krb_shell_sync_vars_to_env(ctx, ctx->krb_runtime);
	if (result != 0) {
		fprint(2, "krb_shell: failed to sync variables\n");
		return -1;
	}

	/* Execute the function code */
	result = execute_shell_code(ctx, func->code);
	if (result != 0) {
		fprint(2, "krb_shell: execution failed\n");
		return -1;
	}

	/* Sync variables back from shell environment */
	result = krb_shell_sync_env_to_vars(ctx, ctx->krb_runtime);
	if (result != 0) {
		fprint(2, "krb_shell: failed to sync variables back\n");
		return -1;
	}

	return 0;
}
