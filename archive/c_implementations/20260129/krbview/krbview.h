/*
 * krbview - KRB File Viewer with Native RC Execution
 *
 * A native application for viewing and interacting with Kryon Binary (KRB) files.
 * Supports full RC script execution and widget inspection.
 */

#ifndef KRBVIEW_H
#define KRBVIEW_H

#include "krb_runtime.h"
#include "krb_render.h"

/* Forward declarations */
typedef struct Eventctl Eventctl;

/*
 * Application state
 */
typedef struct {
    /* Window */
    Display *display;
    Screen *screen;
    Image *window;
    Rectangle winrect;
    int width, height;

    /* KRB content */
    KrbFile *krb_file;
    KrbRuntime *runtime;
    KrbDrawContext *draw_ctx;

    /* Event state */
    Eventctl *eventctl;
    KrbWidget *hovered_widget;
    KrbWidget *focused_widget;
    int running;

    /* RC integration */
    void *rc_vm;              /* RC shell VM (opaque) */
    int rc_debug;             /* Enable RC debug output */

    /* UI state */
    int show_inspector;       /* Show inspector panel */
    int inspector_width;      /* Width of inspector panel */

    /* Command line options */
    char *krb_path;
    int debug_mode;

} KrbviewApp;

/*
 * Application lifecycle
 */

/* Initialize application */
KrbviewApp* krbview_init(int argc, char **argv);

/* Main event loop */
int krbview_run(KrbviewApp *app);

/* Cleanup application */
void krbview_cleanup(KrbviewApp *app);

/*
 * Window management
 */

/* Create main window */
int krbview_create_window(KrbviewApp *app, int width, int height);

/* Resize window */
int krbview_resize_window(KrbviewApp *app, int width, int height);

/* Redraw window */
void krbview_redraw(KrbviewApp *app);

/*
 * Rendering
 */

/* Render entire KRB content */
void krbview_render(KrbviewApp *app);

/* Render inspector panel */
void krbview_render_inspector(KrbviewApp *app);

/*
 * Utilities
 */

/* Log message to status bar */
void krbview_log(KrbviewApp *app, const char *fmt, ...);

/* Show error message */
void krbview_error(KrbviewApp *app, const char *msg);

#endif /* KRBVIEW_H */
