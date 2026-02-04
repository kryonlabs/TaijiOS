implement TestSyn;

include "sys.m";
	sys: Sys;

include "draw.m";

include "syntax.m";
	syntaxmod: Syntax;

TestSyn: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	syntaxmod = load Syntax Syntax->PATH;

	if(syntaxmod == nil) {
		sys->fprint(sys->fildes(2), "Failed to load Syntax: %r\n");
		return;
	}

	syntaxmod->init();
	sys->print("Syntax module enabled: %d\n", syntaxmod->enabled());

	lang := syntaxmod->detect_language("test.b");
	sys->print("Language for test.b: %s\n", lang);

	code := "implement Test;";
	tokens := syntaxmod->parse_limbo(code);
	sys->print("Parsed %d tokens\n", len tokens);
}
