/*
 * KRB Property Resolver
 *
 * Resolves property values including colors, dimensions, and theme variables.
 */

#include "lib9.h"
#include <draw.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "krb_runtime.h"

/* Parse hex color (#RRGGBB or #AARRGGBB) */
static uint32_t
parse_hex_color(const char *value)
{
    uint32_t color = 0xFF000000;  /* Default opaque */
    int len;

    if (value == nil)
        return color;

    /* Skip # if present */
    if (value[0] == '#')
        value++;

    len = strlen(value);

    if (len == 6) {
        /* #RRGGBB format */
        sscanf(value, "%06x", &color);
        color |= 0xFF000000;  /* Set alpha to 0xFF */
    } else if (len == 8) {
        /* #AARRGGBB format */
        sscanf(value, "%08x", &color);
    }

    return color;
}

/* Parse rgb() or rgba() function */
static uint32_t
parse_rgb_color(const char *value)
{
    int r, g, b, a = 255;

    if (strncmp(value, "rgba(", 5) == 0) {
        sscanf(value + 5, "%d,%d,%d,%d", &r, &g, &b, &a);
    } else if (strncmp(value, "rgb(", 4) == 0) {
        sscanf(value + 4, "%d,%d,%d", &r, &g, &b);
    }

    return (a << 24) | (r << 16) | (g << 8) | b;
}

/* Resolve color from value */
uint32_t
krb_resolve_color(KrbRuntime *runtime, const char *value)
{
    char theme_var[256];
    const char *resolved;

    if (value == nil)
        return 0xFF000000;

    /* Check for theme variable reference */
    if (strncmp(value, "theme.", 6) == 0) {
        /* Parse theme.group.variable */
        if (sscanf(value + 6, "%255[^\n]", theme_var) == 1) {
            char *dot = strchr(theme_var, '.');
            if (dot != nil) {
                *dot = '\0';
                char *variable = dot + 1;

                resolved = krb_runtime_resolve_theme_var(runtime, theme_var, variable);
                if (resolved != nil)
                    value = resolved;
            }
        }
    }

    /* Parse color */
    if (value[0] == '#') {
        return parse_hex_color(value);
    } else if (strncmp(value, "rgb", 3) == 0) {
        return parse_rgb_color(value);
    } else if (strcmp(value, "red") == 0) {
        return 0xFF0000FF;
    } else if (strcmp(value, "green") == 0) {
        return 0x00FF00FF;
    } else if (strcmp(value, "blue") == 0) {
        return 0x0000FFFF;
    } else if (strcmp(value, "white") == 0) {
        return 0xFFFFFFFF;
    } else if (strcmp(value, "black") == 0) {
        return 0x000000FF;
    } else if (strcmp(value, "transparent") == 0) {
        return 0x00000000;
    }

    return 0xFF000000;  /* Default: black opaque */
}

/* Resolve dimension */
double
krb_resolve_dimension(KrbRuntime *runtime, const char *value,
                      double parent_size)
{
    char unit[16];
    double number;
    char theme_var[256];
    const char *resolved;

    if (value == nil)
        return 0.0;

    /* Check for theme variable reference */
    if (strncmp(value, "theme.", 6) == 0) {
        if (sscanf(value + 6, "%255[^\n]", theme_var) == 1) {
            char *dot = strchr(theme_var, '.');
            if (dot != nil) {
                *dot = '\0';
                char *variable = dot + 1;

                resolved = krb_runtime_resolve_theme_var(runtime, theme_var, variable);
                if (resolved != nil)
                    value = resolved;
            }
        }
    }

    /* Parse dimension */
    if (sscanf(value, "%lf%15s", &number, unit) == 2) {
        if (strcmp(unit, "px") == 0) {
            return number;
        } else if (strcmp(unit, "%") == 0) {
            return (number / 100.0) * parent_size;
        }
    } else if (sscanf(value, "%lf", &number) == 1) {
        /* No unit = pixels */
        return number;
    }

    return 0.0;
}
