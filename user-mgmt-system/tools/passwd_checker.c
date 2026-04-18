/*
 * passwd_checker.c
 * Standalone password strength checker.
 *
 * Usage:
 *   ./passwd_checker <password>
 *   echo -n "secret" | ./passwd_checker
 *
 * Exit codes:
 *   0 = STRONG
 *   1 = WEAK
 *
 * OS concept: demonstrates using a compiled C binary alongside shell
 * scripts. Reads from argv or stdin via read(2)/fgets.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MIN_LEN 8
#define MAX_PW  256

static int check(const char *pw, char *reason, size_t rsz) {
    int has_upper = 0, has_digit = 0, has_special = 0;
    size_t len = strlen(pw);

    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)pw[i];
        if (isupper(c)) has_upper = 1;
        else if (isdigit(c)) has_digit = 1;
        else if (!isalnum(c) && !isspace(c)) has_special = 1;
    }

    reason[0] = '\0';
    int ok = 1;
    if (len < MIN_LEN) {
        strncat(reason, "length<8; ", rsz - strlen(reason) - 1);
        ok = 0;
    }
    if (!has_upper) {
        strncat(reason, "no uppercase; ", rsz - strlen(reason) - 1);
        ok = 0;
    }
    if (!has_digit) {
        strncat(reason, "no digit; ", rsz - strlen(reason) - 1);
        ok = 0;
    }
    if (!has_special) {
        strncat(reason, "no special; ", rsz - strlen(reason) - 1);
        ok = 0;
    }
    return ok;
}

int main(int argc, char **argv) {
    char pw[MAX_PW];
    char reason[256];

    if (argc >= 2) {
        strncpy(pw, argv[1], sizeof(pw) - 1);
        pw[sizeof(pw) - 1] = '\0';
    } else {
        if (!fgets(pw, sizeof(pw), stdin)) {
            fprintf(stderr, "No password provided.\n");
            return 1;
        }
        size_t n = strlen(pw);
        if (n > 0 && pw[n - 1] == '\n') pw[n - 1] = '\0';
    }

    if (check(pw, reason, sizeof(reason))) {
        printf("STRONG\n");
        return 0;
    } else {
        printf("WEAK: %s\n", reason);
        return 1;
    }
}
