# Lua VM - Opcode Definitions and Instruction Encoding
# Implements all 38 Lua 5.4 opcodes with instruction encoding

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Lua 5.4 Opcodes
# ====================================================================

# Opcode enumeration
OP_MOVE,		# R(A) := R(B)
OP_LOADI,		# R(A) := sBx
OP_LOADF,		# R(A) := sBx (float)
OP_LOADK,		# R(A) := Kst(Bx)
OP_LOADKX,		# R(A) := Kst(EXTRAARG)
OP_LOADFALSE,	# R(A) := false
OP_LFALSESKIP,	# R(A) := false; pc++
OP_LOADTRUE,	# R(A) := true
OP_LOADNIL,		# R(A), R(A+1), ..., R(A+B) := nil
OP_GETUPVAL,	# R(A) := UpValue[B]
OP_SETUPVAL,	# UpValue[B] := R(A)
OP_GETTABUP,	# R(A) := UpValue[B][K(C)]
OP_GETTABLE,	# R(A) := R(B)[R(C)]
OP_GETI,		# R(A) := R(B)[C]
OP_GETFIELD,	# R(A) := R(B)[K(C)]
OP_SETTABUP,	# UpValue[A][K(B)] := RK(C)
OP_SETTABLE,	# R(A)[R(B)] := RK(C)
OP_SETI,		# R(A)[B] := RK(C)
OP_SETFIELD,	# R(A)[K(B)] := RK(C)
OP_NEWTABLE,	# R(A) := {} (size = B,C)
OP_SELF,		# R(A+1) := R(B); R(A) := R(B)[RK(C)]
OP_ADDI,		# R(A) := R(B) + C
OP_ADDK,		# R(A) := R(B) + K(C)
OP_SUBK,		# R(A) := R(B) - K(C)
OP_MULK,		# R(A) := R(B) * K(C)
OP_MODK,		# R(A) := R(B) % K(C)
OP_POWK,		# R(A) := R(B) ^ K(C)
OP_DIVK,		# R(A) := R(B) / K(C)
OP_IDIVK,		# R(A) := R(B) // K(C)
OP_BANDK,		# R(A) := R(B) & K(C)
OP_BORK,		# R(A) := R(B) | K(C)
OP_BXORK,		# R(A) := R(B) ~ K(C)
OP_SHRI,		# R(A) := R(B) >> C
OP_SHLI,		# R(A) := R(B) << C
OP_ADD,			# R(A) := R(B) + R(C)
OP_SUB,			# R(A) := R(B) - R(C)
OP_MUL,			# R(A) := R(B) * R(C)
OP_MOD,			# R(A) := R(B) % R(C)
OP_POW,			# R(A) := R(B) ^ R(C)
OP_DIV,			# R(A) := R(B) / R(C)
OP_IDIV,		# R(A) := R(B) // R(C)
OP_BAND,		# R(A) := R(B) & R(C)
OP_BOR,			# R(A) := R(B) | R(C)
OP_BXOR,		# R(A) := R(B) ~ R(C)
OP_SHL,			# R(A) := R(B) << R(C)
OP_SHR,			# R(A) := R(B) >> R(C)
OP_MMBIN,		# R(A), R(B) := metamethod manipulation
OP_MMBINI,		# R(A), R(B) := metamethod manipulation (immediate)
OP_MMBINK,		# R(A), R(B) := metamethod manipulation (constant)
OP_UNM,			# R(A) := -R(B)
OP_BNOT,		# R(A) := ~R(B)
OP_NOT,			# R(A) := not R(B)
OP_LEN,			# R(A) := length of R(B)
OP_CONCAT,		# R(A) := R(B).. .. R(C)
OP_CLOSE,		# close all upvalues to R(A)
OP_TBC,			# mark variable R(A) as to-be-closed
OP_JMP,			# pc += sBx
OP_EQ,			# if ((R(A) == R(B)) ~= C) then pc++
OP_LT,			# if ((R(A) <  R(B)) ~= C) then pc++
OP_LE,			# if ((R(A) <= R(B)) ~= C) then pc++
OP_EQK,			# if ((R(A) == K(B)) ~= C) then pc++
OP_EQI,			# if ((R(A) == sB) ~= C) then pc++
OP_LTI,			# if ((R(A) < sB) ~= C) then pc++
OP_LEI,			# if ((R(A) <= sB) ~= C) then pc++
OP_GTI,			# if ((R(A) > sB) ~= C) then pc++
OP_GEI,			# if ((R(A) >= sB) ~= C) then pc++
OP_TEST,		# if not R(A) then pc++
OP_TESTSET,		# if (R(B) ~= nil) then R(A) := R(B) else pc++
OP_CALL,		# R(A), ... ,R(A+C-2) := R(A)(R(A+1), ... ,R(A+B-1))
OP_TAILCALL,	# return R(A)(R(A+1), ... ,R(A+B-1))
OP_RETURN,		# return R(A), ... ,R(A+B-2)
OP_RETURN0,		# return
OP_RETURN1,		# return R(A)
OP_FORLOOP,		# R(A) += R(A+2); if R(A) <?= R(A+1) then { pc+=sBx; R(A+3)=R(A) }
OP_FORPREP,		# R(A)-=R(A+2); pc+=sBx
OP_TFORPREP,	#
OP_TFORCALL,	#
OP_TFORLOOP,	# R(A+3), ... ,R(A+2+C) := R(A)(R(A+1), R(A+2)); if R(A+3) ~= nil then R(A+2)=R(A+3) else pc++
OP_SETLIST,		# R(A)[(C-1)*FPF+i] := R(A+i), 1 <= i <= B
OP_CLOSURE,		# R(A) := closure(KPROTO[Bx])
OP_VARARG,		# R(A), R(A+1), ..., R(A+B-2) = vararg
OP_VARARGPREP,	# adjust vararg for current function
OP_EXTRAARG,	# EXTRAARG opcode (for KST in LOADKX)

: con iota;

# Number of opcodes
NUM_OPCODES: con 85;

# ====================================================================
# Instruction Encoding Formats
# ====================================================================

# Instruction size (32 bits)
SIZE_INST: con 4;

# Bit field positions and sizes
POS_OP:		con 0;	# Opcode position (6 bits)
SIZE_OP:	con 6;
POS_A:		con 6;	# A field position (8 bits)
SIZE_A:		con 8;

# Format iABC: B: 9 bits, C: 9 bits
POS_B:		con 14;	# B field position
SIZE_B:		con 9;
POS_C:		con 23;	# C field position
SIZE_C:		con 9;

# Format iABx: Bx: 18 bits
POS_Bx:		con 14;	# Bx field position
SIZE_Bx:	con 18;

# Format iAsBx: sBx: signed 18 bits
MAXARG_Bx:	con (1 << SIZE_Bx) - 1;
MAXARG_sBx:	con MAXARG_Bx >> 1;

# Format iAx: Ax: 26 bits
POS_Ax:		con 6;	# Ax field position
SIZE_Ax:	con 26;

# Format isJ: sJ: signed 26 bits (for jump offsets)
MAXARG_Ax:	con (1 << SIZE_Ax) - 1;
MAXARG_sJ:	con MAXARG_Ax >> 1;

# Maximum arguments for CALL
MAXARG_A:	con 255;	# (1 << SIZE_A) - 1
MAXARG_B:	con 511;	# (1 << SIZE_B) - 1
MAXARG_C:	con 511;	# (1 << SIZE_C) - 1

# ====================================================================
# Instruction Creation Helpers
# ====================================================================

# Create iABC instruction
CREATE_ABC(o, a, b, c): int
{
	return o | (a << POS_A) | (b << POS_B) | (c << POS_C);
}

# Create iABx instruction
CREATE_ABX(o, a, bx: int): int
{
	return o | (a << POS_A) | (bx << POS_Bx);
}

# Create iAsBx instruction (signed)
CREATE_ASBX(o, a, sbx: int): int
{
	bx := sbx + MAXARG_sBx;
	return o | (a << POS_A) | (bx << POS_Bx);
}

# Create iAx instruction
CREATE_AX(o, ax: int): int
{
	return o | (ax << POS_Ax);
}

# Create isJ instruction (signed jump)
CREATE_SJ(o, j: int): int
{
	aj := j + MAXARG_sJ;
	return o | (aj << POS_Ax);
}

# Get opcode from instruction
GET_OPCODE(i: int): int
{
	return i & ((1 << SIZE_OP) - 1);
}

# Get A operand
GETARG_A(i: int): int
{
	return (i >> POS_A) & ((1 << SIZE_A) - 1);
}

# Get B operand
GETARG_B(i: int): int
{
	return (i >> POS_B) & ((1 << SIZE_B) - 1);
}

# Get C operand
GETARG_C(i: int): int
{
	return (i >> POS_C) & ((1 << SIZE_C) - 1);
}

# Get Bx operand
GETARG_Bx(i: int): int
{
	return (i >> POS_Bx) & ((1 << SIZE_Bx) - 1);
}

# Get signed Bx operand
GETARG_sBx(i: int): int
{
	bx := GETARG_Bx(i);
	if(bx >= MAXARG_sBx)
		return bx - MAXARG_Bx;
	return bx;
}

# Get Ax operand
GETARG_Ax(i: int): int
{
	return (i >> POS_Ax) & ((1 << SIZE_Ax) - 1);
}

# Get signed J operand
GETARG_sJ(i: int): int
{
	j := GETARG_Ax(i);
	if(j >= MAXARG_sJ)
		return j - MAXARG_Ax;
	return j;
}

# Set operand (for patching jumps)
SETARG_A(i, a: int): int
{
	return (i & ~(((1 << SIZE_A) - 1) << POS_A)) | (a << POS_A);
}

# ====================================================================
# RK (Register or Constant) Encoding
# ====================================================================

# Check if value is constant (bit 9 set in B/C)
ISKCONST(k: int): int
{
	return (k >> (SIZE_B - 1));
}

# Index in constant table
INDEXK(r: int): int
{
	return r & ((1 << (SIZE_B - 1)) - 1);
}

# Encode constant index
RKASK(x: int): int
{
	return x | (1 << (SIZE_B - 1));
}

# Maximum constant index
MAXINDEXRK: con (1 << (SIZE_B - 1)) - 1;

# ====================================================================
# Opcode Names for Debugging
# }

opcodenames[NUM_OPCODES] = array[] of {
	"MOVE",
	"LOADI",
	"LOADF",
	"LOADK",
	"LOADKX",
	"LOADFALSE",
	"LFALSESKIP",
	"LOADTRUE",
	"LOADNIL",
	"GETUPVAL",
	"SETUPVAL",
	"GETTABUP",
	"GETTABLE",
	"GETI",
	"GETFIELD",
	"SETTABUP",
	"SETTABLE",
	"SETI",
	"SETFIELD",
	"NEWTABLE",
	"SELF",
	"ADDI",
	"ADDK",
	"SUBK",
	"MULK",
	"MODK",
	"POWK",
	"DIVK",
	"IDIVK",
	"BANDK",
	"BORK",
	"BXORK",
	"SHRI",
	"SHLI",
	"ADD",
	"SUB",
	"MUL",
	"MOD",
	"POW",
	"DIV",
	"IDIV",
	"BAND",
	"BOR",
	"BXOR",
	"SHL",
	"SHR",
	"MMBIN",
	"MMBINI",
	"MMBINK",
	"UNM",
	"BNOT",
	"NOT",
	"LEN",
	"CONCAT",
	"CLOSE",
	"TBC",
	"JMP",
	"EQ",
	"LT",
	"LE",
	"EQK",
	"EQI",
	"LTI",
	"LEI",
	"GTI",
	"GEI",
	"TEST",
	"TESTSET",
	"CALL",
	"TAILCALL",
	"RETURN",
	"RETURN0",
	"RETURN1",
	"FORLOOP",
	"FORPREP",
	"TFORPREP",
	"TFORCALL",
	"TFORLOOP",
	"SETLIST",
	"CLOSURE",
	"VARARG",
	"VARARGPREP",
	"EXTRAARG",
};

# Get opcode name
getopname(op: int): string
{
	if(op >= 0 && op < NUM_OPCODES)
		return opcodenames[op];
	return "UNKNOWN";
}

# ====================================================================
# Disassembler
# ====================================================================

# Disassemble instruction
disassemble(inst: int): string
{
	op := GET_OPCODE(inst);
	name := getopname(op);
	a := GETARG_A(inst);

	case(op) {
	OP_MOVE or OP_LOADNIL or OP_GETUPVAL or OP_SETUPVAL or
	OP_UNM or OP_BNOT or OP_NOT or OP_LEN or OP_CLOSE or OP_TBC =>
		return sprint("%s %d", name, a);

	OP_LOADI or OP_LOADF =>
		return sprint("%s %d %d", name, a, GETARG_sBx(inst));

	OP_LOADK or OP_GETTABUP or OP_SETTABUP =>
		bx := GETARG_Bx(inst);
		return sprint("%s %d %d", name, a, bx);

	OP_LOADKX or OP_CLOSURE =>
		bx := GETARG_Bx(inst);
		return sprint("%s %d %d", name, a, bx);

	OP_LOADFALSE or OP_LFALSESKIP or OP_LOADTRUE =>
		return sprint("%s %d", name, a);

	OP_GETTABLE or OP_SETTABLE or OP_ADD or OP_SUB or
	OP_MUL or OP_MOD or OP_POW or OP_DIV or OP_IDIV or
	OP_BAND or OP_BOR or OP_BXOR or OP_SHL or OP_SHR or
	OP_CONCAT =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_GETI or OP_SETI =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_GETFIELD or OP_SETFIELD =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_NEWTABLE =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_SELF =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_ADDI or OP_ADDK or OP_SUBK or OP_MULK or OP_MODK or
	OP_POWK or OP_DIVK or OP_IDIVK or OP_BANDK or OP_BORK or
	OP_BXORK =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_SHRI or OP_SHLI =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_JMP =>
		sbx := GETARG_sBx(inst);
		return sprint("%s %d ; to %d", name, sbx, sbx);

	OP_EQ or OP_LT or OP_LE or OP_EQK or OP_EQI or
	OP_LTI or OP_LEI or OP_GTI or OP_GEI =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_TEST or OP_TESTSET =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_CALL or OP_TAILCALL =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_RETURN =>
		b := GETARG_B(inst);
		return sprint("%s %d %d", name, a, b);

	OP_RETURN0 =>
		return sprint("RETURN0");

	OP_RETURN1 =>
		return sprint("%s %d", name, a);

	OP_FORLOOP or OP_FORPREP =>
		sbx := GETARG_sBx(inst);
		return sprint("%s %d %d ; to %d", name, a, sbx, sbx);

	OP_TFORPREP =>
		sbx := GETARG_sBx(inst);
		return sprint("%s %d %d", name, a, sbx);

	OP_TFORCALL =>
		c := GETARG_C(inst);
		return sprint("%s %d %d", name, a, c);

	OP_TFORLOOP =>
		sbx := GETARG_sBx(inst);
		return sprint("%s %d %d", name, a, sbx);

	OP_SETLIST =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_VARARG =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	OP_VARARGPREP =>
		return sprint("%s %d", name, a);

	OP_EXTRAARG =>
		ax := GETARG_Ax(inst);
		return sprint("%s %d", name, ax);

	OP_MMBIN or OP_MMBINI or OP_MMBINK =>
		b := GETARG_B(inst);
		c := GETARG_C(inst);
		return sprint("%s %d %d %d", name, a, b, c);

	* =>
		return sprint("UNKNOWN %d", op);
	}
}

# Disassemble a list of instructions
disassemblecode(code: array of int): list of string
{
	result: list of string;

	for(i := 0; i < len code; i++) {
		line := sprint("%4d: 0x%08x  %s", i, code[i], disassemble(code[i]));
		result = list of {line} + result;
	}

	return result;
}

# ====================================================================
# Module Interface Functions
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
		"Opcode Definitions and Instruction Encoding",
		"All 38 Lua 5.4 opcodes implemented",
	};
}
