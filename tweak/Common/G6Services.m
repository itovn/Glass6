#import "G6Services.h"

#import "G6Log.h"
#import <UIKit/UIKit.h>
#import <fcntl.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

// SpringBoard mở xong và chạy được chừng này giây thì coi là máy khởi động ổn
static const NSTimeInterval kSvcConfirmDelay = 60;

int G6SvcRun(NSArray *args, NSString **output) {
    if (output) *output = nil;
    if (access(G6_SVC_TOOL, X_OK) != 0) return -1;
    NSUInteger n = args.count;
    char **argv = calloc(n + 2, sizeof(char *));
    if (!argv) return -1;
    argv[0] = (char *)"g6svc";
    for (NSUInteger i = 0; i < n; i++) argv[i + 1] = (char *)[[args[i] description] UTF8String];
    int fds[2];
    if (pipe(fds) != 0) {
        free(argv);
        return -1;
    }
    // Tiến trình con chỉ nhận ba tệp chuẩn: mọi tệp đang mở khác của tiến trình chủ (SpringBoard, Cài đặt) tự đóng — không
    // để lọt sang một công cụ chạy quyền root
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
    char *envp[] = {NULL};
    pid_t pid = 0;
    int rc = posix_spawn(&pid, G6_SVC_TOOL, &actions, &attr, argv, envp);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);
    close(fds[1]);
    free(argv);
    if (rc != 0) {
        close(fds[0]);
        G6Log(@"dịch vụ: không chạy được g6svc (lỗi %d)", rc);
        return -1;
    }
    NSMutableData *data = [NSMutableData data];
    char buf[1024];
    for (;;) {
        ssize_t r = read(fds[0], buf, sizeof(buf));
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) break;
        [data appendBytes:buf length:(NSUInteger)r];
    }
    close(fds[0]);
    int status = 0;
    pid_t waited;
    do {
        waited = waitpid(pid, &status, 0);
    } while (waited < 0 && errno == EINTR);
    if (output) *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // Tiến trình chủ bỏ qua SIGCHLD thì không lấy được mã thoát: đầu ra đã đọc hết nghĩa là công cụ đã chạy xong
    if (waited < 0) return 0;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

NSDictionary *G6SvcStatus(void) {
    NSString *out = nil;
    if (G6SvcRun(@[@"status"], &out) != 0 || !out) return nil;
    NSMutableDictionary *disabled = [NSMutableDictionary dictionary];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        NSArray *cols = [line componentsSeparatedByString:@"\t"];
        if (cols.count != 2) continue;
        NSString *key = cols[0];
        NSInteger value = [cols[1] integerValue];
        if ([key isEqualToString:@"#pending"]) result[@"pending"] = @(value);
        else if ([key isEqualToString:@"#reverted"]) result[@"reverted"] = @YES;
        else if (![key hasPrefix:@"#"]) disabled[key] = @(value != 0);
    }
    result[@"disabled"] = disabled;
    return result;
}

G6UpdateBlock G6SvcUpdateBlock(NSDictionary *status) {
    NSDictionary *disabled = status[@"disabled"];
    if (![disabled isKindOfClass:[NSDictionary class]]) return G6UpdateOpen;
    NSNumber *off = disabled[G6_SVC_UPDATE_ID];
    if (off) return off.boolValue ? G6UpdateBlocked : G6UpdateOpen;
    // g6svc chỉ báo dịch vụ CÓ trên máy. Không báo mục này mà hai tệp việc đúng là không còn → máy đã bị chặn theo kiểu gỡ tệp.
    // (Còn tệp mà không báo = g6svc bản cũ chưa biết mục này: coi như chưa chặn.)
    for (NSString *job in @[@"com.apple.softwareupdateservicesd", @"com.apple.mobile.softwareupdated"]) {
        NSString *path = [NSString stringWithFormat:@"/System/Library/LaunchDaemons/%@.plist", job];
        if (access(path.fileSystemRepresentation, F_OK) == 0) return G6UpdateOpen;
    }
    return G6UpdateRemoved;
}

void G6SvcScheduleConfirm(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSvcConfirmDelay * NSEC_PER_SEC)),
                                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                                           if (access(G6_SVC_PENDING, F_OK) != 0) return;
                                           @autoreleasepool {
                                               int rc = G6SvcRun(@[@"confirm"], NULL);
                                               BOOL still = access(G6_SVC_PENDING, F_OK) == 0;
                                               G6Log(@"dịch vụ: máy chạy ổn %.0f giây — %@ (mã %d)", kSvcConfirmDelay,
                                                     still ? @"lần đổi còn chờ một lần khởi động lại máy" : @"đã xác nhận lần đổi",
                                                     rc);
                                           }
                                       });
                    }];
    });
}
