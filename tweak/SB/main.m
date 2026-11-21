// Glass6SB — phần của Glass 6 nạp vào SpringBoard (MobileSubstrate, Glass6SB.plist). Xem docs/THIET-KE.md.
//
// Thứ tự lúc nạp (mỗi bước hỏng thì dừng, SpringBoard vẫn chạy như chưa cài):
//   0. Rào theo mẫu máy (G6Device.c): máy không có trong bảng mẫu đã làm → dừng, không đụng gì.
//   1. Bộ gác (libc): công tắc tổng bằng tệp, bộ đếm «khởi động mà chưa chạy ổn».
//   2. Nạp lõi Rust (/usr/lib/libglass6core.dylib).
//   3. Đọc cấu hình; công tắc «Bật Glass 6» tắt thì thôi.
//   4. SpringBoard mở xong: quét xung đột, cài các thành phần giao diện; 20 giây sau xác nhận «chạy ổn».
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "G6Alert.h"
#import "G6Assist.h"
#import "G6Core.h"
#import "G6Banner.h"
#import "G6Device.h"
#import "G6Clock.h"
#import "G6CTGuard.h"
#import "G6NotifGuard.h"
#import "G6ControlCenter.h"
#import "G6Dock.h"
#import "G6Folders.h"
#import "G6Guard.h"
#import "G6HUD.h"
#import "G6Icons.h"
#import "G6Keyboard.h"
#import "G6Lang.h"
#import "G6Lock.h"
#import "G6Newsstand.h"
#import "G6NotificationCenter.h"
#import "G6Perf.h"
#import "G6SearchPill.h"
#import "G6Spotlight.h"
#import "G6OTACheck.h"
#import "G6UpdateBlock.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Services.h"
#import "G6StatusBar.h"
#import "G6CardSwitcher.h"
#import "G6Switcher.h"

#if G6_DEBUG
#import "G6Debug.h"
#endif

#ifndef G6_VERSION
#define G6_VERSION "?"
#endif

static const char *const kProcess = "SpringBoard";
// Chạy được chừng này giây sau khi SpringBoard mở xong thì coi là ổn
static const NSTimeInterval kConfirmDelay = 20;

// Gói và thư viện MobileSubstrate đang cài → lõi đối chiếu với danh sách xung đột đã biết.
static void G6ScanConflicts(void) {
    NSString *dir = @"/Library/MobileSubstrate/DynamicLibraries";
    NSMutableArray *dylibs = [NSMutableArray array];
    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        if (![file.pathExtension isEqualToString:@"plist"]) continue;
        // Tệp lọc có ba dạng (XML, nhị phân, kiểu cũ «{ Filter = … }») — NSDictionary đọc được cả ba
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:file]];
        NSDictionary *filter = d[@"Filter"];
        NSMutableArray *filters = [NSMutableArray array];
        if ([filter isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in @[@"Bundles", @"Executables"]) {
                NSArray *list = filter[key];
                if (![list isKindOfClass:[NSArray class]]) continue;
                for (id s in list) {
                    if ([s isKindOfClass:[NSString class]]) [filters addObject:s];
                }
            }
        }
        [dylibs addObject:@{@"name" : file.stringByDeletingPathExtension, @"filters" : filters}];
    }
    NSData *raw = [NSData dataWithContentsOfFile:@"/var/lib/dpkg/status"];
    // Mô tả gói có thể không phải UTF-8 — Latin-1 đọc được mọi byte, mã gói vốn là ASCII
    NSString *status = raw ? ([[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding]
                                  ?: [[NSString alloc] initWithData:raw encoding:NSISOLatin1StringEncoding])
                           : nil;
    NSDictionary *r = G6CoreCall(@{@"cmd" : @"guard.scan", @"dylibs" : dylibs, @"dpkgStatus" : status ?: @""});
    NSArray *blocked = [r[@"blocked"] isKindOfClass:[NSArray class]] ? r[@"blocked"] : @[];
    NSArray *findings = [r[@"findings"] isKindOfClass:[NSArray class]] ? r[@"findings"] : @[];
    G6SetBlockedFeatures(blocked);
    G6StatusSet(@{@"findings" : findings, @"blocked" : blocked});
    if (blocked.count) G6Log(@"thành phần tự tắt vì xung đột: %@", [blocked componentsJoinedByString:@", "]);
}

// Cài các thành phần giao diện. Mỗi thành phần tự hỏi G6Feature() — tắt trong Cài đặt hoặc bị chặn vì xung đột thì đứng yên.
static void G6InstallFeatures(void) {
    @try {
        G6DockInstall();
    } @catch (NSException *e) {
        G6Log(@"cài dock lỗi: %@", e);
    }
    @try {
        G6IconsStart();
    } @catch (NSException *e) {
        G6Log(@"cài biểu tượng lỗi: %@", e);
    }
    @try {
        G6FoldersInstall();
    } @catch (NSException *e) {
        G6Log(@"cài thư mục lỗi: %@", e);
    }
    @try {
        G6StatusBarInstall();
    } @catch (NSException *e) {
        G6Log(@"cài thanh trạng thái lỗi: %@", e);
    }
    @try {
        G6SwitcherInstall();
        G6CardSwitcherInstall();
    } @catch (NSException *e) {
        G6Log(@"cài khay đa nhiệm lỗi: %@", e);
    }
    @try {
        G6LockInstall();
    } @catch (NSException *e) {
        G6Log(@"cài màn khoá lỗi: %@", e);
    }
    @try {
        G6HUDInstall();
    } @catch (NSException *e) {
        G6Log(@"cài bảng âm lượng lỗi: %@", e);
    }
    @try {
        G6BannerInstall();
    } @catch (NSException *e) {
        G6Log(@"cài băng thông báo lỗi: %@", e);
    }
    @try {
        G6NotificationCenterInstall();
    } @catch (NSException *e) {
        G6Log(@"cài trung tâm thông báo lỗi: %@", e);
    }
    @try {
        G6AlertInstall();
    } @catch (NSException *e) {
        G6Log(@"cài hộp thoại lỗi: %@", e);
    }
    @try {
        G6ControlCenterInstall();
    } @catch (NSException *e) {
        G6Log(@"cài control center lỗi: %@", e);
    }
    @try {
        G6AssistInstall();
    } @catch (NSException *e) {
        G6Log(@"cài nút trợ năng lỗi: %@", e);
    }
    @try {
        // Bàn phím của SpringBoard (ô Tìm kiếm): tối ở chế độ tối; đổi theo mỗi lần cấu hình đổi
        G6KeyboardApply();
        [[NSNotificationCenter defaultCenter] addObserverForName:G6ConfigDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6LangReload();  // mục «Ngôn ngữ» có thể vừa đổi
                                                          G6KeyboardApply();
                                                      }];
    } @catch (NSException *e) {
        G6Log(@"cài bàn phím lỗi: %@", e);
    }
    @try {
        G6PerfInstall();
    } @catch (NSException *e) {
        G6Log(@"cài dải hiệu suất lỗi: %@", e);
    }
    @try {
        G6SpotlightInstall();
    } @catch (NSException *e) {
        G6Log(@"cài ô tìm kiếm lỗi: %@", e);
    }
    @try {
        G6SearchPillInstall();
    } @catch (NSException *e) {
        G6Log(@"cài viên tìm kiếm lỗi: %@", e);
    }
    @try {
        G6UpdateBlockInstall();
    } @catch (NSException *e) {
        G6Log(@"cài phần chặn cập nhật lỗi: %@", e);
    }
    @try {
        G6OTACheckInstall();
    } @catch (NSException *e) {
        G6Log(@"cài phần tự kiểm bản mới lỗi: %@", e);
    }
    G6StatusSet(@{@"running" : @YES, @"reason" : @"", @"version" : @G6_VERSION, @"core" : G6CoreVersion() ?: @"?"});
    G6Log(@"đã sẵn sàng (chế độ %@)", G6IsDark() ? @"tối" : @"sáng");
}

static void G6DidFinishLaunching(void) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            G6ScanConflicts();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            G6InstallFeatures();
        });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kConfirmDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        g6_guard_confirm(kProcess);
    });
}

static void G6Stopped(NSString *reason) {
    G6Log(@"không chạy: %@", reason);
    G6StatusSet(@{@"running" : @NO, @"reason" : reason, @"version" : @G6_VERSION});
}

__attribute__((constructor)) static void G6Init(void) {
    if (!objc_getClass("SpringBoard")) return;
    @autoreleasepool {
        if (!g6_device_supported()) {
            // Máy lạ: không bộ gác, không lõi, không dịch vụ — chỉ ghi trạng thái cho bảng Cài đặt báo «chưa hỗ trợ»
            G6Log(@"mẫu máy «%s» chưa được hỗ trợ — Glass 6 đứng yên", g6_device_machine());
            G6Stopped(@"device");
            return;
        }
        G6Log(@"mẫu máy: %s (%s)", g6_device_name(g6_device_kind()), g6_device_machine());
        int guard = g6_guard_begin(kProcess);
        if (guard != G6GuardRun) {
            G6Stopped(guard == G6GuardOffFile ? @"off" : @"auto");
            return;
        }
        // iPhone: giữ callback CoreTelephony của SpringBoard ở luồng chính (G6CTGuard.h) — phải trước khi SpringBoard tạo
        // SBTelephonyManager; không phụ thuộc lõi hay công tắc giao diện vì «Bật 4G» vẫn có thể khởi động lại CommCenter.
        if (g6_device_is_phone()) G6CTGuardInstall();
        // Mọi máy: chữ thông báo có nửa emoji làm SpringBoard sập (G6NotifGuard.h) — cũng không phụ thuộc lõi hay công tắc giao diện
        G6NotifGuardInstall();
        // Xác nhận «máy khởi động ổn» cho lần đổi dịch vụ hệ thống đang chờ — không phụ thuộc lõi hay công tắc giao diện:
        // dịch vụ đã tắt vẫn tắt dù giao diện Glass 6 đang tắt. (Có tệp «off» thì không xác nhận: hai lần khởi động máy
        // sau, bộ gác tự trả dịch vụ về như trước.)
        G6SvcScheduleConfirm();
        if (!G6CoreLoad()) {
            // Không phải sập: đừng để bộ đếm tăng dần tới tự tắt
            g6_guard_confirm(kProcess);
            G6Stopped(@"core");
            return;
        }
        G6PrefsStart();
        if (!G6Enabled()) {
            g6_guard_confirm(kProcess);
            G6Stopped(@"disabled");
            return;
        }
        G6Log(@"Glass 6 %s (lõi %@) nạp vào SpringBoard", G6_VERSION, G6CoreVersion());
        // Gắn sớm, trước khi SpringBoard tạo ảnh biểu tượng đầu tiên — khỏi phải tạo hai lần
        @try {
            G6IconsInstall();
        } @catch (NSException *e) {
            G6Log(@"gắn biểu tượng lỗi: %@", e);
        }
        @try {
            G6ClockInstall();
        } @catch (NSException *e) {
            G6Log(@"gắn đồng hồ lỗi: %@", e);
        }
        // Cũng phải sớm: lượt xếp biểu tượng đầu tiên của SpringBoard hỏi từng biểu tượng có được hiện không
        @try {
            G6NewsstandInstall();
        } @catch (NSException *e) {
            G6Log(@"gắn quầy báo lỗi: %@", e);
        }
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6DidFinishLaunching();
                                                      }];
#if G6_DEBUG
        G6DebugStart();
#endif
    }
}
