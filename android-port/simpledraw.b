implement Simpledraw;

include "sys.m";
include "draw.m";

sys: Sys;
draw: Draw;
Display, Image: import draw;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;

	disp := Display.allocate(nil);
	if(disp == nil) {
		sys->print("No display\n");
		return;
	}

	red := disp.color(16rFF0000);
	blue := disp.color(16r0000FF);
	green := disp.color(16r00FF00);

	screen := disp.image;

	screen.draw(((100,100),(200,200)), red, nil, (0,0));
	screen.draw(((200,100),(300,200)), green, nil, (0,0));
	screen.draw(((300,100),(400,200)), blue, nil, (0,0));

	sys->print("Simpledraw: Drew colored rectangles\n");
}
