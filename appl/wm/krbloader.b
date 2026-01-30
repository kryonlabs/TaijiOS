implement Krbloader;

include "sys.m";
	sys: Sys;
include "krbloader.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;

KRB_MAGIC: con 16r4B52594E;	# "KRYN"
KRB_VERSION_MAJOR: con 1;
KRB_VERSION_MINOR: con 0;

init()
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
}

# Module-level error message
errormsg: string;

set_error(s: string)
{
	errormsg = s;
}

get_error(): string
{
	return errormsg;
}

# Big-endian read helpers (KRB format is big-endian)

get_u32(data: array of byte, offset: int): int
{
	if(offset + 4 > len data)
		return 0;
	return (int data[offset] << 24) |
	       (int data[offset+1] << 16) |
	       (int data[offset+2] << 8) |
	       int data[offset+3];
}

get_u16(data: array of byte, offset: int): int
{
	if(offset + 2 > len data)
		return 0;
	return (int data[offset] << 8) | int data[offset+1];
}

# Load and parse KRB file
krbload(path: string): ref KrbFile
{
	errormsg = nil;

	# Open and read file
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		set_error(sys->sprint("Cannot open file: %r"));
		return nil;
	}

	# Get file size
	(ok, stat) := sys->fstat(fd);
	if(!ok) {
		set_error(sys->sprint("Cannot stat file: %r"));
		return nil;
	}

	size := int stat.length;
	if(size < 100) {	# Minimum KRB file size
		set_error("File too small to be a KRB file");
		return nil;
	}

	# Read entire file
	data := array[size] of byte;
	nread := sys->read(fd, data, size);
	if(nread != size) {
		set_error("Failed to read entire file");
		return nil;
	}

	krb := ref KrbFile;
	krb.data = data;
	krb.size = size;

	# Parse header
	if(!parse_header(krb))
		return nil;

	# Parse string table
	if(!parse_string_table(krb))
		return nil;

	# Parse widget instances
	if(!parse_widget_instances(krb))
		return nil;

	# Parse properties
	if(!parse_properties(krb))
		return nil;

	# Parse events
	if(!parse_events(krb))
		return nil;

	return krb;
}

# Parse KRB header
parse_header(krb: ref KrbFile): int
{
	if(krb.size < 100) {
		set_error("File too small for header");
		return 0;
	}

	hdr := ref KrbHeader;
	hdr.magic = get_u32(krb.data, 0);

	if(hdr.magic != KRB_MAGIC) {
		set_error(sys->sprint("Invalid magic number: 0x%x", hdr.magic));
		return 0;
	}

	hdr.version_major = get_u16(krb.data, 4);
	hdr.version_minor = get_u16(krb.data, 6);
	hdr.flags = get_u16(krb.data, 8);
	hdr.reserved = get_u16(krb.data, 10);

	# Section counts
	hdr.style_count = get_u32(krb.data, 12);
	hdr.theme_count = get_u32(krb.data, 16);
	hdr.widget_def_count = get_u32(krb.data, 20);
	hdr.widget_instance_count = get_u32(krb.data, 24);
	hdr.property_count = get_u32(krb.data, 28);
	hdr.event_count = get_u32(krb.data, 32);
	hdr.script_count = get_u32(krb.data, 36);

	# Section offsets
	hdr.string_table_offset = get_u32(krb.data, 60);
	hdr.widget_defs_offset = get_u32(krb.data, 64);
	hdr.widget_instances_offset = get_u32(krb.data, 68);
	hdr.styles_offset = get_u32(krb.data, 72);
	hdr.themes_offset = get_u32(krb.data, 76);
	hdr.properties_offset = get_u32(krb.data, 80);
	hdr.events_offset = get_u32(krb.data, 84);
	hdr.scripts_offset = get_u32(krb.data, 88);

	# Section sizes
	hdr.string_table_size = get_u32(krb.data, 92);
	hdr.widget_defs_size = get_u32(krb.data, 96);
	hdr.widget_instances_size = get_u32(krb.data, 100);
	hdr.styles_size = get_u32(krb.data, 104);
	hdr.themes_size = get_u32(krb.data, 108);
	hdr.properties_size = get_u32(krb.data, 112);
	hdr.events_size = get_u32(krb.data, 116);
	hdr.scripts_size = get_u32(krb.data, 120);

	hdr.checksum = get_u32(krb.data, 124);

	krb.header = hdr;

	# Validate version
	if(hdr.version_major != KRB_VERSION_MAJOR) {
		set_error(sys->sprint("Unsupported version: %d.%d",
			hdr.version_major, hdr.version_minor));
		return 0;
	}

	return 1;
}

# Parse string table
parse_string_table(krb: ref KrbFile): int
{
	hdr := krb.header;
	offset := hdr.string_table_offset;
	size := hdr.string_table_size;

	if(offset + size > krb.size) {
		set_error("String table exceeds file size");
		return 0;
	}

	# Parse null-terminated strings
	strings := array[10] of string;
	count := 0;

	pos := offset;
	end := offset + size;

	while(pos < end && count < 1000) {
		start := pos;
		while(pos < end && krb.data[pos] != byte 0)
			pos++;

		if(pos > start) {
			if(count >= len strings) {
				newarr := array[len strings * 2] of string;
				for(j := 0; j < count; j++)
					newarr[j] = strings[j];
				strings = newarr;
			}
			strings[count++] = string krb.data[start:pos];
		}
		pos++;
	}

	krb.strings = strings[0:count];
	return 1;
}

# Parse widget instances
parse_widget_instances(krb: ref KrbFile): int
{
	hdr := krb.header;
	offset := hdr.widget_instances_offset;
	count := hdr.widget_instance_count;

	if(count == 0)
		return 1;	# No widgets is OK

	if(offset + count * 40 > krb.size) {	# Each instance is 40 bytes
		set_error("Widget instances exceed file size");
		return 0;
	}

	widgets := array[count] of ref KrbWidgetInstance;

	for(i := 0; i < count; i++) {
		pos := offset + i * 40;
		w := ref KrbWidgetInstance;

		w.id = get_u32(krb.data, pos);
		w.type_id = get_u32(krb.data, pos + 4);
		w.parent_id = get_u32(krb.data, pos + 8);
		w.style_id = get_u32(krb.data, pos + 12);

		w.property_count = get_u16(krb.data, pos + 16);
		w.child_count = get_u16(krb.data, pos + 18);
		w.event_count = get_u16(krb.data, pos + 20);
		w.flags = get_u16(krb.data, pos + 22);

		w.id_str_offset = get_u32(krb.data, pos + 24);
		w.properties_offset = get_u32(krb.data, pos + 28);
		w.children_offset = get_u32(krb.data, pos + 32);
		w.events_offset = get_u32(krb.data, pos + 36);

		widgets[i] = w;
	}

	krb.widgets = widgets;
	return 1;
}

# Parse properties
parse_properties(krb: ref KrbFile): int
{
	hdr := krb.header;
	offset := hdr.properties_offset;
	count := hdr.property_count;

	if(count == 0)
		return 1;

	if(offset + count * 12 > krb.size) {	# Each property is 12 bytes
		set_error("Properties exceed file size");
		return 0;
	}

	props := array[count] of ref KrbProperty;

	for(i := 0; i < count; i++) {
		pos := offset + i * 12;
		p := ref KrbProperty;

		p.id = get_u32(krb.data, pos);
		p.name_offset = get_u32(krb.data, pos + 4);
		p.value_offset = get_u32(krb.data, pos + 8);

		props[i] = p;
	}

	krb.properties = props;
	return 1;
}

# Parse events
parse_events(krb: ref KrbFile): int
{
	hdr := krb.header;
	offset := hdr.events_offset;
	count := hdr.event_count;

	if(count == 0)
		return 1;

	if(offset + count * 16 > krb.size) {	# Each event is 16 bytes
		set_error("Events exceed file size");
		return 0;
	}

	events := array[count] of ref KrbEvent;

	for(i := 0; i < count; i++) {
		pos := offset + i * 16;
		e := ref KrbEvent;

		e.id = get_u32(krb.data, pos);
		e.event_type_offset = get_u32(krb.data, pos + 4);
		e.handler_offset = get_u32(krb.data, pos + 8);
		e.metadata_offset = get_u32(krb.data, pos + 12);

		events[i] = e;
	}

	krb.events = events;
	return 1;
}

# Get string from string table by offset
get_string(krb: ref KrbFile, offset: int): string
{
	if(offset < 0 || offset >= krb.header.string_table_size)
		return "";

	# Find string at offset
	pos := krb.header.string_table_offset + offset;
	start := pos;

	while(pos < krb.size && krb.data[pos] != byte 0)
		pos++;

	return string krb.data[start:pos];
}

# Find widget by ID
find_widget(krb: ref KrbFile, id: int): ref KrbWidgetInstance
{
	for(i := 0; i < len krb.widgets; i++) {
		if(krb.widgets[i].id == id)
			return krb.widgets[i];
	}
	return nil;
}

# Get root widget (widget with parent_id == 0)
get_root(krb: ref KrbFile): ref KrbWidgetInstance
{
	for(i := 0; i < len krb.widgets; i++) {
		if(krb.widgets[i].parent_id == 0)
			return krb.widgets[i];
	}
	return nil;
}

# Free KRB file resources
free(krb: ref KrbFile)
{
	# Limbo's garbage collector will handle cleanup
	krb.data = nil;
	krb.strings = nil;
	krb.widgets = nil;
	krb.properties = nil;
	krb.events = nil;
}

# ============================================================
# Widget Types and Functions (merged from Krbwidgets)
# ============================================================

# PropertyValue constructors

PropertyValue.new_string(s: string): ref PropertyValue
{
	pv := ref PropertyValue;
	pv.ptype = PropString;
	pv.str_val = s;
	return pv;
}

PropertyValue.new_number(r: real): ref PropertyValue
{
	pv := ref PropertyValue;
	pv.ptype = PropNumber;
	pv.num_val = r;
	return pv;
}

PropertyValue.new_boolean(b: int): ref PropertyValue
{
	pv := ref PropertyValue;
	pv.ptype = PropBoolean;
	pv.bool_val = b;
	return pv;
}

PropertyValue.new_color(c: int): ref PropertyValue
{
	pv := ref PropertyValue;
	pv.ptype = PropColor;
	pv.color_val = c;
	return pv;
}

# WidgetTree methods

WidgetTree.new(): ref WidgetTree
{
	tree := ref WidgetTree;
	tree.root = nil;
	tree.widgets = nil;
	return tree;
}

WidgetTree.find_by_id(tree: self ref WidgetTree, id: string): ref Widget
{
	for(w := tree.widgets; w != nil; w = tl w)
		if((hd w).id == id)
			return hd w;
	return nil;
}

WidgetTree.add_widget(tree: self ref WidgetTree, w: ref Widget)
{
	tree.widgets = w :: tree.widgets;
}

# Color conversion: KRB uses 0xAABBGGRR, TK uses "#RRGGBB"
krb_to_tk_color(krb_color: int): string
{
	r := (krb_color >> 16) & 16rFF;
	g := (krb_color >> 8) & 16rFF;
	b := krb_color & 16rFF;
	return sys->sprint("#%02x%02x%02x", r, g, b);
}

# ============================================================
# Phase 3: Widget Tree Builder
# ============================================================

# Helper: get list length for widgets
widget_list_len(l: list of ref Widget): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# Helper: reverse widget list
rev_widget_list(l: list of ref Widget): list of ref Widget
{
	result: list of ref Widget = nil;
	for(; l != nil; l = tl l)
		result = (hd l) :: result;
	return result;
}

# Helper: reverse property list
rev_prop_list(l: list of (string, ref PropertyValue)): list of (string, ref PropertyValue)
{
	result: list of (string, ref PropertyValue) = nil;
	for(; l != nil; l = tl l)
		result = (hd l) :: result;
	return result;
}

# Helper: reverse int list
rev_int_list(l: list of int): list of int
{
	result: list of int = nil;
	for(; l != nil; l = tl l)
		result = (hd l) :: result;
	return result;
}

# Convert widget type ID to name
widget_type_name(type_id: int): string
{
	case type_id {
	CONTAINER =>
		return "Container";
	ROW =>
		return "Row";
	COLUMN =>
		return "Column";
	TEXT =>
		return "Text";
	BUTTON =>
		return "Button";
	INPUT =>
		return "Input";
	CHECKBOX =>
		return "Checkbox";
	DROPDOWN =>
		return "Dropdown";
	IMAGE =>
		return "Image";
	TOGGLE =>
		return "Toggle";
	SCROLLBAR =>
		return "Scrollbar";
	PROGRESS =>
		return "Progress";
	SLIDER =>
		return "Slider";
	* =>
		return sys->sprint("Unknown(0x%x)", type_id);
	}
}

# Extract properties from KRB data
extract_properties(krb: ref KrbFile, w: ref KrbWidgetInstance): list of (string, ref PropertyValue)
{
	props: list of (string, ref PropertyValue) = nil;

	# Properties are stored inline, parse from properties_offset
	if(w.properties_offset == 0)
		return nil;

	offset := w.properties_offset;
	for(i := 0; i < w.property_count; i++) {
		if(offset + 12 > krb.size)
			break;

		prop_id := get_u32(krb.data, offset);
		name_offset := get_u32(krb.data, offset + 4);
		value_offset := get_u32(krb.data, offset + 8);

		name := get_string(krb, name_offset);
		value_str := get_string(krb, value_offset);

		# Parse property value based on name
		pv := parse_property_value(name, value_str);
		props = (name, pv) :: props;

		offset += 12;
	}

	return rev_prop_list(props);
}

# Parse a property value string into appropriate type
parse_property_value(name: string, value: string): ref PropertyValue
{
	if(value == nil || value == "")
		return PropertyValue.new_string("");

	# Check for boolean
	if(value == "true")
		return PropertyValue.new_boolean(1);
	if(value == "false")
		return PropertyValue.new_boolean(0);

	# Check for number
	(numok, num) := str->toint(value, 10);
	if(numok)
		return PropertyValue.new_number(real num);

	# Check for color (0xAABBGGRR format)
	if(len value >= 2 && value[0:2] == "0x") {
		(hexnum, rest) := str->toint(value, 16);
		return PropertyValue.new_color(hexnum);
	}

	# Default: string
	return PropertyValue.new_string(value);
}

# Extract event handlers from KRB data
extract_events(krb: ref KrbFile, w: ref KrbWidgetInstance): (string, string, string)
{
	on_click := "";
	on_change := "";
	on_key := "";

	if(w.events_offset == 0 || w.event_count == 0)
		return (on_click, on_change, on_key);

	offset := w.events_offset;
	for(i := 0; i < w.event_count; i++) {
		if(offset + 16 > krb.size)
			break;

		# event_id := get_u32(krb.data, offset);
		event_type_offset := get_u32(krb.data, offset + 4);
		handler_offset := get_u32(krb.data, offset + 8);
		# metadata_offset := get_u32(krb.data, offset + 12);

		event_type := get_string(krb, event_type_offset);
		handler := get_string(krb, handler_offset);

		case event_type {
		"onClick" =>
			on_click = handler;
		"onChange" =>
			on_change = handler;
		"onKeyPress" =>
			on_key = handler;
		}

		offset += 16;
	}

	return (on_click, on_change, on_key);
}

# Build widget tree from KRB file
build_widget_tree(krb: ref KrbFile): ref WidgetTree
{
	if(krb == nil || krb.widgets == nil)
		return nil;

	tree := WidgetTree.new();

	# Find root widget
	root_inst := get_root(krb);
	if(root_inst == nil) {
		sys->fprint(sys->fildes(2), "build_widget_tree: no root widget found\n");
		return nil;
	}

	# Build widget map (id -> instance)
	widget_map: list of (int, ref KrbWidgetInstance) = nil;
	for(i := 0; i < len krb.widgets; i++) {
		w := krb.widgets[i];
		widget_map = (w.id, w) :: widget_map;
	}

	# Recursively build tree
	root := build_widget_recursive(krb, root_inst, widget_map);
	if(root == nil) {
		sys->fprint(sys->fildes(2), "build_widget_tree: failed to build root widget\n");
		return nil;
	}

	tree.root = root;
	return tree;
}

# Recursively build widget tree
build_widget_recursive(krb: ref KrbFile, inst: ref KrbWidgetInstance,
	widget_map: list of (int, ref KrbWidgetInstance)): ref Widget
{
	if(inst == nil)
		return nil;

	w := ref Widget;
	w.id = get_string(krb, inst.id_str_offset);
	w.type_id = inst.type_id;
	w.type_name = widget_type_name(inst.type_id);

	# Initialize layout
	w.x = 0;
	w.y = 0;
	w.width = 100;
	w.height = 30;

	# Initialize padding and margin (top, right, bottom, left)
	w.padding = array[4] of {0, 0, 0, 0};
	w.margin = array[4] of {0, 0, 0, 0};

	# Initialize colors (default: transparent/black)
	w.background = 0;
	w.foreground = 0;

	# Initialize font
	w.font_size = 12;
	w.font_family = "sans";

	# Initialize text
	w.text = "";

	# Initialize event handlers
	w.on_click = "";
	w.on_change = "";
	w.on_key = "";

	# Initialize properties list
	w.properties = nil;

	# Initialize tree structure
	w.children = nil;
	w.parent = nil;
	w.tk_widget = "";

	# Extract properties
	props := extract_properties(krb, inst);
	w.properties = props;

	# Apply properties to widget fields
	apply_properties_to_widget(w, props);

	# Extract event handlers
	(on_click, on_change, on_key) := extract_events(krb, inst);
	w.on_click = on_click;
	w.on_change = on_change;
	w.on_key = on_key;

	# Build children recursively
	if(inst.child_count > 0) {
		children_list: list of ref Widget = nil;

		# Find children by searching widget_map for widgets with parent_id == inst.id
		child_ids := get_child_ids(krb, inst);
		while(child_ids != nil) {
			child_id := hd child_ids;
			child_ids = tl child_ids;

			# Find child instance in map
			child_inst := find_instance_in_map(widget_map, child_id);
			if(child_inst != nil) {
				child := build_widget_recursive(krb, child_inst, widget_map);
				if(child != nil) {
					child.parent = w;
					children_list = child :: children_list;
				}
			}
		}

		w.children = rev_widget_list(children_list);
	}

	return w;
}

# Find widget instance in map
find_instance_in_map(map: list of (int, ref KrbWidgetInstance), id: int): ref KrbWidgetInstance
{
	for(; map != nil; map = tl map) {
		(pid, inst) := hd map;
		if(pid == id)
			return inst;
	}
	return nil;
}

# Get child widget IDs
get_child_ids(krb: ref KrbFile, inst: ref KrbWidgetInstance): list of int
{
	if(inst.child_count == 0 || inst.children_offset == 0)
		return nil;

	# Children are stored as array of uint32 at children_offset
	ids: list of int = nil;
	offset := inst.children_offset;

	for(i := 0; i < inst.child_count; i++) {
		if(offset + 4 > krb.size)
			break;
		child_id := get_u32(krb.data, offset);
		ids = child_id :: ids;
		offset += 4;
	}

	return rev_int_list(ids);
}

# Apply properties to widget fields
apply_properties_to_widget(w: ref Widget, props: list of (string, ref PropertyValue))
{
	for(; props != nil; props = tl props) {
		(name, pv) := hd props;

		case name {
		"text" =>
			if(pv.ptype == PropString)
				w.text = pv.str_val;
		"backgroundColor" =>
			if(pv.ptype == PropColor)
				w.background = pv.color_val;
		"color" =>
			if(pv.ptype == PropColor)
				w.foreground = pv.color_val;
		"fontSize" =>
			if(pv.ptype == PropNumber)
				w.font_size = int pv.num_val;
		"fontFamily" =>
			if(pv.ptype == PropString)
				w.font_family = pv.str_val;
		"width" =>
			if(pv.ptype == PropNumber)
				w.width = int pv.num_val;
		"height" =>
			if(pv.ptype == PropNumber)
				w.height = int pv.num_val;
		"padding" =>
			if(pv.ptype == PropNumber) {
				pad := int pv.num_val;
				w.padding[0] = pad;
				w.padding[1] = pad;
				w.padding[2] = pad;
				w.padding[3] = pad;
			}
		"paddingTop" =>
			if(pv.ptype == PropNumber)
				w.padding[0] = int pv.num_val;
		"paddingRight" =>
			if(pv.ptype == PropNumber)
				w.padding[1] = int pv.num_val;
		"paddingBottom" =>
			if(pv.ptype == PropNumber)
				w.padding[2] = int pv.num_val;
		"paddingLeft" =>
			if(pv.ptype == PropNumber)
				w.padding[3] = int pv.num_val;
		"margin" =>
			if(pv.ptype == PropNumber) {
				mar := int pv.num_val;
				w.margin[0] = mar;
				w.margin[1] = mar;
				w.margin[2] = mar;
				w.margin[3] = mar;
			}
		"marginTop" =>
			if(pv.ptype == PropNumber)
				w.margin[0] = int pv.num_val;
		"marginRight" =>
			if(pv.ptype == PropNumber)
				w.margin[1] = int pv.num_val;
		"marginBottom" =>
			if(pv.ptype == PropNumber)
				w.margin[2] = int pv.num_val;
		"marginLeft" =>
			if(pv.ptype == PropNumber)
				w.margin[3] = int pv.num_val;
		"flex" =>
			# Flex is used during layout, stored in properties
			w.properties = (name, pv) :: w.properties;
		"expand" =>
			# Expand is used during layout, stored in properties
			w.properties = (name, pv) :: w.properties;
		"gap" =>
			# Gap is used during layout, stored in properties
			w.properties = (name, pv) :: w.properties;
		}
	}
}

# Get property value by name
get_property_value(w: ref Widget, prop_name: string): ref PropertyValue
{
	for(l := w.properties; l != nil; l = tl l) {
		(name, pv) := hd l;
		if(name == prop_name)
			return pv;
	}
	return nil;
}

# ============================================================
# Phase 4: Layout Engine
# ============================================================

# Calculate layout for entire widget tree
calculate_layout(tree: ref WidgetTree, width: int, height: int): int
{
	if(tree == nil || tree.root == nil)
		return -1;

	# Start layout from root with full available space
	layout_widget(tree.root, 0, 0, width, height);

	# Build flat widget list for lookup
	tree.widgets = nil;
	build_widget_list(tree, tree.root);

	return 0;
}

# Build flat widget list from tree
build_widget_list(tree: ref WidgetTree, w: ref Widget)
{
	tree.widgets = w :: tree.widgets;
	for(c := w.children; c != nil; c = tl c)
		build_widget_list(tree, hd c);
}

# Layout a single widget and its children
layout_widget(w: ref Widget, x: int, y: int, width: int, height: int): (int, int)
{
	# Apply margin
	mtop := w.margin[0];
	mright := w.margin[1];
	mbottom := w.margin[2];
	mleft := w.margin[3];

	# Position widget with margin
	w.x = x + mleft;
	w.y = y + mtop;

	# Calculate available size inside margin
	avail_width := width - mleft - mright;
	avail_height := height - mtop - mbottom;

	# Set widget size (use specified or available)
	w.width = avail_width;
	w.height = avail_height;

	# Layout children based on widget type
	case w.type_id {
	ROW =>
		return layout_row(w, avail_width, avail_height);
	COLUMN =>
		return layout_column(w, avail_width, avail_height);
	CONTAINER =>
		return layout_container(w, avail_width, avail_height);
	* =>
		# Leaf widget - use specified size or default
		(wid, hei) := get_leaf_size(w);
		w.width = wid;
		w.height = hei;
		return (w.width, w.height);
	}
}

# Layout row widget (children arranged horizontally)
layout_row(w: ref Widget, width: int, height: int): (int, int)
{
	if(w.children == nil)
		return (width, height);

	# Get gap and flex properties
	gap := get_int_property(w, "gap", 0);

	# Calculate total flex and count non-flex children
	total_flex := 0.0;
	child_count := widget_list_len(w.children);
	fixed_count := 0;
	fixed_width := 0;

	for(children := w.children; children != nil; children = tl children) {
		child := hd children;
		flex_val := get_property_value(child, "flex");
		if(flex_val != nil && flex_val.ptype == PropNumber && flex_val.num_val > 0.0) {
			total_flex += flex_val.num_val;
		} else {
			fixed_count++;
			(cw, ch) := get_leaf_size(child);
			fixed_width += cw;
		}
	}

	# Calculate space available for flex children
	flex_space := width - fixed_width - (gap * (child_count - 1));
	if(flex_space < 0)
		flex_space = 0;

	# Layout children
	x := 0;
	for(children2 := w.children; children2 != nil; children2 = tl children2) {
		child := hd children2;

		# Calculate child width
		flex_val := get_property_value(child, "flex");
		child_width := 0;
		if(flex_val != nil && flex_val.ptype == PropNumber && flex_val.num_val > 0.0 && total_flex > 0.0) {
			child_width = int (real flex_space * (flex_val.num_val / total_flex));
		} else {
			(cw, ch) := get_leaf_size(child);
			child_width = cw;
		}

		# Get padding
		ptop := child.padding[0];
		pright := child.padding[1];
		pbottom := child.padding[2];
		pleft := child.padding[3];

		# Layout child
		inner_x := x + pleft;
		inner_y := ptop;
		inner_width := child_width - pleft - pright;
		inner_height := height - ptop - pbottom;

		layout_widget(child, inner_x, inner_y, inner_width, inner_height);

		x += child_width + gap;
	}

	return (width, height);
}

# Layout column widget (children arranged vertically)
layout_column(w: ref Widget, width: int, height: int): (int, int)
{
	if(w.children == nil)
		return (width, height);

	# Get gap property
	gap := get_int_property(w, "gap", 0);

	# Calculate total flex and count non-flex children
	total_flex := 0.0;
	child_count := widget_list_len(w.children);
	fixed_count := 0;
	fixed_height := 0;

	for(children := w.children; children != nil; children = tl children) {
		child := hd children;
		flex_val := get_property_value(child, "flex");
		if(flex_val != nil && flex_val.ptype == PropNumber && flex_val.num_val > 0.0) {
			total_flex += flex_val.num_val;
		} else {
			fixed_count++;
			(cw, ch) := get_leaf_size(child);
			fixed_height += ch;
		}
	}

	# Calculate space available for flex children
	flex_space := height - fixed_height - (gap * (child_count - 1));
	if(flex_space < 0)
		flex_space = 0;

	# Layout children
	y := 0;
	for(children2 := w.children; children2 != nil; children2 = tl children2) {
		child := hd children2;

		# Calculate child height
		flex_val := get_property_value(child, "flex");
		child_height := 0;
		if(flex_val != nil && flex_val.ptype == PropNumber && flex_val.num_val > 0.0 && total_flex > 0.0) {
			child_height = int (real flex_space * (flex_val.num_val / total_flex));
		} else {
			(cw, ch) := get_leaf_size(child);
			child_height = ch;
		}

		# Get padding
		ptop := child.padding[0];
		pright := child.padding[1];
		pbottom := child.padding[2];
		pleft := child.padding[3];

		# Layout child
		inner_x := pleft;
		inner_y := y + ptop;
		inner_width := width - pleft - pright;
		inner_height := child_height - ptop - pbottom;

		layout_widget(child, inner_x, inner_y, inner_width, inner_height);

		y += child_height + gap;
	}

	return (width, height);
}

# Layout container widget (children overlap/stack)
layout_container(w: ref Widget, width: int, height: int): (int, int)
{
	# All children get full size
	for(children := w.children; children != nil; children = tl children) {
		child := hd children;

		# Get padding
		ptop := child.padding[0];
		pright := child.padding[1];
		pbottom := child.padding[2];
		pleft := child.padding[3];

		# Layout child with full available space
		inner_x := pleft;
		inner_y := ptop;
		inner_width := width - pleft - pright;
		inner_height := height - ptop - pbottom;

		layout_widget(child, inner_x, inner_y, inner_width, inner_height);
	}

	return (width, height);
}

# Get size for leaf widget
get_leaf_size(w: ref Widget): (int, int)
{
	width := w.width;
	height := w.height;

	# Check for explicit size property
	w_prop := get_property_value(w, "width");
	if(w_prop != nil && w_prop.ptype == PropNumber)
		width = int w_prop.num_val;

	h_prop := get_property_value(w, "height");
	if(h_prop != nil && h_prop.ptype == PropNumber)
		height = int h_prop.num_val;

	# Use defaults if still zero
	if(width <= 0)
		width = 100;
	if(height <= 0)
		height = 30;

	return (width, height);
}

# Get integer property value with default
get_int_property(w: ref Widget, prop_name: string, default: int): int
{
	pv := get_property_value(w, prop_name);
	if(pv != nil && pv.ptype == PropNumber)
		return int pv.num_val;
	return default;
}

# ============================================================
# Phase 7: RC Script Integration
# ============================================================

# RCContext.new - create new RC context
RCContext.new(tree: ref WidgetTree): ref RCContext
{
	if(tree == nil)
		return nil;

	ctx := ref RCContext;
	ctx.tree = tree;
	ctx.output = "";
	ctx.variables = nil;
	ctx.toplevel = nil;
	return ctx;
}

# Set variable in RC context
RCContext.set_var(ctx: self ref RCContext, name: string, value: string)
{
	# Remove existing variable if present
	new_vars: list of (string, string) = nil;
	for(l := ctx.variables; l != nil; l = tl l) {
		(n, v) := hd l;
		if(n != name)
			new_vars = (n, v) :: new_vars;
	}
	ctx.variables = (name, value) :: new_vars;
}

# Get variable from RC context
RCContext.get_var(ctx: self ref RCContext, name: string): string
{
	for(l := ctx.variables; l != nil; l = tl l) {
		(n, v) := hd l;
		if(n == name)
			return v;
	}
	return "";
}

# Export widget properties to RC variables
RCContext.export_widget(ctx: self ref RCContext, w: ref Widget)
{
	if(w == nil)
		return;

	# Export common properties
	ctx.set_var("widget_id", w.id);
	ctx.set_var("widget_type", w.type_name);

	if(w.text != nil)
		ctx.set_var("widget_text", w.text);

	# Export colors
	ctx.set_var("background", sys->sprint("0x%08x", w.background));
	ctx.set_var("foreground", sys->sprint("0x%08x", w.foreground));

	# Export dimensions
	ctx.set_var("widget_x", sys->sprint("%d", w.x));
	ctx.set_var("widget_y", sys->sprint("%d", w.y));
	ctx.set_var("widget_width", sys->sprint("%d", w.width));
	ctx.set_var("widget_height", sys->sprint("%d", w.height));
}

# Import RC variables back to widget
RCContext.import_widget(ctx: self ref RCContext, w: ref Widget)
{
	if(w == nil)
		return;

	# Import text
	new_text := ctx.get_var("widget_text");
	if(new_text != nil && new_text != "")
		w.text = new_text;

	# Import colors
	bg_str := ctx.get_var("background");
	if(bg_str != nil && bg_str != "") {
		(val, rest) := str->toint(bg_str, 0);
		w.background = val;
	}

	fg_str := ctx.get_var("foreground");
	if(fg_str != nil && fg_str != "") {
		(val, rest) := str->toint(fg_str, 0);
		w.foreground = val;
	}
}

# Clear all variables
RCContext.clear_vars(ctx: self ref RCContext)
{
	ctx.variables = nil;
}

# Execute RC script
execute_rc_script(ctx: ref RCContext, script: string, w: ref Widget): string
{
	if(script == nil || script == "")
		return "";

	ctx.output = "";
	ctx.toplevel = w;

	# Export widget state
	ctx.export_widget(w);

	# Parse and execute script line by line
	lines: list of string = nil;
	(nil, tokens) := sys->tokenize(script, "\n");
	for(; tokens != nil; tokens = tl tokens) {
		lines = (hd tokens) :: lines;
	}

	# Execute in reverse (since we built list backwards)
	for(; lines != nil; lines = tl lines) {
		line := hd lines;

		if(line == nil || line == "" || line[0:1] == "#")
			continue;

		execute_rc_line(ctx, line);
	}

	# Import changes back to widget
	ctx.import_widget(w);

	return ctx.output;
}

# Execute a single RC line
execute_rc_line(ctx: ref RCContext, line: string)
{
	# Parse command: command arg1 arg2 ...
	(nil, parts) := sys->tokenize(line, " \t");
	if(parts == nil)
		return;

	cmd := hd parts;
	args := tl parts;

	case cmd {
	"echo" =>
		result := builtin_echo(ctx, args);
		if(result != nil && result != "")
			ctx.output = result;
	"get_widget_prop" =>
		result := builtin_get_prop(ctx, args);
		if(result != nil && result != "")
			ctx.output = result;
	"set_widget_prop" =>
		builtin_set_prop(ctx, args);
	"get_widget_text" =>
		result := builtin_get_text(ctx, args);
		if(result != nil && result != "")
			ctx.output = result;
	"set_widget_text" =>
		builtin_set_text(ctx, args);
	* =>
		ctx.output = sys->sprint("Unknown command: %s", cmd);
	}
}

# Built-in: echo <message>
builtin_echo(ctx: ref RCContext, args: list of string): string
{
	if(args == nil)
		return "";

	# Join arguments
	msg := "";
	for(; args != nil; args = tl args) {
		msg += hd args;
		if(tl args != nil)
			msg += " ";
	}
	return msg;
}

# Built-in: get_widget_prop <widget_id> <property_name>
builtin_get_prop(ctx: ref RCContext, args: list of string): string
{
	if(args == nil || tl args == nil)
		return "Usage: get_widget_prop <widget_id> <property_name>";

	widget_id := hd args;
	prop_name := hd (tl args);

	if(ctx.tree == nil)
		return "Error: No widget tree";

	widget := ctx.tree.find_by_id(widget_id);
	if(widget == nil)
		return sys->sprint("Error: Widget '%s' not found", widget_id);

	pv := get_property_value(widget, prop_name);
	if(pv == nil)
		return sys->sprint("Error: Property '%s' not found", prop_name);

	case pv.ptype {
	PropString =>
		return pv.str_val;
	PropNumber =>
		return sys->sprint("%g", pv.num_val);
	PropBoolean =>
		return sys->sprint("%d", pv.bool_val);
	PropColor =>
		return sys->sprint("0x%08x", pv.color_val);
	* =>
		return "?";
	}
}

# Built-in: set_widget_prop <widget_id> <property_name> <value>
builtin_set_prop(ctx: ref RCContext, args: list of string): string
{
	if(args == nil || tl args == nil || tl (tl args) == nil)
		return "Usage: set_widget_prop <widget_id> <property_name> <value>";

	widget_id := hd args;
	prop_name := hd (tl args);
	value := hd (tl (tl args));

	if(ctx.tree == nil)
		return "Error: No widget tree";

	widget := ctx.tree.find_by_id(widget_id);
	if(widget == nil)
		return sys->sprint("Error: Widget '%s' not found", widget_id);

	# Parse value and set property
	pv := parse_property_value(prop_name, value);

	# Update property in list
	new_props: list of (string, ref PropertyValue) = nil;
	found := 0;
	for(l := widget.properties; l != nil; l = tl l) {
		(n, v) := hd l;
		if(n == prop_name) {
			new_props = (prop_name, pv) :: new_props;
			found = 1;
		} else {
			new_props = (n, v) :: new_props;
		}
	}

	if(!found)
		new_props = (prop_name, pv) :: new_props;

	widget.properties = rev_prop_list(new_props);

	# Apply to widget fields
	apply_properties_to_widget(widget, widget.properties);

	return "";
}

# Built-in: get_widget_text <widget_id>
builtin_get_text(ctx: ref RCContext, args: list of string): string
{
	if(args == nil)
		return "Usage: get_widget_text <widget_id>";

	widget_id := hd args;

	if(ctx.tree == nil)
		return "Error: No widget tree";

	widget := ctx.tree.find_by_id(widget_id);
	if(widget == nil)
		return sys->sprint("Error: Widget '%s' not found", widget_id);

	if(widget.text == nil)
		return "";
	return widget.text;
}

# Built-in: set_widget_text <widget_id> <text>
builtin_set_text(ctx: ref RCContext, args: list of string): string
{
	if(args == nil || tl args == nil)
		return "Usage: set_widget_text <widget_id> <text>";

	widget_id := hd args;
	text := hd (tl args);

	if(ctx.tree == nil)
		return "Error: No widget tree";

	widget := ctx.tree.find_by_id(widget_id);
	if(widget == nil)
		return sys->sprint("Error: Widget '%s' not found", widget_id);

	widget.text = text;
	return "";
}
