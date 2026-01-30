/*
 * krbview - KRB File Viewer Public API
 *
 * This header provides the public API for embedding krbview
 * functionality into other applications.
 */

#ifndef KRBVIEW_PUBLIC_H
#define KRBVIEW_PUBLIC_H

#include <stdint.h>

/* Forward declarations */
typedef struct KrbviewApp KrbviewApp;

/*
 * Create krbview application instance
 *
 * This creates a viewer application for the specified KRB file.
 * The application must be freed with krbview_free() when done.
 *
 * Parameters:
 *   krb_path - Path to KRB file to view
 *   width    - Window width (0 for default)
 *   height   - Window height (0 for default)
 *
 * Returns: Application instance, or NULL on error
 */
KrbviewApp* krbview_create(const char *krb_path, int width, int height);

/*
 * Run the viewer application
 *
 * This enters the main event loop and blocks until the window is closed.
 *
 * Parameters:
 *   app - Application instance from krbview_create()
 *
 * Returns: 0 on success, -1 on error
 */
int krbview_run(KrbviewApp *app);

/*
 * Free application resources
 *
 * Parameters:
 *   app - Application instance from krbview_create()
 */
void krbview_free(KrbviewApp *app);

/*
 * Convenience function - view KRB file with default settings
 *
 * This is a simple wrapper that creates, runs, and frees the viewer.
 *
 * Parameters:
 *   krb_path - Path to KRB file to view
 *
 * Returns: 0 on success, -1 on error
 */
int krbview_view_file(const char *krb_path);

#endif /* KRBVIEW_PUBLIC_H */
