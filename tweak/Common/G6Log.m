#import "G6Log.h"

#import "G6Guard.h"
#import <fcntl.h>
#import <mach/mach_time.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *const kStatusPath = @G6_DIR "/status.plist";
static const off_t kLogLimit = 256 * 1024;

void G6Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"Glass6: %@", msg);

    // Tệp nhật ký: G6_DIR; app trong hộp cát (Mail, Safari…) không đụng được G6_DIR nên ghi ở G6_APP_DIR. Chọn MỘT lần cho
    // cả đời tiến trình: mỗi lần thử mở tệp bị hộp cát chặn tốn cả chục mili giây (hộp cát ghi lại vi phạm) — thử lại ở mỗi
    // dòng nhật ký từng làm app trong hộp cát mở chậm thêm ~100 ms.
    static const char *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        path = access(G6_DIR, W_OK) == 0 ? G6_DIR "/glass6.log" : G6_APP_DIR "/glass6.log";
    });
    struct stat st;
    if (stat(path, &st) == 0 && st.st_size > kLogLimit) {
        char old[256];
        snprintf(old, sizeof(old), "%s.1", path);
        rename(path, old);
    }
    NSString *line = [NSString stringWithFormat:@"%.0f %@ %@\n", [[NSDate date] timeIntervalSince1970],
                                                [[NSProcessInfo processInfo] processName], msg];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    // O_APPEND: mỗi dòng một lệnh write — nhiều tiến trình cùng ghi không cắt dòng của nhau
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    ssize_t r = write(fd, data.bytes, data.length);
    (void)r;
    close(fd);
}

void G6StatusSet(NSDictionary *values) {
    @synchronized(kStatusPath) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:kStatusPath] ?: [NSMutableDictionary dictionary];
        [d addEntriesFromDictionary:values];
        d[@"time"] = @((long long)[[NSDate date] timeIntervalSince1970]);
        [d writeToFile:kStatusPath atomically:YES];
    }
}

double G6NowMs(void) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}
