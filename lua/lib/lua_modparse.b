# Lua VM - Module Definition Parser
# Parses .m files to extract function signatures, ADT definitions, and constants

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Data Structures for Module Signatures
# ====================================================================

# Type descriptor
Type: adt {
	pick {
	Basic =>
		name: string;  # int, real, string, byte, etc.
	Array =>
		elem: ref Type;
		len: int;  # 0 for dynamic
	List =>
		elem: ref Type;
	Ref =>
		target: string;  # ADT or module name
	Function =>
		params: list of ref Param;
		returns: ref Type;
	};
};

# Function parameter
Param: adt {
	name: string;
	typ: ref Type;
};

# Function signature
FuncSig: adt {
	name: string;
	params: list of ref Param;
	returns: list of ref Type;  # Multiple return values
};

# ADT field
ADTField: adt {
	name: string;
	typ: ref Type;
};

# ADT signature (pick variant)
ADTPick: adt {
	name: string;          # Variant name
	fields: list of ref ADTField;
};

# ADT signature
ADTSig: adt {
	name: string;
	picks: list of ref ADTPick;  # nil if not a pick ADT
	fields: list of ref ADTField;  # nil if a pick ADT
};

# Constant signature
ConstSig: adt {
	name: string;
	typ: ref Type;
	value: string;  # String representation
};

# Complete module signature
ModSignature: adt {
	modname: string;
	functions: list of ref FuncSig;
	adts: list of ref ADTSig;
	constants: list of ref ConstSig;
};

# ====================================================================
# Tokenizer
# ====================================================================

Token: adt {
	kind: int;     # 0:ident, 1:string, 2:number, 3:symbol, 4:keyword
	text: string;
	line: int;
};

TK_IDENT: con 0;
TK_STRING: con 1;
TK_NUMBER: con 2;
TK_SYMBOL: con 3;
TK_KEYWORD: con 4;

# Tokenize input buffer
tokenize(buf: string): list of ref Token
{
	tokens: list of ref Token = nil;

	i := 0;
	line := 1;
	lenbuf := len buf;

	while(i < lenbuf) {
		# Skip whitespace
		while(i < lenbuf && (buf[i] == ' ' || buf[i] == '\t' || buf[i] == '\n' || buf[i] == '\r')) {
			if(buf[i] == '\n')
				line++;
			i++;
		}

		if(i >= lenbuf)
			break;

		# Skip comments
		if(i + 1 < lenbuf && buf[i] == '#' && buf[i+1] == '#') {
			while(i < lenbuf && buf[i] != '\n')
				i++;
			continue;
		}

		if(i + 1 < lenbuf && buf[i] == '#') {
			while(i < lenbuf && buf[i] != '\n')
				i++;
			continue;
		}

		# Identify token
		start := i;

		if(buf[i] == '"' || buf[i] == '\'') {
			# String literal
			quote := buf[i];
			i++;
			strval := "";
			while(i < lenbuf && buf[i] != quote) {
				if(buf[i] == '\\' && i + 1 < lenbuf) {
					i++;
					case buf[i] {
					'n' => strval[len strval] = '\n';
					't' => strval[len strval] = '\t';
					'r' => strval[len strval] = '\r';
					'0' => strval[len strval] = '\0';
					* => strval[len strval] = buf[i];
					}
				} else {
					strval[len strval] = buf[i];
				}
				i++;
			}
			i++;  # Skip closing quote

			tok := ref Token;
			tok.kind = TK_STRING;
			tok.text = strval;
			tok.line = line;
			tokens = tok :: tokens;

		} else if(buf[i] >= '0' && buf[i] <= '9') {
			# Number
			while(i < lenbuf && ((buf[i] >= '0' && buf[i] <= '9') || buf[i] == '.' || buf[i] == 'e' || buf[i] == 'E' || buf[i] == '-' || buf[i] == '+'))
				i++;

			tok := ref Token;
			tok.kind = TK_NUMBER;
			tok.text = buf[start:i];
			tok.line = line;
			tokens = tok :: tokens;

		} else if((buf[i] >= 'a' && buf[i] <= 'z') || (buf[i] >= 'A' && buf[i] <= 'Z') || buf[i] == '_') {
			# Identifier or keyword
			while(i < lenbuf && ((buf[i] >= 'a' && buf[i] <= 'z') || (buf[i] >= 'A' && buf[i] <= 'Z') || (buf[i] >= '0' && buf[i] <= '9') || buf[i] == '_'))
				i++;

			text := buf[start:i];

			tok := ref Token;
			tok.kind = iskeyword(text) ? TK_KEYWORD : TK_IDENT;
			tok.text = text;
			tok.line = line;
			tokens = tok :: tokens;

		} else {
			# Symbol (operator or punctuation)
			# Handle multi-char symbols
			if(i + 1 < lenbuf) {
				two := buf[i:i+2];
				if(two == ":=" || two == "==" || two == "!=" || two == "<=" || two == ">=" || two == "<<" || two == ">>" || two == "||" || two == "&&") {
					tok := ref Token;
					tok.kind = TK_SYMBOL;
					tok.text = two;
					tok.line = line;
					tokens = tok :: tokens;
					i += 2;
					continue;
				}
			}

			# Single char symbol
			tok := ref Token;
			tok.kind = TK_SYMBOL;
			tok.text = string buf[i];
			tok.line = line;
			tokens = tok :: tokens;
			i++;
		}
	}

	# Reverse to get correct order
	result: list of ref Token = nil;
	while(tokens != nil) {
		result = hd tokens :: result;
		tokens = tl tokens;
	}

	return result;
}

# Check if identifier is a keyword
iskeyword(id: string): int
{
	keywords := [] of {"module", "implement", "include", "con", "fn", "adt", "pick", "import", "self", "load", "return", "if", "else", "while", "for", "do", "case", "alt", "spawn", "nil", "ref"};

	for(i := 0; i < len keywords; i++) {
		if(id == keywords[i])
			return 1;
	}
	return 0;
}

# ====================================================================
# Parser
# ====================================================================

# Parse module file
parsemodulefile(modpath: string): ref ModSignature
{
	if(modpath == nil)
		return nil;

	# Read file
	fd := sys->open(modpath, Sys->OREAD);
	if(fd == nil)
		return nil;

	buf := "";
	bufarray := array[8192] of byte;
	while((n := fd.read(bufarray, len bufarray)) > 0) {
		buf += string bufarray[0:n];
	}
	fd.close();

	return parsemodule(buf);
}

# Parse module from buffer
parsemodule(buf: string): ref ModSignature
{
	if(buf == nil)
		return nil;

	tokens := tokenize(buf);
	if(tokens == nil)
		return nil;

	modsig := ref ModSignature;
	modsig.modname = "";
	modsig.functions = nil;
	modsig.adts = nil;
	modsig.constants = nil;

	i := 0;

	# Find module declaration
	while(i < len tokens) {
		tok := hd tokens;

		if(tok.kind == TK_KEYWORD && tok.text == "module") {
			# Parse: ModuleName: module { ... };
			tokens = tl tokens;
			if(tokens == nil)
				break;

			nametok := hd tokens;
			modsig.modname = nametok.text;

			tokens = tl tokens;
			if(tokens == nil)
				break;

			tokens = tl tokens;  # Skip ':'
			if(tokens == nil)
				break;

			tokens = tl tokens;  # Skip 'module'
			if(tokens == nil)
				break;

			# Parse module body
			(modsig, tokens) = parsemodulebody(modsig, tokens);
			break;
		}

		tokens = tl tokens;
		i++;
	}

	return modsig;
}

# Parse module body between { }
parsemodulebody(modsig: ref ModSignature; tokens: list of ref Token): (ref ModSignature, list of ref Token)
{
	if(tokens == nil)
		return (modsig, tokens);

	# Skip {
	open := hd tokens;
	if(open.kind != TK_SYMBOL || open.text != "{")
		return (modsig, tokens);

	tokens = tl tokens;

	# Parse until }
	while(tokens != nil) {
		tok := hd tokens;

		if(tok.kind == TK_SYMBOL && tok.text == "}")
			break;

		if(tok.kind == TK_KEYWORD && tok.text == "fn") {
			# Parse function
			(funcsig, rest) := parsefunction(tokens);
			if(funcsig != nil) {
				modsig.functions = funcsig :: modsig.functions;
				tokens = rest;
			} else {
				tokens = tl tokens;
			}

		} else if(tok.kind == TK_KEYWORD && tok.text == "adt") {
			# Parse ADT
			(adtsig, rest) := parseadt(tokens);
			if(adtsig != nil) {
				modsig.adts = adtsig :: modsig.adts;
				tokens = rest;
			} else {
				tokens = tl tokens;
			}

		} else if(tok.kind == TK_KEYWORD && tok.text == "con") {
			# Parse constant
			(constsig, rest) := parseconstant(tokens);
			if(constsig != nil) {
				modsig.constants = constsig :: modsig.constants;
				tokens = rest;
			} else {
				tokens = tl tokens;
			}

		} else {
			tokens = tl tokens;
		}
	}

	# Reverse lists
	modsig.functions = reverselist(modsig.functions);
	modsig.adts = reverselist(modsig.adts);
	modsig.constants = reverselist(modsig.constants);

	return (modsig, tl tokens);  # Skip }
}

# Parse function declaration
parsefunction(tokens: list of ref Token): (ref FuncSig, list of ref Token)
{
	if(tokens == nil)
		return (nil, tokens);

	# fn fname(p1: type1, p2: type2): returntype;

	tokens = tl tokens;  # Skip 'fn'
	if(tokens == nil)
		return (nil, tokens);

	fnametok := hd tokens;
	if(fnametok.kind != TK_IDENT)
		return (nil, tokens);

	funcsig := ref FuncSig;
	funcsig.name = fnametok.text;

	tokens = tl tokens;
	if(tokens == nil)
		return (nil, tokens);

	tokens = tl tokens;  # Skip ':'
	if(tokens == nil)
		return (nil, tokens);

	# Parse parameters
	tokens = tl tokens;  # Skip '('
	if(tokens == nil)
		return (nil, tokens);

	params: list of ref Param = nil;

	while(tokens != nil) {
		tok := hd tokens;

		if(tok.kind == TK_SYMBOL && tok.text == ")")
			break;

		if(tok.kind == TK_SYMBOL && tok.text == ",") {
			tokens = tl tokens;
			if(tokens == nil)
				break;
			tok = hd tokens;
		}

		if(tok.kind != TK_IDENT)
			break;

		pname := tok.text;
		tokens = tl tokens;

		if(tokens == nil)
			break;

		tokens = tl tokens;  # Skip ':'
		if(tokens == nil)
			break;

		# Parse type
		(typ, rest) = parsetype(tokens);
		if(typ == nil)
			break;

		param := ref Param;
		param.name = pname;
		param.typ = typ;
		params = param :: params;

		tokens = rest;
	}

	funcsig.params = reverselist(params);

	# Skip )
	if(tokens == nil)
		return (nil, tokens);

	tokens = tl tokens;
	if(tokens == nil)
		return (nil, tokens);

	# Skip :
	if(tokens == nil || hd tokens.kind != TK_SYMBOL || hd tokens.text != ":")
		return (nil, tokens);

	tokens = tl tokens;

	# Parse return type(s)
	returns: list of ref Type = nil;
	if(tokens != nil) {
		# Check for '(' (multiple returns)
		if(hd tokens.kind == TK_SYMBOL && hd tokens.text == "(") {
			tokens = tl tokens;

			while(tokens != nil) {
				tok := hd tokens;

				if(tok.kind == TK_SYMBOL && tok.text == ")")
					break;

				(rettype, rest) = parsetype(tokens);
				if(rettype == nil)
					break;

				returns = rettype :: returns;
				tokens = rest;

				if(tokens != nil && hd tokens.kind == TK_SYMBOL && hd tokens.text == ",") {
					tokens = tl tokens;
				}
			}

			tokens = tl tokens;  # Skip ')'
		} else {
			# Single return type
			(rettype, rest) := parsetype(tokens);
			if(rettype != nil) {
				returns = rettype :: returns;
				tokens = rest;
			}
		}
	}

	funcsig.returns = reverselist(returns);

	# Skip ;
	if(tokens != nil && hd tokens.kind == TK_SYMBOL && hd tokens.text == ";")
		tokens = tl tokens;

	return (funcsig, tokens);
}

# Parse type
parsetype(tokens: list of ref Token): (ref Type, list of ref Token)
{
	if(tokens == nil)
		return (nil, tokens);

	tok := hd tokens;

	# Check for array of type
	if(tok.kind == TK_KEYWORD && tok.text == "array") {
		tokens = tl tokens;
		if(tokens == nil)
			return (nil, tokens);

		tokens = tl tokens;  # Skip 'of'
		if(tokens == nil)
			return (nil, tokens);

		(elemtype, rest) := parsetype(tokens);
		if(elemtype == nil)
			return (nil, tokens);

		t := ref Type.Array;
		t.elem = elemtype;
		t.length = 0;  # Dynamic array

		return (t, rest);
	}

	# Check for list of type
	if(tok.kind == TK_KEYWORD && tok.text == "list") {
		tokens = tl tokens;
		if(tokens == nil)
			return (nil, tokens);

		tokens = tl tokens;  # Skip 'of'
		if(tokens == nil)
			return (nil, tokens);

		(elemtype, rest) := parsetype(tokens);
		if(elemtype == nil)
			return (nil, tokens);

		t := ref Type.List;
		t.elem = elemtype;

		return (t, rest);
	}

	# Basic type or ref type
	if(tok.kind != TK_IDENT)
		return (nil, tokens);

	t := ref Type.Basic;
	t.name = tok.text;

	return (t, tl tokens);
}

# Parse ADT declaration
parseadt(tokens: list of ref Token): (ref ADTSig, list of ref Token)
{
	if(tokens == nil)
		return (nil, tokens);

	# adt AdtName { ... };

	tokens = tl tokens;  # Skip 'adt'
	if(tokens == nil)
		return (nil, tokens);

	nametok := hd tokens;
	if(nametok.kind != TK_IDENT)
		return (nil, tokens);

	adtsig := ref ADTSig;
	adtsig.name = nametok.text;
	adtsig.picks = nil;
	adtsig.fields = nil;

	tokens = tl tokens;
	if(tokens == nil)
		return (nil, tokens);

	tokens = tl tokens;  # Skip ':'
	if(tokens == nil)
		return (nil, tokens);

	# Check for pick
	if(tokens != nil && hd tokens.kind == TK_KEYWORD && hd tokens.text == "pick") {
		tokens = tl tokens;

		picks: list of ref ADTPick = nil;

		# Parse pick variants
		tokens = tl tokens;  # Skip '{'
		if(tokens == nil)
			return (nil, tokens);

		while(tokens != nil) {
			tok := hd tokens;

			if(tok.kind == TK_SYMBOL && tok.text == "}")
				break;

			if(tok.kind != TK_IDENT)
				break;

			pickname := tok.text;
			tokens = tl tokens;

			if(tokens == nil)
				break;

			tokens = tl tokens;  # Skip '=>'
			if(tokens == nil)
				break;

			# Parse fields
			fields: list of ref ADTField = nil;

			if(tokens != nil && hd tokens.kind == TK_SYMBOL && hd tokens.text == "{") {
				tokens = tl tokens;

				while(tokens != nil) {
					ftok := hd tokens;

					if(ftok.kind == TK_SYMBOL && ftok.text == "}")
						break;

					if(ftok.kind != TK_IDENT)
						break;

					fname := ftok.text;
					tokens = tl tokens;

					if(tokens == nil)
						break;

					tokens = tl tokens;  # Skip ':'
					if(tokens == nil)
						break;

					(ftype, rest) := parsetype(tokens);
					if(ftype == nil)
						break;

					field := ref ADTField;
					field.name = fname;
					field.typ = ftype;
					fields = field :: fields;

					tokens = rest;

					if(tokens != nil && hd tokens.kind == TK_SYMBOL && hd tokens.text == ";")
						tokens = tl tokens;
				}

				tokens = tl tokens;  # Skip '}'
			}

			pick := ref ADTPick;
			pick.name = pickname;
			pick.fields = reverselist(fields);
			picks = pick :: picks;

			if(tokens != nil && hd tokens.kind == TK_SYMBOL && hd tokens.text == ";")
				tokens = tl tokens;
		}

		adtsig.picks = reverselist(picks);

	} else {
		# Regular ADT
		tokens = tl tokens;  # Skip '{'
		if(tokens == nil)
			return (nil, tokens);

		fields: list of ref ADTField = nil;

		while(tokens != nil) {
			tok := hd tokens;

			if(tok.kind == TK_SYMBOL && tok.text == "}")
				break;

			if(tok.kind != TK_IDENT)
				break;

			fname := tok.text;
			tokens = tl tokens;

			if(tokens == nil)
				break;

			tokens = tl tokens;  # Skip ':'
			if(tokens == nil)
				break;

			(ftype, rest) := parsetype(tokens);
			if(ftype == nil)
				break;

			field := ref ADTField;
			field.name = fname;
			field.typ = ftype;
			fields = field :: fields;

			tokens = rest;

			if(tokens != nil && hd tokens.kind == TK_SYMBOL && hd tokens.text == ";")
				tokens = tl tokens;
		}

		adtsig.fields = reverselist(fields);
		tokens = tl tokens;  # Skip '}'
	}

	# Skip ;
	if(tokens != nil && hd tokens.kind == TK_SYMBOL && hd tokens.text == ";")
		tokens = tl tokens;

	return (adtsig, tokens);
}

# Parse constant declaration
parseconstant(tokens: list of ref Token): (ref ConstSig, list of ref Token)
{
	if(tokens == nil)
		return (nil, tokens);

	# con name: type = value;

	tokens = tl tokens;  # Skip 'con'
	if(tokens == nil)
		return (nil, tokens);

	nametok := hd tokens;
	if(nametok.kind != TK_IDENT)
		return (nil, tokens);

	constsig := ref ConstSig;
	constsig.name = nametok.text;

	tokens = tl tokens;
	if(tokens == nil)
		return (nil, tokens);

	# Check for type
	if(hd tokens.kind == TK_SYMBOL && hd tokens.text == ":") {
		tokens = tl tokens;

		(typ, rest) = parsetype(tokens);
		if(typ == nil)
			return (nil, tokens);

		constsig.typ = typ;
		tokens = rest;
	} else {
		# No type specified, infer from value
		t := ref Type.Basic;
		t.name = "int";
		constsig.typ = t;
	}

	# Check for value
	if(tokens == nil || hd tokens.kind != TK_SYMBOL || hd tokens.text != "=")
		return (nil, tokens);

	tokens = tl tokens;

	if(tokens == nil)
		return (nil, tokens);

	valtok := hd tokens;
	constsig.value = valtok.text;

	tokens = tl tokens;

	# Skip ;
	if(tokens != nil && hd tokens.kind == TK_SYMBOL && hd tokens.text == ";")
		tokens = tl tokens;

	return (constsig, tokens);
}

# ====================================================================
# Helper Functions
# ====================================================================

# Reverse a list
reverselist(l: list of ref ^1^): list of ref ^1^
{
	result: list of ref ^1^ = nil;
	while(l != nil) {
		result = hd l :: result;
		l = tl l;
	}
	return result;
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Module Definition Parser",
		"Parses .m files to extract signatures",
	};
}
