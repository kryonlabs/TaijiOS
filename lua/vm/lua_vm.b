# Lua VM - Virtual Machine Executor
# Main bytecode execution engine (fetch-decode-execute loop)

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_opcodes.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# VM State
# ====================================================================

VM: adt {
	L:			ref State;		# Lua state
	base:		int;			# Base stack index
	top:		int;			# Top stack index
	ci:			ref CallInfo;	# Current call frame
	pc:			int;			# Program counter
};

# Call frame information (extended from luavm.m)
CallInfo: adt {
	func:		ref Value;		# Function being executed
	base:		int;			# Base register
	top:		int;			# Top register
	savedpc:	int;			# Saved PC for returns
	nresults:	int;			# Number of results
	next:		ref CallInfo;	# Next frame in chain
};

# ====================================================================
# VM Creation
# ====================================================================

newvm(L: ref State): ref VM
{
	vm := ref VM;
	vm.L = L;
	vm.base = 0;
	vm.top = L.top;
	vm.ci = nil;
	vm.pc = 0;
	return vm;
}

# ====================================================================
# Main VM Loop
# ====================================================================

# Execute a function
execute(vm: ref VM, func: ref Value, nargs: int): int
{
	if(func == nil || func.ty != TFUNCTION || func.f == nil)
		return ERRRUN;

	# Set up call frame
	vm.ci = ref CallInfo;
	vm.ci.func = func;
	vm.ci.base = vm.L.top - nargs;
	vm.ci.top = vm.L.top;
	vm.ci.savedpc = 0;
	vm.ci.nresults = -1;  # Multi-return
	vm.ci.next = nil;

	# Allocate stack space for function
	proto := func.f.proto;
	if(proto != nil && proto.maxstacksize > 0) {
		reserve(vm.L, proto.maxstacksize);
		vm.ci.top = vm.ci.base + proto.maxstacksize;
	}

	vm.base = vm.ci.base;
	vm.top = vm.ci.top;
	vm.pc = 0;

	# Execute bytecode
	return vmexec(vm);
}

# Main execution loop (fetch-decode-execute)
vmexec(vm: ref VM): int
{
	L := vm.L;

	for(;;) {
		# Fetch instruction
		if(vm.ci == nil || vm.ci.func == nil || vm.ci.func.f == nil ||
		   vm.ci.func.f.proto == nil || vm.ci.func.f.proto.code == nil)
			break;

		proto := vm.ci.func.f.proto;
		if(vm.pc < 0 || vm.pc >= proto.numparams)  # Simplified check
			break;

		inst := getinst(proto, vm.pc);
		vm.pc++;

		# Decode
		op := GET_OPCODE(inst);
		a := GETARG_A(inst);
		b := GETARG_B(inst);
		c := GETARG_C(inst);

		# Execute
		case(op) {
		OP_MOVE =>
			ra := vm.base + a;
			rb := vm.base + b;
			if(rb >= 0 && rb < L.top)
				L.stack[ra] = L.stack[rb];

		OP_LOADI =>
			ra := vm.base + a;
			sbx := GETARG_sBx(inst);
			setnumvalue(L, ra, real(sbx));

		OP_LOADF =>
			ra := vm.base + a;
			sbx := GETARG_sBx(inst);
			setnumvalue(L, ra, real(sbx));

		OP_LOADK =>
			ra := vm.base + a;
			bx := GETARG_Bx(inst);
			if(proto.k != nil && bx >= 0 && bx < len proto.k) {
				L.stack[ra] = proto.k[bx];
			}

		OP_LOADFALSE =>
			ra := vm.base + a;
			setboolvalue(L, ra, 0);

		OP_LFALSESKIP =>
			ra := vm.base + a;
			setboolvalue(L, ra, 0);
			vm.pc++;  # Skip next instruction

		OP_LOADTRUE =>
			ra := vm.base + a;
			setboolvalue(L, ra, 1);

		OP_LOADNIL =>
			for(i := 0; i <= b; i++) {
				ra := vm.base + a + i;
				setnilvalue(L, ra);
			}

		OP_GETUPVAL =>
			ra := vm.base + a;
			# Get upvalue b (simplified - needs upvalue chain)
			setnilvalue(L, ra);

		OP_SETUPVAL =>
			ra := vm.base + a;
			# Set upvalue b (simplified)
			skip;

		OP_GETTABUP =>
			ra := vm.base + a;
			# Upvalue[b][K(c)]
			setnilvalue(L, ra);

		OP_GETTABLE =>
			ra := vm.base + a;
			rb := vm.base + b;
			rc := vm.base + c;
			if(rb < L.top && rc < L.top) {
				table := L.stack[rb];
				key := L.stack[rc];
				if(table.ty == TTABLE && table.t != nil) {
					val := gettablevalue(table.t, key);
					L.stack[ra] = val;
				}
			}

		OP_GETI =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := R(B)[C]
			if(rb < L.top) {
				table := L.stack[rb];
				if(table.ty == TTABLE && table.t != nil) {
					key := mknumber(real(c));
					val := gettablevalue(table.t, key);
					L.stack[ra] = val;
				}
			}

		OP_GETFIELD =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := R(B)[K(C)]
			if(rb < L.top && proto.k != nil && c < len proto.k) {
				table := L.stack[rb];
				key := proto.k[c];
				if(table.ty == TTABLE && table.t != nil && key.ty == TSTRING) {
					val := gettablevalue(table.t, key);
					L.stack[ra] = val;
				}
			}

		OP_SETTABUP =>
			# UpValue[A][K(B)] := RK(C)
			skip;

		OP_SETTABLE =>
			ra := vm.base + a;
			rb := vm.base + b;
			rc := rk2addr(vm, c);
			if(ra < L.top && rb < L.top && rc < L.top) {
				table := L.stack[ra];
				key := L.stack[rb];
				val := L.stack[rc];
				if(table.ty == TTABLE && table.t != nil) {
					settablevalue(table.t, key, val);
				}
			}

		OP_SETI =>
			ra := vm.base + a;
			rc := rk2addr(vm, c);
			# R(A)[B] := RK(C)
			if(ra < L.top && rc < L.top) {
				table := L.stack[ra];
				key := mknumber(real(b));
				val := L.stack[rc];
				if(table.ty == TTABLE && table.t != nil) {
					settablevalue(table.t, key, val);
				}
			}

		OP_SETFIELD =>
			ra := vm.base + a;
			rc := rk2addr(vm, c);
			# R(A)[K(B)] := RK(C)
			if(ra < L.top && proto.k != nil && b < len proto.k && rc < L.top) {
				table := L.stack[ra];
				key := proto.k[b];
				val := L.stack[rc];
				if(table.ty == TTABLE && table.t != nil && key.ty == TSTRING) {
					settablevalue(table.t, key, val);
				}
			}

		OP_NEWTABLE =>
			ra := vm.base + a;
			barray := b;
			chash := c;
			t := createtable(barray, chash);
			settablevalue(L, ra, mktable(t));

		OP_SELF =>
			ra := vm.base + a;
			rb := vm.base + b;
			rc := rk2addr(vm, c);
			# R(A+1) := R(B); R(A) := R(B)[RK(C)]
			if(rb < L.top && rc < L.top) {
				obj := L.stack[rb];
				key := L.stack[rc];
				L.stack[ra + 1] = obj;
				if(obj.ty == TTABLE && obj.t != nil) {
					val := gettablevalue(obj.t, key);
					L.stack[ra] = val;
				}
			}

		OP_ADDI =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := R(B) + C
			if(rb < L.top) {
				v := L.stack[rb];
				if(v.ty == TNUMBER) {
					setnumvalue(L, ra, v.n + real(c));
				}
			}

		OP_ADDK =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := R(B) + K(C)
			if(rb < L.top && proto.k != nil && c < len proto.k) {
				v := L.stack[rb];
				k := proto.k[c];
				if(v.ty == TNUMBER && k.ty == TNUMBER) {
					setnumvalue(L, ra, v.n + k.n);
				}
			}

		OP_SUBK or OP_MULK or OP_MODK or OP_POWK or OP_DIVK or
		OP_IDIVK or OP_BANDK or OP_BORK or OP_BXORK =>
			# Similar binary ops with constant
			execternaryop(vm, op, a, b, c);

		OP_SHRI =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := R(B) >> C
			if(rb < L.top) {
				v := L.stack[rb];
				if(v.ty == TNUMBER) {
					iv := int(v.n);
					setnumvalue(L, ra, real(iv >> c));
				}
			}

		OP_SHLI =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := R(B) << C
			if(rb < L.top) {
				v := L.stack[rb];
				if(v.ty == TNUMBER) {
					iv := int(v.n);
					setnumvalue(L, ra, real(iv << c));
				}
			}

		OP_ADD =>
			ra := vm.base + a;
			rb := vm.base + b;
			rc := vm.base + c;
			# R(A) := R(B) + R(C)
			execbinaryop(vm, ra, rb, rc, OP_ADD);

		OP_SUB or OP_MUL or OP_MOD or OP_POW or OP_DIV or
		OP_IDIV or OP_BAND or OP_BOR or OP_BXOR or OP_SHL or OP_SHR =>
			ra := vm.base + a;
			rb := vm.base + b;
			rc := vm.base + c;
			execbinaryop(vm, ra, rb, rc, op);

		OP_UNM =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := -R(B)
			if(rb < L.top) {
				v := L.stack[rb];
				if(v.ty == TNUMBER) {
					setnumvalue(L, ra, -v.n);
				}
			}

		OP_BNOT =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := ~R(B)
			if(rb < L.top) {
				v := L.stack[rb];
				if(v.ty == TNUMBER) {
					iv := int(v.n);
					setnumvalue(L, ra, real(~iv));
				}
			}

		OP_NOT =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := not R(B)
			if(rb < L.top) {
				v := L.stack[rb];
				setboolvalue(L, ra, !toboolean(v));
			}

		OP_LEN =>
			ra := vm.base + a;
			rb := vm.base + b;
			# R(A) := length of R(B)
			if(rb < L.top) {
				v := L.stack[rb];
				if(v.ty == TSTRING) {
					setnumvalue(L, ra, real(len v.s));
				}
			}

		OP_CONCAT =>
			ra := vm.base + a;
			rb := vm.base + b;
			rc := vm.base + c;
			# R(A) := R(B).. .. R(C)
			s := "";
			for(i := rb; i <= rc; i++) {
				if(i < L.top) {
					v := L.stack[i];
					if(v.ty == TSTRING)
						s += v.s;
				}
			}
			setstrvalue(L, ra, s);

		OP_CLOSE =>
			# Close all upvalues to R(A)
			skip;

		OP_TBC =>
			# Mark variable R(A) as to-be-closed
			skip;

		OP_JMP =>
			sbx := GETARG_sBx(inst);
			vm.pc += sbx;

		OP_EQ =>
			rb := vm.base + b;
			rc := rk2addr(vm, c);
			# if ((R(A) == R(B)) ~= C) then pc++
			res := 0;
			if(a < L.top && rb < L.top && rc < L.top) {
				va := L.stack[vm.base + a];
				vb := L.stack[rb];
				vc := L.stack[rc];
				res = (valueseq(va, vb) != 0);
			}
			if((res != 0) != (c != 0))
				vm.pc++;

		OP_LT =>
			rb := vm.base + b;
			rc := rk2addr(vm, c);
			# if ((R(A) < R(B)) ~= C) then pc++
			res := 0;
			if(a < L.top && rb < L.top && rc < L.top) {
				va := L.stack[vm.base + a];
				vb := L.stack[rb];
				res = (comparelt(va, vb) != 0);
			}
			if((res != 0) != (c != 0))
				vm.pc++;

		OP_LE =>
			rb := vm.base + b;
			rc := rk2addr(vm, c);
			# if ((R(A) <= R(B)) ~= C) then pc++
			res := 0;
			if(a < L.top && rb < L.top && rc < L.top) {
				va := L.stack[vm.base + a];
				vb := L.stack[rb];
				res = (comparele(va, vb) != 0);
			}
			if((res != 0) != (c != 0))
				vm.pc++;

		OP_EQK or OP_EQI or OP_LTI or OP_LEI or OP_GTI or OP_GEI =>
			# Comparisons with immediates/constants
			skip;

		OP_TEST =>
			ra := vm.base + a;
			# if not R(A) then pc++
			if(ra < L.top) {
				v := L.stack[ra];
				if(!toboolean(v))
					vm.pc++;
			}

		OP_TESTSET =>
			ra := vm.base + a;
			rb := vm.base + b;
			# if (R(B) ~= nil) then R(A) := R(B) else pc++
			if(rb < L.top) {
				v := L.stack[rb];
				if(!isnil(v)) {
					if(ra < L.top)
						L.stack[ra] = v;
				} else {
					vm.pc++;
				}
			}

		OP_CALL =>
			ra := vm.base + a;
			nargs := b;
			nresults := c;
			# R(A), ... ,R(A+C-2) := R(A)(R(A+1), ... ,R(A+B-1))
			if(ra < L.top) {
				func := L.stack[ra];
				if(func.ty == TFUNCTION && func.f != nil) {
					# Call function
					# For now, just handle simple calls
					newci := ref CallInfo;
					newci.func = func;
					newci.base = ra;
					newci.top = ra + nargs;
					newci.nresults = nresults;
					newci.next = vm.ci;
					vm.ci = newci;
					# Execute (recursive for now)
					ret := execute(vm, func, nargs);
					# Restore frame
					vm.ci = newci.next;
				}
			}

		OP_TAILCALL =>
			# return R(A)(R(A+1), ... ,R(A+B-1))
			skip;

		OP_RETURN =>
			ra := vm.base + a;
			b := GETARG_B(inst);
			# return R(A), ... ,R(A+B-2)
			if(b == 1) {
				# No return values
				return OK;
			} else if(b == 0) {
				# Variable return (not implemented)
				return OK;
			} else {
				# Return b-1 values starting at R(A)
				return OK;
			}

		OP_RETURN0 =>
			return OK;

		OP_RETURN1 =>
			return OK;

		OP_FORLOOP =>
			ra := vm.base + a;
			# Numeric for loop
			if(ra + 2 < L.top) {
				init := L.stack[ra];
				limit := L.stack[ra + 1];
				step := L.stack[ra + 2];

				if(init.ty == TNUMBER && limit.ty == TNUMBER && step.ty == TNUMBER) {
					init.n += step.n;
					setnumvalue(L, ra, init.n);

					# Check loop condition
					if(step.n >= 0.0) {
						if(init.n <= limit.n) {
							# Continue loop
							sbx := GETARG_sBx(inst);
							vm.pc += sbx;
							# Set loop variable
							if(ra + 3 < L.top)
								setnumvalue(L, ra + 3, init.n);
						}
					} else {
						if(init.n >= limit.n) {
							sbx := GETARG_sBx(inst);
							vm.pc += sbx;
							if(ra + 3 < L.top)
								setnumvalue(L, ra + 3, init.n);
						}
					}
				}
			}

		OP_FORPREP =>
			ra := vm.base + a;
			# R(A) -= R(A+2)
			if(ra + 2 < L.top) {
				init := L.stack[ra];
				step := L.stack[ra + 2];
				if(init.ty == TNUMBER && step.ty == TNUMBER) {
					init.n -= step.n;
					setnumvalue(L, ra, init.n);
				}
			}
			sbx := GETARG_sBx(inst);
			vm.pc += sbx;

		OP_TFORPREP or OP_TFORCALL or OP_TFORLOOP =>
			# Generic for loop (not implemented)
			skip;

		OP_SETLIST =>
			ra := vm.base + a;
			b := GETARG_B(inst);
			c := GETARG_C(inst);
			# R(A)[(C-1)*FPF+i] := R(A+i), 1 <= i <= B
			skip;

		OP_CLOSURE =>
			ra := vm.base + a;
			bx := GETARG_Bx(inst);
			# R(A) := closure(KPROTO[Bx])
			# Create closure from prototype
			if(proto.p != nil && bx >= 0 && bx < len proto.p) {
				f := allocclosure(0, 0);
				f.proto = proto.p[bx];
				f.env = L.global;
				setfuncvalue(L, ra, f);
			}

		OP_VARARG =>
			ra := vm.base + a;
			b := GETARG_B(inst);
			# R(A), R(A+1), ..., R(A+B-2) = vararg
			skip;

		OP_VARARGPREP =>
			# Prepare vararg
			skip;

		OP_EXTRAARG =>
			# Extra argument for large constants
			skip;

		OP_MMBIN or OP_MMBINI or OP_MMBINK =>
			# Metamethod operations
			skip;

		* =>
			# Unknown opcode
			skip;
		}
	}

	return OK;
}

# ====================================================================
# VM Helper Functions
# ====================================================================

# Get instruction from prototype
getinst(proto: ref Proto, pc: int): int
{
	if(proto.code == nil || pc < 0 || pc * 4 + 3 >= len proto.code)
		return 0;

	inst := 0;
	for(i := 0; i < 4; i++) {
		inst |= int(proto.code[pc * 4 + i]) << (i * 8);
	}
	return inst;
}

# Convert RK (register or constant) to address
rk2addr(vm: ref VM, rk: int): int
{
	if(ISKCONST(rk))
		return -1;  # Constant marker
	return vm.base + rk;
}

# Execute binary operation
execbinaryop(vm: ref VM, ra, rb, rc, op: int)
{
	L := vm.L;
	if(rb >= L.top || rc >= L.top)
		return;

	vb := L.stack[rb];
	vc := L.stack[rc];

	if(vb.ty != TNUMBER || vc.ty != TNUMBER)
		return;

	result := 0.0;
	case(op) {
	OP_ADD =>	result = vb.n + vc.n;
	OP_SUB =>	result = vb.n - vc.n;
	OP_MUL =>	result = vb.n * vc.n;
	OP_MOD =>	result = fmod(vb.n, vc.n);
	OP_POW =>	result = pow(vb.n, vc.n);
	OP_DIV =>	result = vb.n / vc.n;
	OP_IDIV =>	result = real(int(vb.n) / int(vc.n));
	OP_BAND =>	result = real(int(vb.n) & int(vc.n));
	OP_BOR =>	result = real(int(vb.n) | int(vc.n));
	OP_BXOR =>	result = real(int(vb.n) ^ int(vc.n));
	OP_SHL =>	result = real(int(vb.n) << int(vc.n));
	OP_SHR =>	result = real(int(vb.n) >> int(vc.n));
	* =>		result = 0.0;
	}

	setnumvalue(L, ra, result);
}

# Execute ternary operation (with constant)
execternaryop(vm: ref VM, op, a, b, c: int)
{
	L := vm.L;
	ra := vm.base + a;
	rb := vm.base + b;

	if(rb >= L.top || vm.ci == nil || vm.ci.func == nil || vm.ci.func.f == nil)
		return;

	proto := vm.ci.func.f.proto;
	if(proto.k == nil || c >= len proto.k)
		return;

	vb := L.stack[rb];
	vc := proto.k[c];

	if(vb.ty != TNUMBER || vc.ty != TNUMBER)
		return;

	result := 0.0;
	case(op) {
	OP_SUBK =>	result = vb.n - vc.n;
	OP_MULK =>	result = vb.n * vc.n;
	OP_MODK =>	result = fmod(vb.n, vc.n);
	OP_POWK =>	result = pow(vb.n, vc.n);
	OP_DIVK =>	result = vb.n / vc.n;
	OP_IDIVK =>	result = real(int(vb.n) / int(vc.n));
	OP_BANDK =>	result = real(int(vb.n) & int(vc.n));
	OP_BORK =>	result = real(int(vb.n) | int(vc.n));
	OP_BXORK =>	result = real(int(vb.n) ^ int(vc.n));
	* =>		result = 0.0;
	}

	setnumvalue(L, ra, result);
}

# Value setters
setnilvalue(L: ref State, idx: int)
{
	if(idx >= 0 && idx < L.top) {
		v := ref Value;
		v.ty = TNIL;
		L.stack[idx] = v;
	}
}

setboolvalue(L: ref State, idx, val: int)
{
	if(idx >= 0 && idx < L.top) {
		v := ref Value;
		v.ty = TBOOLEAN;
		v.b = val;
		L.stack[idx] = v;
	}
}

setnumvalue(L: ref State, idx: int, val: real)
{
	if(idx >= 0 && idx < L.top) {
		v := ref Value;
		v.ty = TNUMBER;
		v.n = val;
		L.stack[idx] = v;
	}
}

setstrvalue(L: ref State, idx: int, val: string)
{
	if(idx >= 0 && idx < L.top) {
		v := ref Value;
		v.ty = TSTRING;
		v.s = val;
		L.stack[idx] = v;
	}
}

settablevalue(L: ref State, idx: int, val: ref Value)
{
	if(idx >= 0 && idx < L.top) {
		L.stack[idx] = val;
	}
}

setfuncvalue(L: ref State, idx: int, val: ref Function)
{
	if(idx >= 0 && idx < L.top) {
		v := ref Value;
		v.ty = TFUNCTION;
		v.f = val;
		L.stack[idx] = v;
	}
}

# Value comparisons
valueseq(a, b: ref Value): int
{
	if(a == nil && b == nil)
		return 1;
	if(a == nil || b == nil)
		return 0;
	if(a.ty != b.ty)
		return 0;

	case(a.ty) {
	TNIL =>		return 1;
	TBOOLEAN =>	return a.b == b.b;
	TNUMBER =>	return a.n == b.n;
	TSTRING =>	return a.s == b.s;
	TTABLE =>	return a.t == b.t;
	TFUNCTION =>	return a.f == b.f;
	* =>		return 0;
	}
}

comparelt(a, b: ref Value): int
{
	if(a == nil || b == nil)
		return 0;
	if(a.ty == TNUMBER && b.ty == TNUMBER)
		return a.n < b.n;
	if(a.ty == TSTRING && b.ty == TSTRING)
		return a.s < b.s;
	return 0;
}

comparele(a, b: ref Value): int
{
	if(a == nil || b == nil)
		return 0;
	if(a.ty == TNUMBER && b.ty == TNUMBER)
		return a.n <= b.n;
	if(a.ty == TSTRING && b.ty == TSTRING)
		return a.s <= b.s;
	return 0;
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
		"Virtual Machine Executor",
		"Fetch-decode-execute loop for Lua bytecode",
	};
}
