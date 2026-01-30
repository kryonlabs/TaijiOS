/*
 * krbview_loader - KRB File Loading Wrapper
 *
 * Wrapper around libkrb.a for loading and validating KRB files.
 */

#ifndef KRBVIEW_LOADER_H
#define KRBVIEW_LOADER_H

#include "krb.h"
#include <stdint.h>

/*
 * Load KRB file with validation
 *
 * Returns: KrbFile pointer on success, NULL on error
 * Sets error message accessible via krbview_loader_get_error()
 */
KrbFile* krbview_loader_load(const char *path);

/*
 * Load KRB from memory buffer
 *
 * Returns: KrbFile pointer on success, NULL on error
 */
KrbFile* krbview_loader_load_from_memory(const char *data, size_t size);

/*
 * Validate KRB file structure
 *
 * Returns: 1 if valid, 0 if invalid
 */
int krbview_loader_validate(KrbFile *file);

/*
 * Get metadata from KRB file
 */
const char* krbview_loader_get_title(KrbFile *file);
const char* krbview_loader_get_version(KrbFile *file);
const char* krbview_loader_get_author(KrbFile *file);

/*
 * Get last error message
 */
const char* krbview_loader_get_error(void);

/*
 * Free loaded KRB file
 */
void krbview_loader_free(KrbFile *file);

#endif /* KRBVIEW_LOADER_H */
