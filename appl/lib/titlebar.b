implement Titlebar;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "titlebar.m";

# Title bar color indices (matching tk.h)
TITLE_BG_ACTIVE := 17;		# TkCtitlebgnd
TITLE_BG_INACTIVE := 18;	# TkCtitlebginactive
TITLE_FG := 19;		# TkCtitlefgnd
TITLE_BORDER := 20;		# TkCtitleborder
TITLE_BUTTON := 21;		# TkCtitlebutton

# Cached colors
title_bg: string;
title_inactive: string;
title_fg: string;

# Track all titlebars for refresh
titlebars: list of ref Tk->Toplevel;

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
}

# Read a theme color from #w/{idx}
get_title_color(idx: int): string
{
	fd := sys->open(sys->sprint("#w/%d", idx), Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[32] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	s := string buf[0:n];
	# Trim trailing whitespace
	while(len s > 0 && (s[len s-1] == '\n' || s[len s-1] == '\r' || s[len s-1] == ' '))
		s = s[0:len s-1];
	return s;
}

# Load theme colors, with fallback defaults
load_title_colors()
{
	title_bg = get_title_color(TITLE_BG_ACTIVE);
	if(title_bg == nil)
		title_bg = "#4169E1FF";	# Royal blue default

	title_inactive = get_title_color(TITLE_BG_INACTIVE);
	if(title_inactive == nil)
		title_inactive = "#D3D3D3FF";	# Light gray default

	title_fg = get_title_color(TITLE_FG);
	if(title_fg == nil)
		title_fg = "#FFFFFFFF";	# White default
}

new(top: ref Tk->Toplevel, buts: int): chan of string
{
	ctl := chan of string;
	tk->namechan(top, ctl, "wm_title");

	if(buts & Plain)
		return ctl;

	# Load theme colors
	load_title_colors();

	# Track this titlebar for refresh
	titlebars = top :: titlebars;

	# Build title bar with theme colors
	cmd(top, sys->sprint("frame .Wm_t -bg %s -borderwidth 1", title_inactive));
	cmd(top, sys->sprint("label .Wm_t.title -anchor w -bg %s -fg %s", title_inactive, title_fg));
	cmd(top, "button .Wm_t.e -bitmap exit.bit -command {send wm_title exit} -takefocus 0");
	cmd(top, "pack .Wm_t.e -side right");
	cmd(top, "bind .Wm_t <Button-1> {send wm_title move %X %Y}");
	cmd(top, "bind .Wm_t <Double-Button-1> {send wm_title lower .}");
	cmd(top, "bind .Wm_t <Motion-Button-1> {}");
	cmd(top, "bind .Wm_t <Motion> {}");
	cmd(top, "bind .Wm_t.title <Button-1> {send wm_title move %X %Y}");
	cmd(top, "bind .Wm_t.title <Double-Button-1> {send wm_title lower .}");
	cmd(top, "bind .Wm_t.title <Motion-Button-1> {}");
	cmd(top, "bind .Wm_t.title <Motion> {}");
	cmd(top, sys->sprint("bind . <FocusIn> {.Wm_t configure -bg %s;"+
		".Wm_t.title configure -bg %s;update}", title_bg, title_bg));
	cmd(top, sys->sprint("bind . <FocusOut> {.Wm_t configure -bg %s;"+
		".Wm_t.title configure -bg %s;update}", title_inactive, title_inactive));

	if(buts & OK)
		cmd(top, "button .Wm_t.ok -bitmap ok.bit"+
			" -command {send wm_title ok} -takefocus 0; pack .Wm_t.ok -side right");

	if(buts & Hide)
		cmd(top, "button .Wm_t.top -bitmap task.bit"+
			" -command {send wm_title task} -takefocus 0; pack .Wm_t.top -side right");

	if(buts & Resize)
		cmd(top, "button .Wm_t.m -bitmap maxf.bit"+
			" -command {send wm_title size} -takefocus 0; pack .Wm_t.m -side right");

	if(buts & Help)
		cmd(top, "button .Wm_t.h -bitmap help.bit"+
			" -command {send wm_title help} -takefocus 0; pack .Wm_t.h -side right");

	# pack the title last so it gets clipped first
	cmd(top, "pack .Wm_t.title -side left");
	cmd(top, "pack .Wm_t -fill x");

	return ctl;
}

title(top: ref Tk->Toplevel): string
{
	if(tk->cmd(top, "winfo class .Wm_t.title")[0] != '!')
		return cmd(top, ".Wm_t.title cget -text");
	return nil;
}
	
settitle(top: ref Tk->Toplevel, t: string): string
{
	s := title(top);
	tk->cmd(top, ".Wm_t.title configure -text '" + t);
	return s;
}

sendctl(top: ref Tk->Toplevel, c: string)
{
	cmd(top, "send wm_title " + c);
}

minsize(top: ref Tk->Toplevel): Point
{
	buts := array[] of {"e", "ok", "top", "m", "h"};
	r := tk->rect(top, ".", Tk->Border);
	r.min.x = r.max.x;
	r.max.y = r.min.y;
	for(i := 0; i < len  buts; i++){
		br := tk->rect(top, ".Wm_t." + buts[i], Tk->Border);
		if(br.dx() > 0)
			r = r.combine(br);
	}
	r.max.x += tk->rect(top, ".Wm_t." + buts[0], Tk->Border).dx();
	return r.size();
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "wmclient: tk error %s on '%s'\n", e, s);
	return e;
}

# Refresh a single titlebar with new theme colors
refresh(top: ref Tk->Toplevel)
{
	# Check if this toplevel has a titlebar
	if(tk->cmd(top, "winfo exists .Wm_t")[0] == '!')
		return;  # No titlebar

	# Reload theme colors
	load_title_colors();

	# Update frame and title label colors
	cmd(top, sys->sprint(".Wm_t configure -bg %s", title_inactive));
	cmd(top, sys->sprint(".Wm_t.title configure -bg %s -fg %s", title_inactive, title_fg));

	# Update focus bindings with new colors
	cmd(top, sys->sprint("bind . <FocusIn> {.Wm_t configure -bg %s;"+
		".Wm_t.title configure -bg %s;update}", title_bg, title_bg));
	cmd(top, sys->sprint("bind . <FocusOut> {.Wm_t configure -bg %s;"+
		".Wm_t.title configure -bg %s;update}", title_inactive, title_inactive));

	cmd(top, "update");
}

# Refresh all tracked titlebars
refresh_all()
{
	for(l := titlebars; l != nil; l = tl l)
		refresh(hd l);
}
