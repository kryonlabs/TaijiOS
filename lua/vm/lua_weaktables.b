# Lua VM - Weak Tables and Write Barriers
# Implements weak table support and write barriers for generational GC

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Weak Table Modes
# ====================================================================

# Weak mode constants
WEAKKEY:	con 1 << 0;	# __mode = "k" (weak keys)
WEAKVALUE:	con 1 << 1;	# __mode = "v" (weak values)
WEAKKEYVALUE:	con WEAKKEY | WEAKVALUE;  # __mode = "kv" (weak both)

# Table with weak attribute
Table: adt {
	metatable:	cyclic ref Table;	# Metatable
	array:		cyclic array of ref Value;	# Array part
	hash:		cyclic ref Hashnode;	# Hash part
	sizearray:	int;			# Size of array part
	mode:		int;			# Weak mode
	marked:	int;			# GC marked status
};

# ====================================================================
# Weak Table Operations
# ====================================================================

# Set weak mode on table
setweakmode(t: ref Table, mode: int)
{
	if(t == nil)
		return;

	t.mode = mode;
}

# Get weak mode from table
getweakmode(t: ref Table): int
{
	if(t == nil)
		return 0;

	# Check metatable for __mode
	if(t.metatable == nil)
		return 0;

	key := ref Value;
	key.ty = TSTRING;
	key.s = "__mode";

	modeval := gettablevalue(t.metatable, key);
	if(modeval == nil || modeval.ty != TSTRING)
		return 0;

	mode := 0;
	s := modeval.s;
	if(s == "k")
		mode = WEAKKEY;
	else if(s == "v")
		mode = WEAKVALUE;
	else if(s == "kv")
		mode = WEAKKEYVALUE;

	return mode;
}

# Check if table has weak keys
isweakkey(t: ref Table): int
{
	if(t == nil)
		return 0;
	return (t.mode & WEAKKEY) != 0;
}

# Check if table has weak values
isweakvalue(t: ref Table): int
{
	if(t == nil)
		return 0;
	return (t.mode & WEAKVALUE) != 0;
}

# ====================================================================
# Clear Dead Entries (Weak Table Support)
# ====================================================================

# Clear dead entries from weak table
clearweak(t: ref Table, g: ref G)
{
	if(t == nil || g == nil)
		return;

	mode := getweakmode(t);
	if(mode == 0)
		return;

	if((mode & WEAKKEY) != 0) {
		# Clear entries with dead keys
		clearweakkeys(t, g);
	}

	if((mode & WEAKVALUE) != 0) {
		# Clear entries with dead values
		clearweakvalues(t, g);
	}
}

# Clear entries with dead keys
clearweakkeys(t: ref Table, g: ref G)
{
	if(t == nil || t.hash == nil)
		return;

	prev := ref Hashnode;
	node := t.hash;

	while(node != nil) {
		nextnode := node.next;

		if(node.key != nil && isdead(g, node.key)) {
			# Remove this entry
			if(prev != nil)
				prev.next = nextnode;
			else
				t.hash = nextnode;
		} else {
			prev = node;
		}

		node = nextnode;
	}
}

# Clear entries with dead values
clearweakvalues(t: ref Table, g: ref G)
{
	if(t == nil || t.hash == nil)
		return;

	node := t.hash;

	while(node != nil) {
		if(node.val != nil && isdead(g, node.val)) {
			# Clear value (keep key)
			node.val = nil;
		}
		node = node.next;
	}
}

# Check if value is dead (not marked)
isdead(g: ref G, v: ref Value): int
{
	if(v == nil)
		return 1;  # nil is always dead

	case(v.ty) {
	TNIL or TBOOLEAN or TNUMBER =>
		return 0;  # Scalar values are always alive

	TSTRING =>
		# Strings are never collected in weak tables (they are interned)
		return 0;

	TTABLE =>
		if(v.t == nil)
			return 1;
		# Check table's mark
		return v.t.marked == WHITE0 || v.t.marked == WHITE1;

	TFUNCTION =>
		if(v.f == nil)
			return 1;
		return v.f.marked == WHITE0 || v.f.marked == WHITE1;

	TUSERDATA =>
		if(v.u == nil)
			return 1;
		return v.u.marked == WHITE0 || v.u.marked == WHITE1;

	TTHREAD =>
		if(v.th == nil)
			return 1;
		return v.th.marked == WHITE0 || v.th.marked == WHITE1;

	* =>
		return 0;
	}
}

# ====================================================================
# Write Barriers for Generational GC
# ====================================================================

# Write barrier for table assignment
barriert(t: ref Table, key, val: ref Value)
{
	if(t == nil)
		return;

	# Check if table is old
	if(isoldgen(t)) {
		# Check if key or value is young
		if(isyoung(key) || isyoung(val)) {
			# Add to remember set
			addtoremember(t, key, val);
		}
	}
}

# Write barrier for table set
barbackset(t: ref Table, key, val: ref Value)
{
	barriert(t, key, val);
}

# Write barrier for upvalue assignment
barrierupval(uv: ref Upval, v: ref Value)
{
	if(uv == nil)
		return;

	# If upvalue is old and value is young
	if(isoldupval(uv) && isyoung(v)) {
		# Remember
		adduptoremember(uv, v);
	}
}

# Check if table is old generation
isoldgen(t: ref Table): int
{
	if(t == nil)
		return 0;
	# In full implementation, would check generation
	return 0;
}

# Check if value is young
isyoung(v: ref Value): int
{
	if(v == nil)
		return 0;

	case(v.ty) {
	TTABLE =>	return v.t != nil && isyoungobj(v.t);
	TFUNCTION =>	return v.f != nil && isyoungobj(v.f);
	TUSERDATA =>	return v.u != nil && isyoungobj(v.u);
	TTHREAD =>	return v.th != nil && isyoungobj(v.th);
	* =>		return 0;
	}
}

# Check if object is young
isyoungobj(obj: ref GCheader): int
{
	if(obj == nil)
		return 0;
	return obj.marked == WHITE0;  # Young objects are white
}

# Check if upvalue is old
isoldupval(uv: ref Upval): int
{
	if(uv == nil)
		return 0;
	# Upvalues are always old if they're closed
	return !uv.open;  # Closed upvalues are old
}

# ====================================================================
# Remember Set Operations
# ====================================================================

# Add to remember set
addtoremember(t: ref Table, key, val: ref Value)
{
	if(t == nil)
		return;

	# Get global remember set
	g := getglobalg();
	if(g == nil)
		return;

	# Remember this table
	hdr := ref GCheader(t);
	remember(g, hdr, key, val);
}

# Add upvalue to remember set
adduptoremember(uv: ref Upval, val: ref Value)
{
	if(uv == nil)
		return;

	# Would add upvalue to remember set
}

# Remember operation
remember(g: ref G, obj: ref GCheader, key, val: ref Value)
{
	if(g == nil || obj == nil)
		return;

	# Create remember entry
	entry := ref RememberEntry;
	entry.oldobj = obj;
	entry.key = key;
	entry.val = val;
	entry.next = nil;

	# Add to remember set (simplified)
	# In full implementation, would use global remember set
}

# ====================================================================
# Finalization (__gc metamethod)
# ====================================================================

# Check if object has finalizer
hasfin(obj: ref GCheader): int
{
	if(obj == nil)
		return 0;

	case(obj.tt) {
	TUSERDATA =>
		u := ref Userdata(obj - 4);
		return u != nil && u.metatable != nil && hasgcmetamethod(u.metatable);

	TTABLE =>
		t := ref Table(obj - 4);
		return t != nil && t.metatable != nil && hasgcmetamethod(t.metatable);

	* =>
		return 0;
	}
}

# Check if metatable has __gc
hasgcmetamethod(mt: ref Table): int
{
	if(mt == nil)
		return 0;

	key := ref Value;
	key.ty = TSTRING;
	key.s = "__gc";

	val := gettablevalue(mt, key);
	return val != nil && val.ty == TFUNCTION;
}

# Call finalizer
callfin(obj: ref GCheader, L: ref State)
{
	if(obj == nil || L == nil)
		return;

	# Get __gc metamethod
	gcfunc := ref Value;

	case(obj.tt) {
	TUSERDATA =>
		u := ref Userdata(obj - 4);
		if(u != nil && u.metatable != nil) {
			key := ref Value;
			key.ty = TSTRING;
			key.s = "__gc";
			gcfunc = gettablevalue(u.metatable, key);
		}

	TTABLE =>
		t := ref Table(obj - 4);
		if(t != nil && t.metatable != nil) {
			key := ref Value;
			key.ty = TSTRING;
			key.s = "__gc";
			gcfunc = gettablevalue(t.metatable, key);
		}
	}

	# Call finalizer with object as argument
	if(gcfunc != nil && gcfunc.ty == TFUNCTION) {
		pushvalue(L, mkvaluefromheader(obj));
		# Would call gcfunc(L, 1)
	}
}

# ====================================================================
# Helper Functions
# ====================================================================

# Get global GC state
getglobalg(): ref G
{
	# Would return global GC state
	return nil;
}

# Create value from header
mkvaluefromheader(obj: ref GCheader): ref Value
{
	v := ref Value;
	case(obj.tt) {
	TUSERDATA =>
		v.ty = TUSERDATA;
		v.u = ref Userdata(obj - 4);
	TTABLE =>
		v.ty = TTABLE;
		v.t = ref Table(obj - 4);
	* =>
		v.ty = TNIL;
	}
	return v;
}

# Push value
pushvalue(L: ref State, v: ref Value)
{
	if(L == nil || L.stack == nil)
		return;
	if(L.top < len L.stack)
		L.stack[L.top++] = v;
}

# Get table value
gettablevalue(t: ref Table, key: ref Value): ref Value
{
	if(t == nil || key == nil)
		return nil;
	result := ref Value;
	result.ty = TNIL;
	return result;
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
		"Weak Tables and Write Barriers",
		"Support for weak tables and generational GC",
	};
}
