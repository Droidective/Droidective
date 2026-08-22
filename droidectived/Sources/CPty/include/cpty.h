#ifndef DROIDECTIVE_CPTY_H
#define DROIDECTIVE_CPTY_H

/*
 * Opening a pseudo-terminal and starting a shell on it.
 *
 * In C rather than Swift because of one hard requirement: between `fork` and
 * `exec` a process may only call async-signal-safe functions. Swift marks
 * `fork` unavailable for exactly that reason — the runtime is not safe there —
 * so doing this in Swift would mean either working around the unavailability or
 * hoping no allocation happens in a code path the compiler is free to change.
 * Here the constraint is expressed where it can actually be honoured.
 *
 * Why a controlling terminal matters: without one the shell reads from a
 * terminal it does not control, takes SIGTTIN and stops — alive, still echoing
 * keystrokes through the tty driver, running nothing. Linux grants the terminal
 * as a side effect of a session leader opening it; Darwin needs the explicit
 * `ioctl(TIOCSCTTY)` below, which no `posix_spawn` file action can express.
 */

#if defined(_WIN32)

/* Windows needs ConPTY, which is a different API rather than a variation on
 * this one. Declared so the Swift side compiles; it always fails. */
int droidective_pty_spawn(const char *executable, char *const argv[], char *const envp[],
                          const char *directory, unsigned short columns, unsigned short rows,
                          int *master_out, int *slave_out);

#else

#include <sys/types.h>

/*
 * Opens a pty, sets its window size, and execs `executable` on the slave side
 * as a session leader owning the terminal.
 *
 * Returns the child pid and writes both descriptors out, or returns -1 with
 * `errno` set and neither touched. On failure nothing is left open.
 *
 * `slave_out` is the caller's *own* handle on the terminal, and it is what the
 * window-size ioctl needs: macOS rejects `TIOCSWINSZ` on the master with
 * ENOTTY. It must be held for the pty's whole life rather than opened per
 * resize — closing the last slave descriptor hangs the master up, so an
 * open/ioctl/close pair races the child's own open and kills the shell before
 * it has printed a prompt. Closing it is therefore also how the caller makes
 * the master report EOF once the child is gone.
 *
 * `directory` is where the shell starts. NULL keeps whatever the caller's own
 * working directory is; a path that cannot be entered is not fatal — the shell
 * starts anyway, in the inherited directory, because a terminal is more useful
 * than an error.
 */
pid_t droidective_pty_spawn(const char *executable, char *const argv[], char *const envp[],
                            const char *directory, unsigned short columns, unsigned short rows,
                            int *master_out, int *slave_out);

/*
 * Tells the terminal it is a different size, so a resized pane re-wraps rather
 * than drawing to the old width. `terminal` is the slave descriptor from
 * `droidective_pty_spawn`.
 *
 * Here rather than in Swift because `TIOCSWINSZ` does not survive the trip:
 * Darwin defines it as `_IOW('t', 103, struct winsize)`, which is 0x80087467 —
 * a value Swift imports as a *signed* 32-bit constant, so it sign-extends to
 * something the kernel rejects. In C the type is right by construction.
 */
int droidective_pty_resize(int terminal, unsigned short columns, unsigned short rows);

#endif

#endif /* DROIDECTIVE_CPTY_H */
