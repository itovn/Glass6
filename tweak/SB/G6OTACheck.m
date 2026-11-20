// Tự kiểm bản mới của Glass 6 (docs/THIET-KE.md mục 10, bước 1) — khoá cấu hình `updateAutoCheck`, mặc định bật.
//
// SpringBoard không tự nói chuyện với mạng: nó chạy `glass6ctl update check` (công cụ ngoài, quyền mobile, có TLS riêng) ở
// luồng nền, tối đa một lần mỗi 24 giờ. Lúc xét: ít lâu sau khi SpringBoard mở xong, rồi mỗi lần máy vừa mở khoá (chỉ là một
// lệnh stat — chưa tới hạn thì thôi). Yêu cầu gửi đi không kèm gì về máy hay người dùng ngoài số bản Glass 6 đang cài (trong
// User-Agent).
//
// Có bản mới hơn → một hộp thoại, MỘT lần cho mỗi bản («Để sau» thì không hỏi lại bản đó; bảng Cài đặt › Glass 6 vẫn hiện
// nút cập nhật). Máy đang khoá thì đợi tới lúc mở khoá mới báo. «Cập nhật» mở Cài đặt › Glass 6 — việc tải và cài làm ở đó
// (prefs/G6RootListController.m), SpringBoard không tự cài gì.
//
// Tệp G6_DIR/update.stamp: giờ sửa tệp = lần hỏi gần nhất; nội dung = bản đã báo.
#import "G6OTACheck.h"

#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <unistd.h>

#import "G6Guard.h"
#import "G6Lang.h"
#import "G6Log.h"
#import "G6OTA.h"
#import "G6Prefs.h"
#import "G6Screen.h"

#define G6_OTA_STAMP G6_DIR "/update.stamp"

// Đợi SpringBoard mở xong hẳn (và máy kịp vào mạng) rồi mới xét lần đầu
static const NSTimeInterval kFirstDelay = 120;
// Sau khi mở khoá: đợi hoạt ảnh mở khoá xong rồi mới xét / hiện hộp thoại
static const NSTimeInterval kUnlockDelay = 4;
static const NSTimeInterval kEvery = 24 * 3600;
// Lượt hỏi hỏng (mất mạng…): thử lại sau chừng này thay vì đợi đủ 24 giờ
static const NSTimeInterval kRetry = 2 * 3600;

static BOOL gChecking;
static BOOL gTickQueued;
// Kết quả lượt kiểm có bản mới, đang chờ báo
static NSDictionary *gFound;
static __weak UIAlertView *gAlert;

@interface G6OTAAlertHandler : NSObject <UIAlertViewDelegate>
@end

@implementation G6OTAAlertHandler

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    // Mục vào của PreferenceLoader tên «Glass 6»
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"prefs:root=Glass%206"]];
}

@end

static G6OTAAlertHandler *gHandler;

static BOOL G6OTAAutoEnabled(void) {
    id value = G6Config()[@"update_auto_check"];
    return value ? [value boolValue] : YES;
}

static NSString *G6OTAAnnounced(void) {
    NSString *text = [NSString stringWithContentsOfFile:@G6_OTA_STAMP encoding:NSUTF8StringEncoding error:NULL];
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

// Ghi tệp dấu: nội dung = bản đã báo; giờ sửa tệp = `when` (lần hỏi gần nhất)
static void G6OTAStamp(NSString *announced, NSTimeInterval when) {
    [(announced ?: @"") writeToFile:@G6_OTA_STAMP atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    struct timeval times[2] = {{(time_t)when, 0}, {(time_t)when, 0}};
    utimes(G6_OTA_STAMP, times);
}

static BOOL G6OTADue(void) {
    struct stat st;
    if (stat(G6_OTA_STAMP, &st) != 0) return YES;
    NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - (NSTimeInterval)st.st_mtime;
    // Đồng hồ máy bị chỉnh lùi (tuổi âm) cũng coi là tới hạn
    return age >= kEvery || age < -kEvery;
}

static void G6OTAAnnounce(void) {
    if (!gFound || gAlert || !G6ScreenAwake() || !G6OTAAutoEnabled()) return;
    NSString *latest = gFound[@"latest"];
    NSString *notes = [gFound[@"notes"] isKindOfClass:[NSString class]] ? gFound[@"notes"] : @"";
    gFound = nil;
    if (![latest isKindOfClass:[NSString class]] || [latest isEqualToString:G6OTAAnnounced()]) return;
    // Ghi «đã báo» trước khi hiện: SpringBoard có khởi động lại giữa chừng cũng không hỏi lại bản này
    struct stat st;
    NSTimeInterval when = stat(G6_OTA_STAMP, &st) == 0 ? (NSTimeInterval)st.st_mtime : [[NSDate date] timeIntervalSince1970];
    G6OTAStamp(latest, when);
    NSString *how = G6L(@"Chạm «Cập nhật» để mở Cài đặt › Glass 6.");
    NSString *message = notes.length ? [NSString stringWithFormat:@"%@\n\n%@", notes, how] : how;
    if (!gHandler) gHandler = [G6OTAAlertHandler new];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:G6L(@"Glass 6 có bản mới %@"), latest]
                                                    message:message
                                                   delegate:gHandler
                                          cancelButtonTitle:G6L(@"Để sau")
                                          otherButtonTitles:G6L(@"Cập nhật"), nil];
    gAlert = alert;
    [alert show];
    G6Log(@"cập nhật: báo có bản mới %@", latest);
}

static void G6OTATick(void) {
    gTickQueued = NO;
    if (!G6OTAAutoEnabled()) return;
    G6OTAAnnounce();
    if (gChecking || !G6OTADue()) return;
    gChecking = YES;
    NSString *announced = G6OTAAnnounced();
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    G6OTAStamp(announced, now);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            NSDictionary *result = G6OTACheck(@G6_VERSION);
            dispatch_async(dispatch_get_main_queue(), ^{
                gChecking = NO;
                if (![result[@"ok"] boolValue]) {
                    G6Log(@"cập nhật: tự kiểm không được (%@)", result[@"error"]);
                    // Hẹn thử lại sớm hơn 24 giờ
                    G6OTAStamp(G6OTAAnnounced(), now - kEvery + kRetry);
                    return;
                }
                NSString *latest = result[@"latest"];
                BOOL newer = G6OTANewer(latest, @G6_VERSION);
                G6Log(@"cập nhật: bản mới nhất %@ (đang dùng %s)%@", latest, G6_VERSION, newer ? @" — có bản mới" : @"");
                if (!newer) return;
                gFound = result;
                G6OTAAnnounce();
            });
        }
    });
}

static void G6OTAQueueTick(NSTimeInterval delay) {
    if (gTickQueued) return;
    gTickQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        G6OTATick();
    });
}

void G6OTACheckForce(void) {
    unlink(G6_OTA_STAMP);
    gFound = nil;
    // Không qua G6OTAQueueTick: lượt xét đầu (kFirstDelay) có thể còn đang chờ, lệnh thử không đợi nó
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        G6OTATick();
    });
}

void G6OTACheckInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        G6ScreenWatchInstall();
        [[NSNotificationCenter defaultCenter] addObserverForName:G6ScreenStateDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          if (G6ScreenAwake()) G6OTAQueueTick(kUnlockDelay);
                                                      }];
        G6OTAQueueTick(kFirstDelay);
        // Gói của lượt cập nhật trước còn nằm trong thư mục tải (g6update cài bản chép riêng của nó, không xoá ở đây). Dọn ngay
        // lúc SpringBoard vừa mở — lúc này chưa ai kịp mở Cài đặt để tải bản khác.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            @autoreleasepool {
                G6OTARun(@[@"update", @"clean"], nil, nil);
            }
        });
    });
}
