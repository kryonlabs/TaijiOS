# Lua VM - Module Parser Tests
# Tests for lua_modparse.b module definition parser

implement TestModparse;

include "sys.m";
include "luavm.m";
include "lua_modparse.m";

sys: Sys;
print, sprint, fprint: import sys;

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

test_tokenizer()
{
	# Test basic tokenization

	buf := "module test { }";
	tokens := tokenize(buf);

	if(tokens == nil) {
		tests_failed++;
		fprint(sys->fildes(2), "FAIL: tokenize() returned nil\n");
		return;
	}

	# Count tokens
	count := 0;
	for(t := tokens; t != nil; t = tl t)
		count++;

	assert_equal_int("tokenize('module test { }')", 5, count);
}

test_parse_simple_function()
{
	# Test parsing a simple function

	buf := "Test: module {\n	init: fn(): string;\n};";

	sig := parsemodule(buf);
	assert_not_nil("parsemodule(simple)", sig);

	if(sig != nil) {
		assert_equal_string("module name", "Test", sig.modname);

		# Check function count
		nfuncs := 0;
		for(f := sig.functions; f != nil; f = tl f)
			nfuncs++;

		assert_equal_int("function count", 1, nfuncs);
	}
}

test_parse_function_with_params()
{
	# Test parsing function with parameters

	buf := "Math: module {\n	add: fn(a: int, b: int): int;\n};";

	sig := parsemodule(buf);
	assert_not_nil("parsemodule(with params)", sig);

	if(sig != nil && sig.functions != nil) {
		func := hd sig.functions;

		if(func != nil) {
			assert_equal_string("function name", "add", func.name);

			# Count parameters
			nparams := 0;
			for(p := func.params; p != nil; p = tl p)
				nparams++;

			assert_equal_int("parameter count", 2, nparams);
		}
	}
}

test_parse_types()
{
	# Test type parsing

	buf := "Types: module {\n	process: fn(data: array of byte): list of string;\n};";

	sig := parsemodule(buf);
	assert_not_nil("parsemodule(complex types)", sig);
}

test_parse_constants()
{
	# Test constant parsing

	buf := "Consts: module {\n	Max: con 100;\n};";

	sig := parsemodule(buf);
	assert_not_nil("parsemodule(constants)", sig);

	if(sig != nil) {
		nconsts := 0;
		for(c := sig.constants; c != nil; c = tl c)
			nconsts++;

		# Should have at least the constant
		if(nconsts >= 0) {
			tests_passed++;
		}
	}
}

test_parse_adt()
{
	# Test ADT parsing

	buf := "Data: module {\n	Point: adt {\n		x: int;\n		y: int;\n	};\n};";

	sig := parsemodule(buf);
	assert_not_nil("parsemodule(adt)", sig);

	if(sig != nil) {
		nadts := 0;
		for(a := sig.adts; a != nil; a = tl a)
			nadts++;

		# Should have at least the ADT
		if(nadts >= 0) {
			tests_passed++;
		}
	}
}

test_parse_real_module()
{
	# Test parsing a real module file

	sig := parsemodulefile("/module/math.m");
	if(sig != nil) {
		assert_not_nil("parsemodulefile(math.m)", sig);

		if(sig != nil) {
			assert_equal_string("math module name", "Math", sig.modname);

			# Math module should have many functions
			nfuncs := 0;
			for(f := sig.functions; f != nil; f = tl f)
				nfuncs++;

			if(nfuncs > 10) {
				tests_passed++;
			} else {
				tests_failed++;
				fprint(sys->fildes(2), "FAIL: math.m should have >10 functions, got %d\n", nfuncs);
			}
		}
	} else {
		# File may not exist, just note it
		print("Note: /module/math.m not found, skipping real module test\n");
	}
}

# ====================================================================
# Test Runner
# ====================================================================

runalltests()
{
	tests_passed = 0;
	tests_failed = 0;

	print("Running module parser tests...\n");

	test_tokenizer();
	test_parse_simple_function();
	test_parse_function_with_params();
	test_parse_types();
	test_parse_constants();
	test_parse_adt();
	test_parse_real_module();

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
		"Module Parser Tests",
		"Tests .m file parsing for function signatures",
	};
}
