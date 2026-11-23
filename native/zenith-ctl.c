/* =============================================================================
 *  ZENITH-CTL: Sub-Millisecond Toggle Dispatcher (C)
 * =============================================================================
 *  Replaces bash/pgrep/pkill cascades on the keybind hot path.
 *  Uses atomic PID inspection and direct execve() to achieve true 0ms dispatch.
 * =============================================================================
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <limits.h>

static void get_runtime_path(char *dest, size_t size, const char *filename) {
    const char *xdg = getenv("XDG_RUNTIME_DIR");
    if (xdg && *xdg) {
        snprintf(dest, size, "%s/zenith", xdg);
    } else {
        snprintf(dest, size, "/tmp/zenith-%d", getuid());
    }
    mkdir(dest, 0700);
    if (filename) {
        size_t len = strlen(dest);
        snprintf(dest + len, size - len, "/%s", filename);
    }
}

static const char *get_zenith_root(void) {
    static char root[PATH_MAX] = {0};
    if (root[0]) return root;

    const char *env = getenv("ZENITH_ROOT");
    if (env && *env) {
        strncpy(root, env, sizeof(root) - 1);
        return root;
    }

    /* Fallback: derive from executable directory */
    ssize_t len = readlink("/proc/self/exe", root, sizeof(root) - 1);
    if (len > 0) {
        root[len] = '\0';
        char *slash = strrchr(root, '/');
        if (slash) *slash = '\0'; /* in bin or build */
        slash = strrchr(root, '/');
        if (slash) *slash = '\0'; /* root */
        return root;
    }

    const char *home = getenv("HOME");
    if (home) {
        char root_file[PATH_MAX];
        snprintf(root_file, sizeof(root_file), "%s/.config/zenith/root", home);
        FILE *rf = fopen(root_file, "r");
        if (rf) {
            if (fgets(root, sizeof(root), rf)) {
                size_t l = strlen(root);
                while (l > 0 && (root[l - 1] == '\n' || root[l - 1] == '\r' || root[l - 1] == ' ')) {
                    root[--l] = '\0';
                }
                fclose(rf);
                if (root[0]) return root;
            } else {
                fclose(rf);
            }
        }
        snprintf(root, sizeof(root), "%s/zenith", home);
    } else {
        strcpy(root, "/etc/zenith");
    }
    return root;
}

static pid_t read_pid(const char *pid_file) {
    FILE *f = fopen(pid_file, "r");
    if (!f) return -1;
    pid_t pid = -1;
    if (fscanf(f, "%d", &pid) != 1) pid = -1;
    fclose(f);
    return pid;
}

static void write_pid(const char *pid_file, pid_t pid) {
    FILE *f = fopen(pid_file, "w");
    if (f) {
        fprintf(f, "%d\n", pid);
        fclose(f);
    }
}

int main(int argc, char **argv) {
    if (argc < 3 || strcmp(argv[1], "toggle") != 0) {
        fprintf(stderr, "Usage: %s toggle <launcher|clipboard|window|gallery>\n", argv[0]);
        return 1;
    }

    const char *target = argv[2];
    char pid_file[PATH_MAX];
    char pid_name[64];
    snprintf(pid_name, sizeof(pid_name), "%s.pid", target);
    get_runtime_path(pid_file, sizeof(pid_file), pid_name);

    /* 1. Fast path: If process exists and responds to kill(pid, 0), toggle off */
    pid_t existing_pid = read_pid(pid_file);
    if (existing_pid > 0 && kill(existing_pid, 0) == 0) {
        kill(existing_pid, SIGTERM);
        unlink(pid_file);
        return 0;
    }

    /* 2. Process is not active: spawn immediately */
    const char *root = get_zenith_root();
    pid_t child = fork();
    if (child < 0) {
        perror("fork");
        return 1;
    }

    if (child == 0) {
        /* In child process */
        write_pid(pid_file, getpid());

        if (strcmp(target, "launcher") == 0) {
            char theme_path[PATH_MAX];
            snprintf(theme_path, sizeof(theme_path), "%s/rofi/launcher.rasi", root);
            char *args[] = {"rofi", "-show", "drun", "-theme", theme_path, NULL};
            execvp("rofi", args);
        } else if (strcmp(target, "clipboard") == 0) {
            char theme_path[PATH_MAX], mode_arg[PATH_MAX];
            snprintf(theme_path, sizeof(theme_path), "%s/rofi/clipboard.rasi", root);
            snprintf(mode_arg, sizeof(mode_arg), "clipboard:%s/scripts/clipboard-mode.sh", root);
            char *args[] = {
                "rofi", "-no-config", "-show", "clipboard",
                "-modes", mode_arg, "-hover-select",
                "-theme", theme_path,
                "-kb-delete-entry", "",
                "-kb-custom-1", "Shift+Delete",
                "-kb-custom-2", "Control+Shift+Delete",
                NULL
            };
            execvp("rofi", args);
        } else if (strcmp(target, "window") == 0) {
            char theme_path[PATH_MAX];
            snprintf(theme_path, sizeof(theme_path), "%s/rofi/launcher.rasi", root);
            char *args[] = {"rofi", "-show", "window", "-theme", theme_path, NULL};
            execvp("rofi", args);
        } else if (strcmp(target, "gallery") == 0) {
            char gallery_path[PATH_MAX];
            snprintf(gallery_path, sizeof(gallery_path), "%s/build/gallery", root);
            char *args[] = {gallery_path, NULL};
            execv(gallery_path, args);
        }

        perror("execvp");
        _exit(127);
    }

    /* Parent exits instantly (< 0.2ms) */
    return 0;
}
