Krbloader: module
{
	# Widget type constants (matching KRB format)
	CONTAINER: con 16r0001;
	ROW: con 16r0002;
	COLUMN: con 16r0003;
	TEXT: con 16r0400;
	BUTTON: con 16r0401;
	INPUT: con 16r0402;
	CHECKBOX: con 16r0403;
	DROPDOWN: con 16r0404;
	IMAGE: con 16r0405;
	TOGGLE: con 16r0406;
	SCROLLBAR: con 16r0407;
	PROGRESS: con 16r0408;
	SLIDER: con 16r0409;

	# Property type constants
	PropString: con 0;
	PropNumber: con 1;
	PropBoolean: con 2;
	PropColor: con 3;
	PropReference: con 4;
	PropArray: con 5;
	PropExpression: con 6;

	# Property value ADT
	PropertyValue: adt {
		ptype:	int;
		str_val:	string;
		num_val:	real;
		bool_val:	int;
		color_val:	int;	# 0xAABBGGRR format
		ref_val:	int;

		new_string:	fn(s: string): ref PropertyValue;
		new_number:	fn(r: real): ref PropertyValue;
		new_boolean:	fn(b: int): ref PropertyValue;
		new_color:	fn(c: int): ref PropertyValue;
	};

	# Widget ADT representing a KRB widget
	Widget: adt {
		id:		string;		# Widget ID
		type_id:	int;		# Widget type
		type_name:	string;		# Type name for debugging

		# Layout properties
		x:		int;
		y:		int;
		width:		int;
		height:		int;

		# Spacing (array of 4: top, right, bottom, left)
		padding:	array of int;
		margin:		array of int;

		# Style properties
		background:	int;
		foreground:	int;
		font_size:	int;
		font_family:	string;

		# Content
		text:		string;

		# Event handlers (RC script strings)
		on_click:	string;
		on_change:	string;
		on_key:		string;

		# Widget-specific properties
		properties:	list of (string, ref PropertyValue);

		# Tree structure
		children:	cyclic list of ref Widget;
		parent:		cyclic ref Widget;

		# TK widget path (assigned during rendering)
		tk_widget:	string;
	};

	# Widget tree container
	WidgetTree: adt {
		root:		ref Widget;
		widgets:	list of ref Widget;	# Flat list for easy lookup

		new:		fn(): ref WidgetTree;
		find_by_id:	fn(tree: self ref WidgetTree, id: string): ref Widget;
		add_widget:	fn(tree: self ref WidgetTree, w: ref Widget);
	};

	# KRB file handle (opaque)
	KrbFile: adt {
		data:	array of byte;
		size:	int;

		# Parsed sections
		header:	ref KrbHeader;
		strings:	array of string;
		widgets:	array of ref KrbWidgetInstance;
		properties:	array of ref KrbProperty;
		events:	array of ref KrbEvent;
	};

	# KRB file header (big-endian format)
	KrbHeader: adt {
		magic:	int;		# 0x4B52594E "KRYN"
		version_major:	int;
		version_minor:	int;
		flags:		int;
		reserved:	int;

		# Section counts
		style_count:	int;
		theme_count:	int;
		widget_def_count:	int;
		widget_instance_count:	int;
		property_count:	int;
		event_count:	int;
		script_count:	int;

		# Section offsets
		string_table_offset:	int;
		widget_defs_offset:	int;
		widget_instances_offset:	int;
		styles_offset:		int;
		themes_offset:		int;
		properties_offset:	int;
		events_offset:		int;
		scripts_offset:		int;

		# Section sizes
		string_table_size:	int;
		widget_defs_size:	int;
		widget_instances_size:	int;
		styles_size:		int;
		themes_size:		int;
		properties_size:	int;
		events_size:		int;
		scripts_size:		int;

		checksum:	int;
	};

	# Widget instance from KRB file
	KrbWidgetInstance: adt {
		id:		int;
		type_id:	int;
		parent_id:	int;
		style_id:	int;
		property_count:	int;
		child_count:	int;
		event_count:	int;
		flags:		int;
		id_str_offset:	int;
		properties_offset: int;
		children_offset:	int;
		events_offset:		int;
	};

	# Property definition
	KrbProperty: adt {
		id:		int;
		name_offset:	int;
		value_offset:	int;
	};

	# Event handler
	KrbEvent: adt {
		id:			int;
		event_type_offset:	int;
		handler_offset:	int;
		metadata_offset:	int;
	};

	# Load and parse a KRB file
	krbload:	fn(path: string): ref KrbFile;

	# Initialization (called by Limbo runtime)
	init:	fn();

	# Free KRB file resources
	free:	fn(krb: ref KrbFile);

	# Get string from string table
	get_string:	fn(krb: ref KrbFile, offset: int): string;

	# Get widget by ID
	find_widget:	fn(krb: ref KrbFile, id: int): ref KrbWidgetInstance;

	# Get root widget
	get_root:	fn(krb: ref KrbFile): ref KrbWidgetInstance;

	# Helper: get_u32 for reading big-endian uint32
	get_u32:	fn(data: array of byte, offset: int): int;

	# Error reporting
	get_error:	fn(): string;

	# Color conversion helper
	krb_to_tk_color:	fn(krb_color: int): string;

	# Widget tree builder (Phase 3)
	build_widget_tree:	fn(krb: ref KrbFile): ref WidgetTree;

	# Layout engine (Phase 4)
	calculate_layout:	fn(tree: ref WidgetTree, width: int, height: int): int;

	# Property helpers
	get_property_value:	fn(w: ref Widget, prop_name: string): ref PropertyValue;

	# Type name helper
	widget_type_name:	fn(type_id: int): string;

	# RC execution (Phase 7)
	RCContext: adt {
		tree:		ref WidgetTree;
		output:		string;
		variables:	list of (string, string);
		toplevel:	ref Widget;	# Triggering widget

		new:		fn(tree: ref WidgetTree): ref RCContext;
		set_var:	fn(ctx: self ref RCContext, name: string, value: string);
		get_var:	fn(ctx: self ref RCContext, name: string): string;
		export_widget:	fn(ctx: self ref RCContext, w: ref Widget);
		import_widget:	fn(ctx: self ref RCContext, w: ref Widget);
		clear_vars:	fn(ctx: self ref RCContext);
	};

	execute_rc_script:	fn(ctx: ref RCContext, script: string, w: ref Widget): string;

	# Built-in RC functions
	builtin_get_prop:	fn(ctx: ref RCContext, args: list of string): string;
	builtin_set_prop:	fn(ctx: ref RCContext, args: list of string): string;
	builtin_echo:	fn(ctx: ref RCContext, args: list of string): string;
	builtin_get_text:	fn(ctx: ref RCContext, args: list of string): string;
	builtin_set_text:	fn(ctx: ref RCContext, args: list of string): string;
};
