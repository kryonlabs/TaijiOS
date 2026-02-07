implement Testdraw;

include "sys.m";
include "draw.m";

sys: Sys;
draw: Draw;
Display, Image: import draw;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;

	sys->print("Testdraw: Starting\n");

	disp := Display.allocate("");
	if(disp == nil) {
		sys->print("Testdraw: No display\n");
		return;
	}
	sys->print("Testdraw: Got display\n");

	screen := disp.image;
	if(screen == nil) {
		sys->print("Testdraw: No screen\n");
		return;
	}
	sys->print("Testdraw: Got screen\n");

	red := disp.color(16rFF0000);
	if(red == nil) {
		sys->print("Testdraw: No red\n");
		return;
	}
	sys->print("Testdraw: Got red\n");

	draw_rect := ((200,200), (300,300));
	screen.draw(draw_rect, red, nil, (0,0));
	sys->print("Testdraw: Drew red rect\n");

	blue := disp.color(16r0000FF);
	draw_rect2 := ((400,200), (500,300));
	screen.draw(draw_rect2, blue, nil, (0,0));
	sys->print("Testdraw: Drew blue rect\n");

	sys->print("Testdraw: Done\n");
}
