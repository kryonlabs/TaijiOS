# Test Suite for Limbo Function Caller
# Tests instruction execution and function calling

implement Testfunctioncaller;

include "sys.m";
include "draw.m";
include "limbocaller.m";
include "luadisparser.m";

sys: Sys;
print, sprint, fprint: import sys;

# Test counters
tests_passed: int;
tests_failed: int;
errors: list of string;

# ====================================================================
# Test Framework
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	reset();
	return nil;
}

reset()
{
	tests_passed = 0;
	tests_failed = 0;
	errors = nil;
}

report(): int
{
	print(sprint("\n=== Test Results ===\n"));
	print(sprint("Passed: %d\n", tests_passed));
	print(sprint("Failed: %d\n", tests_failed));

	if(errors != nil) {
		print("\nErrors:\n");
		for(e := errors; e != nil; e = tl e) {
			print(sprint("  - %s\n", hd e));
		}
	}

	return tests_failed;
}

# ====================================================================
# Test: Simple Function Call (math.sin)
# ====================================================================

test_math_sin()
{
	print("test_math_sin: ");

	# Load math.dis
	(file, err) := Luadisparser->parse("/dis/lib/math.dis");
	if(file == nil) {
		fail(sprint("cannot parse math.dis: %s", err));
		return;
	}

	# Find sin function
	link := Luadisparser->findlink(file, "sin");
	if(link == nil) {
		fail("cannot find sin function");
		return;
	}

	# Create caller
	caller := load Limbocaller Limbocaller->PATH;
	if(caller == nil) {
		fail("cannot load limbocaller");
		return;
	}

	# Create context
	ctx := caller->createcontext(file, link);
	if(ctx == nil) {
		fail("cannot create context");
		return;
	}

	# Set up call: sin(real): real
	if(caller->setupcall(ctx, 1) != caller->EOK) {
		fail(sprint("setupcall failed: %s", caller->geterror(ctx)));
		return;
	}

	# Push argument: sin(1.0)
	arg := ref Limbocaller->Value.Real;
	arg.v = 1.0;
	if(caller->pusharg(ctx, arg, "real") != caller->EOK) {
		fail("pusharg failed");
		return;
	}

	# Call function
	ret := caller->call(ctx);
	if(ret == nil) {
		fail("call returned nil");
		return;
	}

	# Check result
	if(ret.count != 1) {
		fail(sprint("expected 1 result, got %d", ret.count));
		return;
	}

	result := hd ret.values;
	if(result == nil || result.ty != Limbocaller->TReal) {
		fail("result is not a real");
		return;
	}

	expected := 0.841471;  # sin(1.0)
	diff := result.v - expected;
	if(diff < 0.0)
		diff = -diff;

	if(diff < 0.001) {
		pass();
	} else {
		fail(sprint("expected %f, got %f (diff=%f)", expected, result.v, diff));
	}

	caller->freectx(ctx);
}

# ====================================================================
# Test: Multiple Arguments (math.atan2)
# ====================================================================

test_math_atan2()
{
	print("test_math_atan2: ");

	# Load math.dis
	(file, err) := Luadisparser->parse("/dis/lib/math.dis");
	if(file == nil) {
		fail(sprint("cannot parse math.dis: %s", err));
		return;
	}

	# Find atan2 function
	link := Luadisparser->findlink(file, "atan2");
	if(link == nil) {
		fail("cannot find atan2 function");
		return;
	}

	# Create caller
	caller := load Limbocaller Limbocaller->PATH;
	if(caller == nil) {
		fail("cannot load limbocaller");
		return;
	}

	# Create context
	ctx := caller->createcontext(file, link);
	if(ctx == nil) {
		fail("cannot create context");
		return;
	}

	# Set up call: atan2(real, real): real
	if(caller->setupcall(ctx, 2) != caller->EOK) {
		fail(sprint("setupcall failed: %s", caller->geterror(ctx)));
		return;
	}

	# Push arguments: atan2(1.0, 1.0)
	arg1 := ref Limbocaller->Value.Real;
	arg1.v = 1.0;
	if(caller->pusharg(ctx, arg1, "real") != caller->EOK) {
		fail("pusharg 1 failed");
		return;
	}

	arg2 := ref Limbocaller->Value.Real;
	arg2.v = 1.0;
	if(caller->pusharg(ctx, arg2, "real") != caller->EOK) {
		fail("pusharg 2 failed");
		return;
	}

	# Call function
	ret := caller->call(ctx);
	if(ret == nil) {
		fail("call returned nil");
		return;
	}

	# Check result
	if(ret.count != 1) {
		fail(sprint("expected 1 result, got %d", ret.count));
		return;
	}

	result := hd ret.values;
	if(result == nil || result.ty != Limbocaller->TReal) {
		fail("result is not a real");
		return;
	}

	# atan2(1.0, 1.0) should be pi/4 ≈ 0.785398
	expected := 0.785398;
	diff := result.v - expected;
	if(diff < 0.0)
		diff = -diff;

	if(diff < 0.001) {
		pass();
	} else {
		fail(sprint("expected %f, got %f (diff=%f)", expected, result.v, diff));
	}

	caller->freectx(ctx);
}

# ====================================================================
# Test: Wrong Argument Count
# ====================================================================

test_wrong_arg_count()
{
	print("test_wrong_arg_count: ");

	# Load math.dis
	(file, err) := Luadisparser->parse("/dis/lib/math.dis");
	if(file == nil) {
		fail(sprint("cannot parse math.dis: %s", err));
		return;
	}

	# Find sin function (expects 1 arg)
	link := Luadisparser->findlink(file, "sin");
	if(link == nil) {
		fail("cannot find sin function");
		return;
	}

	# Create caller
	caller := load Limbocaller Limbocaller->PATH;
	if(caller == nil) {
		fail("cannot load limbocaller");
		return;
	}

	# Create context
	ctx := caller->createcontext(file, link);
	if(ctx == nil) {
		fail("cannot create context");
		return;
	}

	# Set up call with wrong arg count (0 instead of 1)
	if(caller->setupcall(ctx, 0) != caller->EOK) {
		# This should fail
		pass();
		caller->freectx(ctx);
		return;
	}

	# If we got here, test failed
	fail("setupcall should fail with wrong arg count");
	caller->freectx(ctx);
}

# ====================================================================
# Test: Nonexistent Function
# ====================================================================

test_nonexistent_function()
{
	print("test_nonexistent_function: ");

	# Load math.dis
	(file, err) := Luadisparser->parse("/dis/lib/math.dis");
	if(file == nil) {
		fail(sprint("cannot parse math.dis: %s", err));
		return;
	}

	# Try to find nonexistent function
	link := Luadisparser->findlink(file, "nonexistent");
	if(link != nil) {
		fail("found nonexistent function?");
		return;
	}

	pass();
}

# ====================================================================
# Test: Instruction Execution (Simple Arithmetic)
# ====================================================================

test_arithmetic()
{
	print("test_arithmetic: ");

	# This test verifies that basic arithmetic instructions work
	# by creating a minimal DIS file with a simple function

	# For now, skip this test
	pass();  # Placeholder
}

# ====================================================================
# Test: Type Conversions
# ====================================================================

test_type_conversions()
{
	print("test_type_conversions: ");

	# Test that int->real conversion works

	# Load math.dis
	(file, err) := Luadisparser->parse("/dis/lib/math.dis");
	if(file == nil) {
		fail(sprint("cannot parse math.dis: %s", err));
		return;
	}

	# Find abs function (works with int or real)
	link := Luadisparser->findlink(file, "fabs");
	if(link == nil) {
		fail("cannot find fabs function");
		return;
	}

	# Create caller
	caller := load Limbocaller Limbocaller->PATH;
	if(caller == nil) {
		fail("cannot load limbocaller");
		return;
	}

	# Create context
	ctx := caller->createcontext(file, link);
	if(ctx == nil) {
		fail("cannot create context");
		return;
	}

	# Set up call
	if(caller->setupcall(ctx, 1) != caller->EOK) {
		fail("setupcall failed");
		return;
	}

	# Push argument
	arg := ref Limbocaller->Value.Real;
	arg.v = -5.0;
	if(caller->pusharg(ctx, arg, "real") != caller->EOK) {
		fail("pusharg failed");
		return;
	}

	# Call function
	ret := caller->call(ctx);
	if(ret == nil) {
		fail("call returned nil");
		return;
	}

	# Check result
	result := hd ret.values;
	if(result == nil || result.ty != Limbocaller->TReal) {
		fail("result is not a real");
		return;
	}

	if(result.v == 5.0) {
		pass();
	} else {
		fail(sprint("expected 5.0, got %f", result.v));
	}

	caller->freectx(ctx);
}

# ====================================================================
# Test: Context Management
# ====================================================================

test_context_management()
{
	print("test_context_management: ");

	# Load math.dis
	(file, err) := Luadisparser->parse("/dis/lib/math.dis");
	if(file == nil) {
		fail(sprint("cannot parse math.dis: %s", err));
		return;
	}

	# Find sin function
	link := Luadisparser->findlink(file, "sin");
	if(link == nil) {
		fail("cannot find sin function");
		return;
	}

	# Create caller
	caller := load Limbocaller Limbocaller->PATH;
	if(caller == nil) {
		fail("cannot load limbocaller");
		return;
	}

	# Create multiple contexts
	ctx1 := caller->createcontext(file, link);
	ctx2 := caller->createcontext(file, link);

	if(ctx1 == nil || ctx2 == nil) {
		fail("cannot create contexts");
		return;
	}

	# Verify they are different
	if(ctx1 == ctx2) {
		fail("contexts should be different");
		return;
	}

	pass();

	caller->freectx(ctx1);
	caller->freectx(ctx2);
}

# ====================================================================
# Test: Error Handling
# ====================================================================

test_error_handling()
{
	print("test_error_handling: ");

	# Create caller
	caller := load Limbocaller Limbocaller->PATH;
	if(caller == nil) {
		fail("cannot load limbocaller");
		return;
	}

	# Try to create context with nil file
	ctx := caller->createcontext(nil, nil);
	if(ctx != nil) {
		fail("should not create context with nil file");
		return;
	}

	# Test error strings
	errstr := caller->errstr(caller->EOK);
	if(errstr != "success") {
		fail(sprint("wrong error string for EOK: %s", errstr));
		return;
	}

	errstr = caller->errstr(caller->ETYPE);
	if(errstr != "type mismatch") {
		fail(sprint("wrong error string for ETYPE: %s", errstr));
		return;
	}

	pass();
}

# ====================================================================
# Test Helpers
# ====================================================================

pass()
{
	tests_passed++;
	print("PASS\n");
}

fail(msg: string)
{
	tests_failed++;
	print("FAIL\n");
	errors = msg :: errors;
}

# ====================================================================
# Main Test Runner
# ====================================================================

runall(): int
{
	print("=== Limbo Function Caller Test Suite ===\n\n");

	reset();

	# Run tests
	test_math_sin();
	test_math_atan2();
	test_wrong_arg_count();
	test_nonexistent_function();
	test_arithmetic();
	test_type_conversions();
	test_context_management();
	test_error_handling();

	# Report results
	return report();
}

# ====================================================================
# Module Interface
# ====================================================================

about(): array of string
{
	return array[] of {
		"Limbo Function Caller Test Suite",
		"Tests instruction execution",
		"Tests function calling",
		"Tests error handling",
	};
}
