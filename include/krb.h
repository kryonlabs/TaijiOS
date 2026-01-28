/*
 * KRB (Kryon Binary) Parser Library - Public API
 *
 * This library provides functions for loading, parsing, and querying
 * KRB binary UI files.
 */

#ifndef KRB_H
#define KRB_H

#include "krb_types.h"

/*
 * Load and validate a KRB file
 * Returns: KrbFile pointer on success, NULL on error
 */
KrbFile* krb_load(const char *path);

/*
 * Load KRB from memory buffer
 * Returns: KrbFile pointer on success, NULL on error
 */
KrbFile* krb_load_from_memory(const char *data, size_t size);

/*
 * Free all resources associated with a KrbFile
 */
void krb_free(KrbFile *file);

/*
 * Parse KRB file sections
 * These are called automatically by krb_load(), but can be called
 * separately for validation purposes
 */
int krb_parse_header(KrbFile *file);
int krb_parse_string_table(KrbFile *file);
int krb_parse_widget_definitions(KrbFile *file);
int krb_parse_widget_instances(KrbFile *file);
int krb_parse_styles(KrbFile *file);
int krb_parse_themes(KrbFile *file);
int krb_parse_properties(KrbFile *file);
int krb_parse_events(KrbFile *file);
int krb_parse_scripts(KrbFile *file);

/*
 * Query functions
 */

/* Get string from string table by index */
char* krb_get_string(KrbFile *file, uint32_t offset);

/* Find widget instance by ID */
KrbWidgetInstance* krb_find_widget_instance(KrbFile *file, uint32_t id);

/* Find widget definition by type ID */
KrbWidgetDefinition* krb_find_widget_definition(KrbFile *file, uint32_t type_id);

/* Find style by ID */
KrbStyleDefinition* krb_find_style(KrbFile *file, uint32_t id);

/* Find theme by ID */
KrbThemeDefinition* krb_find_theme(KrbFile *file, uint32_t id);

/* Get property value for widget instance */
KrbProperty* krb_get_widget_property(KrbFile *file,
                                     KrbWidgetInstance *widget,
                                     const char *property_name);

/* Get event handler for widget */
KrbEvent* krb_get_widget_event(KrbFile *file,
                               KrbWidgetInstance *widget,
                               const char *event_type);

/* Get widget type name */
char* krb_get_widget_type_name(KrbFile *file, KrbWidgetInstance *widget);

/* Get widget ID string */
char* krb_get_widget_id(KrbFile *file, KrbWidgetInstance *widget);

/* Get root widget of the tree */
KrbWidgetInstance* krb_get_root_widget(KrbFile *file);

/*
 * Validation functions
 */

/* Validate file header */
int krb_validate_header(KrbFile *file);

/* Validate checksum */
int krb_validate_checksum(KrbFile *file);

/* Get error message for last error */
const char* krb_strerror(int error_code);

/*
 * Error codes
 */
enum KrbErrorCode {
    KRB_OK = 0,
    KRB_ERROR_FILE_NOT_FOUND = -1,
    KRB_ERROR_IO = -2,
    KRB_ERROR_MAGIC = -3,
    KRB_ERROR_VERSION = -4,
    KRB_ERROR_CHECKSUM = -5,
    KRB_ERROR_NO_MEMORY = -6,
    KRB_ERROR_INVALID_DATA = -7,
    KRB_ERROR_OFFSET = -8
};

#endif /* KRB_H */
