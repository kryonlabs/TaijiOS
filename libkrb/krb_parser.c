/*
 * KRB Parser - Section Parsers
 *
 * Parses individual sections of a KRB file.
 */

#include "lib9.h"
#include "krb.h"
#include "krb_types.h"

static int krb_last_error = KRB_OK;

static uint32_t
read_u32_le(const char *data, size_t offset)
{
    const unsigned char *p = (const unsigned char *)(data + offset);
    return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

static uint16_t
read_u16_le(const char *data, size_t offset)
{
    const unsigned char *p = (const unsigned char *)(data + offset);
    return p[0] | (p[1] << 8);
}

int
krb_parse_string_table(KrbFile *file)
{
    const char *p;
    uint32_t offset, size;
    uint32_t count, i, str_offset;

    offset = file->header.string_table_offset;
    size = file->header.string_table_size;

    if (offset == 0 || size == 0) {
        /* Empty string table is valid */
        return KRB_OK;
    }

    if (offset + size > file->size) {
        krb_last_error = KRB_ERROR_OFFSET;
        return KRB_ERROR_OFFSET;
    }

    /* String table format: count followed by NUL-terminated strings */
    p = file->data + offset;
    count = read_u32_le(p, 0);

    /* Allocate string pointer array */
    file->strings.strings = mallocz(count * sizeof(char*), 1);
    if (file->strings.strings == nil) {
        krb_last_error = KRB_ERROR_NO_MEMORY;
        return KRB_ERROR_NO_MEMORY;
    }

    file->strings.data = (char*)p;
    file->strings.size = size;
    file->strings.count = count;

    /* Parse string pointers */
    str_offset = 4;  /* Skip count */
    for (i = 0; i < count; i++) {
        if (str_offset >= size) {
            krb_last_error = KRB_ERROR_INVALID_DATA;
            return KRB_ERROR_INVALID_DATA;
        }

        file->strings.strings[i] = (char*)p + str_offset;

        /* Find NUL terminator */
        while (str_offset < size && p[str_offset] != '\0') {
            str_offset++;
        }
        str_offset++;  /* Skip NUL */
    }

    return KRB_OK;
}

char*
krb_get_string(KrbFile *file, uint32_t offset)
{
    if (file == nil || file->strings.data == nil)
        return nil;

    if (offset >= file->strings.size) {
        return nil;
    }

    return file->strings.data + offset;
}

int
krb_parse_widget_definitions(KrbFile *file)
{
    const char *p;
    uint32_t offset, size;
    uint32_t i, entry_size;

    offset = file->header.widget_defs_offset;
    size = file->header.widget_defs_size;

    if (offset + size > file->size) {
        krb_last_error = KRB_ERROR_OFFSET;
        return KRB_ERROR_OFFSET;
    }

    p = file->data + offset;

    /* Each widget definition is 40 bytes */
    entry_size = 40;
    file->widget_def_count = size / entry_size;

    /* Just point into file data - no need to allocate */
    file->widget_defs = (KrbWidgetDefinition*)p;

    return KRB_OK;
}

int
krb_parse_widget_instances(KrbFile *file)
{
    const char *p;
    uint32_t offset, size;
    uint32_t i, entry_size;

    offset = file->header.widget_instances_offset;
    size = file->header.widget_instances_size;

    if (offset + size > file->size) {
        krb_last_error = KRB_ERROR_OFFSET;
        return KRB_ERROR_OFFSET;
    }

    p = file->data + offset;

    /* Each widget instance is 48 bytes */
    entry_size = 48;
    file->widget_instance_count = size / entry_size;

    /* Just point into file data */
    file->widget_instances = (KrbWidgetInstance*)p;

    return KRB_OK;
}

int
krb_parse_styles(KrbFile *file)
{
    const char *p;
    uint32_t offset, size;

    offset = file->header.styles_offset;
    size = file->header.styles_size;

    if (offset == 0 || size == 0) {
        return KRB_OK;
    }

    if (offset + size > file->size) {
        krb_last_error = KRB_ERROR_OFFSET;
        return KRB_ERROR_OFFSET;
    }

    p = file->data + offset;

    /* Each style is 24 bytes */
    file->style_count = size / 24;

    /* Just point into file data */
    file->styles = (KrbStyleDefinition*)p;

    return KRB_OK;
}

int
krb_parse_themes(KrbFile *file)
{
    const char *p;
    uint32_t offset, size;

    offset = file->header.themes_offset;
    size = file->header.themes_size;

    if (offset == 0 || size == 0) {
        return KRB_OK;
    }

    if (offset + size > file->size) {
        krb_last_error = KRB_ERROR_OFFSET;
        return KRB_ERROR_OFFSET;
    }

    p = file->data + offset;

    /* Each theme is 24 bytes */
    file->theme_count = size / 24;

    /* Just point into file data */
    file->themes = (KrbThemeDefinition*)p;

    return KRB_OK;
}

int
krb_parse_properties(KrbFile *file)
{
    const char *p;
    uint32_t offset, size;

    offset = file->header.properties_offset;
    size = file->header.properties_size;

    if (offset == 0 || size == 0) {
        return KRB_OK;
    }

    if (offset + size > file->size) {
        krb_last_error = KRB_ERROR_OFFSET;
        return KRB_ERROR_OFFSET;
    }

    p = file->data + offset;

    /* Each property is 12 bytes */
    file->property_count = size / 12;

    /* Just point into file data */
    file->properties = (KrbProperty*)p;

    return KRB_OK;
}

int
krb_parse_events(KrbFile *file)
{
    const char *p;
    uint32_t offset, size;

    offset = file->header.events_offset;
    size = file->header.events_size;

    if (offset == 0 || size == 0) {
        return KRB_OK;
    }

    if (offset + size > file->size) {
        krb_last_error = KRB_ERROR_OFFSET;
        return KRB_ERROR_OFFSET;
    }

    p = file->data + offset;

    /* Each event is 16 bytes */
    file->event_count = size / 16;

    /* Just point into file data */
    file->events = (KrbEvent*)p;

    return KRB_OK;
}

int
krb_parse_scripts(KrbFile *file)
{
    const char *p;
    uint32_t offset, size;

    offset = file->header.scripts_offset;
    size = file->header.scripts_size;

    if (offset == 0 || size == 0) {
        return KRB_OK;
    }

    if (offset + size > file->size) {
        krb_last_error = KRB_ERROR_OFFSET;
        return KRB_ERROR_OFFSET;
    }

    p = file->data + offset;

    /* Each script is 24 bytes */
    file->script_count = size / 24;

    /* Just point into file data */
    file->scripts = (KrbScript*)p;

    return KRB_OK;
}

KrbWidgetInstance*
krb_find_widget_instance(KrbFile *file, uint32_t id)
{
    uint32_t i;

    for (i = 0; i < file->widget_instance_count; i++) {
        KrbWidgetInstance *w = &file->widget_instances[i];
        uint32_t widget_id = read_u32_le(file->data,
            file->header.widget_instances_offset + i * 48);
        if (widget_id == id)
            return w;
    }

    return nil;
}

KrbWidgetDefinition*
krb_find_widget_definition(KrbFile *file, uint32_t type_id)
{
    uint32_t i;

    for (i = 0; i < file->widget_def_count; i++) {
        KrbWidgetDefinition *def = &file->widget_defs[i];
        uint32_t def_type_id = read_u32_le(file->data,
            file->header.widget_defs_offset + i * 40);
        if (def_type_id == type_id)
            return def;
    }

    return nil;
}

KrbStyleDefinition*
krb_find_style(KrbFile *file, uint32_t id)
{
    uint32_t i;

    for (i = 0; i < file->style_count; i++) {
        KrbStyleDefinition *style = &file->styles[i];
        uint32_t style_id = read_u32_le(file->data,
            file->header.styles_offset + i * 24);
        if (style_id == id)
            return style;
    }

    return nil;
}

KrbThemeDefinition*
krb_find_theme(KrbFile *file, uint32_t id)
{
    uint32_t i;

    for (i = 0; i < file->theme_count; i++) {
        KrbThemeDefinition *theme = &file->themes[i];
        uint32_t theme_id = read_u32_le(file->data,
            file->header.themes_offset + i * 24);
        if (theme_id == id)
            return theme;
    }

    return nil;
}

char*
krb_get_widget_type_name(KrbFile *file, KrbWidgetInstance *widget)
{
    uint32_t type_id;
    KrbWidgetDefinition *def;
    uint32_t name_offset;

    if (file == nil || widget == nil)
        return nil;

    /* Get type_id from widget */
    uintptr_t widget_offset = (uintptr_t)widget - (uintptr_t)file->data;
    type_id = read_u32_le(file->data, widget_offset + 4);

    /* Find widget definition */
    def = krb_find_widget_definition(file, type_id);
    if (def == nil)
        return nil;

    /* Get name offset from definition */
    uintptr_t def_offset = (uintptr_t)def - (uintptr_t)file->data;
    name_offset = read_u32_le(file->data, def_offset + 4);

    return krb_get_string(file, name_offset);
}

char*
krb_get_widget_id(KrbFile *file, KrbWidgetInstance *widget)
{
    uint32_t id_str_offset;

    if (file == nil || widget == nil)
        return nil;

    uintptr_t widget_offset = (uintptr_t)widget - (uintptr_t)file->data;
    id_str_offset = read_u32_le(file->data, widget_offset + 20);

    return krb_get_string(file, id_str_offset);
}
