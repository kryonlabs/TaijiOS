# Lua VM - Draw Library
# Implements draw.* functions for Inferno
# Provides drawing operations: points, lines, circles, text, images

implement Lua_drawlib;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_drawlib.m";

sys: Sys;
print, sprint, fprint: import sys;

draw: Draw;
Display, Image, Font, Point, Rect, Chans: import draw;

luavm: Luavm;
State, Value, Table, TNIL, TNUMBER, TSTRING, TFUNCTION, TUSERDATA, TTABLE: import luavm;

# ====================================================================
# Module State
# ====================================================================

drawdisplay: ref Display;  # Set by wlua before use

# ====================================================================
# Helper Functions - Type Validation
# ====================================================================

# Check if argument is a DrawImage userdata
checkdrawimage(L: ref State; idx: int): ref DrawImage
{
	if(L == nil || idx < 0 || idx >= L.top)
		return nil;

	val := L.stack[L.top - idx];
	if(val == nil || val.ty != TUSERDATA)
		return nil;

	img := val.u;
	if(img == nil)
		return nil;

	# Try to cast to DrawImage
	dimg := ref DrawImage;
	dimg = img;
	if(dimg.img == nil)
		return nil;

	return dimg;
}

# Check if argument is a DrawFont userdata
checkdrawfont(L: ref State; idx: int): ref DrawFont
{
	if(L == nil || idx < 0 || idx >= L.top)
		return nil;

	val := L.stack[L.top - idx];
	if(val == nil || val.ty != TUSERDATA)
		return nil;

	f := val.u;
	if(f == nil)
		return nil;

	# Try to cast to DrawFont
	dfont := ref DrawFont;
	dfont = f;
	if(dfont.font == nil)
		return nil;

	return dfont;
}

# Check if argument is a number
checknumber(L: ref State; idx: int): (real, int)
{
	if(L == nil || idx < 0 || idx >= L.top)
		return (0.0, 0);

	val := L.stack[L.top - idx];
	if(val == nil || val.ty != TNUMBER)
		return (0.0, 0);

	return (val.n, 1);
}

# Check if argument is a string
checkstring(L: ref State; idx: int): (string, int)
{
	if(L == nil || idx < 0 || idx >= L.top)
		return (nil, 0);

	val := L.stack[L.top - idx];
	if(val == nil || val.ty != TSTRING)
		return (nil, 0);

	return (val.s, 1);
}

# Push DrawImage as userdata
pushdrawimage(L: ref State; img: ref DrawImage)
{
	if(L == nil || img == nil)
		return;

	val := ref Value;
	val.ty = TUSERDATA;
	val.u = img;
	luavm->pushvalue(L, val);
}

# Push DrawFont as userdata
pushdrawfont(L: ref State; font: ref DrawFont)
{
	if(L == nil || font == nil)
		return;

	val := ref Value;
	val.ty = TUSERDATA;
	val.u = font;
	luavm->pushvalue(L, val);
}

# ====================================================================
# Draw Functions
# ====================================================================

# draw.image(width, height) -> userdata
draw_image(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	# Get width and height
	(w, okw) := checknumber(L, 2);
	(h, okh) := checknumber(L, 1);

	if(!okw || !okh) {
		luavm->pushstring(L, "image: width and height must be numbers");
		return luavm->ERRRUN;
	}

	width := int w;
	height := int h;

	if(width <= 0 || height <= 0) {
		luavm->pushstring(L, "image: invalid dimensions");
		return luavm->ERRRUN;
	}

	if(drawdisplay == nil) {
		luavm->pushstring(L, "image: display not set");
		return luavm->ERRRUN;
	}

	# Create image
	r := Rect((0, 0), (width, height));
	chans := Draw->RGBA32;
	img := drawdisplay.newimage(r, chans, 0, Draw->Nofill);
	if(img == nil) {
		luavm->pushstring(L, "image: failed to create image");
		return luavm->ERRRUN;
	}

	# Wrap in DrawImage
	dimg := ref DrawImage;
	dimg.img = img;
	dimg.display = drawdisplay;
	dimg.width = width;
	dimg.height = height;
	dimg.chans = chans;

	pushdrawimage(L, dimg);
	return 1;
}

# draw.point(img, x, y, color)
draw_point(L: ref State): int
{
	if(L == nil || L.top < 4)
		return 0;

	dimg := checkdrawimage(L, 4);
	if(dimg == nil) {
		luavm->pushstring(L, "point: first argument must be image");
		return luavm->ERRRUN;
	}

	(x, okx) := checknumber(L, 3);
	(y, oky) := checknumber(L, 2);
	(c, okc) := checknumber(L, 1);

	if(!okx || !oky || !okc) {
		luavm->pushstring(L, "point: coordinates and color must be numbers");
		return luavm->ERRRUN;
	}

	# Create color image
	color := int c;
	colorimg := dimg.display.color(color);
	if(colorimg == nil) {
		luavm->pushstring(L, "point: invalid color");
		return luavm->ERRRUN;
	}

	# Draw point (1x1 rectangle)
	pt := Point(int x, int y);
	r := Rect(pt, pt.add((1, 1)));
	dimg.img.draw(r, colorimg, nil, (0, 0));

	return 0;
}

# draw.line(img, x1, y1, x2, y2, color)
draw_line(L: ref State): int
{
	if(L == nil || L.top < 6)
		return 0;

	dimg := checkdrawimage(L, 6);
	if(dimg == nil) {
		luavm->pushstring(L, "line: first argument must be image");
		return luavm->ERRRUN;
	}

	(x1, ok1) := checknumber(L, 5);
	(y1, ok2) := checknumber(L, 4);
	(x2, ok3) := checknumber(L, 3);
	(y2, ok4) := checknumber(L, 2);
	(c, ok5) := checknumber(L, 1);

	if(!ok1 || !ok2 || !ok3 || !ok4 || !ok5) {
		luavm->pushstring(L, "line: coordinates and color must be numbers");
		return luavm->ERRRUN;
	}

	# Create color image
	color := int c;
	colorimg := dimg.display.color(color);
	if(colorimg == nil) {
		luavm->pushstring(L, "line: invalid color");
		return luavm->ERRRUN;
	}

	# Draw line (simple implementation using endpoints)
	p1 := Point(int x1, int y1);
	p2 := Point(int x2, int y2);

	# Bresenham's line algorithm
	dx := p2.x - p1.x;
	dy := p2.y - p1.y;
	steps := abs(dx) > abs(dy) ? abs(dx) : abs(dy);

	xinc := real dx / real steps;
	yinc := real dy / real steps;

	x := real p1.x;
	y := real p1.y;

	for(i := 0; i <= steps; i++) {
		pt := Point(int x, int y);
		r := Rect(pt, pt.add((1, 1)));
		dimg.img.draw(r, colorimg, nil, (0, 0));
		x += xinc;
		y += yinc;
	}

	return 0;
}

# draw.rect(img, x, y, width, height, color)
draw_rect(L: ref State): int
{
	if(L == nil || L.top < 6)
		return 0;

	dimg := checkdrawimage(L, 6);
	if(dimg == nil) {
		luavm->pushstring(L, "rect: first argument must be image");
		return luavm->ERRRUN;
	}

	(x, ok1) := checknumber(L, 5);
	(y, ok2) := checknumber(L, 4);
	(w, ok3) := checknumber(L, 3);
	(h, ok4) := checknumber(L, 2);
	(c, ok5) := checknumber(L, 1);

	if(!ok1 || !ok2 || !ok3 || !ok4 || !ok5) {
		luavm->pushstring(L, "rect: coordinates, dimensions and color must be numbers");
		return luavm->ERRRUN;
	}

	# Create color image
	color := int c;
	colorimg := dimg.display.color(color);
	if(colorimg == nil) {
		luavm->pushstring(L, "rect: invalid color");
		return luavm->ERRRUN;
	}

	# Draw rectangle
	min := Point(int x, int y);
	max := Point(int x + int w, int y + int h);
	r := Rect(min, max);
	dimg.img.draw(r, colorimg, nil, (0, 0));

	return 0;
}

# draw.circle(img, x, y, radius, color)
draw_circle(L: ref State): int
{
	if(L == nil || L.top < 5)
		return 0;

	dimg := checkdrawimage(L, 5);
	if(dimg == nil) {
		luavm->pushstring(L, "circle: first argument must be image");
		return luavm->ERRRUN;
	}

	(x, ok1) := checknumber(L, 4);
	(y, ok2) := checknumber(L, 3);
	(r, ok3) := checknumber(L, 2);
	(c, ok4) := checknumber(L, 1);

	if(!ok1 || !ok2 || !ok3 || !ok4) {
		luavm->pushstring(L, "circle: coordinates, radius and color must be numbers");
		return luavm->ERRRUN;
	}

	# Create color image
	color := int c;
	colorimg := dimg.display.color(color);
	if(colorimg == nil) {
		luavm->pushstring(L, "circle: invalid color");
		return luavm->ERRRUN;
	}

	# Draw filled circle using midpoint algorithm
	cx := int x;
	cy := int y;
	radius := int r;

	xoff := 0;
	yoff := radius;
	err := 1 - radius;

	while(xoff <= yoff) {
		# Draw horizontal lines for filled circle
		dimg.img.draw(Rect((cx - xoff, cy + yoff), (cx + xoff + 1, cy + yoff + 1)), colorimg, nil, (0, 0));
		dimg.img.draw(Rect((cx - xoff, cy - yoff), (cx + xoff + 1, cy - yoff + 1)), colorimg, nil, (0, 0));
		dimg.img.draw(Rect((cx - yoff, cy + xoff), (cx + yoff + 1, cy + xoff + 1)), colorimg, nil, (0, 0));
		dimg.img.draw(Rect((cx - yoff, cy - xoff), (cx + yoff + 1, cy - xoff + 1)), colorimg, nil, (0, 0));

		xoff++;
		if(err < 0) {
			err += 2 * xoff + 1;
		} else {
			yoff--;
			err += 2 * (xoff - yoff) + 1;
		}
	}

	return 0;
}

# draw.text(img, str, x, y, font, color)
draw_text(L: ref State): int
{
	if(L == nil || L.top < 6)
		return 0;

	dimg := checkdrawimage(L, 6);
	if(dimg == nil) {
		luavm->pushstring(L, "text: first argument must be image");
		return luavm->ERRRUN;
	}

	(str, oks) := checkstring(L, 5);
	(x, ok1) := checknumber(L, 4);
	(y, ok2) := checknumber(L, 3);
	if(!oks || !ok1 || !ok2) {
		luavm->pushstring(L, "text: string and coordinates required");
		return luavm->ERRRUN;
	}

	dfont := checkdrawfont(L, 2);
	if(dfont == nil) {
		luavm->pushstring(L, "text: font argument must be font userdata");
		return luavm->ERRRUN;
	}

	(c, okc) := checknumber(L, 1);
	if(!okc) {
		luavm->pushstring(L, "text: color must be a number");
		return luavm->ERRRUN;
	}

	# Create color image
	color := int c;
	colorimg := dimg.display.color(color);
	if(colorimg == nil) {
		luavm->pushstring(L, "text: invalid color");
		return luavm->ERRRUN;
	}

	# Draw text
	pt := Point(int x, int y);
	dimg.img.text(pt, colorimg, pt, dfont.font, str);

	return 0;
}

# draw.font(name, size) -> userdata
draw_font(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	(name, okn) := checkstring(L, 2);
	(s, oks) := checknumber(L, 1);

	if(!okn || !oks) {
		luavm->pushstring(L, "font: name and size must be provided");
		return luavm->ERRRUN;
	}

	if(drawdisplay == nil) {
		luavm->pushstring(L, "font: display not set");
		return luavm->ERRRUN;
	}

	# Load font
	fontname := name;
	size := int s;

	font := drawdisplay.open(fontname);
	if(font == nil) {
		# Try default font
		font = drawdisplay.open("*default*");
		if(font == nil) {
			luavm->pushstring(L, "font: failed to load font");
			return luavm->ERRRUN;
		}
	}

	# Wrap in DrawFont
	dfont := ref DrawFont;
	dfont.font = font;
	dfont.display = drawdisplay;
	dfont.name = fontname;
	dfont.size = size;

	pushdrawfont(L, dfont);
	return 1;
}

# draw.color(r, g, b) -> number
draw_color(L: ref State): int
{
	if(L == nil || L.top < 3)
		return 0;

	(r, okr) := checknumber(L, 3);
	(g, okg) := checknumber(L, 2);
	(b, okb) := checknumber(L, 1);

	if(!okr || !okg || !okb) {
		luavm->pushstring(L, "color: r, g, b must be numbers");
		return luavm->ERRRUN;
	}

	# Create color value: 0xRRGGBBFF ( RGBA32 format)
	red := int r & 16rFF;
	green := int g & 16rFF;
	blue := int b & 16rFF;
	color := (red << 24) | (green << 16) | (blue << 8) | 16rFF;

	luavm->pushnumber(L, real color);
	return 1;
}

# draw.save(img, path)
draw_save(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	dimg := checkdrawimage(L, 2);
	if(dimg == nil) {
		luavm->pushstring(L, "save: first argument must be image");
		return luavm->ERRRUN;
	}

	(path, ok) := checkstring(L, 1);
	if(!ok) {
		luavm->pushstring(L, "save: path must be string");
		return luavm->ERRRUN;
	}

	# Write image to file
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil) {
		luavm->pushstring(L, sprint("save: cannot create %s: %r", path));
		return luavm->ERRRUN;
	}

	# Simple bitmap write (could be improved with proper format)
	err := dimg.img.write(fd);
	fd.close();

	if(err != 0) {
		luavm->pushstring(L, sprint("save: write failed"));
		return luavm->ERRRUN;
	}

	return 0;
}

# draw.load(path) -> userdata
draw_load(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	(path, ok) := checkstring(L, 1);
	if(!ok) {
		luavm->pushstring(L, "load: path must be string");
		return luavm->ERRRUN;
	}

	if(drawdisplay == nil) {
		luavm->pushstring(L, "load: display not set");
		return luavm->ERRRUN;
	}

	# Read image from file
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		luavm->pushstring(L, sprint("load: cannot open %s: %r", path));
		return luavm->ERRRUN;
	}

	img := drawdisplay.readimage(fd);
	fd.close();

	if(img == nil) {
		luavm->pushstring(L, sprint("load: failed to read image"));
		return luavm->ERRRUN;
	}

	# Wrap in DrawImage
	dimg := ref DrawImage;
	dimg.img = img;
	dimg.display = drawdisplay;
	dimg.width = img.r.dx();
	dimg.height = img.r.dy();
	dimg.chans = img.chans;

	pushdrawimage(L, dimg);
	return 1;
}

# ====================================================================
# Library Registration
# ====================================================================

# Set library function
setlibfunc(lib: ref Table; name: string; func: fn(L: ref State): int)
{
	if(lib == nil)
		return;

	f := ref luavm->Function;
	f.isc = 1;
	f.cfunc = func;
	f.upvals = nil;
	f.env = nil;

	key := ref Value;
	key.ty = TSTRING;
	key.s = name;

	val := ref Value;
	val.ty = TFUNCTION;
	val.f = f;

	luavm->settablevalue(lib, key, val);
}

# Open draw library
opendraw(L: ref State): int
{
	if(L == nil)
		return 0;

	# Create draw library table
	lib := luavm->createtable(0, 10);

	# Register functions
	setlibfunc(lib, "image", draw_image);
	setlibfunc(lib, "point", draw_point);
	setlibfunc(lib, "line", draw_line);
	setlibfunc(lib, "rect", draw_rect);
	setlibfunc(lib, "circle", draw_circle);
	setlibfunc(lib, "text", draw_text);
	setlibfunc(lib, "font", draw_font);
	setlibfunc(lib, "color", draw_color);
	setlibfunc(lib, "save", draw_save);
	setlibfunc(lib, "load", draw_load);

	# Set global 'draw'
	val := ref Value;
	val.ty = TTABLE;
	val.t = lib;

	key := ref Value;
	key.ty = TSTRING;
	key.s = "draw";

	luavm->settablevalue(L.global, key, val);

	return 0;
}

# Set display context
setdisplay(d: ref Display)
{
	drawdisplay = d;
}

# Process timers (placeholder for future use)
processtimers()
{
	# No timers in draw library
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	draw = load Draw Draw;
	luavm = load Luavm Luavm;

	if(luavm == nil)
		return "cannot load Luavm";

	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Draw Library",
		"Drawing operations for Inferno",
	};
}
