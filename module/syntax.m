Syntax: module
{
	PATH:	con "/dis/lib/syntax.dis";

	# Token types for syntax highlighting - must match frame.m SYN_ constants
	TKEYWORD, TSTRING, TCHAR, TNUMBER, TCOMMENT,
	TTYPE, TFUNCTION, TOPERATOR, TPREPROCESSOR, TIDENTIFIER: con iota;
	NTOKENS: con 10;

	Token: adt {
		toktype: int;
		start: int;
		end: int;
	};

	# Core functions
	init:	fn();
	enabled:	fn(): int;
	settheme:	fn(path: string): int;

	# Language-specific parsing
	parse_limbo:	fn(text: string): array of Token;
	parse_c:	fn(text: string): array of Token;
	parse_sh:	fn(text: string): array of Token;

	# Helper to detect language from file extension
	detect_language:	fn(filename: string): string;
};
