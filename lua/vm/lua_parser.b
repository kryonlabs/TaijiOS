# Lua VM - Parser (Recursive Descent)
# Implements Lua syntax parser with AST generation

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_lexer.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# AST Node Types
# ====================================================================

# AST base type
Ast: type ref Astnode;

Astnode: adt {
	kind:	int;	# Node type
	line:	int;	# Line number
	name:	string;	# Name (for identifiers, etc.)
	value:	ref Value;	# Value (for literals)
	left:	Ast;	# Left child
	right:	Ast;	# Right child
	list:	list of Ast;	# List of children (for blocks, etc.)
};

# AST node kinds
AST_BLOCK:		con 1;	# Block of statements
AST_ASSIGN:		con 2;	# Assignment
AST_CALL:		con 3;	# Function call
AST_FUNCTION:	con 4;	# Function definition
AST_IF:			con 5;	# If statement
AST_WHILE:		con 6;	# While loop
AST_REPEAT:		con 7;	# Repeat loop
AST_FOR:		con 8;	# For loop
AST_RETURN:		con 9;	# Return statement
AST_LOCAL:		con 10;	# Local declaration
AST_NAME:		con 11;	# Identifier
AST_LITERAL:	con 12;	# Literal value
AST_BINARYOP:	con 13;	# Binary operation
AST_UNARYOP:	con 14;	# Unary operation
AST_INDEX:		con 15;	# Table indexing
AST_FIELD:		con 16;	# Field access
AST_TABLE:		con 17;	# Table constructor
AST_BREAK:		con 18;	# Break statement
AST_GOTO:		con 19;	# Goto statement
AST_LABEL:		con 20;	# Label
AST_DO:			con 21;	# Do block
AST_ELSEIF:		con 22;	# Elseif clause

# ====================================================================
# Parser State
# ====================================================================

Parser: adt {
	lexer:		ref Lexer;		# Lexer
	token:		int;			# Current token
	lookahead:	int;			# Lookahead token
	fn:			ref FuncState;	# Current function state
};

# Function state (for tracking local variables, upvalues, etc.)
FuncState: adt {
	prev:		ref FuncState;	# Outer function
	f:			ref Proto;		# Function prototype
	locals:		list of ref LocVar;	# Local variables
	nactvar:	int;			# Number of active locals
	nupvals:	int;			# Number of upvalues
	upvalues:	list of string;	# Upvalue names
	upvalnames:	array of string;	# Upvalue name table
	firstlocal:	int;			# First local in this function
_freereg:	int;			# First free register
};

# Local variable info
LocVar: adt {
	name:		string;
	startpc:	int;	# First point where variable is active
	endpc:		int;	# Point where variable becomes inactive
};

# ====================================================================
# Parser Creation
# ====================================================================

newparser(source: string): ref Parser
{
	p := ref Parser;
	p.lexer = newlexer(source);
	p.token = 0;
	p.lookahead = -1;
	p.fn = nil;
	return p;
}

# Get next token
next(p: ref Parser): int
{
	p.token = lex(p.lexer);
	return p.token;
}

# Look at current token
current(p: ref Parser): int
{
	return p.token;
}

# Check current token
check(p: ref Parser, token: int): int
{
	return p.token == token;
}

# Test and consume if matches
testandnext(p: ref Parser, token: int): int
{
	if(p.token == token) {
		next(p);
		return 1;
	}
	return 0;
}

# Check if variable is local in current function
islocalvar(fs: ref FuncState, name: string): int
{
	if(fs == nil || fs.locals == nil)
		return 0;

	locs := fs.locals;
	while(locs != nil) {
		loc := hd locs;
		if(loc != nil && loc.name == name)
			return 1;
		locs = tl locs;
	}
	return 0;
}

# Find local variable index
findlocalvar(fs: ref FuncState, name: string): int
{
	if(fs == nil || fs.locals == nil)
		return -1;

	locs := fs.locals;
	idx := 0;
	while(locs != nil) {
		loc := hd locs;
		if(loc != nil && loc.name == name)
			return idx;
		locs = tl locs;
		idx++;
	}
	return -1;
}

# Add local variable
addlocalvar(fs: ref FuncState, name: string)
{
	if(fs == nil)
		return;

	loc := ref LocVar;
	loc.name = name;
	loc.startpc = 0;  # Will be set by codegen
	loc.endpc = 0;

	fs.locals = list of {loc} + fs.locals;
	fs.nactvar++;
}

# Check if name is upvalue
checkupval(fs: ref FuncState, name: string): int
{
	if(fs == nil || fs.prev == nil)
		return 0;  # Not upvalue, global

	# Check if it's local in outer function
	if(islocalvar(fs.prev, name))
		return 1;  # Is upvalue

	# Recursively check outer scopes
	return checkupval(fs.prev, name);
}

# Add upvalue
addupval(fs: ref FuncState, name: string): int
{
	if(fs == nil)
		return -1;

	# Check if already exists
	if(fs.upvalnames != nil) {
		for(i := 0; i < len fs.upvalnames; i++) {
			if(fs.upvalnames[i] == name)
				return i;
		}
	}

	# Add new upvalue
	if(fs.upvalnames == nil) {
		fs.upvalnames = array[16] of string;
	} else if(fs.nupvals >= len fs.upvalnames) {
		newnames := array[len fs.upvalnames * 2] of string;
		newnames[:fs.nupvals] = fs.upvalnames[:fs.nupvals];
		fs.upvalnames = newnames;
	}

	idx := fs.nupvals;
	fs.upvalnames[idx] = name;
	fs.nupvals++;

	return idx;
}

# Resolve variable (local, upvalue, or global)
resolvevar(fs: ref FuncState, name: string): int
{
	if(fs == nil)
		return -1;

	# Check local
	localidx := findlocalvar(fs, name);
	if(localidx >= 0)
		return localidx;

	# Check upvalue
	if(checkupval(fs, name)) {
		return addupval(fs, name);
	}

	# Global
	return -1;
}

# Check for token and error if not present
check_match(p: ref Parser, token: int, what: string): int
{
	if(p.token != token) {
		syntaxerror(plexer.line, what + " expected");
		return 0;
	}
	next(p);
	return 1;
}

# Expect specific token
checknext(p: ref Parser, token: int)
{
	if(p.token != token) {
		syntaxerror(p.lexer.line, tokenname(token) + " expected");
	}
	next(p);
}

# Syntax error
syntaxerror(line: int, msg: string)
{
	# In real implementation, would set error state
	sys->fprint(sys->fildes(2), "syntax error: line %d: %s\n", line, msg);
	raise "syntax error";
}

# ====================================================================
# Expression Parsing
# ====================================================================

# Parse expression
expr(p: ref Parser): Ast
{
	return subexpr(p, 0);
}

# Parse subexpression with precedence limit
subexpr(p: ref Parser, limit: int): Ast
{
	v := primaryexpr(p);

	while(;;) {
		op := getbinop(p.token);
		if(op == 0)
			break;

		# Get operator precedence
		opprec := getprecedence(op);
		if(opprec <= limit)
			break;

		next(p);  # Consume operator

		# Parse right operand
		v2 := subexpr(p, opprec);

		# Build binary operation node
		node := newastnode(AST_BINARYOP, p.lexer.lastline);
		node.left = v;
		node.right = v2;
		node.value = mknumber(real(op));  # Store operator
		v = node;
	}

	return v;
}

# Parse primary expression
primaryexpr(p: ref Parser): Ast
{
	case(p.token) {
	TK_NAME =>
		node := newastnode(AST_NAME, p.lexer.lastline);
		node.name = p.lexer.seminfo.s;
		next(p);
		return suffixexpr(p, node);

	TK_NUMBER =>
		node := newastnode(AST_LITERAL, p.lexer.lastline);
		node.value = mknumber(p.lexer.seminfo.r);
		next(p);
		return suffixexpr(p, node);

	TK_STRING =>
		node := newastnode(AST_LITERAL, p.lexer.lastline);
		node.value = mkstring(p.lexer.seminfo.s);
		next(p);
		return suffixexpr(p, node);

	TK_NIL =>
		node := newastnode(AST_LITERAL, p.lexer.lastline);
		node.value = mknil();
		next(p);
		return suffixexpr(p, node);

	TK_TRUE =>
		node := newastnode(AST_LITERAL, p.lexer.lastline);
		node.value = mkbool(1);
		next(p);
		return suffixexpr(p, node);

	TK_FALSE =>
		node := newastnode(AST_LITERAL, p.lexer.lastline);
		node.value = mkbool(0);
		next(p);
		return suffixexpr(p, node);

	'(' =>
		next(p);
		v := expr(p);
		check_match(p, ')', "expression");
		return suffixexpr(p, v);

	'{' =>
		return tableconstructor(p);

	TK_FUNCTION =>
		next(p);
		body := functionbody(p);
		return suffixexpr(p, body);

	* =>
		syntaxerror(p.lexer.line, "expression expected");
		return nil;
	}
}

# Parse suffix expressions (indexing, calls, field access)
suffixexpr(p: ref Parser, v: Ast): Ast
{
	for(;;) {
		case(p.token) {
		'.' =>
			next(p);
			if(p.token != TK_NAME)
				syntaxerror(p.lexer.line, "identifier expected");
			node := newastnode(AST_FIELD, p.lexer.lastline);
			node.left = v;
			node.name = p.lexer.seminfo.s;
			next(p);
			v = node;

		'[' =>
			next(p);
			index := expr(p);
			check_match(p, ']', "index");
			node := newastnode(AST_INDEX, p.lexer.lastline);
			node.left = v;
			node.right = index;
			v = node;

		':' =>
			next(p);
			if(p.token != TK_NAME)
				syntaxerror(p.lexer.line, "method name expected");
			method := p.lexer.seminfo.s;
			next(p);
			args := funcargs(p);
			node := newastnode(AST_CALL, p.lexer.lastline);
			node.left = v;
			node.name = method;  # Method name
			node.list = args;  # Arguments
			v = node;

		'(' or TK_STRING or '{' =>
			args := funcargs(p);
			node := newastnode(AST_CALL, p.lexer.lastline);
			node.left = v;
			node.list = args;
			v = node;

		* =>
			return v;
		}
	}
}

# Parse function arguments
funcargs(p: ref Parser): list of Ast
{
	args: list of Ast;

	if(p.token == '(') {
		next(p);
		if(p.token != ')') {
			args = explist(p);
		}
		check_match(p, ')', "arguments");
	} else if(p.token == '{') {
		args = list of {tableconstructor(p)};
	} else if(p.token == TK_STRING) {
		node := newastnode(AST_LITERAL, p.lexer.lastline);
		node.value = mkstring(p.lexer.seminfo.s);
		args = list of {node};
		next(p);
	} else {
		syntaxerror(p.lexer.line, "function arguments expected");
	}

	return args;
}

# Parse expression list
explist(p: ref Parser): list of Ast
{
	exprs: list of Ast;

	while(;;) {
		exprs = list of {expr(p)} + exprs;
		if(p.token != ',')
			break;
		next(p);
	}

	return exprs;
}

# Parse table constructor
tableconstructor(p: ref Parser): Ast
{
	line := p.lexer.lastline;
	next(p);  # Consume '{'

	node := newastnode(AST_TABLE, line);
	fields: list of Ast;

	while(p.token != '}') {
		if(p.token == TK_NAME && p.lexer.seminfo.s == "") {
			# Check for named field
		}

		# Parse field
		key: Ast;
		if(p.token == TK_NAME) {
			key = newastnode(AST_LITERAL, p.lexer.lastline);
			key.value = mkstring(p.lexer.seminfo.s);
			next(p);
		} else {
			key = expr(p);
		}

		if(p.token == '=') {
			next(p);
			val := expr(p);
			field := newastnode(AST_FIELD, p.lexer.lastline);
			field.left = key;
			field.right = val;
			fields = list of {field} + fields;
		} else {
			# Array part
			fields = list of {key} + fields;
		}

		if(p.token != ',' && p.token != ';')
			break;
		next(p);
	}

	check_match(p, '}', "table constructor");
	node.list = fields;
	return node;
}

# ====================================================================
# Statement Parsing
# ====================================================================

# Parse statement
statement(p: ref Parser): Ast
{
	line := p.lexer.lastline;

	case(p.token) {
	TK_IF =>
		return ifstmt(p);

	TK_WHILE =>
		return whilestmt(p);

	TK_DO =>
		next(p);
		block := block(p);
		check_match(p, TK_END, "do block");
		node := newastnode(AST_DO, line);
		node.list = list of {block};
		return node;

	TK_FOR =>
		return forstmt(p);

	TK_REPEAT =>
		return repeatstmt(p);

	TK_FUNCTION =>
		next(p);
		if(p.token != TK_NAME)
			syntaxerror(p.lexer.line, "function name expected");
		name := p.lexer.seminfo.s;
		next(p);
		body := funcbody(p);
		node := newastnode(AST_FUNCTION, line);
		node.name = name;
		node.left = body;
		return node;

	TK_LOCAL =>
		return localstmt(p);

	TK_RETURN =>
		next(p);
		exprs: list of Ast;
		if(blockstart(p.token) || p.token == ';') {
			# No return values
		} else {
			exprs = explist(p);
		}
		node := newastnode(AST_RETURN, line);
		node.list = exprs;
		return node;

	TK_BREAK =>
		next(p);
		return newastnode(AST_BREAK, line);

	TK_GOTO =>
		next(p);
		if(p.token != TK_NAME)
			syntaxerror(p.lexer.line, "label expected");
		node := newastnode(AST_GOTO, line);
		node.name = p.lexer.seminfo.s;
		next(p);
		return node;

	'::' =>
		return label(p);

	* =>
		return assignment(p);
	}
}

# Check if token starts a block
blockstart(token: int): int
{
	return token == TK_END || token == TK_ELSE || token == TK_ELSEIF ||
	       token == TK_UNTIL || token == TK_EOS;
}

# Parse if statement
ifstmt(p: ref Parser): Ast
{
	line := p.lexer.lastline;
	next(p);  # Consume 'if'

	condition := expr(p);
	checknext(p, TK_THEN);

	thenblock := block(p);

	node := newastnode(AST_IF, line);
	node.left = condition;
	node.list = list of {thenblock};

	# Parse elseif/else
	elseifs: list of Ast;
	while(p.token == TK_ELSEIF) {
		eline := p.lexer.lastline;
		next(p);
		econd := expr(p);
		checknext(p, TK_THEN);
		eblock := block(p);
		enode := newastnode(AST_ELSEIF, eline);
		enode.left = econd;
		enode.list = list of {eblock};
		elseifs = list of {enode} + elseifs;
	}

	if(p.token == TK_ELSE) {
		next(p);
		elseblock := block(p);
		node.right = elseblock;
	}

	check_match(p, TK_END, "if");
	return node;
}

# Parse while statement
whilestmt(p: ref Parser): Ast
{
	line := p.lexer.lastline;
	next(p);  # Consume 'while'

	condition := expr(p);
	checknext(p, TK_DO);

	body := block(p);
	check_match(p, TK_END, "while loop");

	node := newastnode(AST_WHILE, line);
	node.left = condition;
	node.right = body;
	return node;
}

# Parse repeat-until statement
repeatstmt(p: ref Parser): Ast
{
	line := p.lexer.lastline;
	next(p);  # Consume 'repeat'

	body := block(p);

	check_match(p, TK_UNTIL, "repeat");
	condition := expr(p);

	node := newastnode(AST_REPEAT, line);
	node.left = body;
	node.right = condition;
	return node;
}

# Parse for statement (numeric and generic)
forstmt(p: ref Parser): Ast
{
	line := p.lexer.lastline;
	next(p);  # Consume 'for'

	if(p.token != TK_NAME)
		syntaxerror(p.lexer.line, "variable expected");

	varname := p.lexer.seminfo.s;
	next(p);

	node := newastnode(AST_FOR, line);
	node.name = varname;

	if(p.token == '=') {
		# Numeric for loop
		next(p);
		init := expr(p);
		checknext(p, ',');
		limit := expr(p);

		step: Ast;
		if(p.token == ',') {
			next(p);
			step = expr(p);
		} else {
			step = newastnode(AST_LITERAL, line);
			step.value = mknumber(1.0);
		}

		checknext(p, TK_DO);
		body := block(p);
		check_match(p, TK_END, "for loop");

		node.left = init;
		node.right = limit;
		node.value = step;  # Store step
		node.list = list of {body};
	} else if(p.token == ',' || p.token == TK_IN) {
		# Generic for loop
		check_match(p, TK_IN, "for loop");

		iterators: list of Ast;
		while(p.token == TK_NAME) {
			n := newastnode(AST_NAME, p.lexer.lastline);
			n.name = p.lexer.seminfo.s;
			iterators = list of {n} + iterators;
			next(p);
			if(p.token != ',')
				break;
			next(p);
		}

		checknext(p, TK_IN);
		exprs := explist(p);
		checknext(p, TK_DO);
		body := block(p);
		check_match(p, TK_END, "for loop");

		node.list = iterators;
		node.left = body;
		node.right = exprs;  # Store iterator functions
	}

	return node;
}

# Parse local declaration
localstmt(p: ref Parser): Ast
{
	line := p.lexer.lastline;
	next(p);  # Consume 'local'

	if(p.token == TK_FUNCTION) {
		next(p);
		if(p.token != TK_NAME)
			syntaxerror(p.lexer.line, "function name expected");
		name := p.lexer.seminfo.s;
		next(p);
		body := funcbody(p);

		node := newastnode(AST_FUNCTION, line);
		node.name = name;
		node.left = body;
		return node;
	}

	# Variable declaration
	names: list of string;
	while(p.token == TK_NAME) {
		names = list of {p.lexer.seminfo.s} + names;
		next(p);
		if(p.token != ',')
			break;
		next(p);
	}

	init: list of Ast;
	if(p.token == '=') {
		next(p);
		init = explist(p);
	}

	node := newastnode(AST_LOCAL, line);
	node.list = init;
	return node;
}

# Parse assignment or function call
assignment(p: ref Parser): Ast
{
	line := p.lexer.lastline;

	varlist: list of Ast;
	varlist = list of {primaryexpr(p)} + varlist;

	while(p.token == ',') {
		next(p);
		varlist = list of {primaryexpr(p)} + varlist;
	}

	if(p.token != '=') {
		# Function call statement
		if(len varlist != 1)
			syntaxerror(p.lexer.line, "syntax error");
		return hd varlist;
	}

	next(p);  # Consume '='

	exprlist := explist(p);

	node := newastnode(AST_ASSIGN, line);
	node.list = exprlist;
	return node;
}

# Parse label
label(p: ref Parser): Ast
{
	line := p.lexer.lastline;
	next(p);  # Consume '::'

	if(p.token != TK_NAME)
		syntaxerror(p.lexer.line, "label expected");

	name := p.lexer.seminfo.s;
	next(p);

	check_match(p, TK_DBCOLON, "label");

	node := newastnode(AST_LABEL, line);
	node.name = name;
	return node;
}

# ====================================================================
# Block and Function Parsing
# ====================================================================

# Parse block
block(p: ref Parser): Ast
{
	node := newastnode(AST_BLOCK, p.lexer.lastline);
	stats: list of Ast;

	while(!blockstart(p.token) && p.token != TK_EOS && p.token != TK_RETURN) {
		stats = list of {statement(p)} + stats;
	}

	if(p.token == TK_RETURN) {
		stats = list of {statement(p)} + stats;
	}

	node.list = stats;
	return node;
}

# Parse function body
funcbody(p: ref Parser): Ast
{
	line := p.lexer.lastline;

	checknext(p, '(');

	params: list of string;
	isvararg := 0;

	while(p.token == TK_NAME) {
		params = list of {p.lexer.seminfo.s} + params;
		next(p);
		if(p.token != ',')
			break;
		next(p);
	}

	if(p.token == TK_DOTS) {
		isvararg = 1;
		next(p);
	}

	check_match(p, ')', "parameters");

	body := block(p);
	check_match(p, TK_END, "function");

	node := newastnode(AST_FUNCTION, line);
	node.list = list of {body};
	return node;
}

# ====================================================================
# Entry Point
# ====================================================================

# Parse entire source
parse(p: ref Parser): Ast
{
	next(p);
	return block(p);
}

# ====================================================================
# AST Helpers
# ====================================================================

newastnode(kind, line: int): ref Astnode
{
	node := ref Astnode;
	node.kind = kind;
	node.line = line;
	node.name = "";
	node.value = nil;
	node.left = nil;
	node.right = nil;
	node.list = nil;
	return node;
}

# ====================================================================
# Binary Operator Support
# ====================================================================

# Get binary operator from token
getbinop(token: int): int
{
	case(token) {
	'+' =>	return 1;
	'-' =>	return 2;
	'*' =>	return 3;
	'/' =>	return 4;
	'%' =>	return 5;
	'^' =>	return 6;
	TK_CONCAT =>	return 7;
	TK_NE =>	return 8;
	TK_EQ =>	return 9;
	'<' =>	return 10;
	TK_LE =>	return 11;
	'>' =>	return 12;
	TK_GE =>	return 13;
	TK_AND =>	return 14;
	TK_OR =>	return 15;
	* =>	return 0;
	}
}

# Get operator precedence
getprecedence(op: int): int
{
	case(op) {
	1 or 2 =>	return 5;  # + -
	3 or 4 or 5 =>	return 6;  # * / %
	6 =>		return 10;  # ^ (right associative)
	7 =>		return 4;  # ..
	8 or 9 =>	return 3;  # == !=
	10 or 11 or 12 or 13 =>	return 3;  # < <= > >=
	14 =>		return 2;  # and
	15 =>		return 1;  # or
	* =>		return 0;
	}
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
		"Recursive Descent Parser",
		"Parses Lua source to AST",
	};
}
