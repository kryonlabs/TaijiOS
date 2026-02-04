implement Testsimple;

include "sys.m";
include "draw.m";
include "tk.m";
include "tkclient.m";

sys: Sys;
draw: Draw;
tk: Tk;
tkclient: Tkclient;

Testsimple: module
{
    init: fn(ctxt: ref Draw->Context, nil: list of string);
};

init(ctxt: ref Draw->Context, nil: list of string)
{
    sys = load Sys Sys->PATH;
    draw = load Draw Draw->PATH;
    tk = load Tk Tk->PATH;
    tkclient = load Tkclient Tkclient->PATH;

    tkclient->init();

    (toplevel, menubut) := tkclient->toplevel(ctxt, "", "Test Simple", 0);

    # Create a simple button
    tk->cmd(toplevel, ".b button -text TestButton");
    tk->cmd(toplevel, "pack .b");

    tk->cmd(toplevel, "update");
    tkclient->onscreen(toplevel, nil);
    tkclient->startinput(toplevel, "kbd"::"ptr"::nil);

    stop := chan of int;
    spawn tkclient->handler(toplevel, stop);
    while((msg := <-menubut) != "exit")
        tkclient->wmctl(toplevel, msg);
    stop <-= 1;
}
