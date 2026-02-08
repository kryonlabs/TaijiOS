implement Graphics;

include "sys.m";
    sys: Sys;
include "draw.m";
    draw: Draw;
    Point, Rect, Image, Display, Screen, Font: import draw;
include "graphics.m";

# Zero point constant
ZP: Point;

# Initialize module
init()
{
    sys = load Sys Sys->PATH;
    draw = load Draw Draw->PATH;
    ZP = Point(0, 0);
}

# Create a new graphics context
create(screen: ref Image, display: ref Display): ref Context
{
    ctx := ref Context;
    ctx.screen = screen;
    ctx.display = display;
    ctx.fill_color = display.black;
    ctx.stroke_color = display.black;
    ctx.line_width = 1;
    ctx.font = nil;
    return ctx;
}

# Clear the screen with a color
clear(ctx: ref Context, color: ref Image)
{
    if (ctx.screen == nil || color == nil)
        return;
    ctx.screen.draw(ctx.screen.r, color, nil, ZP);
}

# Set fill color
setfill(ctx: ref Context, color: ref Image)
{
    if (color != nil)
        ctx.fill_color = color;
}

# Set stroke color
setstroke(ctx: ref Context, color: ref Image)
{
    if (color != nil)
        ctx.stroke_color = color;
}

# Set line width
setlinewidth(ctx: ref Context, width: int)
{
    ctx.line_width = width;
}

# Draw filled rectangle
rect(ctx: ref Context, x, y, w, h: int)
{
    if (ctx.screen == nil || ctx.fill_color == nil)
        return;
    r := Rect((x, y), (x + w, y + h));
    ctx.screen.draw(r, ctx.fill_color, nil, ZP);
}

# Draw filled circle (using fillellipse)
circle(ctx: ref Context, x, y, r: int)
{
    if (ctx.screen == nil || ctx.fill_color == nil)
        return;
    p := Point(x, y);
    ctx.screen.fillellipse(p, r, r, ctx.fill_color, ZP);
}

# Draw filled ellipse
ellipse(ctx: ref Context, x, y, rx, ry: int)
{
    if (ctx.screen == nil || ctx.fill_color == nil)
        return;
    p := Point(x, y);
    ctx.screen.fillellipse(p, rx, ry, ctx.fill_color, ZP);
}

# Draw line
line(ctx: ref Context, x1, y1, x2, y2: int)
{
    if (ctx.screen == nil || ctx.stroke_color == nil)
        return;
    p1 := Point(x1, y1);
    p2 := Point(x2, y2);
    ctx.screen.line(p1, p2, 0, 0, ctx.line_width, ctx.stroke_color, ZP);
}

# Draw text
text(ctx: ref Context, str: string, x, y: int)
{
    if (ctx.screen == nil || ctx.stroke_color == nil || str == nil)
        return;

    # Load font if needed
    if (ctx.font == nil && ctx.display != nil) {
        # Try default font path
        ctx.font = Font.open(ctx.display, "*default*");
        if (ctx.font == nil)
            ctx.font = Font.open(ctx.display, "/lib/font/bit/luc/latin1.8.font");
    }

    if (ctx.font == nil)
        return;

    p := Point(x, y);
    ctx.screen.text(p, ctx.stroke_color, p, ctx.font, str);
}

# Flush drawing to screen
flush(ctx: ref Context)
{
    if (ctx.screen != nil)
        ctx.screen.flush(draw->Flushnow);
}

# Helper: allocate a color from RGB values
rgb(display: ref Display, r, g, b: int): ref Image
{
    if (display == nil)
        return nil;
    return display.rgb(r, g, b);
}

# Helper: allocate a color from hex string (#rrggbb or #rgb)
hexcolor(display: ref Display, hex: string): ref Image
{
    if (display == nil || hex == nil || len hex < 2)
        return nil;

    # Skip leading # if present
    if (hex[0] == '#')
        hex = hex[1:];

    r: int;
    g: int;
    b: int;

    if (len hex == 3) {
        # Short form #rgb -> expand to #rrggbb
        r = hexval(hex[0]) * 17;
        g = hexval(hex[1]) * 17;
        b = hexval(hex[2]) * 17;
    } else if (len hex == 6) {
        # Full form #rrggbb
        r = hexval(hex[0]) * 16 + hexval(hex[1]);
        g = hexval(hex[2]) * 16 + hexval(hex[3]);
        b = hexval(hex[4]) * 16 + hexval(hex[5]);
    } else {
        return display.black;
    }

    return display.rgb(r, g, b);
}

# Helper: convert hex char to value
hexval(c: int): int
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return 0;
}
