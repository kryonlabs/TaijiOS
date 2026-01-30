implement YAML;

#
# YAML 1.2 subset parser for configuration files
# Supports: scalars, mappings, sequences, nesting
#

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "yaml.m";

init(b: Bufio)
{
	sys = load Sys Sys->PATH;
	bufio = b;
}

Syntax: exception(string);

# Type checking
YAMLValue.ismapping(v: self ref YAMLValue): int
{
	return tagof v == tagof YAMLValue.Mapping;
}

YAMLValue.issequence(v: self ref YAMLValue): int
{
	return tagof v == tagof YAMLValue.Sequence;
}

YAMLValue.isscalar(v: self ref YAMLValue): int
{
	return tagof v == tagof YAMLValue.Scalar;
}

YAMLValue.isnull(v: self ref YAMLValue): int
{
	return tagof v == tagof YAMLValue.Null;
}

# Get value from mapping by key
YAMLValue.get(v: self ref YAMLValue, key: string): ref YAMLValue
{
	pick r := v {
	Mapping =>
		for(p := r.pairs; p != nil; p = tl p){
			if((hd p).t0 == key)
				return (hd p).t1;
		}
		return nil;
	* =>
		return nil;
	}
}

# Get item from sequence by index
YAMLValue.getitem(v: self ref YAMLValue, index: int): ref YAMLValue
{
	pick r := v {
	Sequence =>
		if(index >= 0 && index < len r.items)
			return r.items[index];
		return nil;
	* =>
		return nil;
	}
}

# Get length
YAMLValue.length(v: self ref YAMLValue): int
{
	pick r := v {
	Mapping =>
		n := 0;
		for(p := r.pairs; p != nil; p = tl p)
			n++;
		return n;
	Sequence =>
		return len r.items;
	Scalar =>
		return len r.value;
	Null =>
		return 0;
	}
}

# Convert to string
YAMLValue.text(v: self ref YAMLValue): string
{
	pick r := v {
	Scalar =>
		return r.value;
	Null =>
		return "null";
	Mapping =>
		return "<mapping>";
	Sequence =>
		return "<sequence>";
	}
}

# Load from file
loadfile(filename: string): (ref YAMLValue, string)
{
	fd := sys->open(filename, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("cannot open %s: %r", filename));

	io := bufio->fopen(fd, Sys->OREAD);
	if(io == nil)
		return (nil, sys->sprint("cannot buffer %s: %r", filename));

	return parse(io);
}

# Load from string
loads(content: string): (ref YAMLValue, string)
{
	io := bufio->sopen(content);
	if(io == nil)
		return (nil, "cannot create string buffer");

	return parse(io);
}

# Main parsing function
parse(io: ref Iobuf): (ref YAMLValue, string)
{
	{
		return (parse_value(io, 0), nil);
	} exception e {
	Syntax =>
		return (nil, e);
	}
}

# Parse YAML value (recursive)
parse_value(io: ref Iobuf, base_indent: int): ref YAMLValue raises(Syntax)
{
	# Buffer to handle peeking
	lines: list of (string, int);

	# Read all non-empty, non-comment lines
	while((line := io.gets('\n')) != nil){
		if(line == nil)
			break;

		# Trim trailing newline
		if(len line > 0 && line[len line - 1] == '\n')
			line = line[:len line - 1];
		if(len line > 0 && line[len line - 1] == '\r')
			line = line[:len line - 1];

		# Count indentation
		indent := 0;
		while(indent < len line && (line[indent] == ' ' || line[indent] == '\t'))
			indent++;

		# Trim indentation
		content := line[indent:];

		# Skip empty lines and comments
		if(content == nil || (len content > 0 && content[0] == '#'))
			continue;

		lines = (content, indent) :: lines;
	}

	# Reverse to get correct order
	reversed: list of (string, int);
	for(; lines != nil; lines = tl lines)
		reversed = hd lines :: reversed;

	if(reversed == nil)
		return nullfn();

	# Parse the first value
	(first_line, first_indent) := hd reversed;
	reversed = tl reversed;

	return parse_line(first_line, first_indent, base_indent, reversed);
}

# Parse a single line and its children
parse_line(line: string, indent: int, base_indent: int, rest: list of (string, int)): ref YAMLValue raises(Syntax)
{
	# Check for list item
	if(len line > 0 && line[0] == '-'){
		# Parse sequence
		items := parse_sequence(line, indent, base_indent, rest);
		return sequence(items);
	}

	# Check for mapping (key: value)
	colon := find_unescaped(line, ':');
	if(colon >= 0){
		# Parse mapping
		pairs := parse_mapping(line, indent, base_indent, rest);
		return mapping(pairs);
	}

	# Default: scalar
	return scalar(line);
}

# Parse a sequence starting with -
parse_sequence(line: string, indent: int, base_indent: int, rest: list of (string, int)): array of ref YAMLValue raises(Syntax)
{
	items: list of ref YAMLValue;

	for(;;){
		# Remove the dash
		if(len line > 0 && line[0] == '-'){
			line = line[1:];
			line = trim_spaces(line);
		}

		# Parse this item
		item: ref YAMLValue;
		if(line == nil || line == ""){
			# Check for nested structure on next line
			if(rest != nil){
				(next_line, next_indent) := hd rest;
				if(next_indent > indent){
					rest = tl rest;
					item = parse_line(next_line, next_indent, indent, rest);
					# Skip remaining lines at this level or deeper
					new_rest: list of (string, int);
					while(rest != nil){
						(r_line, r_indent) := hd rest;
						if(r_indent <= indent)
							new_rest = hd rest :: new_rest;
						rest = tl rest;
					}
					# Reverse back
					reversed: list of (string, int);
					for(; new_rest != nil; new_rest = tl new_rest)
						reversed = hd new_rest :: reversed;
					rest = reversed;
				} else {
					item = scalar("");
				}
			} else {
				item = scalar("");
			}
		} else {
			item = scalar(line);
		}

		items = item :: items;

		# Look for next item at same level
		if(rest != nil){
			(next_line, next_indent) := hd rest;
			if(next_indent == indent && len next_line > 0 && next_line[0] == '-'){
				rest = tl rest;
				line = next_line;
				continue;
			}
		}
		break;
	}

	# Reverse and convert to array
	n := 0;
	for(l := items; l != nil; l = tl l)
		n++;
	a := array[n] of ref YAMLValue;
	for(i := 0; i < n; items = tl items)
		a[i++] = hd items;

	return a;
}

# Parse a mapping
parse_mapping(line: string, indent: int, base_indent: int, rest: list of (string, int)): list of (string, ref YAMLValue) raises(Syntax)
{
	pairs: list of (string, ref YAMLValue);

	for(;;){
		colon := find_unescaped(line, ':');
		if(colon < 0)
			raise Syntax("expected ':' in mapping");

		key := trim_spaces(line[:colon]);
		value_part := trim_spaces(line[colon+1:]);

		# Parse value
		value: ref YAMLValue;
		if(value_part == nil || value_part == ""){
			# Check for nested structure on next line
			if(rest != nil){
				(next_line, next_indent) := hd rest;
				if(next_indent > indent){
					rest = tl rest;
					value = parse_line(next_line, next_indent, indent, rest);
					# Skip remaining lines at this level or deeper
					new_rest: list of (string, int);
					while(rest != nil){
						(r_line, r_indent) := hd rest;
						if(r_indent <= indent)
							new_rest = hd rest :: new_rest;
						rest = tl rest;
					}
					# Reverse back
					reversed: list of (string, int);
					for(; new_rest != nil; new_rest = tl new_rest)
						reversed = hd new_rest :: reversed;
					rest = reversed;
				} else {
					value = scalar("");
				}
			} else {
				value = scalar("");
			}
		} else {
			value = scalar(value_part);
		}

		pairs = (key, value) :: pairs;

		# Look for next pair at same level
		if(rest != nil){
			(next_line, next_indent) := hd rest;
			if(next_indent == indent){
				rest = tl rest;
				line = next_line;
				continue;
			}
		}
		break;
	}

	# Reverse pairs
	reversed: list of (string, ref YAMLValue);
	for(; pairs != nil; pairs = tl pairs)
		reversed = hd pairs :: reversed;

	return reversed;
}

# Helper: Find character in string
find_unescaped(s: string, c: int): int
{
	for(i := 0; i < len s; i++){
		if(s[i] == c)
			return i;
	}
	return -1;
}

# Helper: Trim leading/trailing spaces
trim_spaces(s: string): string
{
	if(s == nil)
		return nil;

	start := 0;
	while(start < len s && (s[start] == ' ' || s[start] == '\t'))
		start++;

	end := len s;
	while(end > start && (s[end-1] == ' ' || s[end-1] == '\t'))
		end--;

	if(start >= end)
		return nil;

	return s[start:end];
}

# Construction helpers
mapping(pairs: list of (string, ref YAMLValue)): ref YAMLValue.Mapping
{
	return ref YAMLValue.Mapping(pairs);
}

sequence(items: array of ref YAMLValue): ref YAMLValue.Sequence
{
	return ref YAMLValue.Sequence(items);
}

scalar(value: string): ref YAMLValue.Scalar
{
	return ref YAMLValue.Scalar(value);
}

nullfn(): ref YAMLValue.Null
{
	return ref YAMLValue.Null;
}
