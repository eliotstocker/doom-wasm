#include <errno.h>

int system(const char *cmd) {
    (void)cmd;
    errno = ENOSYS;
    return -1;
}
