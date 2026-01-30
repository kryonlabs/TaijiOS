YAML: module
{
	PATH:	con "/dis/lib/yaml.dis";

	YAMLValue: adt {
		pick{
		Mapping =>
			pairs: cyclic list of (string, ref YAMLValue);
		Sequence =>
			items: cyclic array of ref YAMLValue;
		Scalar =>
			value: string;
		Null =>
		}

		ismapping:	fn(v: self ref YAMLValue): int;
		issequence:	fn(v: self ref YAMLValue): int;
		isscalar:	fn(v: self ref YAMLValue): int;
		isnull:	fn(v: self ref YAMLValue): int;

		get:	fn(v: self ref YAMLValue, key: string): ref YAMLValue;
		getitem:	fn(v: self ref YAMLValue, index: int): ref YAMLValue;
		length:	fn(v: self ref YAMLValue): int;
		text:	fn(v: self ref YAMLValue): string;
	};

	init:	fn(bufio: Bufio);
	loadfile:	fn(filename: string): (ref YAMLValue, string);
	loads:	fn(content: string): (ref YAMLValue, string);

	mapping:	fn(pairs: list of (string, ref YAMLValue)): ref YAMLValue.Mapping;
	sequence:	fn(items: array of ref YAMLValue): ref YAMLValue.Sequence;
	scalar:	fn(value: string): ref YAMLValue.Scalar;
	nullfn:	fn(): ref YAMLValue.Null;
};
