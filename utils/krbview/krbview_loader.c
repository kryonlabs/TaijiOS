/*
 * krbview_loader - KRB File Loading Wrapper
 */

#define _BSD_SOURCE
#define _DEFAULT_SOURCE
#include <lib9.h>
#include "krbview_loader.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Thread-local error message */
static char loader_error[256] = {0};

/*
 * Utility functions for reading little-endian values
 * These should be in libkrb_runtime but are missing, so we define them here
 */
static uint16_t read_u16_le(const char *data, size_t offset)
{
    const unsigned char *p = (const unsigned char *)(data + offset);
    return p[0] | (p[1] << 8);
}

static uint32_t read_u32_le(const char *data, size_t offset)
{
    const unsigned char *p = (const unsigned char *)(data + offset);
    return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

/*
 * Load KRB file with validation
 */
KrbFile* krbview_loader_load(const char *path)
{
    KrbFile *file;

    if (!path || strlen(path) == 0) {
        snprintf(loader_error, sizeof(loader_error), "Invalid file path");
        return NULL;
    }

    /* Use existing libkrb loader */
    file = krb_load(path);
    if (!file) {
        snprintf(loader_error, sizeof(loader_error),
                "Failed to load KRB file: %s", path);
        return NULL;
    }

    /* Validate the file */
    if (!krbview_loader_validate(file)) {
        krb_free(file);
        return NULL;
    }

    return file;
}

/*
 * Load KRB from memory buffer
 */
KrbFile* krbview_loader_load_from_memory(const char *data, size_t size)
{
    KrbFile *file;

    if (!data || size == 0) {
        snprintf(loader_error, sizeof(loader_error), "Invalid data buffer");
        return NULL;
    }

    file = krb_load_from_memory(data, size);
    if (!file) {
        snprintf(loader_error, sizeof(loader_error),
                "Failed to load KRB from memory");
        return NULL;
    }

    if (!krbview_loader_validate(file)) {
        krb_free(file);
        return NULL;
    }

    return file;
}

/*
 * Validate KRB file structure
 */
int krbview_loader_validate(KrbFile *file)
{
    if (!file) {
        snprintf(loader_error, sizeof(loader_error), "NULL file pointer");
        return 0;
    }

    /* Validate header */
    if (krb_validate_header(file) != KRB_OK) {
        snprintf(loader_error, sizeof(loader_error), "Invalid KRB header");
        return 0;
    }

    /* Validate checksum */
    if (krb_validate_checksum(file) != KRB_OK) {
        snprintf(loader_error, sizeof(loader_error), "Invalid KRB checksum");
        return 0;
    }

    /* Verify root widget exists */
    KrbWidgetInstance *root = krb_get_root_widget(file);
    if (!root) {
        snprintf(loader_error, sizeof(loader_error), "No root widget found");
        return 0;
    }

    return 1;
}

/*
 * Get metadata from KRB file
 */
const char* krbview_loader_get_title(KrbFile *file)
{
    /* TODO: Implement metadata extraction from KRB file */
    return "KRB Application";
}

const char* krbview_loader_get_version(KrbFile *file)
{
    return "1.0";
}

const char* krbview_loader_get_author(KrbFile *file)
{
    return "Unknown";
}

/*
 * Get last error message
 */
const char* krbview_loader_get_error(void)
{
    return loader_error;
}

/*
 * Free loaded KRB file
 */
void krbview_loader_free(KrbFile *file)
{
    if (file) {
        krb_free(file);
    }
}
