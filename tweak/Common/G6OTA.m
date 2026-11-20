#import "G6OTA.h"

#import "G6Lang.h"
#import "G6Log.h"
#import <fcntl.h>
#import <signal.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>

@implementation G6OTATask

- (void)cancel {
    self.cancelled = YES;
    pid_t pid = self.pid;
    if (pid > 0) kill(pid, SIGTERM);
}

@end

// Chạy một công cụ, chỉ đưa cho nó ba tệp chuẩn (mọi tệp đang mở khác của tiến trình chủ tự đóng) và một môi trường tối
// thiểu. `outFd`: đầu ghi của ống nhận stdout (-1 = bỏ stdout). Trả pid, 0 nếu không chạy được.
static pid_t G6OTASpawn(const char *tool, NSArray *args, int outFd) {
    if (access(tool, X_OK) != 0) return 0;
    NSUInteger n = args.count;
    char **argv = calloc(n + 2, sizeof(char *));
    if (!argv) return 0;
    argv[0] = (char *)tool;
    for (NSUInteger i = 0; i < n; i++) argv[i + 1] = (char *)[[args[i] description] fileSystemRepresentation];
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    if (outFd >= 0) posix_spawn_file_actions_adddup2(&actions, outFd, 1);
    else posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Luồng nền của GCD chặn gần hết tín hiệu và tiến trình con thừa hưởng mặt nạ đó: không đặt lại thì glass6ctl không nhận
    // SIGTERM — bấm «Huỷ» mà nó vẫn tải nốt (đã gặp). Con chạy với mặt nạ trống, mọi tín hiệu về cách xử lý mặc định.
    sigset_t none, all;
    sigemptyset(&none);
    sigfillset(&all);
    posix_spawnattr_setsigmask(&attr, &none);
    posix_spawnattr_setsigdefault(&attr, &all);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    char *envp[] = {(char *)"PATH=/usr/bin:/bin:/usr/sbin:/sbin", (char *)"HOME=/var/mobile", NULL};
    pid_t pid = 0;
    int rc = posix_spawn(&pid, tool, &actions, &attr, argv, envp);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);
    free(argv);
    if (rc != 0) {
        G6Log(@"cập nhật: không chạy được %s (lỗi %d)", tool, rc);
        return 0;
    }
    return pid;
}

static int G6OTAWait(pid_t pid) {
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

int G6OTARun(NSArray *args, G6OTATask *task, void (^onLine)(NSString *line)) {
    int fds[2];
    if (pipe(fds) != 0) return -1;
    pid_t pid = G6OTASpawn(G6_OTA_CTL, args, fds[1]);
    close(fds[1]);
    if (pid <= 0) {
        close(fds[0]);
        return -1;
    }
    task.pid = pid;
    // Bị huỷ đúng lúc vừa chạy lên: -cancel chưa thấy pid
    if (task.cancelled) kill(pid, SIGTERM);
    NSMutableData *pending = [NSMutableData data];
    char buf[2048];
    for (;;) {
        ssize_t r = read(fds[0], buf, sizeof(buf));
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) break;
        [pending appendBytes:buf length:(NSUInteger)r];
        // Tách các dòng đã trọn; không để một công cụ nói mãi làm phình bộ nhớ (dòng dài nhất là JSON kèm ghi chú, vài KB)
        for (;;) {
            const char *bytes = pending.bytes;
            const char *nl = memchr(bytes, '\n', pending.length);
            if (!nl) break;
            NSUInteger len = (NSUInteger)(nl - bytes);
            NSString *line = [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
            [pending replaceBytesInRange:NSMakeRange(0, len + 1) withBytes:NULL length:0];
            if (line.length && onLine) onLine(line);
        }
        if (pending.length > 256 * 1024) break;
    }
    close(fds[0]);
    if (pending.length && pending.length <= 256 * 1024 && onLine) {
        NSString *line = [[NSString alloc] initWithData:pending encoding:NSUTF8StringEncoding];
        if (line.length) onLine(line);
    }
    int code = G6OTAWait(pid);
    task.pid = 0;
    return code;
}

NSDictionary *G6OTAParse(NSString *line) {
    if (![line hasPrefix:@"{"]) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

NSDictionary *G6OTACheck(NSString *currentVersion) {
    __block NSDictionary *result = nil;
    NSArray *args = currentVersion.length ? @[@"update", @"check", @"--current", currentVersion] : @[@"update", @"check"];
    int code = G6OTARun(args, nil, ^(NSString *line) {
        NSDictionary *d = G6OTAParse(line);
        if (d) result = d;
    });
    if (!result) return @{@"ok" : @NO, @"error" : @"tool", @"detail" : [NSString stringWithFormat:@"glass6ctl → %d", code]};
    return result;
}

// Phần số của một số bản: «v1.2.3», «1.2.3-1+debug» → 1, 2, 3
static NSArray *G6OTANumbers(NSString *version) {
    NSString *v = [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([v hasPrefix:@"v"] || [v hasPrefix:@"V"]) v = [v substringFromIndex:1];
    NSRange cut = [v rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"-+~"]];
    if (cut.location != NSNotFound) v = [v substringToIndex:cut.location];
    NSMutableArray *numbers = [NSMutableArray array];
    for (NSString *part in [v componentsSeparatedByString:@"."]) [numbers addObject:@([part longLongValue])];
    return numbers;
}

BOOL G6OTANewer(NSString *a, NSString *b) {
    if (![a isKindOfClass:[NSString class]] || ![b isKindOfClass:[NSString class]]) return NO;
    NSArray *x = G6OTANumbers(a), *y = G6OTANumbers(b);
    for (NSUInteger i = 0; i < MAX(x.count, y.count); i++) {
        long long p = i < x.count ? [x[i] longLongValue] : 0, q = i < y.count ? [y[i] longLongValue] : 0;
        if (p != q) return p > q;
    }
    return NO;
}

NSDictionary *G6OTAPending(NSString *currentVersion) {
    NSData *data = [NSData dataWithContentsOfFile:@G6_OTA_STATE];
    if (!data.length || data.length > 64 * 1024) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]] || ![json[@"ok"] boolValue]) return nil;
    // Tệp có thể cũ hơn bản đang chạy (vừa cập nhật xong): so lại với bản hiện tại thay vì tin khoá «newer»
    return G6OTANewer(json[@"latest"], currentVersion) ? json : nil;
}

BOOL G6OTAHelperReady(void) {
    struct stat st;
    return stat(G6_OTA_HELPER, &st) == 0 && st.st_uid == 0 && (st.st_mode & S_ISUID) != 0;
}

int G6OTAInstallPackage(NSString *debPath, NSString *sigPath) {
    if (!debPath.length || !sigPath.length) return -1;
    pid_t pid = G6OTASpawn(G6_OTA_HELPER, @[debPath, sigPath], -1);
    if (pid <= 0) return -1;
    int code = G6OTAWait(pid);
    G6Log(@"cập nhật: g6update → %d", code);
    return code;
}

NSString *G6OTAErrorText(NSDictionary *result) {
    NSString *error = [result[@"error"] isKindOfClass:[NSString class]] ? result[@"error"] : @"";
    if ([error isEqualToString:@"network"]) return G6L(@"Không kết nối được tới GitHub. Kiểm tra mạng rồi thử lại.");
    if ([error isEqualToString:@"tls"]) {
        return G6L(@"Không lập được kết nối an toàn tới GitHub. Kiểm tra ngày giờ của máy rồi thử lại.");
    }
    if ([error isEqualToString:@"http"]) {
        int status = [result[@"status"] intValue];
        if (status == 404) return G6L(@"Chưa có bản phát hành nào.");
        if (status == 403 || status == 429) return G6L(@"GitHub đang giới hạn số lần hỏi từ mạng này. Thử lại sau ít phút.");
        return [NSString stringWithFormat:G6L(@"GitHub trả mã lỗi %d. Thử lại sau."), status];
    }
    if ([error isEqualToString:@"unsigned"]) {
        return G6L(@"Bản này không kèm gói có chữ ký số. Cập nhật bằng Cydia (nguồn itovn.github.io/Glass6/cydia).");
    }
    if ([error isEqualToString:@"size"] || [error isEqualToString:@"hash"]) return G6L(@"Tệp tải về bị sai. Thử tải lại.");
    if ([error isEqualToString:@"signature"]) return G6L(@"Không tải được chữ ký số của bản cập nhật. Thử lại sau.");
    if ([error isEqualToString:@"io"]) return G6L(@"Không ghi được tệp tải về. Kiểm tra dung lượng trống của máy.");
    if ([error isEqualToString:@"current"]) return G6L(@"Đang dùng bản mới nhất.");
    if ([error isEqualToString:@"tool"]) {
        return G6L(@"Thiếu công cụ cập nhật (glass6ctl). Cài lại Glass 6 bằng Cydia.");
    }
    return G6L(@"Không đọc được thông tin bản mới. Thử lại sau.");
}

NSString *G6OTAInstallErrorText(int code) {
    switch (code) {
        case 66:
            return G6L(@"Công cụ cài thiếu quyền root. Cài lại Glass 6 bằng Cydia.");
        case 68:
            return G6L(@"Tệp tải về không phải gói của Glass 6.");
        case 72:
            return G6L(@"Chữ ký số của gói không đúng — không cài.");
        case 73:
            return G6L(@"Bản tải về không mới hơn bản đang dùng.");
        case -1:
            return G6L(@"Thiếu công cụ cài (g6update). Cài lại Glass 6 bằng Cydia.");
        default:
            return [NSString stringWithFormat:G6L(@"Không cài được bản cập nhật (mã %d)."), code];
    }
}
