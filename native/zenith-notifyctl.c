/*
 * Thin notification bridge client.
 *
 * Quickshell calls this binary for every presentation command. It forwards a
 * single JSON line to the Rust `zenith-native notify daemon` Unix socket and
 * prints the reply. Keeping the client in C avoids paying process startup cost
 * inside QML and gives shell scripts the same stable entry point.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static const char *socket_path(void) {
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    if (runtime == NULL || runtime[0] == '\0')
        runtime = "/tmp";
    static char path[512];
    snprintf(path, sizeof(path), "%s/zenith/notify.sock", runtime);
    return path;
}

static int usage(void) {
    fprintf(stderr,
        "Usage: zenith-notifyctl <command> [json-object]\n"
        "Commands: sync, hold, release, clear, dismiss, ping, quit\n");
    return 2;
}

int main(int argc, char **argv) {
    if (argc < 2)
        return usage();

    const char *command = argv[1];
    const char *payload = argc > 2 ? argv[2] : "{}";
    if (payload[0] != '{') {
        fprintf(stderr, "zenith-notifyctl: payload must be a JSON object\n");
        return 2;
    }

    /* Flatten the payload into the request: {"cmd":"sync","cards":[...]}.
     * The daemon reads command fields directly from the top-level object. */
    size_t json_size = strlen(command) + strlen(payload) + 32;
    char *json = malloc(json_size);
    if (json == NULL) {
        fprintf(stderr, "zenith-notifyctl: out of memory\n");
        return 1;
    }
    int printed;
    if (strlen(payload) == 2)
        printed = snprintf(json, json_size, "{\"cmd\":\"%s\"}", command);
    else
        printed = snprintf(json, json_size, "{\"cmd\":\"%s\",%s",
            command, payload + 1);
    if (printed < 0 || (size_t)printed >= json_size - 1) {
        fprintf(stderr, "zenith-notifyctl: request too large\n");
        free(json);
        return 1;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("zenith-notifyctl: socket");
        free(json);
        return 1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    const char *path = socket_path();
    if (strlen(path) >= sizeof(addr.sun_path)) {
        fprintf(stderr, "zenith-notifyctl: socket path too long\n");
        close(fd);
        free(json);
        return 1;
    }
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "zenith-notifyctl: cannot reach notify daemon: %s\n",
            strerror(errno));
        close(fd);
        free(json);
        return 1;
    }

    /* The daemon reads one JSON line, so terminate with a newline, not NUL. */
    strcat(json, "\n");
    size_t sent = 0;
    size_t total = strlen(json);
    while (sent < total) {
        ssize_t written = send(fd, json + sent, total - sent, 0);
        if (written <= 0) {
            if (errno == EINTR)
                continue;
            perror("zenith-notifyctl: send");
            close(fd);
            free(json);
            return 1;
        }
        sent += (size_t)written;
    }
    free(json);

    char buffer[4096];
    ssize_t count = recv(fd, buffer, sizeof(buffer) - 1, 0);
    close(fd);
    if (count <= 0) {
        fprintf(stderr, "zenith-notifyctl: daemon closed the connection\n");
        return 1;
    }
    buffer[count] = '\0';

    /* Strip the trailing newline before echoing the response. */
    char *newline = strchr(buffer, '\n');
    if (newline != NULL)
        *newline = '\0';
    printf("%s\n", buffer);

    if (strstr(buffer, "\"ok\":true") == NULL)
        return 1;
    return 0;
}
