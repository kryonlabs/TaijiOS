# DIS Parser Tests
# Comprehensive test suite for DIS parser

implement TestDisparser;

include "sys.m";
include "luadisparser.m";

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

assert_not_nil(msg: string; val: ref ^1^)
{
	if(val != nil) {
		tests_passed++;
	} else {
		tests_failed++;
		fprint(sys->fildes(2), "FAIL: %s (expected non-nil, got nil)\n", msg);
	}
}

assert_true(msg: string; condition: int)
{
	if(condition) {
		tests_passed++;
	} else {
		tests_failed++;
		fprint(sys->fildes(2), "FAIL: %s (expected true, got false)\n", msg);
	}
}

# ====================================================================
# Test Cases
# ====================================================================

test_parse_real_dis_file()
{
	# Try parsing a real DIS file

	# Find a DIS file to test
	testfiles := [] of {
		"/dis/lib/math.dis",
		"/dis/lib/rand.dis",
		"/dis/lib/bufio.dis",
	};

	found := 0;
	for(i := 0; i < len testfiles; i++) {
		(file, err) := parse(testfiles[i]);

		if(file != nil) {
			found++;
			assert_not_nil(sprint("parse(%s)", testfiles[i]), file);

			# Validate header
			assert_not_nil("file.header", file.header);
			assert_true("valid magic", validate(file) != 0);

			# Check instructions
			if(file.inst != nil) {
				assert_equal_int("instruction count", file.header.isize, len file.inst);

				if(len file.inst > 0) {
					assert_not_nil("first instruction", file.inst[0]);
				}
			}

			# Check types
			if(file.types != nil) {
				assert_equal_int("type count", file.header.tsize, len file.types);
			}

			# Check links
			if(file.links != nil) {
				assert_equal_int("link count", file.header.lsize, len file.links);

				# Get exports
				exports := getexports(file);
				if(exports != nil) {
					assert_true("has exports", len exports > 0);
				}
			}

			break;  # Only need to test one file
		}
	}

	if(found == 0) {
		fprint(sys->fildes(2), "SKIP: parse_real_dis_file (no DIS files found)\n");
	}
}

test_validate_good_file()
{
	# Create a valid DIS file structure
	file := ref DISFile;
	file.header = ref DISHeader;
	file.header.magic = 819248;  # XMAGIC
	file.header.rt = 0;
	file.header.ssize = 8192;
	file.header.isize = 100;
	file.header.dsize = 512;
	file.header.tsize = 10;
	file.header.lsize = 5;
	file.header.entry = 0;

	file.inst = array[100] of ref DISInst;
	file.types = array[10] of ref DISType;
	file.links = array[5] of ref DISLink;

	result := validate(file);
	assert_true("validate good file", result != 0);
}

test_validate_bad_magic()
{
	file := ref DISFile;
	file.header = ref DISHeader;
	file.header.magic = 0x1234;  # Bad magic
	file.header.isize = 100;
	file.header.dsize = 512;
	file.header.tsize = 10;
	file.header.lsize = 5;

	file.inst = array[100] of ref DISInst;
	file.types = array[10] of ref DISType;
	file.links = array[5] of ref DISLink;

	result := validate(file);
	assert_true("reject bad magic", result == 0);
}

test_validate_size_mismatch()
{
	file := ref DISFile;
	file.header = ref DISHeader;
	file.header.magic = 819248;
	file.header.isize = 100;
	file.header.dsize = 512;
	file.header.tsize = 10;
	file.header.lsize = 5;

	file.inst = array[50] of ref DISInst;  # Wrong size!
	file.types = array[10] of ref DISType;
	file.links = array[5] of ref DISLink;

	result := validate(file);
	assert_true("catch size mismatch", result == 0);
}

test_find_link()
{
	file := ref DISFile;
	file.links = array[3] of ref DISLink;

	file.links[0] = ref DISLink;
	file.links[0].name = "init";
	file.links[0].sig = 0;
	file.links[0].pc = 0;
	file.links[0].tdesc = 0;

	file.links[1] = ref DISLink;
	file.links[1].name = "run";
	file.links[1].sig = 1;
	file.links[1].pc = 10;
	file.links[1].tdesc = 1;

	file.links[2] = ref DISLink;
	file.links[2].name = "close";
	file.links[2].sig = 2;
	file.links[2].pc = 20;
	file.links[2].tdesc = 2;

	link := findlink(file, "run");
	assert_not_nil("find existing link", link);
	if(link != nil) {
		assert_equal_int("link pc", 10, link.pc);
	}

	link = findlink(file, "nonexistent");
	assert_true("find nonexistent returns nil", link == nil);
}

test_get_exports()
{
	file := ref DISFile;
	file.links = array[3] of ref DISLink;

	file.links[0] = ref DISLink;
	file.links[0].name = "init";

	file.links[1] = ref DISLink;
	file.links[1].name = "run";

	file.links[2] = ref DISLink;
	file.links[2].name = "close";

	exports := getexports(file);
	assert_not_nil("exports list", exports);

	# Count exports
	count := 0;
	for(; exports != nil; exports = tl exports)
		count++;

	assert_equal_int("export count", 3, count);
}

test_get_entry_point()
{
	file := ref DISFile;
	file.header = ref DISHeader;
	file.header.entry = 42;

	entry := getentry(file);
	assert_equal_int("entry point", 42, entry);
}

test_is_executable()
{
	file := ref DISFile;
	file.header = ref DISHeader;
	file.header.magic = 819248;  # XMAGIC

	result := isexecutable(file);
	assert_true("XMAGIC is executable", result != 0);

	file.header.magic = 923426;  # SMAGIC (library)
	result = isexecutable(file);
	assert_true("SMAGIC is not executable", result == 0);
}

test_is_signed()
{
	file := ref DISFile;
	file.sign = array[16] of byte;

	result := issigned(file);
	assert_true("signed file", result != 0);

	file.sign = array[0] of byte;
	result = issigned(file);
	assert_true("unsigned file", result == 0);
}

test_op2str()
{
	# Test opcode to string conversion
	str := op2str(0);
	assert_not_nil("op2str(0)", str);

	str = op2str(57);  # IADDB
	assert_not_nil("op2str(57)", str);
}

test_inst2str()
{
	inst := ref DISInst;
	inst.op = 0;
	inst.addr = 0;
	inst.mid = 0;
	inst.src = 0;
	inst.dst = 0;

	str := inst2str(inst);
	assert_not_nil("inst2str", str);
}

# ====================================================================
# Test Runner
# ====================================================================

runalltests()
{
	tests_passed = 0;
	tests_failed = 0;

	print("Running DIS parser tests...\n");

	test_parse_real_dis_file();
	test_validate_good_file();
	test_validate_bad_magic();
	test_validate_size_mismatch();
	test_find_link();
	test_get_exports();
	test_get_entry_point();
	test_is_executable();
	test_is_signed();
	test_op2str();
	test_inst2str();

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
		"Lua DIS Parser Tests",
		"Tests DIS binary file parser",
	};
}
