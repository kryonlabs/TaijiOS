# Lua VM - Lexer (Lexical Analyzer)
# Implements tokenization of Lua source code

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_opcodes.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Token Types
# ====================================================================

TK_RESERVED:	# Reserved words
TK_AND:		con 1;	or:	con 2;		break:	con 3;
TK_DO:		con 4;	else:	con 5;	elseif:	con 6;
TK_END:		con 7;	false:	con 8;	for:	con 9;
TK_FUNCTION:	con 10;	goto:	con 11;	if:	con 12;
TK_IN:		con 13;	local:	con 14;	nil:	con 15;
TK_REPEAT:	con 16;	return:	con 17;	then:	con 18;
TK_TRUE:	con 19;	until:	con 20;	while:	con 21;

# Other tokens
TK_CONCAT:	con 22;	# ..
TK_DOTS:	con 23;	# ...
TK_EQ:		con 24;	# ==
TK_LE:		con 25;	# <=
TK_GE:		con 26;	# >=
TK_NE:		con 27;	# ~=
TK_SHL:		con 28;	# <<
TK_SHR:		con 29;	# >>
TK_DBCOLON:	con 30;	# ::
TK_EOS:		con 31;	# End of source
TK_NUMBER:	con 32;	# Numeric literal
TK_NAME:		con 33;	# Identifier
TK_STRING:	con 34;	# String literal

TK_FLT:		con 35;	# Floating point number

# First reserved token
TK_FIRST_RESERVED: con TK_AND;
TK_LAST_RESERVED:	con TK_WHILE;

# ====================================================================
# Reserved Words
# }

reserved: array of string = array[] of {
	"and", "or", "break", "do", "else", "elseif",
	"end", "false", "for", "function", "goto", "if",
	"in", "local", "nil", "repeat", "return", "then",
	"true", "until", "while"
};

# Convert reserved word to token
reservedword(s: string): int
{
	case(s) {
	"and" =>	return TK_AND;
	"or" =>		return TK_OR;
	"break" =>	return TK_BREAK;
	"do" =>		return TK_DO;
	"else" =>	return TK_ELSE;
	"elseif" =>	return TK_ELSEIF;
	"end" =>		return TK_END;
	"false" =>	return TK_FALSE;
	"for" =>		return TK_FOR;
	"function" =>	return TK_FUNCTION;
	"goto" =>	return TK_GOTO;
	"if" =>		return TK_IF;
	"in" =>		return TK_IN;
	"local" =>	return TK_LOCAL;
	"nil" =>		return TK_NIL;
	"repeat" =>	return TK_REPEAT;
	"return" =>	return TK_RETURN;
	"then" =>	return TK_THEN;
	"true" =>	return TK_TRUE;
	"until" =>	return TK_UNTIL;
	"while" =>	return TK_WHILE;
	* =>		return 0;
	}
}

# Check if character is a letter
islalpha(c: int): int
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

# Check if character is alphanumeric or underscore
isalnum(c: int): int
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
	       (c >= '0' && c <= '9') || c == '_';
}

# Check if character is a digit
isadigit(c: int): int
{
	return c >= '0' && c <= '9';
}

# Check if character is a space
isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

# Check if character can start a number
isdec(c: int): int
{
	return isadigit(c);
}

# Check for new line
isnewline(c: int): int
{
	return c == '\n' || c == '\r';
}

# ====================================================================
# Lexer State
# ====================================================================

Lexer: adt {
	source:		string;		# Source code
	srclen:		int;		# Source length
	pos:		int;		# Current position
	line:		int;		# Current line
	lastline:	int;		# Line of last token
	token:		int;		# Current token
	seminfo:	ref SemInfo;	# Semantic info
	lookahead:	ref Lexer;	# Lookahead for backtracking
};

# Semantic information for tokens
SemInfo: adt {
	r:	real;		# For numbers
	s:	string;		# For strings/identifiers
	i:	int;		# For integers
};

# Create new lexer
newlexer(source: string): ref Lexer
{
	l := ref Lexer;
	l.source = source;
	l.srclen = len source;
	l.pos = 0;
	l.line = 1;
	l.lastline = 1;
	l.token = 0;
	l.seminfo = ref SemInfo;
	l.lookahead = nil;
	return l;
}

# Get current character
currchar(l: ref Lexer): int
{
	if(l.pos >= l.srclen)
		return -1;
	return l.source[l.pos];
}

# Get next character
nextchar(l: ref Lexer): int
{
	if(l.pos >= l.srclen)
		return -1;
	c := l.source[l.pos];
	l.pos++;
	return c;
}

# Save character (backup)
saveandnext(l: ref Lexer, sb: ref stringbuf)
{
	if(l.pos > 0)
		sb.add(l.source[l.pos - 1]);
	l.pos++;
}

# Skip to next line
inclinenumber(l: ref Lexer)
{
	c := currchar(l);
	l.pos++;  # Skip newline
	if(c == '\r' && currchar(l) == '\n')
		l.pos++;  # Skip \n after \r
	l.line++;
}

# ====================================================================
# String Buffer for Building Tokens
# ====================================================================

stringbuf: adt {
	buf:	array of byte;
	len:	int;
};

newstringbuf(): ref stringbuf
{
	sb := ref stringbuf;
	sb.buf = array[64] of byte;
	sb.length = 0;
	return sb;
}

add(sb: ref stringbuf, c: int)
{
	if(sb.length >= len sb.buf) {
		newbuf := array[len sb.buf * 2] of byte;
		newbuf[:sb.length] = sb.buf[:sb.length];
		sb.buf = newbuf;
	}
	sb.buf[sb.length++] = byte c;
}

tostring(sb: ref stringbuf): string
{
	if(sb.length == 0)
		return "";
	s := string sb.buf[:sb.length];
	return s;
}

reset(sb: ref stringbuf)
{
	sb.length = 0;
}

# ====================================================================
# Lexical Analysis Functions
# ====================================================================

# Main lexer function - get next token
lex(l: ref Lexer): int
{
	l.lastline = l.line;
	sb := newstringbuf();

	for(;;) {
		c := currchar(l);
		l.pos++;

		case(c) {
		-1 or '\0' =>
			l.token = TK_EOS;
			return l.token;

		'\n' or '\r' =>
			l.line++;
			continue;

		' ' or '\t' or '\f' or '\v' =>
			continue;

		'-' =>
			if(currchar(l) == '-') {
				l.pos++;  # Skip second -
				# Long comment (--[[ ... ]]) or short comment
				if(currchar(l) == '[') {
					l.pos++;  # Skip [
					sep := skipsep(l);
					if(sep >= 0) {
						readlongstring(l, sb, sep);
						reset(sb);
						continue;
					}
				}
				# Short comment
				while(!isnewline(currchar(l)) && currchar(l) != -1)
					l.pos++;
				continue;
			}
			l.token = '-';
			return l.token;

		'[' =>
			sep := skipsep(l);
			if(sep >= 0) {
				readlongstring(l, sb, sep);
				l.seminfo.s = tostring(sb);
				l.token = TK_STRING;
				return l.token;
			} else if(sep == -1) {
				l.token = '[';
				return l.token;
			} else {
				# Error, return '['
				l.token = '[';
				return l.token;
			}

		'=' =>
			if(currchar(l) == '=') {
				l.pos++;
				l.token = TK_EQ;
			} else {
				l.token = '=';
			}
			return l.token;

		'<' =>
			if(currchar(l) == '=') {
				l.pos++;
				l.token = TK_LE;
			} else if(currchar(l) == '<') {
				l.pos++;
				l.token = TK_SHL;
			} else {
				l.token = '<';
			}
			return l.token;

		'>' =>
			if(currchar(l) == '=') {
				l.pos++;
				l.token = TK_GE;
			} else if(currchar(l) == '>') {
				l.pos++;
				l.token = TK_SHR;
			} else {
				l.token = '>';
			}
			return l.token;

		'/' =>
			if(currchar(l) == '/') {
				l.pos++;
				l.token = TK_CONCAT;  # Actually //
			} else {
				l.token = '/';
			}
			return l.token;

		':' =>
			if(currchar(l) == ':') {
				l.pos++;
				l.token = TK_DBCOLON;
			} else {
				l.token = ':';
			}
			return l.token;

		'"' or '\'' =>
			readstring(l, sb, c);
			l.seminfo.s = tostring(sb);
			l.token = TK_STRING;
			return l.token;

		'.' =>
			if(currchar(l) == '.') {
				l.pos++;
				if(currchar(l) == '.') {
					l.pos++;
					l.token = TK_DOTS;
				} else {
					l.token = TK_CONCAT;
				}
				return l.token;
			} else if(!isadigit(currchar(l))) {
				l.token = '.';
				return l.token;
			}
			# Fall through to number parsing

		'0' to '9' =>
			# Number
			l.pos--;  # Put back digit
			readnumeral(l, sb);
			return l.token;

		* =>
			if(islalpha(c)) {
				# Identifier or reserved word
				l.pos--;  # Put back first char
				while(isalnum(currchar(l))) {
					add(sb, currchar(l));
					l.pos++;
				}
				s := tostring(sb);
				res := reservedword(s);
				if(res != 0) {
					l.token = res;
				} else {
					l.token = TK_NAME;
					l.seminfo.s = s;
				}
				return l.token;
			} else {
				# Single char token
				l.token = c;
				return l.token;
			}
		}
	}
}

# Check for separator [=[ ... ]=
skipsep(l: ref Lexer): int
{
	sep := 0;
	c := currchar(l);
	while(c == '=') {
		l.pos++;
		sep++;
		c = currchar(l);
	}
	if(c == '[')
		return sep;
	return -sep - 1;
}

# Read long string or comment
readlongstring(l: ref Lexer, sb: ref stringbuf, sep: int)
{
	l.pos++;  # Skip [
	if(!isnewline(currchar(l)))
		l.line--;  # Line is incremented by newline

	while(;;) {
		c := currchar(l);
		if(c == -1) {
			# Error: unfinished long string
			return;
		}
		l.pos++;

		if(c == ']') {
			if(sep == skipsep2(l)) {
				# Found closing
				return;
			}
		} else if(isnewline(c)) {
			l.line++;
			if(sb != nil)
				add(sb, '\n');
		} else if(sb != nil) {
			add(sb, c);
		}
	}
}

# Check for closing separator
skipsep2(l: ref Lexer): int
{
	sep := 0;
	c := currchar(l);
	while(c == '=') {
		l.pos++;
		sep++;
		c = currchar(l);
	}
	if(c == ']')
		return sep;
	return -sep - 1;
}

# Read string literal
readstring(l: ref Lexer, sb: ref stringbuf, delim: int)
{
	l.pos++;  # Skip delimiter
	while(;;) {
		c := currchar(l);
		if(c == -1) {
			# Error: unfinished string
			return;
		}
		l.pos++;

		if(c == delim) {
			# End of string
			return;
		}

		if(c == '\\') {
			# Escape sequence
			c := readescape(l);
			if(c != -1)
				add(sb, c);
		} else if(c == '\n' || c == '\r') {
			# Error: unfinished string
			return;
		} else {
			add(sb, c);
		}
	}
}

# Read escape sequence
readescape(l: ref Lexer): int
{
	c := currchar(l);
	l.pos++;

	case(c) {
	'a' =>	return '\a';  # Bell
	'b' =>	return '\b';  # Backspace
	'f' =>	return '\f';  # Form feed
	'n' =>	return '\n';  # Newline
	'r' =>	return '\r';  # Carriage return
	't' =>	return '\t';  # Tab
	'v' =>	return '\v';  # Vertical tab
	'\\' =>	return '\\';
	'"' =>	return '"';
	'\'' =>	return '\'';
	'-' =>	return 0;  # Skip soft line break
	'\n' or '\r' =>	return 0;  # Skip line break
	* =>
		if(isadigit(c)) {
			# Decimal escape \ddd
			i := 0;
			n := 0;
			while(i < 3 && isadigit(c)) {
				n = n * 10 + (c - '0');
				i++;
				c = currchar(l);
				l.pos++;
			}
			return n;
		}
		# Unknown escape, keep as-is
		return c;
	}
}

# Read number literal
readnumeral(l: ref Lexer, sb: ref stringbuf)
{
	c := currchar(l);
	l.pos();

	# Check for hex
	if(c == '0' && l.pos + 1 < l.srclen) {
		c2 := l.source[l.pos + 1];
		if(c2 == 'x' || c2 == 'X') {
			# Hex number
			add(sb, c);
			l.pos++;
			add(sb, c2);
			l.pos++;
			while(isxdigit(currchar(l))) {
				add(sb, currchar(l));
				l.pos++;
			}
			if(currchar(l) == '.') {
				add(sb, '.');
				l.pos++;
				while(isxdigit(currchar(l))) {
					add(sb, currchar(l));
					l.pos++;
				}
			}
			if(currchar(l) == 'p' || currchar(l) == 'P') {
				add(sb, currchar(l));
				l.pos++;
				if(currchar(l) == '-' || currchar(l) == '+') {
					add(sb, currchar(l));
					l.pos++;
				}
				while(isadigit(currchar(l))) {
					add(sb, currchar(l));
					l.pos++;
				}
			}
			l.seminfo.s = tostring(sb);
			l.token = TK_NUMBER;
			return;
		}
	}

	# Decimal number
	while(isadigit(currchar(l))) {
		add(sb, currchar(l));
		l.pos++;
	}

	if(currchar(l) == '.') {
		add(sb, '.');
		l.pos++;
		while(isadigit(currchar(l))) {
			add(sb, currchar(l));
			l.pos++;
		}
		l.token = TK_FLT;
	} else {
		l.token = TK_NUMBER;
	}

	# Exponent
	if(currchar(l) == 'e' || currchar(l) == 'E') {
		add(sb, currchar(l));
		l.pos++;
		if(currchar(l) == '-' || currchar(l) == '+') {
			add(sb, currchar(l));
			l.pos++;
		}
		while(isadigit(currchar(l))) {
			add(sb, currchar(l));
			l.pos++;
		}
		l.token = TK_FLT;
	}

	l.seminfo.s = tostring(sb);

	# Convert to number
	if(l.token == TK_FLT) {
		# Floating point
		l.seminfo.r = atof(l.seminfo.s);
	} else {
		# Integer
		l.seminfo.i = atoi(l.seminfo.s);
		l.seminfo.r = real(l.seminfo.i);
	}
}

# Check for hex digit
isxdigit(c: int): int
{
	return (c >= '0' && c <= '9') ||
	       (c >= 'a' && c <= 'f') ||
	       (c >= 'A' && c <= 'F');
}

# String to integer (simple)
atoi(s: string): int
{
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= '0' && c <= '9')
			n = n * 10 + (c - '0');
	}
	return n;
}

# String to float (simple)
atof(s: string): real
{
	# Simplified - in real implementation would use full float parsing
	n := 0.0;
	dec := 0.1;
	afterdot := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= '0' && c <= '9') {
			if(!afterdot) {
				n = n * 10.0 + real(c - '0');
			} else {
				n = n + dec * real(c - '0');
				dec = dec / 10.0;
			}
		} else if(c == '.') {
			afterdot = 1;
		}
	}
	return n;
}

# Get token name for debugging
tokenname(token: int): string
{
	case(token) {
	TK_AND =>	return "and";
	TK_OR =>		return "or";
	TK_BREAK =>	return "break";
	TK_DO =>		return "do";
	TK_ELSE =>		return "else";
	TK_ELSEIF =>	return "elseif";
	TK_END =>		return "end";
	TK_FALSE =>	return "false";
	TK_FOR =>		return "for";
	TK_FUNCTION =>	return "function";
	TK_GOTO =>	return "goto";
	TK_IF =>		return "if";
	TK_IN =>		return "in";
	TK_LOCAL =>	return "local";
	TK_NIL =>		return "nil";
	TK_REPEAT =>	return "repeat";
	TK_RETURN =>	return "return";
	TK_THEN =>	return "then";
	TK_TRUE =>		return "true";
	TK_UNTIL =>	return "until";
	TK_WHILE =>	return "while";
	TK_CONCAT =>	return "..";
	TK_DOTS =>		return "...";
	TK_EQ =>		return "==";
	TK_LE =>		return "<=";
	TK_GE =>		return ">=";
	TK_NE =>		return "~=";
	TK_SHL =>		return "<<";
	TK_SHR =>		return ">>";
	TK_DBCOLON =>	return "::";
	TK_EOS =>		return "<eos>";
	TK_NUMBER =>	return "<number>";
	TK_NAME =>		return "<name>";
	TK_STRING =>	return "<string>";
	* =>
		if(token >= 32 && token <= 126)
			return sprint("%c", token);
		return sprint("?%d?", token);
	}
}

# Look ahead without consuming
lookahead(l: ref Lexer): int
{
	if(l.lookahead == nil) {
		l.lookahead = newlexer(l.source[l.pos:]);
		l.lookahead.pos = 0;
		l.lookahead.line = l.line;
	}
	return lex(l.lookahead);
}

# Module initialization
init(): string
{
	sys = load Sys Sys;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Lexical Analyzer (Lexer)",
		"Tokenizes Lua source code",
	};
}
