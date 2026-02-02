# Lua VM - Type Marshaling Tests
# Tests for lua_marshal.b type conversion system

implement TestMarshal;

include "sys.m";
include "luavm.m";
include "lua_baselib.m";
include "lua_marshal.m";

sys: Sys;
print, sprint, fprint: import sys;

luavm: Luavm;
State: import luavm;

# Test results
tests_passed: int;
tests_failed: int;

# ====================================================================
# Test Helpers
# ====================================================================

assert_equal_int(msg: string; expected: int; actual: int)
{
	if(expected == actual) {
		tests_passed++;
	} else {
		tests_failed++;
		fprint(sys->fildes(2), "FAIL: %s (expected %d, got %d)\n", msg, expected, actual);
	}
}

assert_equal_real(msg: string; expected: real; actual: real; epsilon: real)
{
	diff := expected - actual;
	if(diff < 0.0)
		diff = -diff;

	if(diff < epsilon) {
		tests_passed++;
	} else {
		tests_failed++;
		fprint(sys->fildes(2), "FAIL: %s (expected %g, got %g)\n", msg, expected, actual);
	}
}

assert_equal_string(msg: string; expected: string; actual: string)
{
	if(expected == actual) {
		tests_passed++;
	} else {
		tests_failed++;
		fprint(sys->fildes(2), "FAIL: %s (expected '%s', got '%s')\n", msg, expected, actual);
	}
}

assert_not_nil(msg: string; val: ref ^1^)
{
	if(val != nil) {
		tests_passed++;
	} else {
		tests_failed++;
		fprint(sys->fildes(2), "FAIL: %s (expected non-nil, got nil)\n", msg);
	}
}

# ====================================================================
# Test Cases
# ====================================================================

test_lua2int()
{
	L := luavm->newstate();
	if(L == nil) {
		fprint(sys->fildes(2), "Failed to create Lua state\n");
		return;
	}

	# Test integer conversion
	# Push number 42
	val := ref Luavm->Value;
	val.ty = Luavm->TNUMBER;
	val.n = 42.0;

	result := lua2int(L, val);
	assert_not_nil("lua2int(42)", result);

	luavm->close(L);
}

test_lua2real()
{
	L := luavm->newstate();
	if(L == nil) {
		fprint(sys->fildes(2), "Failed to create Lua state\n");
		return;
	}

	# Test real conversion
	val := ref Luavm->Value;
	val.ty = Luavm->TNUMBER;
	val.n = 3.14159;

	result := lua2real(L, val);
	assert_not_nil("lua2real(3.14159)", result);

	luavm->close(L);
}

test_lua2string()
{
	L := luavm->newstate();
	if(L == nil) {
		fprint(sys->fildes(2), "Failed to create Lua state\n");
		return;
	}

	# Test string conversion
	val := ref Luavm->Value;
	val.ty = Luavm->TSTRING;
	val.s = "hello world";

	result := lua2string(L, val);
	assert_not_nil("lua2string('hello world')", result);

	luavm->close(L);
}

test_lua2byte()
{
	L := luavm->newstate();
	if(L == nil) {
		fprint(sys->fildes(2), "Failed to create Lua state\n");
		return;
	}

	# Test byte conversion from number
	val := ref Luavm->Value;
	val.ty = Luavm->TNUMBER;
	val.n = 65.0;

	result := lua2byte(L, val);
	assert_not_nil("lua2byte(65)", result);

	luavm->close(L);
}

test_type_parsing()
{
	# Test type signature parsing

	# Basic types
	(base, elem) := parsetypesig("int");
	assert_equal_string("parsetypesig('int').base", "int", base);
	assert_equal_string("parsetypesig('int').elem", "", elem);

	(base, elem) = parsetypesig("real");
	assert_equal_string("parsetypesig('real').base", "real", base);

	# Array types
	(base, elem) = parsetypesig("array of int");
	assert_equal_string("parsetypesig('array of int').base", "array", base);
	assert_equal_string("parsetypesig('array of int').elem", "int", elem);

	(base, elem) = parsetypesig("array of string");
	assert_equal_string("parsetypesig('array of string').base", "array", base);
	assert_equal_string("parsetypesig('array of string').elem", "string", elem);

	# List types
	(base, elem) = parsetypesig("list of real");
	assert_equal_string("parsetypesig('list of real').base", "list", base);
	assert_equal_string("parsetypesig('list of real').elem", "real", elem);
}

test_numeric_check()
{
	# Test isnumeric()

	result := isnumeric("int");
	assert_equal_int("isnumeric('int')", 1, result);

	result = isnumeric("real");
	assert_equal_int("isnumeric('real')", 1, result);

	result = isnumeric("byte");
	assert_equal_int("isnumeric('byte')", 1, result);

	result = isnumeric("string");
	assert_equal_int("isnumeric('string')", 0, result);

	result = isnumeric("array of int");
	assert_equal_int("isnumeric('array of int')", 0, result);
}

test_ref_check()
{
	# Test isref()

	result := isref("int");
	assert_equal_int("isref('int')", 0, result);

	result = isref("array of int");
	assert_equal_int("isref('array of int')", 1, result);

	result = isref("list of string");
	assert_equal_int("isref('list of string')", 1, result);

	result = isref("SomeADT");
	assert_equal_int("isref('SomeADT')", 1, result);
}

# ====================================================================
# Test Runner
# ====================================================================

runalltests()
{
	tests_passed = 0;
	tests_failed = 0;

	print("Running type marshaling tests...\n");

	test_lua2int();
	test_lua2real();
	test_lua2string();
	test_lua2byte();
	test_type_parsing();
	test_numeric_check();
	test_ref_check();

	print(sprint("\nTest Results: %d passed, %d failed\n", tests_passed, tests_failed));

	if(tests_failed > 0)
		return "some tests failed";
	return nil;
}

# ====================================================================
# Main Entry Point
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	luavm = load Luavm Luavm;

	return nil;
}

main(): string
{
	err := runalltests();
	if(err != nil)
		return "test failed: " + err;
	return "all tests passed";
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Type Marshaling Tests",
		"Tests type conversion between Lua and Limbo",
	};
}
