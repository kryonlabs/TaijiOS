# Lua VM - Hash Table Utilities
# Implements hash functions and collision resolution for Lua tables

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# Hash table node
Hashnode: adt {
	next:	ref Hashnode;
	key:	ref Value;
	val:	ref Value;
	keyhash: int;	# Cached hash value
};

# Hash table structure
Hashtab: adt {
	size:	int;		# Size of hash table
	nodes:	array of ref Hashnode;  # Hash buckets
	count:	int;		# Number of elements
};

# Create hash table
mkhashtab(size: int): ref Hashtab
{
	if(size < 8)
		size = 8;

	# Round up to power of 2
	p := 8;
	while(p < size)
		p *= 2;
	size = p;

	ht := ref Hashtab;
	ht.size = size;
	ht.nodes = array[size] of ref Hashnode;
	ht.count = 0;

	for(i := 0; i < size; i++)
		ht.nodes[i] = nil;

	return ht;
}

# Hash function for values
hashvalue(v: ref Value): int
{
	if(v == nil)
		return 0;

	case(v.ty) {
	TNIL =>
		return 0;
	TBOOLEAN =>
		return v.b;
	TNUMBER =>
		# Hash number - use IEEE 754 representation
		return hashnumber(v.n);
	TSTRING =>
		return hashstring(v.s);
	TTABLE =>
		# Hash by pointer
		return hashpointer(v.t);
	TFUNCTION =>
		return hashpointer(v.f);
	TUSERDATA =>
		return hashpointer(v.u);
	TTHREAD =>
		return hashpointer(v.th);
	* =>
		return 0;
	}
}

# Hash number
hashnumber(n: real): int
{
	# Convert real to bits and hash
	# This is a simplified version
	i := 0;
	if(n != 0.0) {
		if(n < 0.0)
			i = int(-n * 1000.0);
		else
			i = int(n * 1000.0);
	}
	if(i < 0)
		i = -i;
	return i;
}

# Hash string (djb2 algorithm)
hashstring(s: string): int
{
	if(s == nil)
		return 0;

	h := 5381;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < 0)
			c += 256;
		h = ((h << 5) + h) + c;  # h * 33 + c
	}
	if(h < 0)
		h = -h;
	return h;
}

# Hash pointer (simplified)
hashpointer(p: pointer to void): int
{
	# This is very simplified - real implementation would use actual pointer value
	# Limbo doesn't expose pointer addresses directly
	# We'll use a pseudo-hash based on type
	return 0;
}

hashpointer(i: ref anything): int
{
	# Hash based on reference (simplified)
	# In practice, this would use the actual memory address
	# Since Limbo doesn't expose addresses, we use a placeholder
	if(i == nil)
		return 0;

	# Use a simple rotating hash
	h := 12345;
	for(j := 0; j < 4; j++) {
		h = ((h << 5) + h) + j;
	}
	return h;
}

# Get from hash table
hashget(ht: ref Hashtab, key: ref Value): ref Value
{
	if(ht == nil || key == nil) {
		result := ref Value;
		result.ty = TNIL;
		return result;
	}

	h := hashvalue(key);
	idx := h & (ht.size - 1);  # Power of 2 size -> mask

	node := ht.nodes[idx];
	while(node != nil) {
		if(node.keyhash == h && valueeq(node.key, key))
			return node.val;
		node = node.next;
	}

	result := ref Value;
	result.ty = TNIL;
	return result;
}

# Set in hash table
hashset(ht: ref Hashtab, key: ref Value, val: ref Value)
{
	if(ht == nil || key == nil)
		return;

	h := hashvalue(key);
	idx := h & (ht.size - 1);

	# Look for existing key
	node := ht.nodes[idx];
	prev: ref Hashnode;

	while(node != nil) {
		if(node.keyhash == h && valueeq(node.key, key)) {
			# Update existing
			node.val = val;
			return;
		}
		prev = node;
		node = node.next;
	}

	# Add new node
	newnode := ref Hashnode;
	newnode.key = key;
	newnode.val = val;
	newnode.keyhash = h;
	newnode.next = nil;

	if(prev == nil) {
		ht.nodes[idx] = newnode;
	} else {
		prev.next = newnode;
	}

	ht.count++;

	# Resize if too full
	if(ht.count > ht.size * 3 / 4)
		resizehash(ht);
}

# Delete from hash table
hashdel(ht: ref Hashtab, key: ref Value)
{
	if(ht == nil || key == nil)
		return;

	h := hashvalue(key);
	idx := h & (ht.size - 1);

	node := ht.nodes[idx];
	prev: ref Hashnode;

	while(node != nil) {
		if(node.keyhash == h && valueeq(node.key, key)) {
			# Remove node
			if(prev == nil)
				ht.nodes[idx] = node.next;
			else
				prev.next = node.next;
			ht.count--;
			return;
		}
		prev = node;
		node = node.next;
	}
}

# Resize hash table
resizehash(ht: ref Hashtab)
{
	if(ht == nil)
		return;

	oldsize := ht.size;
	oldnodes := ht.nodes;

	# Double size
	newsize := oldsize * 2;
	ht.size = newsize;
	ht.nodes = array[newsize] of ref Hashnode;
	ht.count = 0;

	for(i := 0; i < newsize; i++)
		ht.nodes[i] = nil;

	# Rehash all nodes
	for(i := 0; i < oldsize; i++) {
		node := oldnodes[i];
		while(node != nil) {
			next := node.next;
			rehashnode(ht, node);
			node = next;
		}
	}
}

# Rehash single node into new table
rehashnode(ht: ref Hashtab, node: ref Hashnode)
{
	h := node.keyhash;
	idx := h & (ht.size - 1);

	node.next = ht.nodes[idx];
	ht.nodes[idx] = node;
	ht.count++;
}

# Get next key for iteration
hashnext(ht: ref Hashtab, key: ref Value): (ref Value, ref Value)
{
	if(ht == nil)
		return (nil, nil);

	# If key is nil, return first element
	if(key == nil || key.ty == TNIL) {
		for(i := 0; i < ht.size; i++) {
			node := ht.nodes[i];
			if(node != nil)
				return (node.key, node.val);
		}
		return (nil, nil);
	}

	# Find position of key
	h := hashvalue(key);
	startidx := h & (ht.size - 1);

	# Find the node
	node := ht.nodes[startidx];
	found := 0;
	while(node != nil) {
		if(node.keyhash == h && valueeq(node.key, key)) {
			found = 1;
			node = node.next;
			break;
		}
		node = node.next;
	}

	# If found and has next, return it
	if(found && node != nil)
		return (node.key, node.val);

	# Otherwise, search remaining buckets
	for(i := startidx + 1; i < ht.size; i++) {
		node := ht.nodes[i];
		if(node != nil)
			return (node.key, node.val);
	}

	return (nil, nil);
}

# Check if two values are equal (for hash table)
valueeq(a, b: ref Value): int
{
	if(a == nil && b == nil)
		return 1;
	if(a == nil || b == nil)
		return 0;
	if(a.ty != b.ty)
		return 0;

	case(a.ty) {
	TNIL =>
		return 1;
	TBOOLEAN =>
		return a.b == b.b;
	TNUMBER =>
		return a.n == b.n;
	TSTRING =>
		return a.s == b.s;
	TTABLE =>
		return a.t == b.t;
	TFUNCTION =>
		return a.f == b.f;
	TUSERDATA =>
		return a.u == b.u;
	TTHREAD =>
		return a.th == b.th;
	* =>
		return 0;
	}
}

# Clear hash table
hashclear(ht: ref Hashtab)
{
	if(ht == nil)
		return;

	for(i := 0; i < ht.size; i++)
		ht.nodes[i] = nil;
	ht.count = 0;
}

# Get hash table size
hashsize(ht: ref Hashtab): int
{
	if(ht == nil)
		return 0;
	return ht.count;
}

# Check if hash table is empty
hashempty(ht: ref Hashtab): int
{
	if(ht == nil)
		return 1;
	return ht.count == 0;
}

# Convert hash table to array of key-value pairs
hashtopairs(ht: ref Hashtab): array of (ref Value, ref Value)
{
	if(ht == nil || ht.count == 0)
		return nil;

	result := array[ht.count] of (ref Value, ref Value);
	idx := 0;

	for(i := 0; i < ht.size; i++) {
		node := ht.nodes[i];
		while(node != nil) {
			result[idx++] = (node.key, node.val);
			node = node.next;
		}
	}

	return result;
}

# Weak table support (placeholder for GC integration)
# __mode = "k" (weak keys), "v" (weak values), or "kv" (both)
Weakkey: con 1;
Weakvalue: con 2;

setweakmode(ht: ref Hashtab, mode: int)
{
	# Placeholder - would set weak mode flag
	# Used by garbage collector
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
		"Hash Table Utilities",
		"External chaining with dynamic resizing",
	};
}
