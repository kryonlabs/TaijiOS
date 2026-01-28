/*
 * KRB File Loader
 *
 * Handles loading KRB files from disk or memory.
 */

#include "lib9.h"
#include <fcntl.h>
#include "krb.h"
#include "krb_types.h"

static int krb_last_error = KRB_OK;

/* Read a 32-bit little-endian value */
static uint32_t
read_u32_le(const char *data, size_t offset)
{
    const unsigned char *p = (const unsigned char *)(data + offset);
    return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

/* Read a 16-bit little-endian value */
static uint16_t
read_u16_le(const char *data, size_t offset)
{
    const unsigned char *p = (const unsigned char *)(data + offset);
    return p[0] | (p[1] << 8);
}

KrbFile*
krb_load(const char *path)
{
    int fd;
    char *data;
    Dir *d;
    size_t size;
    KrbFile *file;

    krb_last_error = KRB_OK;

    /* Open file */
    fd = open(path, OREAD);
    if (fd < 0) {
        krb_last_error = KRB_ERROR_FILE_NOT_FOUND;
        return nil;
    }

    /* Get file size */
    d = dirfstat(fd);
    if (d == nil) {
        close(fd);
        krb_last_error = KRB_ERROR_IO;
        return nil;
    }
    size = d->length;
    free(d);

    /* Allocate buffer */
    data = malloc(size);
    if (data == nil) {
        close(fd);
        krb_last_error = KRB_ERROR_NO_MEMORY;
        return nil;
    }

    /* Read entire file */
    if (readn(fd, data, size) != (long)size) {
        free(data);
        close(fd);
        krb_last_error = KRB_ERROR_IO;
        return nil;
    }

    close(fd);

    /* Parse from memory */
    file = krb_load_from_memory(data, size);

    /* The KrbFile now owns the data buffer */
    if (file == nil) {
        free(data);
    }

    return file;
}

KrbFile*
krb_load_from_memory(const char *data, size_t size)
{
    KrbFile *file;

    krb_last_error = KRB_OK;

    if (data == nil || size < sizeof(KrbHeader)) {
        krb_last_error = KRB_ERROR_INVALID_DATA;
        return nil;
    }

    /* Allocate KrbFile structure */
    file = mallocz(sizeof(KrbFile), 1);
    if (file == nil) {
        krb_last_error = KRB_ERROR_NO_MEMORY;
        return nil;
    }

    file->data = (char*)data;  /* Store as non-const for free() */
    file->size = size;

    /* Parse header */
    if (krb_parse_header(file) != KRB_OK) {
        krb_free(file);
        return nil;
    }

    /* Validate header */
    if (krb_validate_header(file) != KRB_OK) {
        krb_free(file);
        return nil;
    }

    /* Parse all sections */
    if (krb_parse_string_table(file) != KRB_OK) {
        krb_free(file);
        return nil;
    }

    if (file->header.widget_def_count > 0) {
        if (krb_parse_widget_definitions(file) != KRB_OK) {
            krb_free(file);
            return nil;
        }
    }

    if (file->header.widget_instance_count > 0) {
        if (krb_parse_widget_instances(file) != KRB_OK) {
            krb_free(file);
            return nil;
        }
    }

    if (file->header.style_count > 0) {
        if (krb_parse_styles(file) != KRB_OK) {
            krb_free(file);
            return nil;
        }
    }

    if (file->header.theme_count > 0) {
        if (krb_parse_themes(file) != KRB_OK) {
            krb_free(file);
            return nil;
        }
    }

    if (file->header.property_count > 0) {
        if (krb_parse_properties(file) != KRB_OK) {
            krb_free(file);
            return nil;
        }
    }

    if (file->header.event_count > 0) {
        if (krb_parse_events(file) != KRB_OK) {
            krb_free(file);
            return nil;
        }
    }

    if (file->header.script_count > 0) {
        if (krb_parse_scripts(file) != KRB_OK) {
            krb_free(file);
            return nil;
        }
    }

    return file;
}

void
krb_free(KrbFile *file)
{
    int i;

    if (file == nil)
        return;

    /* Free string table */
    if (file->strings.strings != nil) {
        /* Note: strings themselves point into file->data */
        free(file->strings.strings);
    }

    /* Free sections - these are pointers into file->data, no need to free */
    /* But if we made copies, free them here */

    /* Free data buffer */
    if (file->data != nil) {
        free(file->data);
    }

    free(file);
}

int
krb_parse_header(KrbFile *file)
{
    const char *p = file->data;

    if (file->size < sizeof(KrbHeader)) {
        krb_last_error = KRB_ERROR_INVALID_DATA;
        return KRB_ERROR_INVALID_DATA;
    }

    /* Read header fields */
    file->header.magic = read_u32_le(p, 0);
    file->header.version_major = read_u16_le(p, 4);
    file->header.version_minor = read_u16_le(p, 6);
    file->header.flags = read_u16_le(p, 8);
    file->header.reserved = read_u16_le(p, 10);

    file->header.style_count = read_u32_le(p, 12);
    file->header.theme_count = read_u32_le(p, 16);
    file->header.widget_def_count = read_u32_le(p, 20);
    file->header.widget_instance_count = read_u32_le(p, 24);
    file->header.property_count = read_u32_le(p, 28);
    file->header.event_count = read_u32_le(p, 32);
    file->header.script_count = read_u32_le(p, 36);

    file->header.string_table_offset = read_u32_le(p, 40);
    file->header.widget_defs_offset = read_u32_le(p, 44);
    file->header.widget_instances_offset = read_u32_le(p, 48);
    file->header.styles_offset = read_u32_le(p, 52);
    file->header.themes_offset = read_u32_le(p, 56);
    file->header.properties_offset = read_u32_le(p, 60);
    file->header.events_offset = read_u32_le(p, 64);
    file->header.scripts_offset = read_u32_le(p, 68);

    file->header.string_table_size = read_u32_le(p, 72);
    file->header.widget_defs_size = read_u32_le(p, 76);
    file->header.widget_instances_size = read_u32_le(p, 80);
    file->header.styles_size = read_u32_le(p, 84);
    file->header.themes_size = read_u32_le(p, 88);
    file->header.properties_size = read_u32_le(p, 92);
    file->header.events_size = read_u32_le(p, 96);
    file->header.scripts_size = read_u32_le(p, 100);

    file->header.checksum = read_u32_le(p, 104);

    /* Update counts for easy access */
    file->widget_def_count = file->header.widget_def_count;
    file->widget_instance_count = file->header.widget_instance_count;
    file->style_count = file->header.style_count;
    file->theme_count = file->header.theme_count;
    file->property_count = file->header.property_count;
    file->event_count = file->header.event_count;
    file->script_count = file->header.script_count;

    return KRB_OK;
}

int
krb_validate_header(KrbFile *file)
{
    /* Check magic number */
    if (file->header.magic != 0x4B52594E) {  /* "KRYN" */
        krb_last_error = KRB_ERROR_MAGIC;
        return KRB_ERROR_MAGIC;
    }

    /* Check version */
    if (file->header.version_major != 1 || file->header.version_minor != 0) {
        krb_last_error = KRB_ERROR_VERSION;
        return KRB_ERROR_VERSION;
    }

    return KRB_OK;
}

int
krb_validate_checksum(KrbFile *file)
{
    /* TODO: Implement CRC32 checksum validation */
    /* For now, always return OK */
    return KRB_OK;
}

const char*
krb_strerror(int error_code)
{
    switch (error_code) {
    case KRB_OK:
        return "Success";
    case KRB_ERROR_FILE_NOT_FOUND:
        return "File not found";
    case KRB_ERROR_IO:
        return "I/O error";
    case KRB_ERROR_MAGIC:
        return "Invalid magic number";
    case KRB_ERROR_VERSION:
        return "Unsupported version";
    case KRB_ERROR_CHECKSUM:
        return "Checksum mismatch";
    case KRB_ERROR_NO_MEMORY:
        return "Out of memory";
    case KRB_ERROR_INVALID_DATA:
        return "Invalid data";
    case KRB_ERROR_OFFSET:
        return "Invalid offset";
    default:
        return "Unknown error";
    }
}
