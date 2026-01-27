CCI: module
{
	PATH:	con "/dis/lib/cci.dis";

	# Common Client Interface, for external control of web clients

	init: fn(smod: String, hctl: chan of string);
	view: fn(url, ctype: string, data: array of byte);
};
