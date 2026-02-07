implement Kryon;

Kryon: module
{
    init: fn(ctxt: ref Draw->Context, argv: list of string);
};

include "sys.m";
    sys: Sys;
include "draw.m";
include "bufio.m";
    bufio: Bufio;
    Iobuf: import bufio;
include "sh.m";
    sh: Sh;
include "ast.m";
    ast: Ast;
include "lexer.m";
    lexer: Lexer;

# Import useful types from ast
Program, Widget, Property, Value, ReactiveFunction, ModuleImport, SymbolTable: import ast;

# Import useful types from lexer
LexerObj, Token: import lexer;

# Internal Parser ADT
Parser: adt {
    l: ref LexerObj;
    peek_tok: ref Token;
    has_peek: int;

    create: fn(l: ref LexerObj): ref Parser;
    next: fn(p: self ref Parser): ref Token;
    peek: fn(p: self ref Parser): ref Token;
    expect: fn(p: self ref Parser, typ: int): (ref Token, string);
};

Parser.create(l: ref LexerObj): ref Parser
{
    return ref Parser(l, nil, 0);
}

Parser.next(p: self ref Parser): ref Token
{
    if (p.has_peek) {
        p.has_peek = 0;
        return p.peek_tok;
    }
    return lexer->lex(p.l);
}

Parser.peek(p: self ref Parser): ref Token
{
    if (!p.has_peek) {
        p.peek_tok = lexer->lex(p.l);
        p.has_peek = 1;
    }
    return p.peek_tok;
}

Parser.expect(p: self ref Parser, typ: int): (ref Token, string)
{
    tok := p.next();
    if (tok.toktype != typ) {
        return (nil, sys->sprint("line %d: expected token type %d, got %d",
            tok.lineno, typ, tok.toktype));
    }
    return (tok, nil);
}

# Internal Codegen ADT
Codegen: adt {
    module_name: string;
    output: ref Sys->FD;
    tk_cmds: list of string;
    widget_counter: int;
    callbacks: list of (string, string);
    width: int;
    height: int;
    reactive_bindings: list of (string, string, string);  # (widget_path, property_name, fn_name)
    is_draw_backend: int;    # 1 if using Draw/wmclient
    ondraw_fn: string;        # name of onDraw function
    ondraw_interval: int;     # timer interval in ms
    oninit_fn: string;        # name of onInit function

    create: fn(output: ref Sys->FD, module_name: string): ref Codegen;
};

Codegen.create(output: ref Sys->FD, module_name: string): ref Codegen
{
    return ref Codegen(module_name, output, nil, 0, nil, 0, 0, nil, 0, "", 0, "");
}

# Module info for code generation
Module: adt {
    mod_file: string;  # module file name (e.g., "sys", "draw")
    var_name: string;  # variable name (e.g., "sys", "draw")
    type_name: string; # type name (e.g., "Sys", "Draw")
};

# =========================================================================
# Parser functions
# =========================================================================

# Format error message with line number
fmt_error(p: ref Parser, msg: string): string
{
    lineno := lexer->get_lineno(p.l);
    return sys->sprint("line %d: %s", lineno, msg);
}

# Determine if we should add a space between current and next token
should_add_space(curr_toktype: int, next_toktype: int): int
{
    # No space after opening delimiters
    if (curr_toktype == '(' || curr_toktype == '[' || curr_toktype == '{' ||
        curr_toktype == ':')
        return 0;

    # No space before closing delimiters or separators
    if (next_toktype == ')' || next_toktype == ']' || next_toktype == '}' ||
        next_toktype == ',' || next_toktype == ';' || next_toktype == '.' ||
        next_toktype == ':' || next_toktype == '[')
        return 0;

    # No space around the arrow operator
    if (curr_toktype == Lexer->TOKEN_ARROW || next_toktype == Lexer->TOKEN_ARROW)
        return 0;

    # No space before opening parenthesis (function calls)
    if (next_toktype == '(')
        return 0;

    # No space after dot operator
    if (curr_toktype == '.')
        return 0;

    # No space around compound operators (+=, -=, ==, !=, <=, >=, ++, --, *=, /=, %=)
    if (is_compound_operator(curr_toktype) || is_compound_operator(next_toktype))
        return 0;

    # Default: add space for keywords and identifiers
    return 1;
}

# Check if token type is a compound operator
is_compound_operator(toktype: int): int
{
    if (toktype == '+' + 256 || toktype == '-' + 256 || toktype == '=' + 256 ||
        toktype == '!' + 256 || toktype == '<' + 256 || toktype == '>' + 256 ||
        toktype == '+' + 512 || toktype == '-' + 512 ||
        toktype == '*' + 256 || toktype == '/' + 256 || toktype == '%' + 256)
        return 1;
    return 0;
}

# Parse a use statement: use module_name [alias]
parse_use_statement(p: ref Parser): (ref ModuleImport, string)
{
    # Expect "use" keyword
    (use_tok, err1) := p.expect(Lexer->TOKEN_IDENTIFIER);
    if (err1 != nil) {
        return (nil, err1);
    }
    if (use_tok.string_val != "use") {
        return (nil, fmt_error(p, "expected 'use' keyword"));
    }

    # Expect module name
    (module_tok, err2) := p.expect(Lexer->TOKEN_IDENTIFIER);
    if (err2 != nil) {
        return (nil, err2);
    }
    module_name := module_tok.string_val;

    return (ast->moduleimport_create(module_name, ""), nil);
}

# Parse a reactive function declaration: name: fn() = expression @ N
# OR: name: fn() = expression @ varname
parse_reactive_function(p: ref Parser): (ref ReactiveFunction, string)
{
    # Parse name (before ":")
    (name_tok, err1) := p.expect(Lexer->TOKEN_IDENTIFIER);
    if (err1 != nil) {
        return (nil, err1);
    }
    name := name_tok.string_val;

    # Expect ":"
    (tok1, err2) := p.expect(':');
    if (err2 != nil) {
        return (nil, fmt_error(p, "expected ':' after reactive function name"));
    }

    # Expect "fn"
    (fn_tok, err3) := p.expect(Lexer->TOKEN_IDENTIFIER);
    if (err3 != nil) {
        return (nil, err3);
    }
    if (fn_tok.string_val != "fn") {
        return (nil, fmt_error(p, "expected 'fn' keyword"));
    }

    # Expect "()"
    (tok2, err4) := p.expect('(');
    if (err4 != nil) {
        return (nil, err4);
    }
    (tok3, err5) := p.expect(')');
    if (err5 != nil) {
        return (nil, err5);
    }

    # Expect "="
    (tok4, err6) := p.expect('=');
    if (err6 != nil) {
        return (nil, err6);
    }

    # Parse expression until "@"
    expr := "";
    while (p.peek().toktype != Lexer->TOKEN_AT) {
        tok := p.next();

        # Build expression from tokens
        if (tok.toktype == Lexer->TOKEN_STRING) {
            expr += "\"" + tok.string_val + "\"";
        } else if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
            expr += tok.string_val;
        } else if (tok.toktype == Lexer->TOKEN_NUMBER) {
            expr += sys->sprint("%bd", tok.number_val);
        } else if (tok.toktype == Lexer->TOKEN_ARROW) {
            expr += "->";
        } else if (tok.toktype >= 32 && tok.toktype <= 126) {
            # Single char token
            expr += sys->sprint("%c", tok.toktype);
        }

        # Add space for next token (with proper spacing rules)
        next_tok := p.peek();
        if (next_tok.toktype != Lexer->TOKEN_AT &&
            should_add_space(tok.toktype, next_tok.toktype)) {
            expr += " ";
        }
    }

    # Expect "@"
    (tok5, err7) := p.expect(Lexer->TOKEN_AT);
    if (err7 != nil) {
        return (nil, err7);
    }

    # Check what follows @
    next_tok := p.peek();

    if (next_tok.toktype == Lexer->TOKEN_NUMBER) {
        # Time-based: @ 1000
        p.next();
        interval := int next_tok.number_val;
        return (ast->reactivefn_create(name, expr, interval, nil), nil);
    } else if (next_tok.toktype == Lexer->TOKEN_IDENTIFIER) {
        # Var-based: @ var1, var2
        watch_vars: ref Ast->WatchVar = nil;
        while (p.peek().toktype == Lexer->TOKEN_IDENTIFIER) {
            var_tok := p.next();
            wv := ast->watchvar_create(var_tok.string_val);
            watch_vars = ast->watchvar_list_add(watch_vars, wv);

            # Check for comma
            if (p.peek().toktype == ',')
                p.next();
        }
        return (ast->reactivefn_create(name, expr, 0, watch_vars), nil);
    }

    return (nil, fmt_error(p, "expected number or identifier after '@'"));
}

# Parse a var declaration: var name = expr
parse_var_decl(p: ref Parser): (ref Ast->VarDecl, string)
{
    # Expect: var name = expr
    # Already have 'var' token
    name_tok := p.next();
    if (name_tok.toktype != Lexer->TOKEN_IDENTIFIER)
        return (nil, fmt_error(p, "expected variable name after 'var'"));

    name := name_tok.string_val;

    # Check for ':' (typed declaration) or '=' (initializer)
    next_tok := p.peek();
    if (next_tok.toktype == ':') {
        # Typed declaration: var name: type
        p.next();  # consume ':'

        # Parse type (could be "ref Image", "int", "string", "chan of int", etc.)
        # Stop at semicolon or any keyword (fn, var, Window, etc.)
        type_str := "";
        while (p.peek().toktype != Lexer->TOKEN_ENDINPUT &&
               p.peek().toktype != ';') {
            tok := p.peek();
            # Stop if we hit a keyword (these signal end of type declaration)
            if (tok.toktype >= Lexer->TOKEN_VAR && tok.toktype <= Lexer->TOKEN_CENTER)
                break;
            if (tok.toktype == Lexer->TOKEN_AT || tok.toktype == Lexer->TOKEN_ARROW)
                break;

            p.next();  # consume the token
            if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
                type_str += tok.string_val;
            } else if (tok.toktype >= 32 && tok.toktype <= 126) {
                type_str += sys->sprint("%c", tok.toktype);
            }
            # Add space between tokens if needed
            if (p.peek().toktype != Lexer->TOKEN_ENDINPUT &&
                p.peek().toktype != ';') {
                peek_tok := p.peek();
                # Stop at keywords
                if (peek_tok.toktype >= Lexer->TOKEN_VAR && peek_tok.toktype <= Lexer->TOKEN_CENTER)
                    break;
                if (peek_tok.toktype == Lexer->TOKEN_AT || peek_tok.toktype == Lexer->TOKEN_ARROW)
                    break;
                if (should_add_space(tok.toktype, peek_tok.toktype))
                    type_str += " ";
            }
        }

        # Optional ';'
        if (p.peek().toktype == ';')
            p.next();  # consume ';'

        # No initialization expression for typed declarations (value set in functions)
        return (ast->var_decl_create(name, type_str, "", nil), nil);
    }

    # Expect '=' (initializer style: var name = expr)
    (eq_tok, err) := p.expect('=');
    if (err != nil)
        return (nil, err);

    # Parse initialization expression
    init_expr := "";
    while (p.peek().toktype != Lexer->TOKEN_ENDINPUT &&
           p.peek().toktype != Lexer->TOKEN_ENDINPUT &&
           p.peek().toktype != '\n') {
        tok := p.next();
        if (tok.toktype == Lexer->TOKEN_STRING) {
            init_expr += "\"" + tok.string_val + "\"";
        } else if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
            init_expr += tok.string_val;
        } else if (tok.toktype == Lexer->TOKEN_NUMBER) {
            init_expr += sys->sprint("%bd", tok.number_val);
        } else if (tok.toktype == Lexer->TOKEN_ARROW) {
            init_expr += "->";
        } else if (tok.toktype >= 32 && tok.toktype <= 126) {
            init_expr += sys->sprint("%c", tok.toktype);
        }
        next_tok := p.peek();
        if (next_tok.toktype != Lexer->TOKEN_ENDINPUT &&
            next_tok.toktype != Lexer->TOKEN_ENDINPUT &&
            next_tok.toktype != '\n' &&
            should_add_space(tok.toktype, next_tok.toktype)) {
            init_expr += " ";
        }
    }

    return (ast->var_decl_create(name, "string", init_expr, nil), nil);
}

# Parse a regular function declaration: fn name() { ... }
# OR: fn name(): type = expression @ interval
parse_function_decl(p: ref Parser): (ref Ast->FunctionDecl, string)
{
    # Expect: fn name() { ... } or fn name(): type = expression @ interval
    # Already have 'fn' token

    # Parse function name
    name_tok := p.next();
    if (name_tok.toktype != Lexer->TOKEN_IDENTIFIER)
        return (nil, fmt_error(p, "expected function name after 'fn'"));

    name := name_tok.string_val;

    # Expect "(" to start parameter list
    (tok1, err1) := p.expect('(');
    if (err1 != nil)
        return (nil, err1);

    # Skip parameters until ")" - we preserve them in the body
    # For simplicity, we just look for the matching ")"
    paren_count := 1;
    params := "";
    while (paren_count > 0 && p.peek().toktype != Lexer->TOKEN_ENDINPUT) {
        tok := p.next();
        if (tok.toktype == '(')
            paren_count++;
        else if (tok.toktype == ')')
            paren_count--;

        if (paren_count > 0) {
            # Add to params string with proper spacing
            if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
                # Check if previous char was not a space and next is not special
                if (len params > 0 && params[len params - 1] != ' ' &&
                    params[len params - 1] != '(' && params[len params - 1] != ':')
                    params += " ";
                params += tok.string_val;
            } else if (tok.toktype == ':') {
                params += ": ";
            } else if (tok.toktype == ',') {
                params += ", ";
            } else if (tok.toktype >= 32 && tok.toktype <= 126) {
                params += sys->sprint("%c", tok.toktype);
            }
        }
    }

    # Check for optional return type: : string
    return_type := "";
    if (p.peek().toktype == ':') {
        p.next();  # consume ':'
        type_tok := p.next();
        if (type_tok.toktype != Lexer->TOKEN_IDENTIFIER)
            return (nil, fmt_error(p, "expected return type identifier after ':'"));

        return_type = type_tok.string_val;
    }

    # Check for inline body (=) or block body ({)
    if (p.peek().toktype == '=') {
        # Inline function: fn name(): type = expression [@ interval]
        p.next();  # consume '='

        # Parse expression until end of line or @
        body := "";
        while (p.peek().toktype != Lexer->TOKEN_ENDINPUT &&
               p.peek().toktype != Lexer->TOKEN_AT &&
               p.peek().toktype != '\n') {
            tok := p.next();

            # Build expression from tokens
            if (tok.toktype == Lexer->TOKEN_STRING) {
                body += "\"" + limbo_escape(tok.string_val) + "\"";
            } else if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
                body += tok.string_val;
            } else if (tok.toktype == Lexer->TOKEN_NUMBER) {
                body += sys->sprint("%bd", tok.number_val);
            } else if (tok.toktype == Lexer->TOKEN_ARROW) {
                body += "->";
            } else if (tok.toktype >= 32 && tok.toktype <= 126) {
                body += sys->sprint("%c", tok.toktype);
            }

            # Add space for next token (if not end, with proper spacing rules)
            next_tok := p.peek();
            if (next_tok.toktype != Lexer->TOKEN_ENDINPUT &&
                next_tok.toktype != Lexer->TOKEN_AT &&
                next_tok.toktype != '\n' &&
                should_add_space(tok.toktype, next_tok.toktype)) {
                body += " ";
            }
        }

        # Check for reactive binding
        interval := 0;
        if (p.peek().toktype == Lexer->TOKEN_AT) {
            p.next();  # consume '@'
            num_tok := p.next();
            if (num_tok.toktype != Lexer->TOKEN_NUMBER)
                return (nil, fmt_error(p, "expected number after '@'"));

            interval = int num_tok.number_val;
        }

        # Inline functions need explicit return statement in Limbo
        # Prepend "return " and ensure semicolon at end
        if (len body > 0) {
            body = "return " + body;
            if (body[len body - 1] != ';') {
                body += ";";
            }
        }

        # Create function declaration with inline body
        fn_decl := ast->functiondecl_create(name, body);
        fn_decl.params = params;
        fn_decl.return_type = return_type;
        fn_decl.reactive_interval = interval;
        return (fn_decl, nil);
    }

    # Block body: fn name() { ... }
    (tok3, err3) := p.expect('{');
    if (err3 != nil)
        return (nil, err3);

    # Parse function body using token-based parsing
    # This avoids manual position manipulation that breaks lexer state
    body := "";
    brace_count := 1;
    while (brace_count > 0) {
        tok := p.next();
        if (tok.toktype == Lexer->TOKEN_ENDINPUT) {
            return (nil, fmt_error(p, "unterminated function body"));
        }

        # Add token to body string
        if (tok.toktype == Lexer->TOKEN_STRING) {
            body += "\"" + limbo_escape(tok.string_val) + "\"";
        } else if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
            body += tok.string_val;
        } else if (tok.toktype == Lexer->TOKEN_NUMBER) {
            body += sys->sprint("%bd", tok.number_val);
        } else if (tok.toktype == Lexer->TOKEN_ARROW) {
            body += "->";
        } else if (tok.toktype == '\n') {
            body += "\n";
        } else if (tok.toktype >= 32 && tok.toktype <= 126) {
            body += sys->sprint("%c", tok.toktype);
        } else {
            # Handle keyword tokens
            case tok.toktype {
            Lexer->TOKEN_VAR or
            Lexer->TOKEN_FN or
            Lexer->TOKEN_WINDOW or
            Lexer->TOKEN_FRAME or
            Lexer->TOKEN_BUTTON or
            Lexer->TOKEN_LABEL or
            Lexer->TOKEN_ENTRY or
            Lexer->TOKEN_CHECKBUTTON or
            Lexer->TOKEN_RADIOBUTTON or
            Lexer->TOKEN_LISTBOX or
            Lexer->TOKEN_CANVAS or
            Lexer->TOKEN_SCALE or
            Lexer->TOKEN_MENUBUTTON or
            Lexer->TOKEN_MESSAGE or
            Lexer->TOKEN_COLUMN or
            Lexer->TOKEN_ROW or
            Lexer->TOKEN_CENTER =>
                # These keywords should have been handled by identifier case
                # But if they appear as tokens, convert to string
                if (tok.toktype == Lexer->TOKEN_VAR)
                    body += "var";
                else if (tok.toktype == Lexer->TOKEN_FN)
                    body += "fn";
                else if (tok.toktype == Lexer->TOKEN_WINDOW)
                    body += "Window";
                else if (tok.toktype == Lexer->TOKEN_FRAME)
                    body += "Frame";
                else if (tok.toktype == Lexer->TOKEN_BUTTON)
                    body += "Button";
                else if (tok.toktype == Lexer->TOKEN_LABEL)
                    body += "Label";
                else if (tok.toktype == Lexer->TOKEN_ENTRY)
                    body += "Entry";
                else if (tok.toktype == Lexer->TOKEN_CHECKBUTTON)
                    body += "Checkbutton";
                else if (tok.toktype == Lexer->TOKEN_RADIOBUTTON)
                    body += "Radiobutton";
                else if (tok.toktype == Lexer->TOKEN_LISTBOX)
                    body += "Listbox";
                else if (tok.toktype == Lexer->TOKEN_CANVAS)
                    body += "Canvas";
                else if (tok.toktype == Lexer->TOKEN_SCALE)
                    body += "Scale";
                else if (tok.toktype == Lexer->TOKEN_MENUBUTTON)
                    body += "Menubutton";
                else if (tok.toktype == Lexer->TOKEN_MESSAGE)
                    body += "Message";
                else if (tok.toktype == Lexer->TOKEN_COLUMN)
                    body += "Column";
                else if (tok.toktype == Lexer->TOKEN_ROW)
                    body += "Row";
                else if (tok.toktype == Lexer->TOKEN_CENTER)
                    body += "Center";

            '+' + 256 =>
                body += "+=";
            '-' + 256 =>
                body += "-=";
            '=' + 256 =>
                body += "==";
            '!' + 256 =>
                body += "!=";
            '<' + 256 =>
                body += "<=";
            '>' + 256 =>
                body += ">=";
            '+' + 512 =>
                body += "++";
            '-' + 512 =>
                body += "--";
            '*' + 256 =>
                body += "*=";
            '/' + 256 =>
                body += "/=";
            '%' + 256 =>
                body += "%=";
            * =>
                # Unknown token, skip
                ;
            }
        }

        # Track braces
        if (tok.toktype == '{') {
            brace_count++;
        } else if (tok.toktype == '}') {
            brace_count--;
        }

        # Add space between tokens if needed (look ahead)
        if (brace_count > 0) {
            next_tok := p.peek();
            if (next_tok.toktype != Lexer->TOKEN_ENDINPUT &&
                next_tok.toktype != '}' &&
                should_add_space(tok.toktype, next_tok.toktype)) {
                body += " ";
            }
        }
    }

    # Clear peek buffer to ensure clean parser state
    # We've consumed the closing }, so reset any peeked token
    p.has_peek = 0;

    # body now includes the closing brace, so remove it
    if (len body > 0 && body[len body - 1] == '}')
        body = body[0: len body - 1];

    fn_decl := ast->functiondecl_create(name, body);
    fn_decl.params = params;
    fn_decl.return_type = return_type;
    return (fn_decl, nil);
}

# Parse a value (STRING, NUMBER, COLOR, IDENTIFIER, FN_CALL)
parse_value(p: ref Parser): (ref Value, string)
{
    tok := p.next();

    case tok.toktype {
    Lexer->TOKEN_STRING =>
        # Check for function call pattern: "name()"
        s := tok.string_val;
        if (len s > 2 && s[len s - 1] == ')' && s[len s - 2] == '(') {
            fn_name := s[0: len s - 2];
            return (ast->value_create_fn_call(fn_name), nil);
        }
        return (ast->value_create_string(s), nil);

    Lexer->TOKEN_NUMBER =>
        return (ast->value_create_number(tok.number_val), nil);

    Lexer->TOKEN_COLOR =>
        return (ast->value_create_color(tok.string_val), nil);

    Lexer->TOKEN_IDENTIFIER =>
        # Check for function call pattern: name ( )
        # Peek to see if next tokens are '(' and ')'
        id_name := tok.string_val;
        if (p.peek().toktype == '(') {
            p.next();  # consume '('
            (close_paren, err) := p.expect(')');
            if (err != nil) {
                return (nil, err);
            }
            return (ast->value_create_fn_call(id_name), nil);
        }
        return (ast->value_create_ident(id_name), nil);

    * =>
        return (nil, fmt_error(p, "expected value (string, number, color, or identifier)"));
    }
}

# Parse a property (name = value)
parse_property(p: ref Parser): (ref Property, string)
{
    tok := p.next();

    if (tok.toktype != Lexer->TOKEN_IDENTIFIER) {
        return (nil, fmt_error(p, "expected property name"));
    }

    name := tok.string_val;

    # Expect '='
    (tok1, err1) := p.expect('=');
    if (err1 != nil) {
        return (nil, err1);
    }

    # Check for reactive syntax: identifier @ number
    # But first check if it's an identifier followed by () (function call)
    if (p.peek().toktype == Lexer->TOKEN_IDENTIFIER) {
        # Peek ahead to see what comes after the identifier
        # We need to look at: identifier, then @ or (
        # But we haven't consumed the identifier yet
        # So we peek at identifier, then peek again to check next token

        # Consume the identifier
        id_tok := p.next();
        id_name := id_tok.string_val;

        # Check if next is '(' (function call)
        if (p.peek().toktype == '(') {
            p.next();  # consume '('
            (close_paren, err) := p.expect(')');
            if (err != nil) {
                return (nil, err);
            }
            prop := ast->property_create(name);
            prop.value = ast->value_create_fn_call(id_name);
            return (prop, nil);
        }

        # Check for @ reactive syntax
        if (p.peek().toktype == Lexer->TOKEN_AT) {
            p.next();  # consume @
            num_tok := p.next();
            if (num_tok.toktype != Lexer->TOKEN_NUMBER)
                return (nil, fmt_error(p, "expected number after '@'"));

            interval := int num_tok.number_val;
            prop := ast->property_create(name);
            prop.value = ast->value_create_ident(sys->sprint("%s@%d", id_name, interval));
            return (prop, nil);
        }

        # Just identifier, no @ or ()
        prop := ast->property_create(name);
        prop.value = ast->value_create_ident(id_name);
        return (prop, nil);
    }

    # Parse other value types normally
    (val, err2) := parse_value(p);
    if (err2 != nil) {
        return (nil, err2);
    }

    prop := ast->property_create(name);
    prop.value = val;

    return (prop, nil);
}

# Parse widget body content (properties and children)
parse_widget_body_content(p: ref Parser): (ref Property, ref Widget, string)
{
    props: ref Property = nil;
    children: ref Widget = nil;

    while (1) {
        tok := p.peek();

        # Check for end of body
        if (tok.toktype == '}' || tok.toktype == Lexer->TOKEN_ENDINPUT) {
            break;
        }

        # Property: identifier = value
        if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
            # Peek ahead to see if next token is '='
            (prop, err1) := parse_property(p);
            if (err1 != nil) {
                return (nil, nil, err1);
            }

            if (props == nil) {
                props = prop;
            } else {
                ast->property_list_add(props, prop);
            }
        }
        # Widget: Window/Frame/Button/etc { ... }
        else if (tok.toktype >= Lexer->TOKEN_WINDOW && tok.toktype <= Lexer->TOKEN_IMG) {
            (child, err2) := parse_widget(p);
            if (err2 != nil) {
                return (nil, nil, err2);
            }

            if (children == nil) {
                children = child;
            } else {
                ast->widget_list_add(children, child);
            }
        } else {
            return (nil, nil, fmt_error(p, "expected property or widget in body"));
        }
    }

    return (props, children, nil);
}

# Parse widget body: { ... }
parse_widget_body(p: ref Parser): (ref Widget, string)
{
    # Expect '{'
    (tok1, err1) := p.expect('{');
    if (err1 != nil) {
        return (nil, err1);
    }

    (props, children, err2) := parse_widget_body_content(p);
    if (err2 != nil) {
        return (nil, err2);
    }

    # Expect '}'
    (tok2, err3) := p.expect('}');
    if (err3 != nil) {
        return (nil, err3);
    }

    # Create a wrapper widget to hold props and children
    w := ast->widget_create(Ast->WIDGET_FRAME);
    w.props = props;
    w.children = children;
    w.is_wrapper = 1;

    return (w, nil);
}

# Parse specific widget types
parse_window(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_WINDOW);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_frame(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_FRAME);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_button(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_BUTTON);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_label(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_LABEL);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_entry(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_ENTRY);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_column(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_COLUMN);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_row(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_ROW);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_center(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_CENTER);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_checkbutton(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_CHECKBUTTON);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_radiobutton(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_RADIOBUTTON);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_listbox(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_LISTBOX);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_canvas(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_CANVAS);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_scale(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_SCALE);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_menubutton(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_MENUBUTTON);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_message(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_MESSAGE);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

parse_img(p: ref Parser): (ref Widget, string)
{
    (body, err) := parse_widget_body(p);
    if (err != nil) {
        return (nil, err);
    }

    w := ast->widget_create(Ast->WIDGET_IMG);
    w.props = body.props;
    w.children = body.children;

    return (w, nil);
}

# Parse a widget (dispatch based on type)
parse_widget(p: ref Parser): (ref Widget, string)
{
    tok := p.next();

    case tok.toktype {
    Lexer->TOKEN_WINDOW =>
        return parse_window(p);

    Lexer->TOKEN_FRAME =>
        return parse_frame(p);

    Lexer->TOKEN_BUTTON =>
        return parse_button(p);

    Lexer->TOKEN_LABEL =>
        return parse_label(p);

    Lexer->TOKEN_ENTRY =>
        return parse_entry(p);

    Lexer->TOKEN_CHECKBUTTON =>
        return parse_checkbutton(p);

    Lexer->TOKEN_RADIOBUTTON =>
        return parse_radiobutton(p);

    Lexer->TOKEN_LISTBOX =>
        return parse_listbox(p);

    Lexer->TOKEN_CANVAS =>
        return parse_canvas(p);

    Lexer->TOKEN_SCALE =>
        return parse_scale(p);

    Lexer->TOKEN_MENUBUTTON =>
        return parse_menubutton(p);

    Lexer->TOKEN_MESSAGE =>
        return parse_message(p);

    Lexer->TOKEN_COLUMN =>
        return parse_column(p);

    Lexer->TOKEN_ROW =>
        return parse_row(p);

    Lexer->TOKEN_CENTER =>
        return parse_center(p);

    Lexer->TOKEN_IMG =>
        return parse_img(p);

    * =>
        return (nil, fmt_error(p, sys->sprint("unknown widget type token: %d", tok.toktype)));
    }
}

# Parse app declaration
parse_app_decl(p: ref Parser): (ref Ast->AppDecl, string)
{
    tok := p.next();

    case tok.toktype {
    Lexer->TOKEN_WINDOW =>
        # OK, continue
    * =>
        return (nil, fmt_error(p, "expected Window declaration"));
    }

    # Expect '{'
    (tok1, err1) := p.expect('{');
    if (err1 != nil) {
        return (nil, err1);
    }

    (props, children, err2) := parse_widget_body_content(p);
    if (err2 != nil) {
        return (nil, err2);
    }

    # Expect '}'
    (tok2, err3) := p.expect('}');
    if (err3 != nil) {
        return (nil, err3);
    }

    app := ast->app_decl_create();
    app.props = props;
    app.body = children;

    return (app, nil);
}

# Parse a complete program
parse_program(p: ref Parser): (ref Program, string)
{
    prog := ast->program_create();

    # Parse use statements at the top
    while (p.peek().toktype == Lexer->TOKEN_IDENTIFIER) {
        # Peek ahead to check if it's "use"
        tok := p.peek();
        if (tok.string_val == "use") {
            (imp, err) := parse_use_statement(p);
            if (err != nil) {
                return (nil, err);
            }
            ast->program_add_module_import(prog, imp);
        } else {
            break;
        }
    }

    # Parse var declarations and reactive functions
    while (p.peek().toktype != Lexer->TOKEN_ENDINPUT) {
        tok := p.peek();

        # Check for regular function declaration
        if (tok.toktype == Lexer->TOKEN_FN) {
            p.next();  # consume 'fn'
            (fd, err) := parse_function_decl(p);
            if (err != nil) {
                return (nil, err);
            }
            ast->program_add_function_decl(prog, fd);
        }
        # Check for var declaration
        else if (tok.toktype == Lexer->TOKEN_VAR) {
            p.next();  # consume 'var'
            (vd, err) := parse_var_decl(p);
            if (err != nil) {
                return (nil, err);
            }
            ast->program_add_var(prog, vd);
        }
        # Check for Window (app declaration) - must come before IDENTIFIER check
        else if (tok.toktype == Lexer->TOKEN_WINDOW) {
            (app, err) := parse_app_decl(p);
            if (err != nil) {
                return (nil, err);
            }
            prog.app = app;

            # Check if we should use Draw backend (has onDraw property)
            if (app.props != nil) {
                if (has_property(app.props, "onDraw"))
                    prog.window_type = 1;  # Draw backend
            }
            break;  # Window is the last thing in the file
        }
        # Check for reactive function (identifier followed by ':')
        else if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
            # Peek ahead to check if next token is ':'
            if (p.peek().toktype == ':') {
                (rfn, err) := parse_reactive_function(p);
                if (err != nil) {
                    return (nil, err);
                }
                ast->program_add_reactive_fn(prog, rfn);
            } else {
                return (nil, fmt_error(p, "expected function declaration, var declaration, reactive function, or Window"));
            }
        } else {
            return (nil, fmt_error(p, "expected function declaration, var declaration, reactive function, or Window"));
        }
    }

    # Check for undefined variables
    parse_err: string;
    parse_err = check_undefined_variables(prog);
    if (parse_err != nil)
        return (nil, parse_err);

    return (prog, nil);
}

# =========================================================================
# Variable validation functions
# =========================================================================

# Built-in Limbo keywords and types that should be excluded from validation
is_builtin_keyword(s: string): int
{
    if (s == "if") return 1;
    if (s == "else") return 1;
    if (s == "for") return 1;
    if (s == "while") return 1;
    if (s == "return") return 1;
    if (s == "nil") return 1;
    if (s == "int") return 1;
    if (s == "real") return 1;
    if (s == "string") return 1;
    if (s == "ref") return 1;
    if (s == "array") return 1;
    if (s == "list") return 1;
    if (s == "chan") return 1;
    if (s == "of") return 1;
    if (s == "do") return 1;
    if (s == "case") return 1;
    if (s == "pick") return 1;
    if (s == "con") return 1;
    if (s == "adt") return 1;
    if (s == "fn") return 1;
    if (s == "impl") return 1;
    if (s == "include") return 1;
    if (s == "import") return 1;
    if (s == "type") return 1;
    if (s == "break") return 1;
    if (s == "continue") return 1;
    if (s == "alt") return 1;
    if (s == "load") return 1;
    if (s == "raise") return 1;
    if (s == "spawn") return 1;
    if (s == "exit") return 1;
    return 0;
}

# Common standard library modules that should be excluded
is_stdlib_module(s: string): int
{
    if (s == "sys") return 1;
    if (s == "draw") return 1;
    if (s == "math") return 1;
    if (s == "daytime") return 1;
    if (s == "wmclient") return 1;
    if (s == "tk") return 1;
    if (s == "bufio") return 1;
    if (s == "bufio") return 1;
    if (s == "sh") return 1;
    if (s == "iostream") return 1;
    if (s == "stringmod") return 1;
    if (s == "rand") return 1;
    if (s == "keyring") return 1;
    if (s == "security") return 1;
    return 0;
}

# Extract parameter names from a parameter string like "c: Point, r: int, degrees: int"
extract_param_names(params: string): list of string
{
    names: list of string = nil;

    if (params == nil || len params == 0)
        return names;

    # Simple parser: split by ',', then take identifier before ':'
    i := 0;
    while (i < len params) {
        # Skip whitespace
        while (i < len params && (params[i] == ' ' || params[i] == '\t'))
            i++;

        if (i >= len params)
            break;

        # Read identifier name
        start := i;
        while (i < len params && ((params[i] >= 'a' && params[i] <= 'z') ||
               (params[i] >= 'A' && params[i] <= 'Z') ||
               (params[i] >= '0' && params[i] <= '9') ||
               params[i] == '_')) {
            i++;
        }

        if (i > start) {
            name := params[start:i];
            # Skip to comma or end
            while (i < len params && params[i] != ',')
                i++;
            if (i < len params && params[i] == ',')
                i++;
            names = name :: names;
        } else {
            # Skip to comma or end
            while (i < len params && params[i] != ',')
                i++;
            if (i < len params && params[i] == ',')
                i++;
        }
    }

    # Reverse to get original order
    result: list of string = nil;
    for (l := names; l != nil; l = tl l)
        result = hd l :: result;

    return result;
}

# Scan a function body string for local var declarations
# Returns list of local variable names
extract_local_vars(body: string): list of string
{
    locals: list of string = nil;

    if (body == nil || len body == 0)
        return locals;

    # Create a lexer to scan the body
    l := lexer->create("<function>", body);

    while (1) {
        tok := lexer->lex(l);
        if (tok.toktype == Lexer->TOKEN_ENDINPUT)
            break;

        # Look for 'var' keyword followed by identifier
        if (tok.toktype == Lexer->TOKEN_VAR) {
            # Next token should be the variable name
            name_tok := lexer->lex(l);
            if (name_tok.toktype == Lexer->TOKEN_IDENTIFIER) {
                # Check if it's a type annotation (var name: type) or assignment (var name =)
                # Either way, the first identifier after 'var' is the variable name
                varname := name_tok.string_val;

                # Skip to end of declaration (consume tokens until we hit ';' or newline)
                # This handles both: var name = expr and var name: type = expr
                while (1) {
                    peek_tok := lexer->peek_token(l);
                    if (peek_tok.toktype == Lexer->TOKEN_ENDINPUT ||
                        peek_tok.toktype == ';' ||
                        peek_tok.toktype == '\n')
                        break;
                    lexer->lex(l);  # consume token
                }

                # Consume the ';' or '\n' too
                peek_tok := lexer->peek_token(l);
                if (peek_tok.toktype == ';' || peek_tok.toktype == '\n')
                    lexer->lex(l);

                # Add to locals (avoid duplicates)
                found := 0;
                for (l2 := locals; l2 != nil; l2 = tl l2) {
                    if (hd l2 == varname) {
                        found = 1;
                        break;
                    }
                }
                if (!found)
                    locals = varname :: locals;
            }
        }
    }

    return locals;
}

# Check all identifiers in a function body against the symbol table
# Returns error string if undefined variable found, nil otherwise
check_function_body(body: string, st: ref Ast->SymbolTable, fn_name: string): string
{
    if (body == nil || len body == 0)
        return nil;

    # Create a lexer to scan the body
    lex := lexer->create("<function>", body);

    prev_tok: ref Token;
    prev_tok = nil;

    while (1) {
        tok := lexer->lex(lex);
        if (tok.toktype == Lexer->TOKEN_ENDINPUT)
            break;

        # Check identifiers
        if (tok.toktype == Lexer->TOKEN_IDENTIFIER) {
            name := tok.string_val;

            # Skip built-in keywords
            if (is_builtin_keyword(name))
                continue;

            # Skip standard library modules
            if (is_stdlib_module(name))
                continue;

            # Skip if previous token was . or -> (method/member access)
            if (prev_tok != nil) {
                if (prev_tok.toktype == '.' ||
                    prev_tok.toktype == Lexer->TOKEN_ARROW) {
                    # This is a method/member name, not a variable
                    # Update prev_tok and continue
                    prev_tok = tok;
                    continue;
                }
            }

            # Peek at next token to check for method calls (obj.method or obj->method)
            # If next token is -> or ., this is the object, which we DO want to check
            peek_tok := lexer->peek_token(lex);

            # Skip uppercase identifiers that are likely type names
            # (unless they're explicitly in the symbol table)
            if (len name > 0 && name[0] >= 'A' && name[0] <= 'Z') {
                # Only check if it's in the symbol table
                if (!ast->symboltable_has_var(st, name))
                    prev_tok = tok;
                    continue;
            }

            # Check if variable is defined
            if (!ast->symboltable_has_var(st, name)) {
                return sys->sprint("undefined variable '%s' in function '%s' at line %d",
                    name, fn_name, tok.lineno);
            }
        }

        # Update previous token
        prev_tok = tok;
    }

    return nil;
}

# Main validation function - checks all function bodies for undefined variables
check_undefined_variables(prog: ref Program): string
{
    if (prog == nil)
        return nil;

    # Build symbol table for module-level variables
    st := ast->symboltable_create();

    # Add module imports
    imp := prog.module_imports;
    while (imp != nil) {
        # Add the module name (e.g., "math" from "use math")
        ast->symboltable_add_import(st, imp.module_name);

        # Also add common aliases if present
        if (imp.alias != nil && len imp.alias > 0)
            ast->symboltable_add_import(st, imp.alias);

        imp = imp.next;
    }

    # Add common standard library modules by default (often used without explicit use)
    ast->symboltable_add_import(st, "sys");
    ast->symboltable_add_import(st, "draw");
    ast->symboltable_add_import(st, "math");
    ast->symboltable_add_import(st, "daytime");
    ast->symboltable_add_import(st, "wmclient");
    ast->symboltable_add_import(st, "tk");

    # Add Draw constants and functions (accessed via Draw->)
    ast->symboltable_add_import(st, "Draw");
    ast->symboltable_add_import(st, "Math");

    # Add module-level variables
    v := prog.vars;
    while (v != nil) {
        ast->symboltable_add_module_var(st, v.name);
        v = v.next;
    }

    # Add function names to module-level symbol table (so functions can call each other)
    fd := prog.function_decls;
    while (fd != nil) {
        ast->symboltable_add_module_var(st, fd.name);
        fd = fd.next;
    }

    # Check each function
    fd = prog.function_decls;
    while (fd != nil) {
        # Create function-specific symbol table
        fn_st := ast->symboltable_create();

        # Copy module-level vars and imports
        fn_st.module_vars = st.module_vars;
        fn_st.imports = st.imports;

        # Copy module-level variables to function symbol table
        fn_st.module_vars = st.module_vars;

        # Add function parameters
        param_names := extract_param_names(fd.params);
        {
        l := param_names;
        while (l != nil) {
            ast->symboltable_add_param(fn_st, hd l);
            l = tl l;
        }
        }

        # Add local variables from function body
        locals := extract_local_vars(fd.body);
        {
        l := locals;
        while (l != nil) {
            ast->symboltable_add_var(fn_st, hd l);
            l = tl l;
        }
        }

        # Check the function body
        err := check_function_body(fd.body, fn_st, fd.name);
        if (err != nil)
            return err;

        fd = fd.next;
    }

    return nil;
}

# =========================================================================
# Code generation functions
# =========================================================================

# Re-escape a string literal for Limbo source code
limbo_escape(s: string): string
{
    res := "";
    for(i := 0; i < len s; i++){
        case s[i] {
            '\n' => res += "\\n";
            '\t' => res += "\\t";
            '\"' => res += "\\\"";
            '\\' => res += "\\\\";
            * => res[len res] = s[i];
        }
    }
    return res;
}

# Convert Kryon var syntax to Limbo syntax
# Kryon: var name: type = expr  or  var name: type;
# Limbo: name := expr  or  name : type = expr;
convert_var_syntax(body: string): string
{
    if (body == nil || len body == 0)
        return body;

    result := "";
    i := 0;

    while (i < len body) {
        # Look for 'var' keyword
        if (i + 3 < len body && body[i] == 'v' && body[i+1] == 'a' && body[i+2] == 'r') {
            # Check if this is really 'var' keyword (not part of another word)
            is_var := 0;
            if (i == 0 || body[i-1] == ' ' || body[i-1] == '\t' || body[i-1] == '\n' || body[i-1] == ';' || body[i-1] == '{' || body[i-1] == '(') {
                is_var = 1;
            }

            if (is_var && (i + 3 >= len body || (body[i+3] == ' ' || body[i+3] == '\t' || body[i+3] == ':'))) {
                j := i + 3;

                # Skip whitespace after 'var'
                while (j < len body && (body[j] == ' ' || body[j] == '\t'))
                    j++;

                if (j >= len body)
                    break;

                # Find variable name (identifier)
                start_name := j;
                while (j < len body && ((body[j] >= 'a' && body[j] <= 'z') ||
                                       (body[j] >= 'A' && body[j] <= 'Z') ||
                                       (body[j] >= '0' && body[j] <= '9') ||
                                       body[j] == '_'))
                    j++;

                if (j > start_name) {
                    varname := body[start_name:j];

                    # Skip whitespace and look for ':'
                    while (j < len body && (body[j] == ' ' || body[j] == '\t'))
                        j++;

                    if (j < len body && body[j] == ':') {
                        # Found 'var name :' - skip the 'var' and ':'
                        j++;  # skip ':'

                        # Skip whitespace after ':'
                        while (j < len body && (body[j] == ' ' || body[j] == '\t'))
                            j++;

                        # Find type name
                        start_type := j;
                        while (j < len body && ((body[j] >= 'a' && body[j] <= 'z') ||
                                               (body[j] >= 'A' && body[j] <= 'Z') ||
                                               (body[j] >= '0' && body[j] <= '9') ||
                                               body[j] == '_' || body[j] == '-' || body[j] == '>'))
                            j++;

                        # Add variable name to result
                        result += varname;

                        # Skip whitespace and look for '=' or ';'
                        while (j < len body && (body[j] == ' ' || body[j] == '\t'))
                            j++;

                        if (j < len body && body[j] == '=') {
                            # 'var name: type = expr' -> 'name := expr'
                            result += " := ";
                            j++;  # skip '='

                            # Skip whitespace after '='
                            while (j < len body && (body[j] == ' ' || body[j] == '\t'))
                                j++;

                            # Copy the rest of the expression until ';'
                            while (j < len body && body[j] != ';' && body[j] != '\n') {
                                result[len result] = body[j];
                                j++;
                            }

                            # Skip the ';' if present
                            if (j < len body && body[j] == ';')
                                j++;

                            # Add semicolon and continue
                            result += ";\n";
                            i = j;
                            continue;
                        } else if (j < len body && body[j] == ';') {
                            # 'var name: type;' -> 'name : type;'
                            result += " : " + body[start_type:j] + ";\n";
                            j++;  # skip ';'
                            i = j;
                            continue;
                        }
                    }
                }
            }
        }

        # Copy character and continue
        result[len result] = body[i];
        i++;
    }

    return result;
}

# Escape a string for Tk
escape_tk_string(s: string): string
{
    if (s == nil)
        return "{}";

    # Check if string needs braces
    needs_braces := 0;
    for (i := 0; i < len s; i++) {
        c := s[i];
        if (c == ' ' || c == '{' || c == '}' || c == '\\' ||
            c == '$' || c == '[' || c == ']') {
            needs_braces = 1;
            break;
        }
    }

    if (!needs_braces)
        return s;

    # Build {value} with escapes
    result := "{";

    for (j := 0; j < len s; j++) {
        c := s[j];
        if (c == '}' || c == '\\')
            result[len result] = '\\';
        result[len result] = c;
    }

    result[len result] = '}';

    return result;
}

# Map Kryon property names to Tk property names
map_property_name(prop_name: string): string
{
    # Tk color properties
    if (prop_name == "fg")
        return "fg";

    if (prop_name == "bg")
        return "bg";

    # Label widget uses -label for text (not -text)
    if (prop_name == "text")
        return "label";

    # Border properties
    if (prop_name == "borderwidth")
        return "borderwidth";

    if (prop_name == "bordercolor")
        return "bordercolor";

    # Pack options - handled separately via pack command
    if (prop_name == "fill" || prop_name == "expand" ||
        prop_name == "side" || prop_name == "weight" ||
        prop_name == "anchor" || prop_name == "posX" ||
        prop_name == "posY" || prop_name == "contentAlignment")
        return "";

    # Widget-specific Tk options - return as-is
    return prop_name;
}

# Convert widget type to Tk widget type
widget_type_to_tk(typ: int): string
{
    case typ {
    Ast->WIDGET_WINDOW =>
        return "toplevel";
    Ast->WIDGET_FRAME =>
        return "frame";
    Ast->WIDGET_BUTTON =>
        return "button";
    Ast->WIDGET_LABEL =>
        return "label";
    Ast->WIDGET_ENTRY =>
        return "entry";
    Ast->WIDGET_CHECKBUTTON =>
        return "checkbutton";
    Ast->WIDGET_RADIOBUTTON =>
        return "radiobutton";
    Ast->WIDGET_LISTBOX =>
        return "listbox";
    Ast->WIDGET_CANVAS =>
        return "canvas";
    Ast->WIDGET_SCALE =>
        return "scale";
    Ast->WIDGET_MENUBUTTON =>
        return "menubutton";
    Ast->WIDGET_MESSAGE =>
        return "message";
    Ast->WIDGET_COLUMN =>
        return "frame";
    Ast->WIDGET_ROW =>
        return "frame";
    Ast->WIDGET_CENTER =>
        return "frame";
    Ast->WIDGET_IMG =>
        return "label";
    * =>
        return "frame";
    }
}

# Check if a property is a callback (returns event name or nil)
is_callback_property(prop_name: string): string
{
    # Callbacks start with "on" (onClick, onChanged, onChecked, etc.)
    if (len prop_name >= 2 && prop_name[0:1] == "o" && prop_name[1:2] == "n")
        return prop_name;

    return nil;
}

# Convert value to Tk string
value_to_tk(v: ref Value): string
{
    if (v == nil)
        return "{}";

    if (v.valtype == Ast->VALUE_STRING)
        return escape_tk_string(ast->value_get_string(v));
    if (v.valtype == Ast->VALUE_NUMBER)
        return sys->sprint("%bd", ast->value_get_number(v));
    if (v.valtype == Ast->VALUE_COLOR)
        return escape_tk_string(ast->value_get_color(v));
    if (v.valtype == Ast->VALUE_IDENTIFIER)
        return ast->value_get_ident(v);

    return "{}";
}

# Append a Tk command to the commands list
append_tk_cmd(cg: ref Codegen, cmd: string)
{
    cg.tk_cmds = cmd :: cg.tk_cmds;
}

# Add a callback to the callback list
add_callback(cg: ref Codegen, name: string, event: string)
{
    cg.callbacks = (name, event) :: cg.callbacks;
}

# Add a reactive binding to the bindings list
add_reactive_binding(cg: ref Codegen, widget_path: string, property_name: string, fn_name: string)
{
    cg.reactive_bindings = (widget_path, property_name, fn_name) :: cg.reactive_bindings;
}

# Generate code for a single widget
generate_widget(cg: ref Codegen, prog: ref Program, w: ref Widget, parent: string, is_root: int): string
{
    if (w == nil)
        return nil;

    # Skip wrapper widgets only (keep layout widgets!)
    if (w.is_wrapper) {
        return generate_widget_list(cg, prog, w.children, parent, is_root);
    }

    # Build widget path
    widget_path := "";

    if (is_root) {
        widget_path = sys->sprint(".w%d", cg.widget_counter);
    } else {
        widget_path = sys->sprint("%s.w%d", parent, cg.widget_counter);
    }
    cg.widget_counter++;

    # Build widget creation command
    tk_type := widget_type_to_tk(w.wtype);

    # Collect properties into a list, then reverse and build command
    # Each property is stored as [prop_name, value]
    props_list: list of string = nil;

    # NEW: Extract pack options from properties
    pack_fill := "";
    pack_expand := 0;
    pack_side := "";
    pack_anchor := "";

    # Generate properties
    callbacks: list of (string, string) = nil;

    prop := w.props;
    while (prop != nil) {
        # Check for pack-specific properties first
        if (prop.name == "fill") {
            pack_fill = ast->value_get_string(prop.value);
            prop = prop.next;
            continue;
        }
        if (prop.name == "expand") {
            s := ast->value_get_string(prop.value);
            if (s == "1" || s == "true")
                pack_expand = 1;
            prop = prop.next;
            continue;
        }
        if (prop.name == "side") {
            pack_side = ast->value_get_string(prop.value);
            prop = prop.next;
            continue;
        }
        if (prop.name == "anchor") {
            pack_anchor = ast->value_get_string(prop.value);
            prop = prop.next;
            continue;
        }

        # Handle callbacks and regular properties
        cb_event := is_callback_property(prop.name);

        if (cb_event != nil && prop.value != nil) {
            # Check if this is a callback (value should be Identifier)
            is_callback := 0;
            callback_name := "";

            if (prop.value.valtype == Ast->VALUE_IDENTIFIER) {
                is_callback = 1;
                callback_name = ast->value_get_ident(prop.value);
            }

            if (is_callback) {
                callbacks = (callback_name, prop.name) :: callbacks;
            } else {
                # Regular property
                tk_prop := map_property_name(prop.name);

                # Skip properties that don't map to valid Tk options
                if (tk_prop != "") {
                    # Check if value is a function call (reactive binding)
                    val_str := "";
                    if (prop.value != nil && prop.value.valtype == Ast->VALUE_FN_CALL) {
                        # Extract function name from FnCall value
                        fn_name := "";
                        pick fv := prop.value {
                        FnCall =>
                            fn_name = fv.fn_name;
                        * =>
                            # Fall through to regular handling
                        }

                        if (fn_name != nil && fn_name != "") {
                            # Track reactive binding
                            add_reactive_binding(cg, widget_path, prop.name, fn_name);
                            # Use placeholder for initial value
                            val_str = "{}";
                        } else {
                            val_str = value_to_tk(prop.value);
                        }
                    } else {
                        val_str = value_to_tk(prop.value);
                    }

                    prop_cmd := sys->sprint("-%s", tk_prop);
                    # Prepend to list (will be reversed later)
                    props_list = val_str :: prop_cmd :: props_list;
                }
            }
        } else {
            # Regular property
            tk_prop := map_property_name(prop.name);

            # Skip properties that don't map to valid Tk options
            if (tk_prop != "") {
                # Check if value is a function call (reactive binding)
                val_str := "";
                if (prop.value != nil && prop.value.valtype == Ast->VALUE_FN_CALL) {
                    # Extract function name from FnCall value
                    fn_name := "";
                    pick fv := prop.value {
                    FnCall =>
                        fn_name = fv.fn_name;
                    * =>
                        # Fall through to regular handling
                    }

                    if (fn_name != nil && fn_name != "") {
                        # Track reactive binding
                        add_reactive_binding(cg, widget_path, prop.name, fn_name);
                        # Use placeholder for initial value
                        val_str = "{}";
                    } else {
                        val_str = value_to_tk(prop.value);
                    }
                } else {
                    val_str = value_to_tk(prop.value);
                }

                prop_cmd := sys->sprint("-%s", tk_prop);
                # Prepend to list (will be reversed later)
                props_list = val_str :: prop_cmd :: props_list;
            }
        }

        prop = prop.next;
    }

    # Reverse props_list to get correct order
    # Currently: [val2, -prop2, val1, -prop1]
    # After reverse: [-prop1, val1, -prop2, val2]
    rev_props: list of string = nil;
    while (props_list != nil) {
        rev_props = hd props_list :: rev_props;
        props_list = tl props_list;
    }

    # Build command string: "type path -prop1 val1 -prop2 val2 ..."
    cmd := sys->sprint("%s %s", tk_type, widget_path);

    while (rev_props != nil) {
        cmd += " " + hd rev_props;
        rev_props = tl rev_props;
    }

    # Add callbacks to widget creation command
    # For Tk, callbacks use -command option
    # Make a copy for widget command, keep original for dispatcher
    cbs_for_widget := callbacks;
    while (cbs_for_widget != nil) {
        (name, event) := hd cbs_for_widget;
        # Map Kryon event names to Tk command names
        # For most widgets, it's just -command
        cmd += " -command {send cmd " + name + "}";
        cbs_for_widget = tl cbs_for_widget;
    }

    append_tk_cmd(cg, cmd);

    # For root widgets (direct children of toplevel), configure their size
    # Root widgets have no parent to give them dimensions, so they need explicit size
    if (is_root && prog.app != nil && prog.app.props != nil) {
        (w, ok) := get_number_prop(prog.app.props, "width");
        (h, ok2) := get_number_prop(prog.app.props, "height");
        if ((ok && w > 0) || (ok2 && h > 0)) {
            append_tk_cmd(cg, sys->sprint("%s configure -width %d -height %d", widget_path, w, h));
        }
    }

    # Process children FIRST (they need to be packed before this widget)
    if (w.children != nil) {
        err := generate_widget_list(cg, prog, w.children, widget_path, 0);
        if (err != nil)
            return err;
    }

    # Generate pack command with explicit options
    pack_opts := "";

    # Layout widget defaults
    if (w.wtype == Ast->WIDGET_CENTER) {
        pack_anchor = "center";
    } else if (w.wtype == Ast->WIDGET_COLUMN) {
        pack_side = "top";
        pack_fill = "x";
    } else if (w.wtype == Ast->WIDGET_ROW) {
        pack_side = "left";
        pack_fill = "y";
    }

    # User-specified options override defaults
    if (pack_side != nil && pack_side != "")
        pack_opts += " -side " + pack_side;
    if (pack_fill != nil && pack_fill != "" && pack_fill != "none")
        pack_opts += " -fill " + pack_fill;
    if (pack_expand)
        pack_opts += " -expand 1";
    if (pack_anchor != nil && pack_anchor != "")
        pack_opts += " -anchor " + pack_anchor;

    # Default fill behavior if no options specified
    if (pack_opts == nil || pack_opts == "")
        pack_opts = " -fill both -expand 1";
    else if (!pack_expand && (pack_fill == nil || pack_fill == ""))
        # Add -fill both if not specified and no expand
        pack_opts += " -fill both -expand 1";

    pack_cmd := sys->sprint("pack %s%s", widget_path, pack_opts);
    append_tk_cmd(cg, pack_cmd);

    # Store callbacks for later
    while (callbacks != nil) {
        (name, event) := hd callbacks;
        add_callback(cg, name, event);
        callbacks = tl callbacks;
    }

    return nil;
}

# Process widget list
generate_widget_list(cg: ref Codegen, prog: ref Program, w: ref Widget, parent: string, is_root: int): string
{
    while (w != nil) {
        if (w.is_wrapper) {
            # Process children of wrapper with same parent
            child := w.children;
            while (child != nil) {
                if (child.is_wrapper) {
                    err := generate_widget_list(cg, prog, child.children, parent, is_root);
                    if (err != nil)
                        return err;
                } else {
                    err := generate_widget(cg, prog, child, parent, is_root);
                    if (err != nil)
                        return err;
                }
                child = child.next;
            }
        } else {
            # Generate widget normally (including layout widgets like Center/Column/Row)
            err := generate_widget(cg, prog, w, parent, is_root);
            if (err != nil)
                return err;
        }
        w = w.next;
    }

    return nil;
}

# Collect widget commands
collect_widget_commands(cg: ref Codegen, prog: ref Program): string
{
    cg.widget_counter = 0;

    if (prog == nil || prog.app == nil || prog.app.body == nil)
        return nil;

    return generate_widget_list(cg, prog, prog.app.body, ".", 1);
}

# Generate variable declarations
generate_var_decls(cg: ref Codegen, prog: ref Program): string
{
    vds := prog.vars;

    while (vds != nil) {
        var_type := vds.typ;
        if (var_type == nil || var_type == "")
            var_type = "string";  # default fallback
        sys->fprint(cg.output, "%s: %s;\n", vds.name, var_type);
        vds = vds.next;
    }

    sys->fprint(cg.output, "\n");
    return nil;
}

# Generate reactive function variables only (no functions)
generate_reactive_vars(cg: ref Codegen, prog: ref Program): string
{
    rfns := prog.reactive_fns;

    while (rfns != nil) {
        name := rfns.name;
        # Generate module variable for cached value
        sys->fprint(cg.output, "%s: string;\n", name);
        rfns = rfns.next;
    }

    # Add tpid variable for timer process tracking
    if (has_reactive_functions(prog)) {
        sys->fprint(cg.output, "tpid: int;\n");
    }

    sys->fprint(cg.output, "\n");
    return nil;
}

# Generate reactive update functions only (no variables)
generate_reactive_funcs(cg: ref Codegen, prog: ref Program): string
{
    rfns := prog.reactive_fns;

    while (rfns != nil) {
        name := rfns.name;
        expr := rfns.expression;

        if (rfns.interval > 0) {
            # Time-based: generate _update() function
            needs_t := 0;
            bindings := cg.reactive_bindings;
            while (bindings != nil) {
                (widget_path, prop_name, fn_name) := hd bindings;
                if (fn_name == name) {
                    needs_t = 1;
                    break;
                }
                bindings = tl bindings;
            }

            if (needs_t) {
                sys->fprint(cg.output, "%s_update(t: ref Tk->Toplevel)\n", name);
            } else {
                sys->fprint(cg.output, "%s_update()\n", name);
            }
            sys->fprint(cg.output, "{\n");
            sys->fprint(cg.output, "    %s = %s;\n", name, expr);

            # Generate widget updates
            all_bindings := cg.reactive_bindings;
            rev_bindings: list of (string, string, string) = nil;
            while (all_bindings != nil) {
                rev_bindings = hd all_bindings :: rev_bindings;
                all_bindings = tl all_bindings;
            }

            while (rev_bindings != nil) {
                (widget_path, prop_name, fn_name) := hd rev_bindings;
                if (fn_name == name) {
                    tk_prop := map_property_name(prop_name);
                    if (tk_prop != "") {
                        sys->fprint(cg.output, "    tk->cmd(t, \"%s configure -%s {\"+%s+\"};update\");\n",
                            widget_path, tk_prop, name);
                    }
                }
                rev_bindings = tl rev_bindings;
            }

            sys->fprint(cg.output, "}\n\n");
        } else {
            # Var-based: generate update function for each watched variable
            wv := rfns.watch_vars;
            while (wv != nil) {
                sys->fprint(cg.output, "%s_on_%s_change(t: ref Tk->Toplevel)\n", name, wv.name);
                sys->fprint(cg.output, "{\n");
                sys->fprint(cg.output, "    %s = %s;\n", name, expr);

                # Update widgets
                bindings := cg.reactive_bindings;
                while (bindings != nil) {
                    (widget_path, prop_name, fn_name) := hd bindings;
                    if (fn_name == name) {
                        tk_prop := map_property_name(prop_name);
                        if (tk_prop != "") {
                            sys->fprint(cg.output, "    tk->cmd(t, \"%s configure -%s {\"+%s+\"};update\");\n",
                                widget_path, tk_prop, name);
                        }
                    }
                    bindings = tl bindings;
                }

                sys->fprint(cg.output, "}\n\n");
                wv = wv.next;
            }
        }

        rfns = rfns.next;
    }

    # Also generate update functions for FunctionDecl with reactive_interval
    fd := prog.function_decls;
    while (fd != nil) {
        if (fd.reactive_interval > 0) {
            # Time-based: generate _update() function
            needs_t := 0;
            bindings := cg.reactive_bindings;
            while (bindings != nil) {
                (widget_path, prop_name, fn_name) := hd bindings;
                if (fn_name == fd.name) {
                    needs_t = 1;
                    break;
                }
                bindings = tl bindings;
            }

            if (needs_t) {
                sys->fprint(cg.output, "%s_update(t: ref Tk->Toplevel)\n", fd.name);
            } else {
                sys->fprint(cg.output, "%s_update()\n", fd.name);
            }
            sys->fprint(cg.output, "{\n");

            # Generate widget updates for FunctionDecl
            # For functions, we call the function directly in the widget update
            all_bindings := cg.reactive_bindings;
            rev_bindings: list of (string, string, string) = nil;
            while (all_bindings != nil) {
                rev_bindings = hd all_bindings :: rev_bindings;
                all_bindings = tl all_bindings;
            }

            while (rev_bindings != nil) {
                (widget_path, prop_name, fn_name) := hd rev_bindings;
                if (fn_name == fd.name) {
                    tk_prop := map_property_name(prop_name);
                    if (tk_prop != "") {
                        sys->fprint(cg.output, "    tk->cmd(t, \"%s configure -%s {\"+%s()+\"};update\");\n",
                            widget_path, tk_prop, fd.name);
                    }
                }
                rev_bindings = tl rev_bindings;
            }

            sys->fprint(cg.output, "}\n\n");
        }
        fd = fd.next;
    }

    return nil;
}

# Check if program has time-based reactive functions
has_time_based_reactive_functions(prog: ref Program): int
{
    rfns := prog.reactive_fns;
    while (rfns != nil) {
        if (rfns.interval > 0)
            return 1;
        rfns = rfns.next;
    }
    # Also check FunctionDecl for reactive_interval
    fd := prog.function_decls;
    while (fd != nil) {
        if (fd.reactive_interval > 0)
            return 1;
        fd = fd.next;
    }
    return 0;
}

# Generate reactive timer function
generate_reactive_timer(cg: ref Codegen, prog: ref Program): string
{
    # Find the minimum interval among time-based functions
    min_interval := 1000000;
    rfns := prog.reactive_fns;

    while (rfns != nil) {
        if (rfns.interval > 0 && rfns.interval < min_interval)
            min_interval = rfns.interval;
        rfns = rfns.next;
    }

    # Also check FunctionDecl for reactive_interval
    fd := prog.function_decls;
    while (fd != nil) {
        if (fd.reactive_interval > 0 && fd.reactive_interval < min_interval)
            min_interval = fd.reactive_interval;
        fd = fd.next;
    }

    if (min_interval >= 1000000)
        return nil;

    # Generate timer function
    sys->fprint(cg.output, "timer(c: chan of int)\n");
    sys->fprint(cg.output, "{\n");
    sys->fprint(cg.output, "    tpid = sys->pctl(0, nil);\n");
    sys->fprint(cg.output, "    for(;;) {\n");
    sys->fprint(cg.output, "        c <-= 1;\n");
    sys->fprint(cg.output, "        sys->sleep(%d);\n", min_interval);
    sys->fprint(cg.output, "    }\n");
    sys->fprint(cg.output, "}\n\n");

    return nil;
}

# Check if program has reactive functions
has_reactive_functions(prog: ref Program): int
{
    return has_time_based_reactive_functions(prog);
}

# Generate module load statements in init
generate_module_loads(cg: ref Codegen, prog: ref Program): string
{
    imports := prog.module_imports;

    while (imports != nil) {
        module_name := imports.module_name;
        alias := imports.alias;

        if (alias == nil || alias == "") {
            alias = module_name;
        }

        # Generate type name (capitalized)
        type_name := alias;
        if (len type_name > 0) {
            first := type_name[0];
            if (first >= 'a' && first <= 'z') {
                type_name = sys->sprint("%c", first - ('a' - 'A')) + type_name[1:];
            }
        }

        # Generate load statement
        # The load path uses the capitalized type name
        sys->fprint(cg.output, "    %s = load %s %s->PATH;\n",
            alias, type_name, type_name);

        imports = imports.next;
    }

    return nil;
}

# Check if module name is already in module list
module_list_contains(mods: list of ref Module, name: string): int
{
    while (mods != nil) {
        if ((hd mods).mod_file == name)
            return 1;
        mods = tl mods;
    }
    return 0;
}

# Generate prologue
generate_prologue(cg: ref Codegen, prog: ref Program): string
{
    buf := "";

    buf += sys->sprint("implement %s;\n\n", cg.module_name);

    # Determine backend
    is_draw := 0;
    if (prog.window_type == 1)
        is_draw = 1;
    cg.is_draw_backend = is_draw;

    # Build list of all modules (required + user imports)
    modules: list of ref Module = nil;

    # Required modules - added in reverse order (after reversal, these come last)
    modules = ref Module("sys", "sys", "Sys") :: modules;
    modules = ref Module("draw", "draw", "Draw") :: modules;

    if (is_draw) {
        # tk must come before wmclient - add wmclient first (it goes to front)
        modules = ref Module("wmclient", "wmclient", "Wmclient") :: modules;
        modules = ref Module("tk", "tk", "Tk") :: modules;
    } else {
        modules = ref Module("tkclient", "tkclient", "Tkclient") :: modules;
        modules = ref Module("tk", "tk", "Tk") :: modules;
    }

    # Add user imports, skip duplicates
    imports := prog.module_imports;
    while (imports != nil) {
        module_name := imports.module_name;
        if (!module_list_contains(modules, module_name)) {
            alias := imports.alias;
            if (alias == nil || alias == "")
                alias = module_name;

            type_name := alias;
            if (len type_name > 0) {
                first := type_name[0];
                if (first >= 'a' && first <= 'z') {
                    type_name = sys->sprint("%c", first - ('a' - 'A')) + type_name[1:];
                }
            }

            modules = ref Module(module_name, alias, type_name) :: modules;
        }
        imports = imports.next;
    }

    # Reverse to get original order
    rev_modules: list of ref Module = nil;
    while (modules != nil) {
        rev_modules = hd modules :: rev_modules;
        modules = tl modules;
    }

    # Output all modules with proper formatting
    mods := rev_modules;
    while (mods != nil) {
        m := hd mods;
        buf += sys->sprint("include \"%s.m\";\n", m.mod_file);
        buf += sys->sprint("\t%s: %s;\n", m.var_name, m.type_name);
        buf += "\n";
        mods = tl mods;
    }

    # Add Draw type imports for wmclient backend
    if (is_draw) {
        buf += "Display, Image, Point, Rect: import draw;\n";
        buf += "Window: import wmclient;\n";
        buf += "\n";
    }

    # Generate module declaration
    buf += sys->sprint("%s: module\n{\n", cg.module_name);
    buf += "    init:\tfn(ctxt: ref Draw->Context, argv: list of string);\n";

    # Add function signatures from function_decls
    fd := prog.function_decls;
    while (fd != nil) {
        if (fd.return_type != nil && fd.return_type != "")
            buf += sys->sprint("    %s: fn(%s): %s;\n", fd.name, fd.params, fd.return_type);
        else
            buf += sys->sprint("    %s: fn(%s);\n", fd.name, fd.params);
        fd = fd.next;
    }

    buf += "};\n";

    # Write prologue
    sys->fprint(cg.output, "%s", buf);

    return nil;
}

# Generate code blocks (Limbo functions)
generate_code_blocks(cg: ref Codegen, prog: ref Program): string
{
    # Generate function bodies from function_decls
    fd := prog.function_decls;

    while (fd != nil) {
        if (fd.return_type != nil && fd.return_type != "")
            sys->fprint(cg.output, "\n%s(%s): %s\n", fd.name, fd.params, fd.return_type);
        else
            sys->fprint(cg.output, "\n%s(%s)\n", fd.name, fd.params);
        sys->fprint(cg.output, "{\n");

        if (fd.body != nil && fd.body != "") {
            # Convert Kryon var syntax to Limbo syntax
            body := convert_var_syntax(fd.body);

            # Trim leading whitespace/newlines from body
            while (len body > 0 && (body[0] == ' ' || body[0] == '\t' || body[0] == '\n' || body[0] == '\r')) {
                body = body[1:];
            }

            # Split body by lines and process each line
            (line_count, lines) := sys->tokenize(body, "\n");
            # Convert list to array for indexing
            if (lines != nil) {
                # Build array from list
                arr := array[line_count] of string;
                tmp := lines;
                for (j := 0; j < line_count; j++) {
                    arr[j] = hd tmp;
                    tmp = tl tmp;
                }

                for (i := 0; i < line_count; i++) {
                    line := arr[i];

                    # Trim leading whitespace from line
                    while (len line > 0 && (line[0] == ' ' || line[0] == '\t')) {
                        line = line[1:];
                    }

                    # Trim trailing whitespace from line
                    while (len line > 0 && (line[len line - 1] == ' ' || line[len line - 1] == '\t' || line[len line - 1] == '\r')) {
                        line = line[0: len line - 1];
                    }

                    # Skip empty lines
                    if (len line == 0)
                        continue;

                    # Add semicolon if line doesn't end with one
                    if (len line > 0 && line[len line - 1] != ';' && line[len line - 1] != '{' && line[len line - 1] != '}') {
                        line += ";";
                    }

                    # Indent the line
                    sys->fprint(cg.output, "    %s\n", line);
                }
            }
        }

        sys->fprint(cg.output, "}\n");
        fd = fd.next;
    }

    return nil;
}

# Generate tkcmds array
generate_tkcmds_array(cg: ref Codegen, prog: ref Program): string
{
    sys->fprint(cg.output, "\ntkcmds := array[] of {\n");

    # Reverse commands to get correct order
    cmds := cg.tk_cmds;
    rev: list of string = nil;

    while (cmds != nil) {
        rev = hd cmds :: rev;
        cmds = tl cmds;
    }

    while (rev != nil) {
        sys->fprint(cg.output, "    \"%s\",\n", hd rev);
        rev = tl rev;
    }

    # Only add pack propagate if width/height were explicitly set on the Window
    # This prevents the window from auto-sizing when dimensions are specified
    has_width := 0;
    has_height := 0;
    if (prog.app != nil && prog.app.props != nil) {
        (w, ok) := get_number_prop(prog.app.props, "width");
        if (ok && w > 0)
            has_width = 1;
        (h, ok2) := get_number_prop(prog.app.props, "height");
        if (ok2 && h > 0)
            has_height = 1;
    }

    if (has_width || has_height) {
        sys->fprint(cg.output, "    \"pack propagate . 0\",\n");
    }
    sys->fprint(cg.output, "    \"update\"\n");
    sys->fprint(cg.output, "};\n\n");

    return nil;
}

# Get string property value
get_string_prop(props: ref Property, name: string): string
{
    while (props != nil) {
        if (props.name == name && props.value != nil) {
            if (props.value.valtype == Ast->VALUE_STRING)
                return ast->value_get_string(props.value);
            if (props.value.valtype == Ast->VALUE_COLOR)
                return ast->value_get_color(props.value);
        }
        props = props.next;
    }
    return nil;
}

# Get number property value
get_number_prop(props: ref Property, name: string): (int, int)
{
    while (props != nil) {
        if (props.name == name && props.value != nil) {
            if (props.value.valtype == Ast->VALUE_NUMBER)
                return (int ast->value_get_number(props.value), 1);
        }
        props = props.next;
    }
    return (0, 0);
}

# Check if widget has a specific property
has_property(props: ref Property, name: string): int
{
    while (props != nil) {
        if (props.name == name)
            return 1;
        props = props.next;
    }
    return 0;
}

# Parse reactive binding "fn_name@interval" -> (fn_name, interval)
parse_reactive_binding(ident: string): (string, int)
{
    if (ident == nil)
        return (nil, 0);

    for (i := 0; i < len ident; i++) {
        if (ident[i] == '@') {
            fn_name := ident[0:i];
            interval_str := ident[i+1:];
            interval := 0;
            if (interval_str != nil && len interval_str > 0) {
                for (j := 0; j < len interval_str; j++) {
                    c := interval_str[j];
                    if (c >= '0' && c <= '9') {
                        interval = interval * 10 + (c - '0');
                    }
                }
            }
            return (fn_name, interval);
        }
    }
    return (ident, 0);
}

# Check if program should use Draw backend
should_use_draw_backend(prog: ref Program): int
{
    if (prog == nil || prog.app == nil || prog.app.props == nil)
        return 0;
    return has_property(prog.app.props, "onDraw");
}

# Generate Draw/wmclient backend init
generate_draw_init(cg: ref Codegen, prog: ref Program): string
{
    # Extract properties
    ondraw_fn := "";
    ondraw_interval := 0;
    oninit_fn := "";
    window_type := "Appl";

    if (prog.app != nil && prog.app.props != nil) {
        p := prog.app.props;
        while (p != nil) {
            if (p.name == "onDraw" && p.value != nil) {
                if (p.value.valtype == Ast->VALUE_IDENTIFIER) {
                    (fname, interval) := parse_reactive_binding(ast->value_get_ident(p.value));
                    ondraw_fn = fname;
                    ondraw_interval = interval;
                }
            } else if (p.name == "onInit" && p.value != nil) {
                if (p.value.valtype == Ast->VALUE_IDENTIFIER) {
                    oninit_fn = ast->value_get_ident(p.value);
                }
            } else if (p.name == "type" && p.value != nil) {
                if (p.value.valtype == Ast->VALUE_IDENTIFIER) {
                    window_type = ast->value_get_ident(p.value);
                }
            }
            p = p.next;
        }
    }

    cg.ondraw_fn = ondraw_fn;
    cg.ondraw_interval = ondraw_interval;
    cg.oninit_fn = oninit_fn;

    # Get window props
    title := "Application";
    width := 100;
    height := 100;

    if (prog.app != nil && prog.app.props != nil) {
        t := get_string_prop(prog.app.props, "title");
        if (t != nil)
            title = t;
        (w, ok) := get_number_prop(prog.app.props, "width");
        if (ok)
            width = w;
        (h, ok2) := get_number_prop(prog.app.props, "height");
        if (ok2)
            height = h;
    }

    # ZP constant
    sys->fprint(cg.output, "ZP := Point(0, 0);\n\n");

    # timer function
    sys->fprint(cg.output, "timer(c: chan of int, ms: int)\n");
    sys->fprint(cg.output, "{\n");
    sys->fprint(cg.output, "    for(;;){\n");
    sys->fprint(cg.output, "        sys->sleep(ms);\n");
    sys->fprint(cg.output, "        c <-= 1;\n");
    sys->fprint(cg.output, "    }\n");
    sys->fprint(cg.output, "}\n\n");

    sys->fprint(cg.output, "init(ctxt: ref Draw->Context, nil: list of string)\n");
    sys->fprint(cg.output, "{\n");
    sys->fprint(cg.output, "    sys = load Sys Sys->PATH;\n");
    sys->fprint(cg.output, "    draw = load Draw Draw->PATH;\n");
    sys->fprint(cg.output, "    math = load Math Math->PATH;\n");

    # Load user modules (skip built-in ones: sys, draw, math, wmclient)
    imports := prog.module_imports;
    while (imports != nil) {
        module_name := imports.module_name;
        # Skip built-in modules that are already loaded
        if (module_name != "sys" && module_name != "draw" &&
            module_name != "math" && module_name != "wmclient" &&
            module_name != "tk" && module_name != "tkclient") {
            alias := imports.alias;
            if (alias == nil || alias == "")
                alias = module_name;

            type_name := alias;
            if (len type_name > 0) {
                first := type_name[0];
                if (first >= 'a' && first <= 'z') {
                    type_name = sys->sprint("%c", first - ('a' - 'A')) + type_name[1:];
                }
            }

            sys->fprint(cg.output, "    %s = load %s %s->PATH;\n", alias, type_name, type_name);
        }
        imports = imports.next;
    }

    sys->fprint(cg.output, "    wmclient = load Wmclient Wmclient->PATH;\n");
    sys->fprint(cg.output, "\n");
    sys->fprint(cg.output, "    sys->pctl(Sys->NEWPGRP, nil);\n");
    sys->fprint(cg.output, "    wmclient->init();\n");
    sys->fprint(cg.output, "\n");
    sys->fprint(cg.output, "    if(ctxt == nil)\n");
    sys->fprint(cg.output, "        ctxt = wmclient->makedrawcontext();\n");
    sys->fprint(cg.output, "\n");
    sys->fprint(cg.output, "    w := wmclient->window(ctxt, \"%s\", Wmclient->%s);\n", title, window_type);
    sys->fprint(cg.output, "    display := w.display;\n");
    sys->fprint(cg.output, "\n");

    if (oninit_fn != nil && oninit_fn != "") {
        sys->fprint(cg.output, "    # Initialize colors\n");
        sys->fprint(cg.output, "    %s(display);\n", oninit_fn);
        sys->fprint(cg.output, "\n");
    }

    sys->fprint(cg.output, "    w.reshape(Rect((0, 0), (%d, %d)));\n", width, height);
    sys->fprint(cg.output, "    w.onscreen(\"place\");\n");
    sys->fprint(cg.output, "    w.startinput(\"ptr\" :: nil);\n");
    sys->fprint(cg.output, "\n");

    if (ondraw_fn != nil && ondraw_fn != "") {
        sys->fprint(cg.output, "    now := daytime->now();\n");
        sys->fprint(cg.output, "    %s(w.image, now);\n", ondraw_fn);
        sys->fprint(cg.output, "\n");
        sys->fprint(cg.output, "    ticks := chan of int;\n");
        sys->fprint(cg.output, "    spawn timer(ticks, %d);\n", ondraw_interval);
    }

    # Event loop
    sys->fprint(cg.output, "    for(;;){\n");
    sys->fprint(cg.output, "        alt{\n");
    sys->fprint(cg.output, "        ctl := <-w.ctl or\n");
    sys->fprint(cg.output, "        ctl = <-w.ctxt.ctl =>\n");
    sys->fprint(cg.output, "            w.wmctl(ctl);\n");
    sys->fprint(cg.output, "            if(ctl != nil && ctl[0] == '!')\n");
    if (ondraw_fn != nil && ondraw_fn != "") {
        sys->fprint(cg.output, "                %s(w.image, now);\n", ondraw_fn);
    } else {
        sys->fprint(cg.output, "                ;\n");
    }
    sys->fprint(cg.output, "\n");
    sys->fprint(cg.output, "        p := <-w.ctxt.ptr =>\n");
    sys->fprint(cg.output, "            w.pointer(*p);\n");
    sys->fprint(cg.output, "\n");

    if (ondraw_fn != nil && ondraw_fn != "") {
        sys->fprint(cg.output, "        <-ticks =>\n");
        sys->fprint(cg.output, "            t := daytime->now();\n");
        sys->fprint(cg.output, "            if(t != now){\n");
        sys->fprint(cg.output, "                now = t;\n");
        sys->fprint(cg.output, "                %s(w.image, now);\n", ondraw_fn);
        sys->fprint(cg.output, "            }\n");
    }

    sys->fprint(cg.output, "        }\n");
    sys->fprint(cg.output, "    }\n");
    sys->fprint(cg.output, "}\n");

    return nil;
}

# Generate init function
generate_init(cg: ref Codegen, prog: ref Program): string
{
    if (cg.is_draw_backend)
        return generate_draw_init(cg, prog);

    sys->fprint(cg.output, "init(ctxt: ref Draw->Context, argv: list of string)\n");
    sys->fprint(cg.output, "{\n");

    sys->fprint(cg.output, "    sys = load Sys Sys->PATH;\n");
    sys->fprint(cg.output, "    draw = load Draw Draw->PATH;\n");
    sys->fprint(cg.output, "    tk = load Tk Tk->PATH;\n");
    sys->fprint(cg.output, "    tkclient = load Tkclient Tkclient->PATH;\n");

    # Load modules from use statements
    err := generate_module_loads(cg, prog);
    if (err != nil) {
        return err;
    }

    sys->fprint(cg.output, "\n");
    sys->fprint(cg.output, "    sys->pctl(Sys->NEWPGRP, nil);\n");
    sys->fprint(cg.output, "    tkclient->init();\n\n");

    # Get app properties
    title := "Application";
    width := 0;
    height := 0;
    bg := "";

    if (prog.app != nil && prog.app.props != nil) {
        t := get_string_prop(prog.app.props, "title");
        if (t != nil)
            title = t;

        bg = get_string_prop(prog.app.props, "background");
        if (bg == nil)
            bg = get_string_prop(prog.app.props, "backgroundColor");

        (w, ok) := get_number_prop(prog.app.props, "width");
        if (ok)
            width = w;

        (h, ok2) := get_number_prop(prog.app.props, "height");
        if (ok2)
            height = h;
    }

    # Store width and height in Codegen for later use
    cg.width = width;
    cg.height = height;

    sys->fprint(cg.output, "    (t, wmctl) := tkclient->toplevel(ctxt, \"\", \"%s\", 0);\n", title);
    if (width > 0 || height > 0) {
        sys->fprint(cg.output, "    tk->cmd(t, \"wm geometry . %dx%d\");\n", width, height);
    }
    if (bg != nil && bg != "") {
        sys->fprint(cg.output, "    tk->cmd(t, \"configure -background %s\");\n", bg);
    }
    sys->fprint(cg.output, "\n");

    # Initialize var declarations
    vds := prog.vars;
    while (vds != nil) {
        if (vds.init_expr != nil)
            sys->fprint(cg.output, "    %s = %s;\n", vds.name, vds.init_expr);
        vds = vds.next;
    }

    # Create command channel if we have callbacks
    has_callbacks := (cg.callbacks != nil);

    if (has_callbacks) {
        sys->fprint(cg.output, "    cmd := chan of string;\n");
        sys->fprint(cg.output, "    tk->namechan(t, cmd, \"cmd\");\n\n");
    }

    # Execute tk commands
    sys->fprint(cg.output, "    for (i := 0; i < len tkcmds; i++)\n");
    sys->fprint(cg.output, "        tk->cmd(t, tkcmds[i]);\n\n");

    # Setup reactive timer if we have reactive functions
    has_reactive := has_reactive_functions(prog);
    if (has_reactive) {
        sys->fprint(cg.output, "    tick := chan of int;\n");
        sys->fprint(cg.output, "    spawn timer(tick);\n\n");

        # Call initial reactive update
        rfns := prog.reactive_fns;
        while (rfns != nil) {
            # Only initialize time-based reactive functions
            if (rfns.interval > 0) {
                # Check if this function has widget bindings
                has_bindings := 0;
                bindings := cg.reactive_bindings;
                while (bindings != nil) {
                    (widget_path, prop_name, fn_name) := hd bindings;
                    if (fn_name == rfns.name) {
                        has_bindings = 1;
                        break;
                    }
                    bindings = tl bindings;
                }

                if (has_bindings) {
                    sys->fprint(cg.output, "    %s_update(t);\n", rfns.name);
                } else {
                    sys->fprint(cg.output, "    %s_update();\n", rfns.name);
                }
            }
            rfns = rfns.next;
        }

        # Also call initial update for FunctionDecl with reactive_interval
        fd := prog.function_decls;
        while (fd != nil) {
            if (fd.reactive_interval > 0) {
                # Check if this function has widget bindings
                has_bindings := 0;
                bindings := cg.reactive_bindings;
                while (bindings != nil) {
                    (widget_path, prop_name, fn_name) := hd bindings;
                    if (fn_name == fd.name) {
                        has_bindings = 1;
                        break;
                    }
                    bindings = tl bindings;
                }

                if (has_bindings) {
                    sys->fprint(cg.output, "    %s_update(t);\n", fd.name);
                } else {
                    sys->fprint(cg.output, "    %s_update();\n", fd.name);
                }
            }
            fd = fd.next;
        }
        sys->fprint(cg.output, "\n");
    }

    # Show window
    sys->fprint(cg.output, "    tkclient->onscreen(t, nil);\n");
    sys->fprint(cg.output, "    tkclient->startinput(t, \"kbd\"::\"ptr\"::nil);\n\n");

    if (has_callbacks) {
        sys->fprint(cg.output, "    for(;;) {\n");
        sys->fprint(cg.output, "        alt {\n");
        sys->fprint(cg.output, "        s := <-t.ctxt.kbd =>\n");
        sys->fprint(cg.output, "            tk->keyboard(t, s);\n");
        sys->fprint(cg.output, "        s := <-t.ctxt.ptr =>\n");
        sys->fprint(cg.output, "            tk->pointer(t, *s);\n");
        sys->fprint(cg.output, "        s := <-t.ctxt.ctl or\n");
        sys->fprint(cg.output, "        s = <-t.wreq or\n");
        sys->fprint(cg.output, "        s = <-wmctl =>\n");
        sys->fprint(cg.output, "            tkclient->wmctl(t, s);\n");
        sys->fprint(cg.output, "        s := <-cmd =>\n");

        # Generate callback cases
        cbs := cg.callbacks;
        while (cbs != nil) {
            (name, event) := hd cbs;
            sys->fprint(cg.output, "            if(s == \"%s\")\n", name);
            sys->fprint(cg.output, "                %s();\n", name);
            cbs = tl cbs;
        }

        # Add tick case for time-based reactive functions
        if (has_reactive) {
            sys->fprint(cg.output, "        <-tick =>\n");
            rfns := prog.reactive_fns;
            while (rfns != nil) {
                # Only call time-based reactive functions
                if (rfns.interval > 0) {
                    # Check if this function has widget bindings
                    has_bindings := 0;
                    bindings := cg.reactive_bindings;
                    while (bindings != nil) {
                        (widget_path, prop_name, fn_name) := hd bindings;
                        if (fn_name == rfns.name) {
                            has_bindings = 1;
                            break;
                        }
                        bindings = tl bindings;
                    }

                    if (has_bindings) {
                        sys->fprint(cg.output, "            %s_update(t);\n", rfns.name);
                    } else {
                        sys->fprint(cg.output, "            %s_update();\n", rfns.name);
                    }
                }
                rfns = rfns.next;
            }

            # Also call update for FunctionDecl with reactive_interval
            fd := prog.function_decls;
            while (fd != nil) {
                if (fd.reactive_interval > 0) {
                    # Check if this function has widget bindings
                    has_bindings := 0;
                    bindings := cg.reactive_bindings;
                    while (bindings != nil) {
                        (widget_path, prop_name, fn_name) := hd bindings;
                        if (fn_name == fd.name) {
                            has_bindings = 1;
                            break;
                        }
                        bindings = tl bindings;
                    }

                    if (has_bindings) {
                        sys->fprint(cg.output, "            %s_update(t);\n", fd.name);
                    } else {
                        sys->fprint(cg.output, "            %s_update();\n", fd.name);
                    }
                }
                fd = fd.next;
            }
        }

        sys->fprint(cg.output, "        }\n");
        sys->fprint(cg.output, "    }\n");
    } else {
        sys->fprint(cg.output, "    for(;;) {\n");
        sys->fprint(cg.output, "        alt {\n");
        sys->fprint(cg.output, "        s := <-t.ctxt.kbd =>\n");
        sys->fprint(cg.output, "            tk->keyboard(t, s);\n");
        sys->fprint(cg.output, "        s := <-t.ctxt.ptr =>\n");
        sys->fprint(cg.output, "            tk->pointer(t, *s);\n");
        sys->fprint(cg.output, "        s := <-t.ctxt.ctl or\n");
        sys->fprint(cg.output, "        s = <-t.wreq or\n");
        sys->fprint(cg.output, "        s = <-wmctl =>\n");
        sys->fprint(cg.output, "            tkclient->wmctl(t, s);\n");

        # Add tick case for time-based reactive functions
        if (has_reactive) {
            sys->fprint(cg.output, "        <-tick =>\n");
            rfns := prog.reactive_fns;
            while (rfns != nil) {
                # Only call time-based reactive functions
                if (rfns.interval > 0) {
                    # Check if this function has widget bindings
                    has_bindings := 0;
                    bindings := cg.reactive_bindings;
                    while (bindings != nil) {
                        (widget_path, prop_name, fn_name) := hd bindings;
                        if (fn_name == rfns.name) {
                            has_bindings = 1;
                            break;
                        }
                        bindings = tl bindings;
                    }

                    if (has_bindings) {
                        sys->fprint(cg.output, "            %s_update(t);\n", rfns.name);
                    } else {
                        sys->fprint(cg.output, "            %s_update();\n", rfns.name);
                    }
                }
                rfns = rfns.next;
            }

            # Also call update for FunctionDecl with reactive_interval
            fd := prog.function_decls;
            while (fd != nil) {
                if (fd.reactive_interval > 0) {
                    # Check if this function has widget bindings
                    has_bindings := 0;
                    bindings := cg.reactive_bindings;
                    while (bindings != nil) {
                        (widget_path, prop_name, fn_name) := hd bindings;
                        if (fn_name == fd.name) {
                            has_bindings = 1;
                            break;
                        }
                        bindings = tl bindings;
                    }

                    if (has_bindings) {
                        sys->fprint(cg.output, "            %s_update(t);\n", fd.name);
                    } else {
                        sys->fprint(cg.output, "            %s_update();\n", fd.name);
                    }
                }
                fd = fd.next;
            }
        }

        sys->fprint(cg.output, "        }\n");
        sys->fprint(cg.output, "    }\n");
    }

    sys->fprint(cg.output, "}\n");

    return nil;
}

# Main generation function
generate(output: string, prog: ref Program, module_name: string): string
{
    if (prog == nil)
        return "nil program";

    if (output == nil || output == "")
        return "nil output path";

    # Open output file
    fd := sys->create(output, Sys->OWRITE, 8r666);
    if (fd == nil)
        return sys->sprint("cannot create output file: %s", output);

    cg := Codegen.create(fd, module_name);
    cg.is_draw_backend = should_use_draw_backend(prog);

    # Generate code in correct order:
    # 1. Prologue (includes, module declaration)
    # 2. Module variables (time, tpid)
    # 3. Collect widget commands (populates reactive_bindings)
    # 4. Generate tkcmds array
    # 5. Init function
    # 6. Reactive update functions
    # 7. Timer function
    # 8. User code blocks

    err := generate_prologue(cg, prog);
    if (err != nil) {
        fd = nil;
        return err;
    }

    # Generate module variables (time, tpid) after module declaration
    err = generate_var_decls(cg, prog);
    if (err != nil) {
        fd = nil;
        return err;
    }

    # Only for Tk backend
    if (!cg.is_draw_backend) {
        err = generate_reactive_vars(cg, prog);
        if (err != nil) {
            fd = nil;
            return err;
        }

        # Collect widget commands to populate reactive_bindings
        err = collect_widget_commands(cg, prog);
        if (err != nil) {
            fd = nil;
            return err;
        }

        err = generate_tkcmds_array(cg, prog);
        if (err != nil) {
            fd = nil;
            return err;
        }
    }

    err = generate_init(cg, prog);
    if (err != nil) {
        fd = nil;
        return err;
    }

    # Only for Tk backend
    if (!cg.is_draw_backend) {
        # Generate reactive update functions after init
        err = generate_reactive_funcs(cg, prog);
        if (err != nil) {
            fd = nil;
            return err;
        }

        # Generate timer function
        err = generate_reactive_timer(cg, prog);
        if (err != nil) {
            fd = nil;
            return err;
        }
    }

    # Generate user code blocks last
    err = generate_code_blocks(cg, prog);
    if (err != nil) {
        fd = nil;
        return err;
    }

    fd = nil;

    return nil;
}

# =========================================================================
# Main entry point
# =========================================================================

# Show usage message
show_usage()
{
    sys->fprint(sys->fildes(2), "Usage: kryon [-o output] input.kry\n");
    sys->fprint(sys->fildes(2), "\nOptions:\n");
    sys->fprint(sys->fildes(2), "  -o <output>  Specify output file (default: input.b)\n");
    sys->fprint(sys->fildes(2), "  -h           Show this help message\n");
    sys->fprint(sys->fildes(2), "\nExamples:\n");
    sys->fprint(sys->fildes(2), "  kryon input.kry           Generate input.b\n");
    sys->fprint(sys->fildes(2), "  kryon -o out.b in.kry    Generate to out.b\n");
}

# Derive module name from input file
derive_module_name(input_file: string): string
{
    if (input_file == nil)
        return "Module";

    # Find basename
    basename := input_file;
    for (i := len input_file - 1; i >= 0; i--) {
        if (input_file[i] == '/') {
            basename = input_file[i+1:];
            break;
        }
    }

    # Remove extension
    module_name := basename;
    dot := len module_name - 1;

    while (dot >= 0 && module_name[dot] != '.')
        dot--;

    if (dot > 0)
        module_name = module_name[0:dot];

    # Capitalize first letter
    if (len module_name > 0) {
        first := module_name[0];
        if (first >= 'a' && first <= 'z') {
            # Capitalize
            c := first - ('a' - 'A');
            module_name = sys->sprint("%c", c) + module_name[1:];
        }
    }

    return module_name;
}

# Derive output filename from input
derive_output_file(input_file: string): string
{
    if (input_file == nil)
        return nil;

    output := input_file;
    dot := len output - 1;

    while (dot >= 0 && output[dot] != '.')
        dot--;

    if (dot > 0)
        output = output[0:dot] + ".b";
    else
        output = output + ".b";

    return output;
}

# Read entire file into string
read_file(path: string): (string, string)
{
    iobuf := bufio->open(path, bufio->OREAD);
    if (iobuf == nil)
        return (nil, sys->sprint("cannot open file: %s: %r", path));

    # Read all lines and join them
    data := "";
    while ((s := iobuf.gets('\n')) != nil) {
        data += s;
    }

    iobuf.close();
    return (data, nil);
}

# Parse command line arguments
parse_args(argv: list of string): (string, string, string)
{
    input_file := "";
    output_file := "";

    # Skip program name
    args := tl argv;

    while (args != nil) {
        arg := hd args;
        args = tl args;

        if (arg == "-o") {
            if (args == nil)
                return (nil, nil, "missing argument for -o");

            output_file = hd args;
            args = tl args;
        } else if (arg == "-h" || arg == "--help") {
            show_usage();
            raise "success:help";
        } else if (arg[0] == '-') {
            return (nil, nil, "unknown option: " + arg);
        } else {
            if (input_file != nil && input_file != "")
                return (nil, nil, "multiple input files specified");

            input_file = arg;
        }
    }

    if (input_file == nil || input_file == "")
        return (nil, nil, "no input file specified");

    # Derive output file if not specified
    if (output_file == nil || output_file == "")
        output_file = derive_output_file(input_file);

    return (input_file, output_file, nil);
}

init(ctxt: ref Draw->Context, argv: list of string)
{
    sys = load Sys Sys->PATH;
    bufio = load Bufio Bufio->PATH;

    # Load dependent modules (use dis file paths)
    ast = load Ast "/dis/ast.dis";
    lexer = load Lexer "/dis/lexer.dis";

    # Parse arguments
    (input, output, err) := parse_args(argv);

    if (err != nil) {
        if (err == "success:help")
            return;

        sys->fprint(sys->fildes(2), "Error: %s\n", err);
        show_usage();
        raise "fail:args";
    }

    sys->print("Parsing %s...\n", input);

    # Read input file
    (contents, read_err) := read_file(input);
    if (read_err != nil) {
        sys->fprint(sys->fildes(2), "Error: %s\n", read_err);
        raise "fail:read";
    }

    # Create lexer
    l := lexer->create(input, contents);

    # Create parser
    p := Parser.create(l);

    # Parse
    (prog, parse_err) := parse_program(p);

    if (parse_err != nil) {
        sys->fprint(sys->fildes(2), "Parse error: %s\n", parse_err);
        raise "fail:parse";
    }

    # Derive module name
    module_name := derive_module_name(input);

    sys->print("Generating %s from %s...\n", output, input);

    # Generate code
    gen_err := generate(output, prog, module_name);

    if (gen_err != nil) {
        sys->fprint(sys->fildes(2), "Code generation error: %s\n", gen_err);
        raise "fail:codegen";
    }

    sys->print("Successfully generated %s\n", output);
}
