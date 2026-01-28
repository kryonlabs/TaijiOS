/*
 * KRB Shell Type Conversion
 * Converts between C types and Limbo types
 */

#include "lib9.h"
#include <string.h>
#include "interp.h"
#include "krb_shell.h"

/*
 * Convert C string to Limbo String*
 */
String*
c_to_limbo_string(const char *str)
{
	String *s;
	int len;

	if (str == nil)
		return nil;

	len = strlen(str);
	s = newstring(len);
	if (s == nil)
		return nil;

	memmove(s->Sascii, str, len);
	s->len = len;

	return s;
}

/*
 * Convert Limbo String* to C string
 * Returns allocated string - caller must free
 */
char*
limbo_to_c_string(String *s)
{
	char *str;
	int len;

	if (s == nil)
		return nil;

	len = s->len;
	str = malloc(len + 1);
	if (str == nil)
		return nil;

	memmove(str, s->Sascii, len);
	str[len] = '\0';

	return str;
}

/*
 * Convert integer to Limbo String*
 */
String*
int_to_limbo_string(int value)
{
	char buf[32];
	snprint(buf, sizeof(buf), "%d", value);
	return c_to_limbo_string(buf);
}

/*
 * Convert Limbo String* to integer
 */
int
limbo_string_to_int(String *s)
{
	char *str;
	int value;

	str = limbo_to_c_string(s);
	if (str == nil)
		return 0;

	value = atoi(str);
	free(str);

	return value;
}

/*
 * Convert double to Limbo String*
 */
String*
double_to_limbo_string(double value)
{
	char buf[64];
	snprint(buf, sizeof(buf), "%g", value);
	return c_to_limbo_string(buf);
}

/*
 * Convert Limbo String* to double
 */
double
limbo_string_to_double(String *s)
{
	char *str;
	double value;

	str = limbo_to_c_string(s);
	if (str == nil)
		return 0.0;

	value = strtod(str, nil);
	free(str);

	return value;
}
