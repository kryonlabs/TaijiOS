implement TestThemes;

TestThemes: module
{
    init: fn(ctxt: ref Draw->Context, argv: list of string);
};

include "sys.m";
    sys: Sys;
include "draw.m";

init(ctxt: ref Draw->Context, argv: list of string)
{
    sys = load Sys Sys->PATH;
    
    fd := sys->open("#w/list", Sys->OREAD);
    if(fd == nil)
        return;
    
    buf := array[1024] of byte;
    n := sys->read(fd, buf, len buf);
    if(n > 0) {
        sys->print("%s", string buf[:n]);
    }
}
