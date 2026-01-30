/*
 * krbview - KRB File Viewer with Native RC Execution
 *
 * Main application entry point and event loop.
 */

#define _BSD_SOURCE
#define _DEFAULT_SOURCE
#include <lib9.h>
#include "krbview.h"
#include "krbview_loader.h"
#include "krbview_renderer.h"
#include "krbview_events.h"
#include "krbview_rc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Default window size */
#define DEFAULT_WIDTH 1024
#define DEFAULT_HEIGHT 768

/* Status bar height */
#define STATUS_BAR_HEIGHT 24

static void print_usage(const char *progname)
{
    fprintf(stderr, "Usage: %s [options] <file.krb>\n", progname);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -W <width>     Window width (default: %d)\n", DEFAULT_WIDTH);
    fprintf(stderr, "  -H <height>    Window height (default: %d)\n", DEFAULT_HEIGHT);
    fprintf(stderr, "  -debug         Enable debug mode\n");
    fprintf(stderr, "  -inspector     Show inspector panel\n");
    fprintf(stderr, "  -rc-debug      Enable RC debug output\n");
    fprintf(stderr, "  -h             Show this help\n");
}

/*
 * Initialize application
 */
KrbviewApp* krbview_init(int argc, char **argv)
{
    KrbviewApp *app;
    int width = DEFAULT_WIDTH;
    int height = DEFAULT_HEIGHT;
    char *krb_path = NULL;
    int i;

    app = (KrbviewApp*)calloc(1, sizeof(KrbviewApp));
    if (!app) {
        fprintf(stderr, "Failed to allocate application\n");
        return NULL;
    }

    /* Parse command line arguments */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-W") == 0 && i + 1 < argc) {
            width = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-H") == 0 && i + 1 < argc) {
            height = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-debug") == 0) {
            app->debug_mode = 1;
        } else if (strcmp(argv[i], "-inspector") == 0) {
            app->show_inspector = 1;
        } else if (strcmp(argv[i], "-rc-debug") == 0) {
            app->rc_debug = 1;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "-help") == 0) {
            print_usage(argv[0]);
            free(app);
            return NULL;
        } else if (argv[i][0] != '-') {
            krb_path = argv[i];
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            free(app);
            return NULL;
        }
    }

    if (!krb_path) {
        fprintf(stderr, "Error: No KRB file specified\n");
        print_usage(argv[0]);
        free(app);
        return NULL;
    }

    app->krb_path = krb_path;
    app->width = width;
    app->height = height;
    app->running = 1;
    app->inspector_width = 300;

    /* Initialize display */
    app->display = initdisplay(nil, nil, nil);
    if (app->display == nil) {
        fprintf(stderr, "Failed to initialize display\n");
        free(app);
        return NULL;
    }

    /* Get screen from display */
    /* Note: display->image is an Image*, but we treat it as Screen* for allocwindow */
    /* This is how the Inferno API works - the screen parameter is actually used as an Image */
    app->screen = (Screen*)app->display->image;
    if (app->screen == nil) {
        fprintf(stderr, "Failed to get screen\n");
        krbview_cleanup(app);
        return NULL;
    }

    /* Load KRB file */
    if (app->debug_mode) {
        fprintf(stderr, "Loading KRB file: %s\n", app->krb_path);
    }

    app->krb_file = krbview_loader_load(app->krb_path);
    if (!app->krb_file) {
        fprintf(stderr, "Error: %s\n", krbview_loader_get_error());
        krbview_cleanup(app);
        return NULL;
    }

    /* Initialize runtime */
    app->runtime = krb_runtime_init(app->krb_file);
    if (!app->runtime) {
        fprintf(stderr, "Failed to initialize KRB runtime\n");
        krbview_cleanup(app);
        return NULL;
    }

    /* Initialize RC shell integration */
    /* Disabled for now - requires full Inferno interpreter runtime */
    app->rc_vm = NULL;
    /*
    app->rc_vm = krbview_rc_init(app->runtime);
    if (!app->rc_vm) {
        fprintf(stderr, "Warning: RC shell integration failed\n");
        // Continue without RC
    }
    */

    /* Create window */
    if (!krbview_create_window(app, width, height)) {
        fprintf(stderr, "Failed to create window\n");
        krbview_cleanup(app);
        return NULL;
    }

    /* Initialize event handling */
    if (krbview_events_init(app->display, &app->eventctl) != 0) {
        fprintf(stderr, "Failed to initialize event handling\n");
        krbview_cleanup(app);
        return NULL;
    }

    /* Calculate initial layout */
    krb_runtime_calculate_layout(app->runtime, width, height - STATUS_BAR_HEIGHT);

    if (app->debug_mode) {
        fprintf(stderr, "krbview initialized successfully\n");
        fprintf(stderr, "Title: %s\n", krbview_loader_get_title(app->krb_file));
        fprintf(stderr, "Version: %s\n", krbview_loader_get_version(app->krb_file));
    }

    return app;
}

/*
 * Create main window
 */
int krbview_create_window(KrbviewApp *app, int width, int height)
{
    Rectangle r;

    if (!app || !app->display) {
        return 0;
    }

    /* Create window rectangle */
    r.min.x = 0;
    r.min.y = 0;
    r.max.x = width;
    r.max.y = height;

    /* Allocate window image */
    app->window = allocwindow(app->screen, r, Refbackup, DWhite);
    if (!app->window) {
        fprintf(stderr, "Failed to allocate window\n");
        return 0;
    }

    app->winrect = r;

    /* Initialize renderer */
    app->draw_ctx = krbview_renderer_init(app->runtime,
                                         app->display,
                                         app->screen,
                                         app->window);
    if (!app->draw_ctx) {
        fprintf(stderr, "Failed to initialize renderer\n");
        return 0;
    }

    return 1;
}

/*
 * Resize window
 */
int krbview_resize_window(KrbviewApp *app, int width, int height)
{
    if (!app) {
        return 0;
    }

    /* TODO: Implement window resizing */
    /* This would require reallocating the window image */
    app->width = width;
    app->height = height;

    /* Recalculate layout */
    krb_runtime_calculate_layout(app->runtime, width, height - STATUS_BAR_HEIGHT);

    return 1;
}

/*
 * Redraw window
 */
void krbview_redraw(KrbviewApp *app)
{
    if (!app || !app->draw_ctx) {
        return;
    }

    /* Clear window with background */
    krbview_renderer_clear(app->draw_ctx, 0x191970FF);  /* Dark blue */

    /* Render KRB content */
    krbview_renderer_render(app->draw_ctx, app->runtime->root);

    /* Draw status bar */
    Rectangle status_rect;
    status_rect.min.x = 0;
    status_rect.min.y = app->height - STATUS_BAR_HEIGHT;
    status_rect.max.x = app->width;
    status_rect.max.y = app->height;

    uint32_t status_bg = 0x000000FF;  /* Black */
    krb_draw_rect(app->draw_ctx, status_rect, status_bg);

    /* Draw status text */
    if (app->rc_vm) {
        /*
        const char *output = krbview_rc_get_output(app->rc_vm);
        if (output && strlen(output) > 0) {
            Point text_pos;
            text_pos.x = 10;
            text_pos.y = app->height - STATUS_BAR_HEIGHT + 16;
            krb_draw_text(app->draw_ctx, text_pos, output, 0xFFFFFFFF,
                         app->draw_ctx->default_font);
        }
        */
        Point text_pos;
        text_pos.x = 10;
        text_pos.y = app->height - STATUS_BAR_HEIGHT + 16;
        krb_draw_text(app->draw_ctx, text_pos, "KRB Viewer - RC disabled", 0xFFFFFFFF,
                     app->draw_ctx->default_font);
    }

    /* Flush drawing */
    draw(app->window, app->window->r, app->window, nil, ZP);
}

/*
 * Main event loop
 */
int krbview_run(KrbviewApp *app)
{
    KrbviewEvent event;

    if (!app) {
        return -1;
    }

    /* Initial render */
    krbview_redraw(app);

    /* Event loop */
    while (app->running) {
        /* Read event */
        int result = krbview_events_read(app->eventctl, &event);

        if (result < 0) {
            fprintf(stderr, "Event read error\n");
            break;
        }

        if (result == 0) {
            /* No event (shouldn't happen with blocking read) */
            continue;
        }

        /* Handle quit */
        if (event.type == KRBVIEW_EVENT_QUIT) {
            app->running = 0;
            break;
        }

        /* Process event */
        krbview_events_process(app->runtime, &event);

        /* Redraw */
        krbview_redraw(app);
    }

    return 0;
}

/*
 * Cleanup application
 */
void krbview_cleanup(KrbviewApp *app)
{
    if (!app) {
        return;
    }

    /* Cleanup RC VM */
    if (app->rc_vm) {
        krbview_rc_cleanup(app->rc_vm);
    }

    /* Cleanup renderer */
    if (app->draw_ctx) {
        krbview_renderer_cleanup(app->draw_ctx);
    }

    /* Cleanup runtime */
    if (app->runtime) {
        krb_runtime_cleanup(app->runtime);
    }

    /* Cleanup KRB file */
    if (app->krb_file) {
        krbview_loader_free(app->krb_file);
    }

    /* Cleanup event handling */
    if (app->eventctl) {
        krbview_events_cleanup(app->eventctl);
    }

    /* Free window */
    if (app->window) {
        freeimage(app->window);
    }

    /* Close display */
    if (app->display) {
        closedisplay(app->display);
    }

    free(app);
}

/*
 * Log message to status bar
 */
void krbview_log(KrbviewApp *app, const char *fmt, ...)
{
    va_list args;

    if (!app || !app->rc_vm) {
        return;
    }

    char buffer[1024];
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    /* Append to output buffer */
    /* TODO: Implement proper logging */
    fprintf(stderr, "%s\n", buffer);
}

/*
 * Show error message
 */
void krbview_error(KrbviewApp *app, const char *msg)
{
    if (!app) {
        return;
    }

    fprintf(stderr, "Error: %s\n", msg);
}

/*
 * Main entry point
 */
int main(int argc, char **argv)
{
    KrbviewApp *app;
    int result;

    app = krbview_init(argc, argv);
    if (!app) {
        return 1;
    }

    result = krbview_run(app);

    krbview_cleanup(app);

    return result;
}
