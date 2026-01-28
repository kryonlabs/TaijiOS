implement Shellbuiltin;

#
# kryonset - Set Kryon variable value
# Usage: kryonset varname value
#
# Sets a Kryon variable to the specified value
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;

myself: Shellbuiltin;

initbuiltin(c: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		return sys->sprint("cannot load self: %r");
	c.addbuiltin("kryonset", myself);
	return nil;
}

runbuiltin(nil: ref Context, nil: Sh, cmd: list of ref Listnode, nil: int): string
{
	if (cmd == nil || tl cmd == nil || tl tl cmd == nil)
		return "usage: kryonset varname value";

	# Get variable name and value
	varname := (hd tl cmd).word;
	value := (hd tl tl cmd).word;

	if (varname == nil || value == nil)
		return "usage: kryonset varname value";

	#
	# TODO: Interface with Kryon runtime to set variable value
	# For now, just echo what we would set
	#
	sys->print("kryonset: %s = %s\n", varname, value);

	return nil;
}

runsbuiltin(nil: ref Context, nil: Sh, nil: list of ref Listnode): list of ref Listnode
{
	return nil;
}

whatis(nil: ref Context, nil: Sh, name: string, wtype: int): string
{
	if (name != "kryonset")
		return nil;
	if (wtype == BUILTIN)
		return "builtin";
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}
