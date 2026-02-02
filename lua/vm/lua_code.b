# Lua VM - Bytecode Generator
# Converts AST to Lua bytecode

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_parser.m";
include "lua_opcodes.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Code Generator State
# ====================================================================

FuncState: adt {
	prev:		ref FuncState;	# Outer function
	f:			ref Proto;		# Function prototype
	pc:			int;			# Program counter
	stacksize:	int;			# Stack size
	nactvar:	int;			# Active variables
 freereg:	int;			# First free register
};

Codegen: adt {
	mainfs:	ref FuncState;	# Main function state
	blks:	list of ref BlockState;	# Block stack
};

# Block state for break/goto
BlockState: adt {
	previous:	ref BlockState;
	breaklist:	list of int;	# Pending jumps
	hasloop:	int;		# Inside loop?
};

# ====================================================================
# Code Generator Creation
# ====================================================================

newcodegen(): ref Codegen
{
	cg := ref Codegen;
	cg.mainfs = newfuncstate(nil);
	cg.blks = nil;
	return cg;
}

newfuncstate(prev: ref FuncState): ref FuncState
{
	fs := ref FuncState;
	fs.prev = prev;
	fs.f = allocproto();
	fs.pc = 0;
	fs.stacksize = 2;  # Minimum: register 0 for function, 1 for temp
	fs.nactvar = 0;
	fs.freereg = 0;
	return fs;
}

# ====================================================================
# Instruction Emission
# ====================================================================

# Emit ABC instruction
emitABC(fs: ref FuncState, o, a, b, c: int)
{
	code(fs, CREATE_ABC(o, a, b, c));
}

# Emit ABx instruction
emitABx(fs: ref FuncState, o, a, bx: int)
{
	code(fs, CREATE_ABX(o, a, bx));
}

# Emit AsBx instruction (signed)
emitAsBx(fs: ref FuncState, o, a, sbx: int)
{
	code(fs, CREATE_ASBX(o, a, sbx));
}

# Emit Ax instruction
emitAx(fs: ref FuncState, o, ax: int)
{
	code(fs, CREATE_AX(o, ax));
}

# Add code to prototype
code(fs: ref FuncState, instruction: int)
{
	if(fs.f.code == nil) {
		fs.f.code = array[64] of byte;
	} else if(fs.pc >= len fs.f.code) {
		newcode := array[len fs.f.code * 2] of byte;
		newcode[:fs.pc] = fs.f.code[:fs.pc];
		fs.f.code = newcode;
	}

	# Convert int to 4 bytes (little endian)
	fs.f.code[fs.pc * 4 + 0] = byte(instruction & 0xff);
	fs.f.code[fs.pc * 4 + 1] = byte((instruction >> 8) & 0xff);
	fs.f.code[fs.pc * 4 + 2] = byte((instruction >> 16) & 0xff);
	fs.f.code[fs.pc * 4 + 3] = byte((instruction >> 24) & 0xff);
	fs.pc++;
}

# ====================================================================
# Register Management
# ====================================================================

# Reserve registers
reserveregs(fs: ref FuncState, n: int): int
{
	if(fs.freereg + n > fs.stacksize) {
		fs.stacksize = fs.freereg + n;
	}
	reg := fs.freereg;
	fs.freereg += n;
	return reg;
}

# Free register
freereg(fs: ref FuncState, n: int)
{
	fs.freereg -= n;
	if(fs.freereg < fs.nactvar)
		fs.freereg = fs.nactvar;
}

# Get free register
getfreereg(fs: ref FuncState): int
{
	if(fs.freereg >= fs.stacksize)
		fs.stacksize++;
	return fs.freereg++;
}

# ====================================================================
# Constant Management
# ====================================================================

# Add number constant
addknumber(fs: ref FuncState, r: real): int
{
	# Check if already exists
	for(i := 0; fs.f.k != nil && i < len fs.f.k; i++) {
		k := fs.f.k[i];
		if(k != nil && k.ty == TNUMBER && k.n == r)
			return i;
	}

	# Add new constant
	idx := 0;
	if(fs.f.k == nil) {
		fs.f.k = array[16] of ref Value;
	} else if(len fs.f.k >= MAXINDEXRK) {
		# Use extraarg if too many constants
		return -1;
	} else if(fs.pc >= len fs.f.k) {
		newk := array[len fs.f.k * 2] of ref Value;
		newk[:fs.pc] = fs.f.k[:fs.pc];
		fs.f.k = newk;
	}

	idx = fs.pc;
	v := ref Value;
	v.ty = TNUMBER;
	v.n = r;
	fs.f.k[fs.pc++] = v;
	return idx;
}

# Add string constant
addkstring(fs: ref FuncState, s: string): int
{
	# Check if already exists
	for(i := 0; fs.f.k != nil && i < len fs.f.k; i++) {
		k := fs.f.k[i];
		if(k != nil && k.ty == TSTRING && k.s == s)
			return i;
	}

	# Add new constant
	idx := 0;
	if(fs.f.k == nil) {
		fs.f.k = array[16] of ref Value;
	} else if(len fs.f.k >= MAXINDEXRK) {
		return -1;
	} else if(fs.pc >= len fs.f.k) {
		newk := array[len fs.f.k * 2] of ref Value;
		newk[:fs.pc] = fs.f.k[:fs.pc];
		fs.f.k = newk;
	}

	idx = fs.pc;
	v := ref Value;
	v.ty = TSTRING;
	v.s = s;
	fs.f.k[fs.pc++] = v;
	return idx;
}

# Add nil constant
addknil(fs: ref FuncState): int
{
	for(i := 0; fs.f.k != nil && i < len fs.f.k; i++) {
		k := fs.f.k[i];
		if(k == nil || k.ty == TNIL)
			return i;
	}

	if(fs.f.k == nil) {
		fs.f.k = array[16] of ref Value;
	} else if(fs.pc >= len fs.f.k) {
		newk := array[len fs.f.k * 2] of ref Value;
		newk[:fs.pc] = fs.f.k[:fs.pc];
		fs.f.k = newk;
	}

	fs.f.k[fs.pc++] = nil;
	return fs.pc - 1;
}

# ====================================================================
# AST to Bytecode Generation
# ====================================================================

# Generate code from AST
gencode(cg: ref Codegen, ast: Ast): ref Proto
{
	if(ast == nil)
		return nil;

	case(ast.kind) {
	AST_BLOCK =>
		return genblock(cg, ast);

	AST_ASSIGN =>
		return genassign(cg, ast);

	AST_CALL =>
		return gencall(cg, ast);

	AST_FUNCTION =>
		return genfunction(cg, ast);

	AST_IF =>
		return genif(cg, ast);

	AST_WHILE =>
		return genwhile(cg, ast);

	AST_REPEAT =>
		return genrepeat(cg, ast);

	AST_RETURN =>
		return genreturn(cg, ast);

	AST_LOCAL =>
		return genlocal(cg, ast);

	AST_NAME =>
		return genname(cg, ast);

	AST_LITERAL =>
		return genliteral(cg, ast);

	AST_BINARYOP =>
		return genbinaryop(cg, ast);

	AST_UNARYOP =>
		return genunaryop(cg, ast);

	* =>
		return cg.mainfs.f;
	}
}

# Generate block
genblock(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	stats := ast.list;
	while(stats != nil) {
		stat := hd stats;
		gencode(cg, stat);
		stats = tl stats;
	}

	return fs.f;
}

# Generate assignment
genassign(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	# Get values
	exprs := ast.list;
	nvals := 0;
	if(exprs != nil) {
		# Count expressions (simplified)
		while(exprs != nil) {
			exprs = tl exprs;
			nvals++;
		}
	}

	# For now, just handle simple assignment: a = expr
	# Full implementation would handle multiple targets
	if(nvals > 0) {
		# Evaluate expression
		exprs = ast.list;
		reg := exp2reg(cg, hd exprs);

		# Store to variable (simplified - uses global)
		emitABC(fs, OP_SETTABUP, 0, 0, reg);  # _ENV[var] = reg
	}

	return fs.f;
}

# Generate function call
gencall(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	# Get function
	funcreg := exp2reg(cg, ast.left);

	# Get arguments
	nargs := 0;
	args := ast.list;
	while(args != nil) {
		arg := hd args;
		argreg := exp2reg(cg, arg);
		args = tl args;
		nargs++;
	}

	emitABC(fs, OP_CALL, funcreg, nargs + 1, 1);

	return fs.f;
}

# Generate function definition
genfunction(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	# Create new function state for nested function
	newfs := newfuncstate(fs);

	# Generate function body
	body := ast.left;
	if(body != nil && body.kind == AST_BLOCK) {
		genblock(cg, body);
	}

	# Return from function
	emitABC(newfs, OP_RETURN0, 0, 0, 0);

	# Emit closure in parent
	emitABx(fs, OP_CLOSURE, getfreereg(fs), 0);

	return fs.f;
}

# Generate if statement
genif(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	# Generate condition
	condreg := exp2reg(cg, ast.left);

	# Test and jump if false
	thenstart := fs.pc;
	emitABC(fs, OP_TEST, condreg, 0, 1);

	# Generate then block
	thenend := fs.pc;
	emitAsBx(fs, OP_JMP, 0, 0);

	if(ast.list != nil) {
		then := hd ast.list;
		gencode(cg, then);
	}

	# Jump to end
	endif := fs.pc;
	emitAsBx(fs, OP_JMP, 0, 0);

	# Patch then jump
	patchjump(fs, thenend, fs.pc - thenend - 1);

	# Generate else/elseif blocks
	if(ast.right != nil) {
		gencode(cg, ast.right);
	}

	# Patch endif jump
	patchjump(fs, endif, fs.pc - endif - 1);

	return fs.f;
}

# Generate while loop
genwhile(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	# Create block state for break
	bs := ref BlockState;
	bs.previous = nil;
	bs.breaklist = nil;
	bs.hasloop = 1;
	cg.blks = list of {bs} + cg.blks;

	# Loop start
	loopstart := fs.pc;

	# Generate condition
	condreg := exp2reg(cg, ast.left);

	# Test and jump if false
	condend := fs.pc;
	emitABC(fs, OP_TEST, condreg, 0, 1);

	exitloop := fs.pc;
	emitAsBx(fs, OP_JMP, 0, 0);

	# Generate body
	if(ast.right != nil) {
		gencode(cg, ast.right);
	}

	# Jump back to start
	emitAsBx(fs, OP_JMP, 0, loopstart - fs.pc - 1);

	# Patch exit jump
	patchjump(fs, exitloop, fs.pc - exitloop - 1);

	# Patch break jumps
	patchbreaks(fs, bs);

	# Restore block state
	cg.blks = tl cg.blks;

	return fs.f;
}

# Generate repeat-until loop
genrepeat(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	# Create block state
	bs := ref BlockState;
	bs.previous = nil;
	bs.breaklist = nil;
	bs.hasloop = 1;
	cg.blks = list of {bs} + cg.blks;

	# Loop start
	loopstart := fs.pc;

	# Generate body
	if(ast.left != nil) {
		gencode(cg, ast.left);
	}

	# Generate condition
	condreg := exp2reg(cg, ast.right);

	# Test and jump back if false (repeat until condition is true)
	emitABC(fs, OP_TEST, condreg, 0, 0);
	emitAsBx(fs, OP_JMP, 0, loopstart - fs.pc - 1);

	# Patch breaks
	patchbreaks(fs, bs);

	cg.blks = tl cg.blks;

	return fs.f;
}

# Generate return statement
genreturn(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	exprs := ast.list;
	if(exprs == nil) {
		emitABC(fs, OP_RETURN0, 0, 0, 0);
	} else {
		# Return values
		first := 1;
		nret := 0;
		while(exprs != nil) {
			reg := exp2reg(cg, hd exprs);
			if(first) {
				first = 0;
			}
			exprs = tl exprs;
			nret++;
		}
		emitABC(fs, OP_RETURN, reg - nret + 1, nret + 1, 0);
	}

	return fs.f;
}

# Generate local declaration
genlocal(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	# Reserve register for local variable
	varreg := reserveregs(fs, 1);
	fs.nactvar++;

	# Initialize if has expression
	if(ast.list != nil) {
		init := hd ast.list;
		valreg := exp2reg(cg, init);

		# Move value to variable register
		emitABC(fs, OP_MOVE, varreg, valreg, 0);
	}

	return fs.f;
}

# Generate name reference
genname(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	# Load variable (simplified: uses global table)
	reg := getfreereg(fs);
	kidx := addkstring(fs, ast.name);
	emitABx(fs, OP_GETTABUP, reg, kidx);

	return fs.f;
}

# Generate literal
genliteral(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	reg := getfreereg(fs);

	if(ast.value == nil) {
		emitABC(fs, OP_LOADNIL, reg, 0, 0);
	} else {
		case(ast.value.ty) {
		TNUMBER =>
			nidx := addknumber(fs, ast.value.n);
			emitABx(fs, OP_LOADK, reg, nidx);
		TSTRING =>
			sidx := addkstring(fs, ast.value.s);
			emitABx(fs, OP_LOADK, reg, sidx);
		TBOOLEAN =>
			if(ast.value.b)
				emitABC(fs, OP_LOADTRUE, reg, 0, 0);
			else
				emitABC(fs, OP_LOADFALSE, reg, 0, 0);
		TNIL =>
			emitABC(fs, OP_LOADNIL, reg, 0, 0);
		}
	}

	return fs.f;
}

# Generate binary operation
genbinaryop(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	leftreg := exp2reg(cg, ast.left);
	rightreg := exp2reg(cg, ast.right);

	result := getfreereg(fs);

	op := int(ast.value.n);
	case(op) {
	1 =>	emitABC(fs, OP_ADD, result, leftreg, rightreg);  # +
	2 =>	emitABC(fs, OP_SUB, result, leftreg, rightreg);  # -
	3 =>	emitABC(fs, OP_MUL, result, leftreg, rightreg);  # *
	4 =>	emitABC(fs, OP_DIV, result, leftreg, rightreg);  # /
	5 =>	emitABC(fs, OP_MOD, result, leftreg, rightreg);  # %
	* =>	emitABC(fs, OP_ADD, result, leftreg, rightreg);  # Default
	}

	return fs.f;
}

# Generate unary operation
genunaryop(cg: ref Codegen, ast: Ast): ref Proto
{
	fs := cg.mainfs;

	operand := exp2reg(cg, ast.left);
	result := getfreereg(fs);

	emitABC(fs, OP_UNM, result, operand, 0);

	return fs.f;
}

# ====================================================================
# Expression to Register
# ====================================================================

# Generate expression code, leave result in register
exp2reg(cg: ref Codegen, ast: Ast): int
{
	fs := cg.mainfs;

	if(ast == nil)
		return 0;

	case(ast.kind) {
	AST_LITERAL =>
		reg := getfreereg(fs);
		genliteral(cg, ast);
		return reg;

	AST_NAME =>
		reg := getfreereg(fs);
		genname(cg, ast);
		return reg;

	AST_BINARYOP =>
		return genbinaryop(cg, ast);

	AST_UNARYOP =>
		return genunaryop(cg, ast);

	AST_CALL =>
		gencall(cg, ast);
		return 0;  # Result in register 0 (simplified)

	* =>
		return 0;
	}
}

# ====================================================================
# Jump Patching
# ====================================================================

# Patch jump instruction to target
patchjump(fs: ref FuncState, pc, offset: int)
{
	if(pc >= fs.pc)
		return;

	# Get instruction
	inst := 0;
	for(i := 0; i < 4; i++) {
		inst |= int(fs.f.code[pc * 4 + i]) << (i * 8);
	}

	# Update sBx field
	inst = (inst & ~(((1 << SIZE_Bx) - 1) << POS_Bx)) |
	       ((offset + MAXARG_sBx) << POS_Bx);

	# Write back
	fs.f.code[pc * 4 + 0] = byte(inst & 0xff);
	fs.f.code[pc * 4 + 1] = byte((inst >> 8) & 0xff);
	fs.f.code[pc * 4 + 2] = byte((inst >> 16) & 0xff);
	fs.f.code[pc * 4 + 3] = byte((inst >> 24) & 0xff);
}

# Patch all pending break jumps
patchbreaks(fs: ref FuncState, bs: ref BlockState)
{
	while(bs.breaklist != nil) {
		pc := hd bs.breaklist;
		patchjump(fs, pc, fs.pc - pc - 1);
		bs.breaklist = tl bs.breaklist;
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
		"Bytecode Generator",
		"Converts AST to Lua bytecode",
	};
}
