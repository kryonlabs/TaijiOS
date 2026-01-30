/*
 * KRB Executor - Simple wrapper to run KRB files
 *
 * This is a convenience program that wraps krbclient for easier usage.
 */

#include <u.h>
#include <libc.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>

void
usage(void)
{
    fprint(2, "usage: krbexec [options] file.krb\n");
    fprint(2, "options:\n");
    fprint(2, "  -t title   Set window title\n");
    fprint(2, "  -W width   Set window width (default: 800)\n");
    fprint(2, "  -H height  Set window height (default: 600)\n");
    exits("usage");
}

int
main(int argc, char *argv[])
{
    char *krb_path;
    char *title;
    char title_arg[256];
    char width_arg[32];
    char height_arg[32];
    int width, height;
    char *client_argv[10];
    int i, argc;
    pid_t pid;
    int status;

    title = nil;
    width = 800;
    height = 600;

    ARGBEGIN {
    case 't':
        title = ARGF();
        break;
    case 'W':
        width = atoi(ARGF());
        break;
    case 'H':
        height = atoi(ARGF());
        break;
    default:
        usage();
    } ARGEND;

    if (argc < 1)
        usage();

    krb_path = argv[0];

    /* Check if file exists */
    int fd = open(krb_path, OREAD);
    if (fd < 0) {
        sysfatal("krbexec: cannot open %s: %r", krb_path);
    }
    close(fd);

    /* Use filename as title if not specified */
    if (title == nil) {
        char *slash = strrchr(krb_path, '/');
        if (slash != nil)
            title = slash + 1;
        else
            title = krb_path;
    }

    /* Build krbclient arguments */
    argc = 0;
    client_argv[argc++] = strdup("krbclient");

    /* Add title argument */
    snprint(title_arg, sizeof(title_arg), "-t");
    client_argv[argc++] = strdup(title_arg);
    client_argv[argc++] = strdup(title);

    /* Add width argument */
    snprint(width_arg, sizeof(width_arg), "-W");
    client_argv[argc++] = strdup(width_arg);
    snprint(width_arg, sizeof(width_arg), "%d", width);
    client_argv[argc++] = strdup(width_arg);

    /* Add height argument */
    snprint(height_arg, sizeof(height_arg), "-H");
    client_argv[argc++] = strdup(height_arg);
    snprint(height_arg, sizeof(height_arg), "%d", height);
    client_argv[argc++] = strdup(height_arg);

    /* Add KRB file path */
    client_argv[argc++] = strdup(krb_path);

    client_argv[argc] = nil;

    /* Execute krbclient */
    execvp("/os/krbclient/krbclient", client_argv);

    /* If execvp returns, it failed */
    sysfatal("krbexec: cannot execute krbclient: %r");
}
