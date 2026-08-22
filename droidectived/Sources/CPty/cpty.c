#include "include/cpty.h"

#if defined(_WIN32)

#include <errno.h>

int droidective_pty_resize(int terminal, unsigned short columns, unsigned short rows) {
    (void)terminal;
    (void)columns;
    (void)rows;
    errno = ENOSYS;
    return -1;
}

int droidective_pty_spawn(const char *executable, char *const argv[], char *const envp[],
                          const char *directory, unsigned short columns, unsigned short rows,
                          int *master_out, int *slave_out) {
    (void)executable;
    (void)argv;
    (void)envp;
    (void)directory;
    (void)columns;
    (void)rows;
    (void)master_out;
    (void)slave_out;
    errno = ENOSYS;
    return -1;
}

#else

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

pid_t droidective_pty_spawn(const char *executable, char *const argv[], char *const envp[],
                            const char *directory, unsigned short columns, unsigned short rows,
                            int *master_out, int *slave_out) {
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0) {
        return -1;
    }
    if (grantpt(master) != 0 || unlockpt(master) != 0) {
        int saved = errno;
        close(master);
        errno = saved;
        return -1;
    }

    /* Copied out before the fork: ptsname returns a pointer into static storage
     * that another thread could overwrite, and the child must not read it. */
    const char *name = ptsname(master);
    if (name == NULL) {
        int saved = errno;
        close(master);
        errno = saved;
        return -1;
    }
    char slave_path[128];
    size_t length = 0;
    while (name[length] != '\0' && length + 1 < sizeof(slave_path)) {
        slave_path[length] = name[length];
        length++;
    }
    slave_path[length] = '\0';

    pid_t child = fork();
    if (child < 0) {
        int saved = errno;
        close(master);
        errno = saved;
        return -1;
    }

    if (child == 0) {
        /* Async-signal-safe calls only, from here to exec. */
        setsid();
        /* Unchecked on purpose: a directory that has been deleted or is not
         * readable should not cost the user their terminal. The shell then
         * starts in whatever the daemon inherited, which is what happened
         * before this argument existed. */
        if (directory != NULL) {
            (void)chdir(directory);
        }
        int slave = open(slave_path, O_RDWR);
        if (slave >= 0) {
            /* Darwin needs this explicitly; on Linux the open above already
             * did it, and asking twice is harmless. */
#if defined(TIOCSCTTY)
            ioctl(slave, TIOCSCTTY, 0);
#endif
            dup2(slave, STDIN_FILENO);
            dup2(slave, STDOUT_FILENO);
            dup2(slave, STDERR_FILENO);
            if (slave > STDERR_FILENO) {
                close(slave);
            }
        }
        /* The master must not survive into the shell: while the child holds it,
         * a read on the parent's side never sees EOF and the terminal looks
         * hung forever after the shell exits. */
        close(master);
        execve(executable, argv, envp);
        /* Only reachable if exec failed. 127 is what a shell reports for a
         * command it could not run. */
        _exit(127);
    }

    /* The parent's own handle on the terminal, for the size ioctl. Held until
     * teardown: closing it is what makes the master report EOF.
     *
     * The size is set **here**, in the parent, and nowhere else. Setting it in
     * the child instead races a resize the caller may already have asked for —
     * the child's `TIOCSWINSZ` then lands second and quietly restores the
     * default, which showed up as a resized pane reporting 80x24 about one run
     * in three. One writer, no race. */
    int slave = open(slave_path, O_RDWR | O_NOCTTY);
    if (slave >= 0) {
        struct winsize size;
        size.ws_row = rows;
        size.ws_col = columns;
        size.ws_xpixel = 0;
        size.ws_ypixel = 0;
        ioctl(slave, TIOCSWINSZ, &size);
    }
    *master_out = master;
    *slave_out = slave;
    return child;
}

int droidective_pty_resize(int terminal, unsigned short columns, unsigned short rows) {
    struct winsize size;
    size.ws_row = rows;
    size.ws_col = columns;
    size.ws_xpixel = 0;
    size.ws_ypixel = 0;
    return ioctl(terminal, TIOCSWINSZ, &size);
}

#endif
