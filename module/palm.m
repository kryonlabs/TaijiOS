Palm: module {

	PATH:	con "/dis/lib/palm.dis";

	# file attributes:
	Fresource:	con 1<<0;	# file is .prc not .pdb

	# record attributes:
	Rdelete:	con 16r80;	# delete next sync
	Rdirty:	con 16r40;	# record modified
	Rinuse:	con 16r20;	# record in use
	Rsecret:	con 16r10;	# record is secret
	Rarchive:	con 16r08;	# archive next sync

	DBInfo: adt {
		name:	string;
		attr:	int;
		dtype:	string;	# database type (byte[4])
		version:	int;	# defined by application
		creator:	string;	# creating application (byte[4])
		ctime:	int;
		mtime:	int;
		btime:	int;	# last backup
		modno:	int;	# modification number: set to zero
		uidseed:	int;	# unique record ID seed (unused, set to zero)
		index:	int;	# used by database access protocol

		new:	fn(name: string, attr: int, dtype: string, version: int, creator: string): ref DBInfo;
	};

	Record: adt {
		id:	int;	# unique record ID
		attr:	int;	# record attributes
		cat:	int;	# category
		data:	array of byte;

		new:	fn(id: int, attr: int, cat: int, size: int): ref Record;
	};

	Resource: adt {
		name:	int;	# byte[4]: resource type
		id:	int;	# resource ID
		data:	array of byte;

		new:	fn(name: int, id: int, size: int): ref Resource;
	};

	Categories: adt {
		renamed:	int;	# which categories have been renamed
		labels:	array of string;	# 16 category names
		uids:	array of int;	# corresponding unique IDs
		lastuid:	int;		# last unique ID assigned
		appdata:	array of byte;	# remaining data is application-specific

		new:	fn(labels: array of string): ref Categories;
		unpack:	fn(a: array of byte): ref Categories;
		pack:	fn(c: self ref Categories): array of byte;
		mkidmap:	fn(c: self ref Categories): array of int;
	};

	init:	fn(): string;

	# name mapping
	filename:	fn(s: string): string;
	dbname:	fn(s: string): string;

	# Latin-1 to string conversion
	gets:	fn(a: array of byte): string;
	puts:	fn(a: array of byte, s: string);

	# big-endian conversion
	get2:	fn(a: array of byte): int;
	get3:	fn(a: array of byte): int;
	get4:	fn(a: array of byte): int;
	put2:	fn(a: array of byte, v: int);
	put3:	fn(a: array of byte, v: int);
	put4:	fn(a: array of byte, v: int);
};
