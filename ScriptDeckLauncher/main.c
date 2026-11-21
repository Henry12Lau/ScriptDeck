#include <errno.h>
#include <unistd.h>

/// Minimal launcher helper that isolates each started script into its own
/// process group before replacing itself with the target executable via execv.
/// Foundation.Process does not expose POSIX_SPAWN_SETPGROUP / setpgid before exec.
int main(int argc, char *argv[]) {
    if (argc < 2) {
        _exit(126);
    }

    // Create a dedicated process group (pgid == pid) so Stop can signal
    // the script and any foreground child processes it spawns together.
    if (setpgid(0, 0) != 0) {
        _exit(126);
    }

    execv(argv[1], &argv[1]);

    int err = errno;
    if (err == ENOENT || err == ENOTDIR) {
        _exit(127);
    }
    _exit(126);
}
