// Bộ gác an toàn (xem G6Guard.h). Chỉ libc: không ObjC, không lõi Rust — thứ gì hỏng thì phần này vẫn phải chạy được.
#include "G6Guard.h"

#include <ctype.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Tệp của một tiến trình: <thư mục>/<loại>.<tên> — tên chỉ giữ chữ và số (không để tên lạ thành đường dẫn)
static int kind_path(const char *dir, const char *kind, const char *process, char *buf, size_t len) {
    char name[64];
    size_t n = 0;
    for (const char *p = process; p && *p && n < sizeof(name) - 1; p++) {
        if (isalnum((unsigned char)*p)) name[n++] = *p;
    }
    name[n] = 0;
    if (n == 0) return -1;
    int w = snprintf(buf, len, "%s/%s.%s", dir, kind, name);
    return (w > 0 && (size_t)w < len) ? 0 : -1;
}

// Tệp đếm của SpringBoard: G6_DIR/boot.<tên>
static int boot_path(const char *process, char *buf, size_t len) {
    return kind_path(G6_DIR, "boot", process, buf, len);
}

static int read_count(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    char buf[8] = {0};
    ssize_t r = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (r <= 0) return 0;
    int v = atoi(buf);
    return v < 0 ? 0 : v;
}

static void write_text(const char *path, const char *text) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    ssize_t r = write(fd, text, strlen(text));
    (void)r;
    // Ghi xuống đĩa ngay: lần này mà sập thì lần sau phải đọc được số mới
    fsync(fd);
    close(fd);
}

int g6_guard_begin(const char *process) {
    mkdir(G6_DIR, 0755);
    if (access(G6_OFF_FILE, F_OK) == 0) return G6GuardOffFile;
    if (access(G6_AUTO_OFF_FILE, F_OK) == 0) return G6GuardAutoOff;
    char path[256];
    // Không lập được tệp đếm thì vẫn chạy — chỉ là không đếm được
    if (boot_path(process, path, sizeof(path)) != 0) return G6GuardRun;
    int n = read_count(path);
    if (n >= G6_BOOT_LIMIT) {
        char why[128];
        snprintf(why, sizeof(why), "%s\n", process);
        write_text(G6_AUTO_OFF_FILE, why);
        unlink(path);
        return G6GuardAutoOff;
    }
    char num[16];
    snprintf(num, sizeof(num), "%d\n", n + 1);
    write_text(path, num);
    return G6GuardRun;
}

void g6_guard_confirm(const char *process) {
    char path[256];
    if (boot_path(process, path, sizeof(path)) == 0) unlink(path);
}

int g6_guard_app_begin(const char *process) {
    if (access(G6_OFF_FILE, F_OK) == 0) return G6GuardOffFile;
    if (access(G6_AUTO_OFF_FILE, F_OK) == 0) return G6GuardAutoOff;
    char count[256], skip[256];
    // Không lập được tên tệp (tên tiến trình không có chữ / số nào): không gác được thì không đụng vào app đó
    if (kind_path(G6_APP_DIR, "app", process, count, sizeof(count)) != 0 ||
        kind_path(G6_APP_DIR, "skip", process, skip, sizeof(skip)) != 0) {
        return G6GuardAppSkip;
    }
    mkdir(G6_APP_DIR, 0755);
    if (access(skip, F_OK) == 0) return G6GuardAppSkip;
    int n = read_count(count);
    if (n >= G6_BOOT_LIMIT) {
        write_text(skip, "1\n");
        unlink(count);
        return G6GuardAppSkip;
    }
    char num[16];
    snprintf(num, sizeof(num), "%d\n", n + 1);
    write_text(count, num);
    // Hộp cát của app không cho ghi cả vào G6_APP_DIR: không đếm được thì không đụng vào app đó
    if (access(count, F_OK) != 0) return G6GuardAppSkip;
    return G6GuardRun;
}

void g6_guard_app_confirm(const char *process) {
    char path[256];
    if (kind_path(G6_APP_DIR, "app", process, path, sizeof(path)) == 0) unlink(path);
}
