implement Shellbuiltin;

#
# kryonget - Get Kryon variable value
# Usage: kryonget varname
#
# Returns the value of a Kryon variable as a string
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
	c.addbuiltin("kryonget", myself);
	return nil;
}

runbuiltin(nil: ref Context, nil: Sh, cmd: list of ref Listnode, nil: int): string
{
	if (cmd == nil || tl cmd == nil)
		return "usage: kryonget varname";

	# Get variable name
	varname := (hd tl cmd).word;
	if (varname == nil)
		return "usage: kryonget varname";

	#
	# TODO: Interface with Kryon runtime to get variable value
	# For now, just return empty string
	#
	sys->print("\n");

	return nil;
}

runsbuiltin(nil: ref Context, nil: Sh, nil: list of ref Listnode): list of ref Listnode
{
	return nil;
}

whatis(nil: ref Context, nil: Sh, name: string, wtype: int): string
{
	if (name != "kryonget")
		return nil;
	if (wtype == BUILTIN)
		return "builtin";
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}
