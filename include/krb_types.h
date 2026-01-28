/*
 * KRB (Kryon Binary) File Format Data Structures
 *
 * This file defines the internal data structures for parsing KRB files.
 * KRB is a binary UI serialization format, not a bytecode VM.
 */

#ifndef KRB_TYPES_H
#define KRB_TYPES_H

#include <stdint.h>

/* KRB File Header */
typedef struct {
    uint32_t magic;              /* 0x4B52594E "KRYN" */
    uint16_t version_major;      /* Major version */
    uint16_t version_minor;      /* Minor version */
    uint16_t flags;              /* Format flags */
    uint16_t reserved;

    /* Section counts */
    uint32_t style_count;
    uint32_t theme_count;
    uint32_t widget_def_count;
    uint32_t widget_instance_count;
    uint32_t property_count;
    uint32_t event_count;
    uint32_t script_count;

    /* Section offsets (from file start) */
    uint32_t string_table_offset;
    uint32_t widget_defs_offset;
    uint32_t widget_instances_offset;
    uint32_t styles_offset;
    uint32_t themes_offset;
    uint32_t properties_offset;
    uint32_t events_offset;
    uint32_t scripts_offset;

    /* Section sizes */
    uint32_t string_table_size;
    uint32_t widget_defs_size;
    uint32_t widget_instances_size;
    uint32_t styles_size;
    uint32_t themes_size;
    uint32_t properties_size;
    uint32_t events_size;
    uint32_t scripts_size;

    uint32_t checksum;           /* CRC32 of entire file */
    uint32_t reserved2[8];       /* Future expansion */
} KrbHeader;

/* Property Types */
enum KrbPropertyType {
    KRB_PROP_STRING = 0,
    KRB_PROP_NUMBER = 1,
    KRB_PROP_BOOLEAN = 2,
    KRB_PROP_COLOR = 3,
    KRB_PROP_REFERENCE = 4,
    KRB_PROP_ARRAY = 5,
    KRB_PROP_EXPRESSION = 6
};

/* Property Value */
typedef struct {
    uint8_t type;                /* KRBPropertyType */
    uint8_t flags;
    uint16_t reserved;

    union {
        char *string_val;
        double number_val;
        int boolean_val;
        uint32_t color_val;      /* 0xAABBGGRR */
        uint32_t reference_val;  /* Index into tables */
        struct {
            void *elements;
            uint32_t count;
        } array_val;
        char *expression_val;
    };
} KrbPropertyValue;

/* Property Definition */
typedef struct {
    uint32_t id;                 /* Property ID */
    uint32_t name_offset;        /* Offset in string table */
    uint32_t value_offset;       /* Offset to value data */
} KrbProperty;

/* Event Handler */
typedef struct {
    uint32_t id;
    uint32_t event_type_offset;  /* "onClick", "onChange", etc. */
    uint32_t handler_offset;     /* Script or reference */
    uint32_t metadata_offset;    /* Additional event metadata */
} KrbEvent;

/* Widget Type Definitions */
typedef struct {
    uint32_t type_id;            /* 0x0001=Column, 0x0400=Text, etc. */
    uint32_t name_offset;        /* "Column", "Text", etc. */
    uint32_t base_class_offset;  /* Base widget type */
    uint32_t flags;

    uint32_t default_style_id;   /* Default style reference */
    uint32_t property_count;
    uint32_t event_count;
} KrbWidgetDefinition;

/* Widget Instance */
typedef struct {
    uint32_t id;                 /* Unique instance ID */
    uint32_t type_id;            /* Type from KrbWidgetDefinition */
    uint32_t parent_id;          /* Parent widget ID (0 for root) */
    uint32_t style_id;           /* Applied style */

    uint16_t property_count;
    uint16_t child_count;
    uint16_t event_count;
    uint16_t flags;

    uint32_t id_str_offset;      /* Widget ID string offset */
    uint32_t properties_offset;  /* Offset to property array */
    uint32_t children_offset;    /* Offset to child ID array */
    uint32_t events_offset;      /* Offset to event array */
} KrbWidgetInstance;

/* Style Definition */
typedef struct {
    uint32_t id;
    uint32_t name_offset;        /* Style name */
    uint32_t parent_id;          /* Inherited style */

    uint16_t property_count;
    uint16_t flags;

    uint32_t properties_offset;  /* Offset to property array */
} KrbStyleDefinition;

/* Theme Variable Group */
typedef struct {
    uint32_t group_name_offset;  /* "colors", "spacing", etc. */
    uint16_t variable_count;
    uint16_t flags;

    uint32_t variables_offset;   /* Offset to variable array */
} KrbThemeGroup;

/* Theme Definition */
typedef struct {
    uint32_t id;
    uint32_t name_offset;        /* "light", "dark", etc. */

    uint16_t group_count;
    uint16_t flags;

    uint32_t groups_offset;      /* Offset to group array */
} KrbThemeDefinition;

/* Script Section */
typedef struct {
    uint32_t id;
    uint32_t language_offset;    /* "limbo", "lua", etc. */
    uint32_t code_offset;        /* Offset to code */
    uint32_t code_size;
    uint32_t metadata_offset;
} KrbScript;

/* String Table */
typedef struct {
    char *data;                  /* Raw string data */
    uint32_t size;
    char **strings;              /* Indexed string pointers */
    uint32_t count;
} KrbStringTable;

/* Parsed KRB File */
typedef struct {
    /* File data */
    char *data;
    size_t size;

    /* Header */
    KrbHeader header;

    /* String table */
    KrbStringTable strings;

    /* Sections */
    KrbWidgetDefinition *widget_defs;
    KrbWidgetInstance *widget_instances;
    KrbStyleDefinition *styles;
    KrbThemeDefinition *themes;
    KrbProperty *properties;
    KrbEvent *events;
    KrbScript *scripts;

    /* Counts (from header) */
    uint32_t widget_def_count;
    uint32_t widget_instance_count;
    uint32_t style_count;
    uint32_t theme_count;
    uint32_t property_count;
    uint32_t event_count;
    uint32_t script_count;

    /* Memory management */
    int *allocated_blocks;
    uint32_t allocated_count;
} KrbFile;

/* Common color structure */
typedef struct {
    uint8_t r, g, b, a;
} KrbColor;

/* Rectangle structure */
typedef struct {
    int x, y;
    int width, height;
} KrbRect;

#endif /* KRB_TYPES_H */
