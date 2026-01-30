implement Krbview;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Context, Rect, Point, Display, Screen, Image: import draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include "tkclient.m";
	tkclient: Tkclient;

include "krbloader.m";
	krbloader: Krbloader;
	Widget, WidgetTree, RCContext, TEXT, BUTTON, INPUT, CHECKBOX, DROPDOWN, CONTAINER, ROW, COLUMN: import krbloader;

include "arg.m";

stderr: ref Sys->FD;
display: ref Display;

# Current file and widget tree
current_tree: ref WidgetTree;
current_filename: string;
current_krbfile: ref Krbloader->KrbFile;

# Event channel for widget events
widget_event_ch: chan of string;

Krbview: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	spawn realinit(ctxt, argv);
}

# ============================================================
# Phase 5 & 8: Widget Renderer and File Operations
# ============================================================

# Load and render a KRB file
load_and_render_file(t: ref Toplevel, filename: string): ref Krbloader->KrbFile
{
	if(filename == nil || filename == "") {
		show_error(t, "No filename specified");
		return nil;
	}

	status(t, "Loading: " + filename);

	# Load KRB file
	krbfile := krbloader->krbload(filename);
	if(krbfile == nil) {
		show_error(t, "Failed to load: " + krbloader->get_error());
		return nil;
	}

	# Build widget tree
	tree := krbloader->build_widget_tree(krbfile);
	if(tree == nil) {
		show_error(t, "Failed to build widget tree");
		return nil;
	}

	# Calculate layout
	err := krbloader->calculate_layout(tree, 800, 600);
	if(err != 0) {
		show_error(t, "Failed to calculate layout");
		return nil;
	}

	# Store current file and tree
	current_krbfile = krbfile;
	current_tree = tree;
	current_filename = filename;

	# Render widget tree
	render_widget_tree(t, tree);

	status(t, "Loaded: " + filename);

	return krbfile;
}

# Render widget tree to TK widgets
render_widget_tree(t: ref Toplevel, tree: ref WidgetTree)
{
	if(tree == nil || tree.root == nil)
		return;

	# Clear previous widgets
	tk->cmd(t, "catch {destroy .p.w}");
	tk->cmd(t, "frame .p.w");
	tk->cmd(t, "pack .p.w -side top -fill both -expand 1");

	# Recursively render widgets
	render_widget_recursive(t, tree.root, ".p.w", 0);

	# Bind events
	bind_widget_events(t, tree.root);
}

# Recursively render widgets
render_widget_recursive(t: ref Toplevel, w: ref Widget,
	parent_path: string, index: int): string
{
	if(w == nil)
		return "";

	# Create unique widget path
	widget_path := sys->sprint("%s.w%d", parent_path, index);

	# Create TK widget
	create_tk_widget(t, w, widget_path);

	# Apply properties
	apply_widget_properties(t, w, widget_path);

	# Pack widget
	pack_widget(t, w, widget_path);

	# Render children recursively
	child_index := 0;
	for(children := w.children; children != nil; children = tl children) {
		child := hd children;
		render_widget_recursive(t, child, widget_path, child_index);
		child_index++;
	}

	return widget_path;
}

# Create TK widget based on KRB widget type
create_tk_widget(t: ref Toplevel, w: ref Widget, path: string)
{
	case w.type_id {
	TEXT =>
		tk->cmd(t, "label " + path);
	BUTTON =>
		tk->cmd(t, "button " + path);
	INPUT =>
		tk->cmd(t, "entry " + path);
	CHECKBOX =>
		tk->cmd(t, "checkbutton " + path + " -variable " + path + "_var");
	DROPDOWN =>
		tk->cmd(t, "menubutton " + path + " -text {Select} -menu " + path + ".m");
		tk->cmd(t, "menu " + path + ".m");
	CONTAINER =>
		tk->cmd(t, "frame " + path);
	ROW =>
		tk->cmd(t, "frame " + path);
	COLUMN =>
		tk->cmd(t, "frame " + path);
	* =>
		# Default: frame
		tk->cmd(t, "frame " + path);
	}

	# Store TK widget path in widget
	w.tk_widget = path;
}

# Apply widget properties
apply_widget_properties(t: ref Toplevel, w: ref Widget, path: string)
{
	# Text content
	if(w.text != nil && w.text != "") {
		case w.type_id {
		TEXT or
		BUTTON or
		DROPDOWN =>
			tk->cmd(t, path + " configure -text {" + w.text + "}");
		}
	}

	# Background color
	if(w.background != 0) {
		color := krbloader->krb_to_tk_color(w.background);
		tk->cmd(t, path + " configure -background " + color);
	}

	# Foreground color
	if(w.foreground != 0) {
		color := krbloader->krb_to_tk_color(w.foreground);
		tk->cmd(t, path + " configure -foreground " + color);
	}

	# Font
	if(w.font_family != nil && w.font_family != "") {
		font_spec := sys->sprint("{%s} %d", w.font_family, w.font_size);
		tk->cmd(t, path + " configure -font {" + font_spec + "}");
	}

	# Size (for leaf widgets)
	if(w.children == nil) {
		if(w.width > 0)
			tk->cmd(t, path + " configure -width " + string w.width);
		if(w.height > 0)
			tk->cmd(t, path + " configure -height " + string w.height);
	}

	# Padding
	padx := w.padding[3] + w.padding[1];  # left + right
	pady := w.padding[0] + w.padding[2];  # top + bottom
	if(padx > 0 || pady > 0)
		tk->cmd(t, sys->sprint("%s configure -padx %d -pady %d", path, padx, pady));
}

# Pack widget with layout
pack_widget(t: ref Toplevel, w: ref Widget, path: string)
{
	# For containers, use place with absolute positioning
	if(w.parent != nil) {
		tk->cmd(t, sys->sprint("place %s -x %d -y %d -width %d -height %d",
			path, w.x, w.y, w.width, w.height));
	} else {
		# Root widget - pack to fill
		tk->cmd(t, "pack " + path + " -side top -fill both -expand 1");
	}
}

# ============================================================
# Phase 6: Event Handling
# ============================================================

# Bind widget events
bind_widget_events(t: ref Toplevel, w: ref Widget)
{
	if(w == nil)
		return;

	path := w.tk_widget;
	if(path == nil || path == "")
		return;

	# Button click
	if(w.type_id == BUTTON && w.on_click != nil && w.on_click != "") {
		tk->cmd(t, sys->sprint(
			"bind %s <Button-1> {send widget_event %s click %%x %%y}",
			path, w.id));
	}

	# Input change
	if(w.type_id == INPUT && w.on_change != nil && w.on_change != "") {
		tk->cmd(t, sys->sprint(
			"bind %s <KeyRelease> {send widget_event %s change %%W}",
			path, w.id));
	}

	# Recursively bind children
	for(children := w.children; children != nil; children = tl children)
		bind_widget_events(t, hd children);
}

# Handle widget event
handle_widget_event(t: ref Toplevel, event_data: string)
{
	if(event_data == nil || event_data == "")
		return;

	# Parse: "widget_id event_type x y"
	(nil, parts) := sys->tokenize(event_data, " ");
	if(parts == nil || len parts < 2)
		return;

	widget_id := hd parts;
	event_type := hd (tl parts);

	# Find widget
	if(current_tree == nil)
		return;

	widget := current_tree.find_by_id(widget_id);
	if(widget == nil) {
		status(t, "Event: " + event_type + " on unknown widget " + widget_id);
		return;
	}

	# Execute event handler
	execute_event_handler(t, widget, event_type, 0, 0);
}

# Execute event handler
execute_event_handler(t: ref Toplevel, w: ref Widget,
	event_type: string, x: int, y: int)
{
	script := "";
	case event_type {
	"click" =>
		script = w.on_click;
	"change" =>
		script = w.on_change;
	"key" =>
		script = w.on_key;
	}

	if(script == nil || script == "") {
		status(t, sys->sprint("Event: %s on %s (%s)", event_type, w.id, w.type_name));
		return;
	}

	# Execute RC script
	ctx := RCContext.new(current_tree);
	if(ctx == nil) {
		status(t, "Failed to create RC context");
		return;
	}
	result := krbloader->execute_rc_script(ctx, script, w);

	if(result != nil && result != "")
		status(t, result);
	else
		status(t, sys->sprint("Executed: %s on %s", event_type, w.id));

	# Re-render to show changes
	if(current_tree != nil)
		render_widget_tree(t, current_tree);
}

# ============================================================
# Phase 8: Interactive Features
# ============================================================

# Open file dialog
open_file_dialog(ctxt: ref Draw->Context): string
{
	# Use sh to run file dialog
	# For now, return empty string (not implemented)
	return "";
}

# Reload current file
reload_current_file(t: ref Toplevel)
{
	if(current_filename == nil || current_filename == "") {
		status(t, "No file to reload");
		return;
	}

	status(t, "Reloading: " + current_filename);
	load_and_render_file(t, current_filename);
}

# Show error dialog
show_error(t: ref Toplevel, msg: string)
{
	if(msg == nil)
		msg = "Unknown error";

	tk->cmd(t, "toplevel .error");
	tk->cmd(t, "wm title .error {Error}");
	tk->cmd(t, "label .error.msg -text {" + msg + "} -justify left -padx 20 -pady 20");
	tk->cmd(t, "button .error.ok -text OK -command {destroy .error}");
	tk->cmd(t, "pack .error.msg .error.ok -side top -fill x");
}

realinit(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "krbview: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	krbloader = load Krbloader "/dis/wm/krbloader.dis";
	if (krbloader == nil) {
		sys->fprint(sys->fildes(2), "krbview: cannot load krbloader: %r\n");
		raise "fail:load";
	}
	krbloader->init();

	sys->pctl(Sys->NEWPGRP, nil);
	tkclient->init();

	stderr = sys->fildes(2);
	display = ctxt.display;

	# Parse command-line arguments
	arg := load Arg Arg->PATH;
	if(arg == nil)
		badload(Arg->PATH);

	arg->init(argv);
	width := 800;
	height := 600;
	filename := "";

	while((c := arg->opt()) != 0)
		case c {
		'W' =>
			width = int arg->arg();
		'H' =>
			height = int arg->arg();
		* =>
			sys->fprint(stderr, "Usage: krbview [-W width] [-H height] [file.krb]\n");
			return;
		}
	argv = arg->argv();
	arg = nil;

	if(argv != nil)
		filename = hd argv;

	# Create main window
	(t, titlechan) := tkclient->toplevel(ctxt, "", "KRB Viewer", Tkclient->Hide);

	# Setup menu
	tk->cmd(t, "menu .m");
	tk->cmd(t, ".m add command -label Open -command {send cmd open}");
	tk->cmd(t, ".m add command -label Reload -command {send cmd reload}");
	tk->cmd(t, ".m add separator");
	tk->cmd(t, ".m add command -label Exit -command {send cmd exit}");

	# Setup main panel
	tk->cmd(t, "panel .p -width " + string width + " -height " + string height);
	tk->cmd(t, "pack .p -side top -fill both -expand 1");

	# Status bar
	tk->cmd(t, "label .status -text {KRB Viewer Ready} -anchor w");
	tk->cmd(t, "pack .status -side bottom -fill x");

	# Command channel
	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	# Widget event channel
	widget_event_ch = chan of string;
	tk->namechan(t, widget_event_ch, "widget_event");

	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	# Initialize state
	current_tree = nil;
	current_filename = "";
	current_krbfile = nil;

	# Load KRB file if specified
	if(filename != "") {
		load_and_render_file(t, filename);
	} else {
		status(t, "No file loaded - Use File → Open");
	}

	# Event loop
	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-titlechan =>
		tkclient->wmctl(t, s);

	s := <-cmd =>
		(nil, l) := sys->tokenize(s, " ");
		if(l != nil) {
			case (hd l) {
			"open" =>
				status(t, "Open file dialog not yet available");
				# TODO: Implement file dialog
			"reload" =>
				reload_current_file(t);
			"exit" =>
				status(t, "Exiting...");
				return;
			}
		}

	s := <-widget_event_ch =>
		handle_widget_event(t, s);
	}
}

badload(s: string)
{
	sys->fprint(stderr, "krbview: can't load %s: %r\n", s);
	raise "fail:load";
}

status(t: ref Toplevel, msg: string)
{
	tk->cmd(t, ".status configure -text {" + msg + "}");
}
