/*
 * KRB Shell Runtime - Dis VM Initialization and Module Loading
 */

#include "lib9.h"
#include <string.h>
#include <draw.h>
#include "interp.h"
#include "krb_shell.h"
#include "krb_runtime.h"

/*
 * Initialize the shell runtime
 * Loads /dis/sh.dis into memory and creates a module instance
 */
KrbShellRuntime*
krb_shell_init(void)
{
	KrbShellRuntime *sh;
	Module *mod;
	Modlink *ml;

	sh = mallocz(sizeof(KrbShellRuntime), 1);
	if (sh == nil) {
		fprint(2, "krb_shell: failed to allocate runtime\n");
		return nil;
	}

	/* Load the shell module */
	mod = load("/dis/sh.dis");
	if (mod == nil) {
		fprint(2, "krb_shell: failed to load /dis/sh.dis\n");
		free(sh);
		return nil;
	}

	/* Create a module instance */
	ml = mklinkmod(mod, 0);
	if (ml == nil) {
		fprint(2, "krb_shell: failed to create module instance\n");
		unload(mod);
		free(sh);
		return nil;
	}

	sh->sh_module = mod;
	sh->sh_modlink = ml;
	sh->sh_context_ref = nil;  /* Created per-context */
	sh->initialized = 1;

	return sh;
}

/*
 * Create an execution context for a Kryon runtime
 */
KrbShellContext*
krb_shell_create_context(KrbShellRuntime *sh, KrbRuntime *rt)
{
	KrbShellContext *ctx;

	if (sh == nil || !sh->initialized) {
		fprint(2, "krb_shell: runtime not initialized\n");
		return nil;
	}

	ctx = mallocz(sizeof(KrbShellContext), 1);
	if (ctx == nil) {
		fprint(2, "krb_shell: failed to allocate context\n");
		return nil;
	}

	ctx->runtime = sh;
	ctx->krb_runtime = rt;
	ctx->prog = nil;  /* Will be created on first execution */

	return ctx;
}

/*
 * Destroy execution context
 */
void
krb_shell_destroy_context(KrbShellContext *ctx)
{
	if (ctx == nil)
		return;

	/* Clean up any Prog references */
	if (ctx->prog != nil) {
		/* Note: Prog cleanup is handled by the VM */
		ctx->prog = nil;
	}

	free(ctx);
}

/*
 * Cleanup shell runtime
 */
void
krb_shell_cleanup(KrbShellRuntime *sh)
{
	if (sh == nil)
		return;

	if (sh->sh_module != nil)
		unload((Module*)sh->sh_module);

	/* Note: Modlink is cleaned up when module is unloaded */

	free(sh);
}
