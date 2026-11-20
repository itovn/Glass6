// g6svc — công cụ quyền root (setuid) tắt / bật các dịch vụ hệ thống CÓ TRONG DANH MỤC của Glass 6. Xem docs/THIET-KE.md mục 7.
//
//   g6svc status              in «<mã>\t<0|1>» cho từng dịch vụ trong danh mục có trên máy (1 = đang tắt); thêm «#pending\t<n>» nếu có
//                             lần đổi chưa được xác nhận, «#reverted\t1» nếu bộ gác vừa tự hoàn tác
//   g6svc set <mã>=<0|1> …    tắt (1) / bật (0) từng dịch vụ; mã lạ → không làm gì cả, thoát mã 2
//   g6svc revert              bật lại mọi dịch vụ trong danh mục (về nguyên bản)
//   g6svc confirm             SpringBoard gọi sau khi chạy ổn 60 giây: xác nhận lần đổi gần nhất — chỉ có tác dụng khi máy
//                             đã khởi động lại ít nhất một lần kể từ lần đổi đó
//   g6svc boot                launchd gọi mỗi lần máy khởi động (vn.glass6.svcguard): lần đổi chưa được xác nhận mà máy đã
//                             khởi động 2 lần → tự hoàn tác về trạng thái trước lần đổi
//   g6svc ack                 bảng Cài đặt gọi sau khi đã báo «đã tự hoàn tác»: bỏ dấu báo
//
// An toàn:
//   - danh sách trắng cứng trong mã (catalog.h, sinh từ data/services.tsv lúc dựng): tham số chỉ là MÃ dịch vụ, không bao giờ
//     là đường dẫn hay nhãn launchd; không có mã thì không có cách nào bảo công cụ đụng tới dịch vụ khác;
//   - tắt bằng «launchctl unload -w», bật bằng «launchctl load -w» trên tệp của chính hệ thống — không xoá, không sửa tệp nào;
//   - môi trường bị xoá sạch trước khi gọi /bin/launchctl bằng đường dẫn tuyệt đối.
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "catalog.h"

#define LAUNCHCTL "/bin/launchctl"
#define DAEMON_DIR "/System/Library/LaunchDaemons/"
#define STATE_DIR "/var/db/glass6"
#define PENDING STATE_DIR "/pending"
#define PREVIOUS STATE_DIR "/previous"
#define REVERTED STATE_DIR "/reverted"
// Số lần khởi động liền mà lần đổi vẫn chưa được xác nhận thì hoàn tác
#define BOOT_LIMIT 2
// Đầu ra của «launchctl list» trên iPad mini 1 khoảng 8 KB; quá ngưỡng này là có gì đó sai
#define LIST_MAX (256 * 1024)

extern char **environ;

static const struct g6_service *find(const char *id) {
    for (int i = 0; i < G6_SERVICE_COUNT; i++) {
        if (strcmp(kServices[i].id, id) == 0) return &kServices[i];
    }
    return NULL;
}

// Chạy launchctl với tối đa 3 tham số; trả mã thoát (−1 nếu không chạy được). `capture` khác NULL thì nhận đầu ra chuẩn
// (bên gọi free), không thì đầu ra bị bỏ.
static int launchctl(const char *a1, const char *a2, const char *a3, char **capture) {
    int fds[2] = {-1, -1};
    if (capture) {
        *capture = NULL;
        if (pipe(fds) != 0) return -1;
    }
    pid_t pid = fork();
    if (pid < 0) {
        if (capture) {
            close(fds[0]);
            close(fds[1]);
        }
        return -1;
    }
    if (pid == 0) {
        int null = open("/dev/null", O_RDWR);
        if (null >= 0) {
            dup2(null, 0);
            dup2(null, 2);
            if (!capture) dup2(null, 1);
        }
        if (capture) {
            dup2(fds[1], 1);
            close(fds[0]);
            close(fds[1]);
        }
        char *const argv[] = {(char *)"launchctl", (char *)a1, (char *)a2, (char *)a3, NULL};
        char *const envp[] = {(char *)"PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL};
        execve(LAUNCHCTL, argv, envp);
        _exit(127);
    }
    if (capture) {
        close(fds[1]);
        size_t size = 0, cap = 16 * 1024;
        char *buf = malloc(cap + 1);
        while (buf) {
            ssize_t n = read(fds[0], buf + size, cap - size);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) break;
            size += (size_t)n;
            if (size == cap) {
                if (cap >= LIST_MAX) break;
                cap *= 2;
                char *bigger = realloc(buf, cap + 1);
                if (!bigger) {
                    free(buf);
                    buf = NULL;
                    break;
                }
                buf = bigger;
            }
        }
        close(fds[0]);
        if (buf) buf[size] = 0;
        *capture = buf;
    }
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static void plist_path(const char *file, char *out, size_t size) {
    snprintf(out, size, DAEMON_DIR "%s.plist", file);
}

// Danh sách việc launchd đang nạp («launchctl list»: mỗi dòng «PID<TAB>Status<TAB>Nhãn») — hỏi một lần cho mọi nhãn thay vì
// chạy launchctl hai chục lần; đọc lại sau mỗi lần nạp / gỡ.
static char *gList;
static int gListStale = 1;

static int label_loaded(const char *label) {
    if (gListStale) {
        free(gList);
        gList = NULL;
        if (launchctl("list", NULL, NULL, &gList) != 0) {
            free(gList);
            gList = NULL;
        }
        gListStale = 0;
    }
    // Không lấy được danh sách: hỏi riêng từng nhãn («launchctl list <nhãn>» thoát 0 khi nhãn đang được nạp)
    if (!gList) return launchctl("list", label, NULL, NULL) == 0;
    size_t len = strlen(label);
    for (const char *line = gList; *line;) {
        const char *end = strchr(line, '\n');
        size_t n = end ? (size_t)(end - line) : strlen(line);
        if (n > len && line[n - len - 1] == '\t' && memcmp(line + n - len, label, len) == 0) return 1;
        if (!end) break;
        line = end + 1;
    }
    return 0;
}

// Máy này có dịch vụ đó không (có ít nhất một tệp việc) — vd bản chỉ Wi-Fi không có dịch vụ của mạng di động
static int service_present(const struct g6_service *s) {
    for (int i = 0; s->jobs[i].file; i++) {
        char path[256];
        plist_path(s->jobs[i].file, path, sizeof(path));
        if (access(path, F_OK) == 0) return 1;
    }
    return 0;
}

// Dịch vụ đang tắt = có ít nhất một việc (có tệp trên máy này) không được launchd nạp
static int service_disabled(const struct g6_service *s) {
    for (int i = 0; s->jobs[i].file; i++) {
        char path[256];
        plist_path(s->jobs[i].file, path, sizeof(path));
        if (access(path, F_OK) != 0) continue;
        if (!label_loaded(s->jobs[i].label)) return 1;
    }
    return 0;
}

static void service_set(const struct g6_service *s, int disable) {
    for (int i = 0; s->jobs[i].file; i++) {
        char path[256];
        plist_path(s->jobs[i].file, path, sizeof(path));
        if (access(path, F_OK) != 0) continue;
        // Chỉ gọi launchctl khi trạng thái thật khác trạng thái muốn: gỡ rồi nạp lại không cần thiết thì dịch vụ đang chạy
        // bị khởi động lại
        int loaded = label_loaded(s->jobs[i].label);
        if (disable && loaded) {
            launchctl("unload", "-w", path, NULL);
            gListStale = 1;
        } else if (!disable && !loaded) {
            launchctl("load", "-w", path, NULL);
            gListStale = 1;
        }
    }
}

// ---- Trạng thái của bộ gác (tệp trong STATE_DIR, chỉ root ghi được) ----

// Số lần máy đã khởi động kể từ lần đổi chưa xác nhận; −1 = không có lần đổi nào đang chờ
static int read_counter(void) {
    FILE *f = fopen(PENDING, "r");
    if (!f) return -1;
    int n = 0;
    if (fscanf(f, "%d", &n) != 1) n = 0;
    fclose(f);
    return n < 0 ? 0 : n;
}

static void write_counter(int n) {
    FILE *f = fopen(PENDING, "w");
    if (!f) return;
    fprintf(f, "%d\n", n);
    fclose(f);
    chmod(PENDING, 0644);
}

// Ghi trạng thái hiện tại của mọi dịch vụ — để hoàn tác nếu lần đổi sắp tới làm máy khởi động không ổn
static void save_previous(void) {
    FILE *f = fopen(PREVIOUS, "w");
    if (!f) return;
    for (int i = 0; i < G6_SERVICE_COUNT; i++) {
        if (service_present(&kServices[i])) fprintf(f, "%s\t%d\n", kServices[i].id, service_disabled(&kServices[i]));
    }
    fclose(f);
}

static void restore_previous(void) {
    FILE *f = fopen(PREVIOUS, "r");
    if (!f) {
        // Không còn bản ghi: về nguyên bản là lựa chọn an toàn nhất
        for (int i = 0; i < G6_SERVICE_COUNT; i++) service_set(&kServices[i], 0);
        return;
    }
    char id[64];
    int disabled = 0;
    while (fscanf(f, "%63s %d", id, &disabled) == 2) {
        const struct g6_service *s = find(id);
        if (s) service_set(s, disabled != 0);
    }
    fclose(f);
}

// Trạng thái hiện tại của mọi dịch vụ có trùng với bản ghi «trước lần đổi» không (không còn gì để xác nhận / hoàn tác)
static int same_as_previous(void) {
    FILE *f = fopen(PREVIOUS, "r");
    if (!f) return 0;
    char id[64];
    int disabled = 0, same = 1;
    while (same && fscanf(f, "%63s %d", id, &disabled) == 2) {
        const struct g6_service *s = find(id);
        if (s && service_disabled(s) != (disabled != 0)) same = 0;
    }
    fclose(f);
    return same;
}

static void clear_state(void) {
    unlink(PENDING);
    unlink(PREVIOUS);
}

static int usage(void) {
    fprintf(stderr, "dùng: g6svc status | set <mã>=<0|1> ... | revert | confirm | boot | ack\n");
    return 2;
}

// Tách «<mã>=<0|1>»; trả dịch vụ và đặt *disable, NULL nếu tham số sai dạng hoặc mã không có trong danh mục
static const struct g6_service *parse_assignment(const char *arg, int *disable) {
    char id[64];
    const char *eq = strchr(arg, '=');
    if (!eq) return NULL;
    size_t n = (size_t)(eq - arg);
    if (n == 0 || n >= sizeof(id)) return NULL;
    if (strcmp(eq + 1, "0") != 0 && strcmp(eq + 1, "1") != 0) return NULL;
    memcpy(id, arg, n);
    id[n] = 0;
    *disable = eq[1] == '1';
    return find(id);
}

int main(int argc, char **argv) {
    if (argc < 2) return usage();
    const char *cmd = argv[1];
    // Cả việc đọc trạng thái cũng cần uid 0: launchctl phải hỏi launchd của hệ thống
    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "g6svc: không lấy được quyền root (tệp phải thuộc root và có bit setuid)\n");
        return 1;
    }
    static char *empty_env[] = {NULL};
    environ = empty_env;
    umask(022);
    // Ba tệp chuẩn 0–2 phải đang mở: tiến trình gọi mà đóng sẵn chúng thì tệp trạng thái / ống dẫn ta mở sau sẽ nhận nhầm
    // số 0–2 và bị ghi lẫn
    for (;;) {
        int fd = open("/dev/null", O_RDWR);
        if (fd < 0) return 1;
        if (fd > 2) {
            close(fd);
            break;
        }
    }

    if (strcmp(cmd, "status") == 0) {
        // Dịch vụ không có trên máy này thì không in — bảng Cài đặt không hiện công tắc cho nó
        for (int i = 0; i < G6_SERVICE_COUNT; i++) {
            if (service_present(&kServices[i])) printf("%s\t%d\n", kServices[i].id, service_disabled(&kServices[i]));
        }
        int pending = read_counter();
        if (pending >= 0) printf("#pending\t%d\n", pending);
        if (access(REVERTED, F_OK) == 0) printf("#reverted\t1\n");
        return 0;
    }

    mkdir(STATE_DIR, 0755);

    if (strcmp(cmd, "set") == 0) {
        if (argc < 3) return usage();
        // Kiểm mọi tham số trước, sai một cái là không làm gì cả
        for (int i = 2; i < argc; i++) {
            int disable = 0;
            if (!parse_assignment(argv[i], &disable)) {
                fprintf(stderr, "g6svc: «%s» sai dạng hoặc không có trong danh mục\n", argv[i]);
                return 2;
            }
        }
        // Lần đổi đầu kể từ lần xác nhận gần nhất: ghi lại trạng thái để hoàn tác được. Mỗi lần đổi đều đếm lại từ 0 —
        // phải qua một lần khởi động máy với đúng cấu hình này rồi mới được xác nhận.
        if (read_counter() < 0) save_previous();
        write_counter(0);
        unlink(REVERTED);
        for (int i = 2; i < argc; i++) {
            int disable = 0;
            const struct g6_service *s = parse_assignment(argv[i], &disable);
            if (s) service_set(s, disable);
        }
        // Đổi qua đổi lại rồi về đúng trạng thái trước lần đổi đầu: không còn gì chờ xác nhận
        if (same_as_previous()) clear_state();
        return 0;
    }
    if (strcmp(cmd, "revert") == 0) {
        for (int i = 0; i < G6_SERVICE_COUNT; i++) service_set(&kServices[i], 0);
        clear_state();
        unlink(REVERTED);
        return 0;
    }
    if (strcmp(cmd, "confirm") == 0) {
        // Chưa qua lần khởi động máy nào với cấu hình mới thì chưa có gì để xác nhận
        if (read_counter() >= 1) clear_state();
        return 0;
    }
    if (strcmp(cmd, "ack") == 0) {
        unlink(REVERTED);
        return 0;
    }
    if (strcmp(cmd, "boot") == 0) {
        int n = read_counter();
        if (n < 0) return 0;  // không có lần đổi nào đang chờ xác nhận
        n++;
        if (n >= BOOT_LIMIT) {
            restore_previous();
            clear_state();
            // Dấu để bảng Cài đặt báo cho người dùng biết đã tự hoàn tác
            int fd = open(REVERTED, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) close(fd);
        } else {
            write_counter(n);
        }
        return 0;
    }
    return usage();
}
