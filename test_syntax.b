implement TestSyntax;

include "sys.m";
include "syntax.m";

sys : Sys;
syntaxmod : Syntax;

init(nil: list of string)
{
    sys = load Sys Sys->PATH;
    syntaxmod = load Syntax Syntax->PATH;

    if (syntaxmod == nil) {
        sys->fprint(sys->fildes(2), "Failed to load Syntax module: %r\n");
        return;
    }

    syntaxmod->init();
    sys->print("Syntax module enabled: %d\n", syntaxmod->enabled());

    # Test language detection
    lang := syntaxmod->detect_language("test.b");
    sys->print("Language for test.b: %s\n", lang);

    lang = syntaxmod->detect_language("main.c");
    sys->print("Language for main.c: %s\n", lang);

    # Test parsing Limbo code
    code := "implement Test;\n\nfn hello() {\n\treturn 1;\n}\n";
    tokens := syntaxmod->parse_limbo(code);
    sys->print("Parsed %d tokens\n", len tokens);

    for (i := 0; i < len tokens; i++) {
        t := tokens[i];
        sys->print("Token %d: type=%d start=%d end=%d\n", i, t.toktype, t.start, t.end);
    }
}
