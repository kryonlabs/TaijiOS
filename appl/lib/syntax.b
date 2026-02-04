implement Syntax;

include "sys.m";
include "draw.m";
include "bufio.m";
include "syntax.m";

sys : Sys;
drawm : Draw;
bufio : Bufio;
Iobuf : import bufio;

# Module state
is_initialized : int = 0;
theme_path : string = nil;

# Default colors (fallback if theme not loaded)
default_colors := array[10] of {
	"#0000FF",	# TKEYWORD - blue
	"#00AA00",	# TSTRING - green
	"#00AA00",	# TCHAR - green
	"#B5CEA8",	# TNUMBER - light green
	"#888888",	# TCOMMENT - gray
	"#4EC9B0",	# TTYPE - teal
	"#DCDCAA",	# TFUNCTION - light yellow
	"#D4D4D4",	# TOPERATOR - light gray
	"#C586C0",	# TPREPROCESSOR - purple
	"#000000",	# TIDENTIFIER - black
};

# Limbo keywords
limbo_keywords : list of string;

init()
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;

	# Initialize Limbo keyword list
	limbo_keywords = list of {
		"implement", "module", "fn", "con", "include",
		"adt", "within", "import", "self", "return",
		"if", "else", "while", "for", "do", "case",
		"break", "continue", "alt", "spawn",
		"load", "raise", "exception", "catch",
		"len", "array", "list", "chan", "nil",
		"int", "big", "real", "string", "byte",
		"ref", "cyclic", "data"
	};

	is_initialized = 1;
}

enabled() : int
{
	return is_initialized;
}

# Check if a string is a Limbo keyword
is_keyword(s : string) : int
{
	for (l := limbo_keywords; l != nil; l = tl l) {
		if (hd l == s)
			return 1;
	}
	return 0;
}

# Check if a character can start an identifier
is_id_start(c : int) : int
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
}

# Check if a character can continue an identifier
is_id_char(c : int) : int
{
	return is_id_start(c) || (c >= '0' && c <= '9');
}

# Check if identifier starts with uppercase (likely a type)
is_type_name(s : string) : int
{
	if (len s == 0)
		return 0;
	c := s[0];
	return (c >= 'A' && c <= 'Z');
}

# Check if identifier is followed by '(' (likely a function call)
is_function_call(text : string, pos : int) : int
{
	# Skip whitespace
	while (pos < len text && (text[pos] == ' ' || text[pos] == '\t' || text[pos] == '\n'))
		pos++;

	return (pos < len text && text[pos] == '(');
}

# Hex digit value
hexval(c : int) : int
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

# Parse Limbo source code
parse_limbo(text : string) : array of Token
{
	tokens : list of ref Token = nil;
	pos : int = 0;
	len_text := len text;

	while (pos < len_text) {
		c := text[pos];

		# Skip whitespace
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
			pos++;
			continue;
		}

		start := pos;

		# Single-line comment: # to end of line
		if (c == '#') {
			while (pos < len_text && text[pos] != '\n')
				pos++;
			tokens = ref Token(TCOMMENT, start, pos) :: tokens;
			continue;
		}

		# String literal: "..."
		if (c == '"') {
			pos++;
			while (pos < len_text) {
				if (text[pos] == '\\' && pos + 1 < len_text) {
					pos += 2;  # Skip escaped char
				} else if (text[pos] == '"') {
					pos++;
					break;
				} else {
					pos++;
				}
			}
			tokens = ref Token(TSTRING, start, pos) :: tokens;
			continue;
		}

		# Character literal: '...'
		if (c == '\'') {
			pos++;
			while (pos < len_text) {
				if (text[pos] == '\\' && pos + 1 < len_text) {
					pos += 2;  # Skip escaped char
				} else if (text[pos] == '\'') {
					pos++;
					break;
				} else {
					pos++;
				}
			}
			tokens = ref Token(TCHAR, start, pos) :: tokens;
			continue;
		}

		# Number: decimal, hex (0x), binary (0b)
		if (c >= '0' && c <= '9') {
			# Check for hex prefix
			if (c == '0' && pos + 1 < len_text &&
			    (text[pos + 1] == 'x' || text[pos + 1] == 'X')) {
				pos += 2;
				while (pos < len_text && hexval(text[pos]) >= 0)
					pos++;
			}
			# Check for binary prefix
			else if (c == '0' && pos + 1 < len_text &&
			         (text[pos + 1] == 'b' || text[pos + 1] == 'B')) {
				pos += 2;
				while (pos < len_text && (text[pos] == '0' || text[pos] == '1'))
					pos++;
			}
			# Decimal number
			else {
				while (pos < len_text && text[pos] >= '0' && text[pos] <= '9')
					pos++;
				# Check for fractional part
				if (pos < len_text && text[pos] == '.') {
					pos++;
					while (pos < len_text && text[pos] >= '0' && text[pos] <= '9')
						pos++;
					# Check for exponent
					if (pos < len_text && (text[pos] == 'e' || text[pos] == 'E')) {
						pos++;
						if (pos < len_text && (text[pos] == '+' || text[pos] == '-'))
							pos++;
						while (pos < len_text && text[pos] >= '0' && text[pos] <= '9')
							pos++;
					}
				}
			}
			tokens = ref Token(TNUMBER, start, pos) :: tokens;
			continue;
		}

		# Identifier or keyword
		if (is_id_start(c)) {
			pos++;
			while (pos < len_text && is_id_char(text[pos]))
				pos++;

			ident := text[start:pos];

			# Check if it's a keyword
			if (is_keyword(ident)) {
				tokens = ref Token(TKEYWORD, start, pos) :: tokens;
			}
			# Check if it's a type (starts with uppercase)
			else if (is_type_name(ident)) {
				tokens = ref Token(TTYPE, start, pos) :: tokens;
			}
			# Check if it's a function call
			else if (is_function_call(text, pos)) {
				tokens = ref Token(TFUNCTION, start, pos) :: tokens;
			}
			# Regular identifier
			else {
				tokens = ref Token(TIDENTIFIER, start, pos) :: tokens;
			}
			continue;
		}

		# Operators and other symbols
		# Multi-character operators
		if (c == ':' && pos + 1 < len_text && text[pos + 1] == '=') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '-' && pos + 1 < len_text && text[pos + 1] == '>') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == ':' && pos + 1 < len_text && text[pos + 1] == ':') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '=' && pos + 1 < len_text && text[pos + 1] == '=') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '!' && pos + 1 < len_text && text[pos + 1] == '=') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '<' && pos + 1 < len_text && text[pos + 1] == '=') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '>' && pos + 1 < len_text && text[pos + 1] == '=') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '|' && pos + 1 < len_text && text[pos + 1] == '|') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '&' && pos + 1 < len_text && text[pos + 1] == '&') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '<' && pos + 1 < len_text && text[pos + 1] == '-') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '-' && pos + 1 < len_text && text[pos + 1] == '<') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '+' && pos + 1 < len_text && text[pos + 1] == '+') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}
		if (c == '-' && pos + 1 < len_text && text[pos + 1] == '-') {
			pos += 2;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}

		# Single-character operators
		if (c == '+' || c == '-' || c == '*' || c == '/' || c == '%' ||
		    c == '=' || c == '<' || c == '>' || c == '|' || c == '&' ||
		    c == '^' || c == '~' || c == ';' || c == ',' || c == '.' ||
		    c == '[' || c == ']' || c == '{' || c == '}' || c == '(' ||
		    c == ')') {
			pos++;
			tokens = ref Token(TOPERATOR, start, pos) :: tokens;
			continue;
		}

		# Unknown - skip
		pos++;
	}

	# Reverse list to get correct order
	result := array[len tokens] of Token;
	i := len result - 1;
	for (l := tokens; l != nil; l = tl l) {
		result[i--] = *(hd l);
	}

	return result;
}

# Parse C source code (placeholder - same as Limbo for now)
parse_c(text : string) : array of Token
{
	return parse_limbo(text);
}

# Parse shell script (placeholder - simple implementation)
parse_sh(text : string) : array of Token
{
	tokens : list of ref Token = nil;
	pos := 0;
	len_text := len text;

	sh_keywords := list of {
		"if", "then", "else", "elif", "fi", "case", "esac",
		"for", "while", "do", "done", "in", "function",
		"return", "break", "continue", "export", "local",
		"cd", "pwd", "echo", "exit", "true", "false"
	};

	while (pos < len_text) {
		c := text[pos];

		# Skip whitespace
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
			pos++;
			continue;
		}

		start := pos;

		# Comment: # to end of line
		if (c == '#') {
			while (pos < len_text && text[pos] != '\n')
				pos++;
			tokens = ref Token(TCOMMENT, start, pos) :: tokens;
			continue;
		}

		# String literal: "..."
		if (c == '"') {
			pos++;
			while (pos < len_text) {
				if (text[pos] == '\\' && pos + 1 < len_text) {
					pos += 2;
				} else if (text[pos] == '"') {
					pos++;
					break;
				} else {
					pos++;
				}
			}
			tokens = ref Token(TSTRING, start, pos) :: tokens;
			continue;
		}

		# String literal: '...'
		if (c == '\'') {
			pos++;
			while (pos < len_text) {
				if (text[pos] == '\\' && pos + 1 < len_text) {
					pos += 2;
				} else if (text[pos] == '\'') {
					pos++;
					break;
				} else {
					pos++;
				}
			}
			tokens = ref Token(TSTRING, start, pos) :: tokens;
			continue;
		}

		# Identifier/keyword
		if (is_id_start(c)) {
			pos++;
			while (pos < len_text && is_id_char(text[pos]))
				pos++;

			ident := text[start:pos];

			# Check for keyword
			is_kw := 0;
			for (l := sh_keywords; l != nil; l = tl l) {
				if (hd l == ident) {
					is_kw = 1;
					break;
				}
			}

			if (is_kw)
				tokens = ref Token(TKEYWORD, start, pos) :: tokens;
			else
				tokens = ref Token(TIDENTIFIER, start, pos) :: tokens;
			continue;
		}

		# Variable reference: $name or ${name}
		if (c == '$') {
			pos++;
			if (pos < len_text && text[pos] == '{') {
				pos++;
				while (pos < len_text && text[pos] != '}')
					pos++;
				if (pos < len_text)
					pos++;
			} else {
				while (pos < len_text && (is_id_char(text[pos]) || text[pos] == '$'))
					pos++;
			}
			tokens = ref Token(TTYPE, start, pos) :: tokens;  # Use TYPE color for variables
			continue;
		}

		pos++;
	}

	# Reverse list
	result := array[len tokens] of Token;
	i := len result - 1;
	for (l := tokens; l != nil; l = tl l) {
		result[i--] = *(hd l);
	}

	return result;
}

# Detect language from file extension
detect_language(filename : string) : string
{
	# Find extension
	dot := 0;
	for (i := len filename - 1; i >= 0; i--) {
		if (filename[i] == '/') {
			break;  # Found directory, no extension
		}
		if (filename[i] == '.') {
			dot = i;
			break;
		}
	}

	if (dot == 0)
		return "";  # No extension

	ext := filename[dot:];

	case ext {
	".b" or ".m" or ".dis" or ".limbo" =>
		return "limbo";
	".c" or ".h" or ".C" or ".H" =>
		return "c";
	".sh" or ".bash" or ".bashrc" or ".profile" or ".zsh" =>
		return "sh";
	* =>
		return "";
	}
}

# Parse hex color string to RGB values
parse_hex_color(color : string) : (int, int, int)
{
	# Remove # if present
	if (len color > 0 && color[0] == '#')
		color = color[1:];

	# Validate length
	if (len color != 6)
		return (-1, -1, -1);

	r := (hexval(color[0]) << 4) | hexval(color[1]);
	g := (hexval(color[2]) << 4) | hexval(color[3]);
	b := (hexval(color[4]) << 4) | hexval(color[5]);

	return (r, g, b);
}

# Set theme from file
settheme(path : string) : int
{
	if (path == nil)
		return -1;

	fd := sys->open(path, Sys->OREAD);
	if (fd == nil)
		return -1;

	io := bufio->fopen(fd, Sys->OREAD);
	if (io == nil)
		return -1;

	# Theme file format: token-name = #RRGGBB
	# Lines starting with # are comments
	new_colors := array[10] of string;
	for (i := 0; i < 10; i++)
		new_colors[i] = default_colors[i];

	while ((line := io.gets('\n')) != nil) {
		# Remove trailing newline
		line = line[0: len line - 1];

		# Skip empty lines and comments
		if (len line == 0 || line[0] == '#')
			continue;

		# Parse "name = color" format
		eq := 0;
		for (i = 0; i < len line; i++) {
			if (line[i] == '=') {
				eq = i;
				break;
			}
		}

		if (eq == 0)
			continue;

		name := line[0:eq];
		color := line[eq + 1:];

		# Trim whitespace from name and color
		while (len name > 0 && name[0] == ' ')
			name = name[1:];
		while (len name > 0 && name[len name - 1] == ' ')
			name = name[0: len name - 1];
		while (len color > 0 && color[0] == ' ')
			color = color[1:];
		while (len color > 0 && color[len color - 1] == ' ')
			color = color[0: len color - 1];

		# Map name to token type
		token_type := -1;
		case name {
		"keyword" =>
			token_type = TKEYWORD;
		"string" =>
			token_type = TSTRING;
		"char" =>
			token_type = TCHAR;
		"number" =>
			token_type = TNUMBER;
		"comment" =>
			token_type = TCOMMENT;
		"type" =>
			token_type = TTYPE;
		"function" =>
			token_type = TFUNCTION;
		"operator" =>
			token_type = TOPERATOR;
		"preprocessor" =>
			token_type = TPREPROCESSOR;
		"identifier" =>
			token_type = TIDENTIFIER;
		}

		if (token_type >= 0) {
			# Validate color format
			(r, g, b) := parse_hex_color(color);
			if (r >= 0 && g >= 0 && b >= 0)
				new_colors[token_type] = "#" + color;
		}
	}

	return 0;
}
