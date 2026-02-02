# DIS Parser Module
# Defines data structures for parsing DIS binary files

Luadisparser: module {
	PATH:	con "/dis/lib/luadisparser.dis";

	# DIS file header
	DISHeader: adt {
		magic:	int;		# XMAGIC or SMAGIC
		rt:	int;		# Runtime flags
		ssize:	int;		# Stack size
		isize:	int;		# Instruction count
		dsize:	int;		# Data size
		tsize:	int;		# Type descriptor count
		lsize:	int;		# Link table size
		entry:	int;		# Entry point PC
		entryt:	int;		# Entry point type
	};

	# Instruction (matches Dis->Inst from dis.m)
	DISInst: adt {
		op:	int;		# Opcode
		addr:	int;		# Addressing mode
		mid:	int;		# Middle operand
		src:	int;		# Source operand
		dst:	int;		# Destination operand
	};

	# Type descriptor (matches Dis->Type)
	DISType: adt {
		size:	int;		# Size in bytes
		np:	int;		# Number of pointers
		map:	array of byte;	# GC bitmap
	};

	# Data entry (matches Dis->Data)
	DISData: adt {
		op:	int;		# Data operation (DEFZ, DEFB, etc.)
		n:	int;		# Number of elements
		off:	int;		# Byte offset
		pick {
		Zero =>
			(void);
		Bytes =>
			bytes:	array of byte;
		Words =>
			words:	array of int;
		String =>
			str:	string;
		Reals =>
			reals:	array of real;
		Array =>
			typex:	int;
			length:	int;
		Aindex =>
			index:	int;
		Arestore =>
			(void);
		Bigs =>
			bigs:	array of big;
		}
	};

	# Link table entry (matches Dis->Link)
	DISLink: adt {
		name:	string;
		sig:	int;
		pc:	int;
		tdesc:	int;
	};

	# Import entry (matches Dis->Import)
	DISImport: adt {
		sig:	int;
		name:	string;
	};

	# Exception entry (matches Dis->Except)
	DISExcept: adt {
		s:	string;
		pc:	int;
	};

	# Exception handler (matches Dis->Handler)
	DISHandler: adt {
		pc1:	int;
		pc2:	int;
		eoff:	int;
		ne:	int;
		t:	ref DISType;
		etab:	array of ref DISExcept;
	};

	# Complete DIS file (matches Dis->Mod)
	DISFile: adt {
		name:	string;
		srcpath:	string;

		header:	ref DISHeader;
		inst:	array of ref DISInst;
		types:	array of ref DISType;
		data:	list of ref DISData;
		links:	array of ref DISLink;
		imports:	array of array of ref DISImport;
		handlers:	array of ref DISHandler;

		sign:	array of byte;
	};

	# Parser API
	parse:		fn(path: string): (ref DISFile, string);
	validate:	fn(file: ref DISFile): int;
	getexports:	fn(file: ref DISFile): list of string;
	findlink:	fn(file: ref DISFile, name: string): ref DISLink;

	# Instruction API
	decodeinst:	fn(buf: array of byte, pc: int): (ref DISInst, int);
	op2str:		fn(op: int): string;
	inst2str:	fn(inst: ref DISInst): string;

	# Data API
	decodedata:	fn(buf: array of byte, off: int): (ref DISData, int);

	# Utility API
	getentry:	fn(file: ref DISFile): int;
	issigned:	fn(file: ref DISFile): int;
	isexecutable:	fn(file: ref DISFile): int;

	# Error reporting
	error:		fn(msg: string): string;
	geterrmsg:	fn(): string;

	# About
	about:		fn(): array of string;
};
