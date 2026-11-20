// Glass6UI — phần của Glass 6 nạp vào các app (MobileSubstrate, Glass6UI.plist lọc theo com.apple.UIKit). Xem docs/THIET-KE.md
// mục 5 (Đợt 2).
//
// Thư viện này được nạp vào MỌI tiến trình dùng UIKit, nên bước đầu phải thật rẻ và thôi thật sớm:
//   1. SpringBoard (đã có Glass6SB), tiến trình không phải app, app ngoài phạm vi → thôi ngay, chưa đụng gì.
//   2. Bộ gác riêng từng app (libc): app này mở 3 lần liền có Glass 6 mà chưa lần nào chạy ổn → từ đó bỏ qua riêng app này.
//   3. Nạp lõi Rust, đọc cấu hình; công tắc «Bật Glass 6» hoặc «Giao diện trong app» tắt thì thôi.
//   4. Cài các thành phần (thanh, bảng, nút, hộp thoại) lúc UIKit vừa khởi động xong mà app chưa tạo view nào: ngay sau
//      -[UIApplication setDelegate:] (UIApplicationMain gọi, trước application:didFinishLaunching…). KHÔNG làm trong hàm
//      khởi tạo của thư viện: lúc đó UIApplicationMain chưa chạy, GraphicsServices chưa khởi động phông chữ — gọi UIFont là
//      app sập ngay (đã gặp, xem DECISIONS D23). Kiểu UIAppearance phải đặt trước khi view đầu tiên vào cửa sổ, nên cũng
//      không chờ tới thông báo «mở xong» được.
//
// Phạm vi mặc định: app của Apple (mã gói «com.apple.…»). App khác chỉ khi bật `appsThirdParty`.
// Hộp cát: Mail, Safari, Ảnh, Lịch, Bản đồ, Camera của iOS 6 chạy trong hộp cát — đọc được tệp cấu hình, phông và lõi, nhưng
// KHÔNG đọc / ghi được /var/mobile/Library/Glass6; ghi được /var/tmp. Vì thế bộ đếm của bộ gác, nhật ký và tệp của công cụ
// thử trong app nằm ở G6_APP_DIR (/var/tmp/vn.glass6). App nào không ghi được cả chỗ đó thì bộ gác bỏ qua app ấy.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "G6Alert.h"
#import "G6Core.h"
#import "G6Device.h"
#import "G6Guard.h"
#import "G6Hook.h"
#import "G6Keyboard.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6UI.h"

#if G6_DEBUG
#import "G6Debug.h"
#endif

#ifndef G6_VERSION
#define G6_VERSION "?"
#endif

// App mở xong và chạy được chừng này giây (hoặc lui về nền mà chưa sập) thì coi là ổn
static const NSTimeInterval kAppConfirmDelay = 1.5;

static NSString *gProcess, *gBundleID;
// Thời gian hàm khởi tạo của thư viện đã tốn (mili giây) — để theo dõi phần Glass 6 cộng thêm vào lúc mở app
static double gLoadMs;
// Chính sách của lõi cho app này (lệnh «app.policy»): app tự vẽ giao diện bằng ảnh riêng thì chừa thanh và bảng ra
static BOOL gAllowBars = YES, gAllowTables = YES, gAllowControls = YES;

static void G6UIConfirm(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g6_guard_app_confirm(gProcess.UTF8String);
    });
}

// Cài / gỡ các thành phần theo cấu hình hiện hành. Gọi lại mỗi lần cấu hình đổi — từng thành phần tự biết mình đang bật hay tắt.
static void G6UIApply(void) {
    BOOL refresh = NO;
    G6UIAppSkinsUpdate(gBundleID);
    double t0 = G6NowMs();
    @try {
        refresh |= G6UIBarsApply(gAllowBars);
    } @catch (NSException *e) {
        G6Log(@"thanh: lỗi %@", e);
    }
    double t1 = G6NowMs();
    @try {
        refresh |= G6UIControlsApply(gAllowControls);
    } @catch (NSException *e) {
        G6Log(@"nút điều khiển: lỗi %@", e);
    }
    double t2 = G6NowMs();
    if (t2 - t0 > 5) G6Log(@"đặt kiểu: thanh %.1f ms, nút điều khiển %.1f ms", t1 - t0, t2 - t1);
    @try {
        G6UIPickersApply(gAllowControls);
    } @catch (NSException *e) {
        G6Log(@"bánh xe chọn: lỗi %@", e);
    }
    @try {
        G6UIPopoverApply(gAllowBars);
    } @catch (NSException *e) {
        G6Log(@"bảng nổi: lỗi %@", e);
    }
    // Kiểu UIAppearance đổi lúc app đang chạy: view đang hiện phải gỡ – gắn lại mới nhận
    if (refresh) G6UIRefreshAppearance();
    @try {
        G6UITablesApply(gAllowTables);
    } @catch (NSException *e) {
        G6Log(@"bảng: lỗi %@", e);
    }
    @try {
        G6UISettingsIconsApply();
    } @catch (NSException *e) {
        G6Log(@"biểu tượng Cài đặt: lỗi %@", e);
    }
    @try {
        G6UIStatusBarApply();
    } @catch (NSException *e) {
        G6Log(@"thanh trạng thái: lỗi %@", e);
    }
    @try {
        G6UIAppSkinsApply(gBundleID);
    } @catch (NSException *e) {
        G6Log(@"vẽ lại app: lỗi %@", e);
    }
    @try {
        G6KeyboardApply();
    } @catch (NSException *e) {
        G6Log(@"bàn phím: lỗi %@", e);
    }
}

// UIKit đã khởi động xong, app chưa có view nào: đặt kiểu lần đầu
static void G6UIStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        double t0 = G6NowMs();
        G6UIApply();
        G6Log(@"đặt kiểu lần đầu %.1f ms (nạp thư viện + lõi + cấu hình trước đó %.1f ms)", G6NowMs() - t0, gLoadMs);
        [[NSNotificationCenter defaultCenter] addObserverForName:G6ConfigDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6UIApply();
                                                      }];
    });
}

static void (*orig_setDelegate)(UIApplication *, SEL, id);
static void repl_setDelegate(UIApplication *self, SEL _cmd, id delegate) {
    orig_setDelegate(self, _cmd, delegate);
    G6UIStart();
}

__attribute__((constructor)) static void G6UIInit(void) {
    @autoreleasepool {
        if (objc_getClass("SpringBoard")) return;
        // Rào theo mẫu máy: máy chưa được làm và thử thì không nạp gì vào app (G6Device.c)
        if (!g6_device_supported()) return;
        double t0 = G6NowMs();
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *bid = bundle.bundleIdentifier;
        // Chỉ app thật — gói .app trong /Applications hoặc thư mục app người dùng cài: bỏ dịch vụ nền có giao diện
        // (AssistiveTouch… nằm ở /System/Library/CoreServices), công cụ dòng lệnh có liên kết UIKit
        NSString *path = bundle.bundlePath;
        if (bid.length == 0 || ![path.pathExtension isEqualToString:@"app"]) return;
        if (![path hasPrefix:@"/Applications/"] && [path rangeOfString:@"/var/mobile/Applications/"].location == NSNotFound) return;

        // Phạm vi — đọc thẳng tệp cấu hình (chưa cần lõi): thiếu khoá = mặc định bật
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/" G6_PREFS_DOMAIN ".plist"];
        NSNumber *enabled = prefs[@"enabled"], *apps = prefs[@"featApps"];
        if (([enabled isKindOfClass:[NSNumber class]] && !enabled.boolValue) ||
            ([apps isKindOfClass:[NSNumber class]] && !apps.boolValue)) {
            return;
        }
        if (![bid hasPrefix:@"com.apple."] && ![prefs[@"appsThirdParty"] boolValue]) return;

        gProcess = [[NSProcessInfo processInfo] processName];
        gBundleID = [bid copy];
        int guard = g6_guard_app_begin(gProcess.UTF8String);
        if (guard != G6GuardRun) return;
        if (!G6CoreLoad()) {
            // Không phải sập: đừng để bộ đếm tăng dần tới «bỏ qua app này»
            g6_guard_app_confirm(gProcess.UTF8String);
            return;
        }
        G6PrefsStart();
        NSDictionary *policy = G6CoreCall(@{@"cmd" : @"app.policy", @"bundle" : bid});
        if ([policy[@"ok"] boolValue]) {
            gAllowBars = [policy[@"bars"] boolValue];
            gAllowTables = [policy[@"tables"] boolValue];
            gAllowControls = [policy[@"controls"] boolValue];
        }
        G6UITablesSetSidebar([bid isEqualToString:@"com.apple.Preferences"]);
        // iPhone: danh sách ô tự vẽ của các app đã thử → ở chế độ tối đảo màu từng ô thay vì để cả bảng sáng
        if (g6_device_is_phone() && [@[@"com.apple.mobilephone"] containsObject:bid]) G6UITablesSetInvertCustomCells(YES);
        // App «giả vật liệu» có bảng thay hình: khai ngay (hình được nạp lúc app dựng giao diện, trước lượt đặt kiểu đầu)
        G6UIAppSkinsPrepare(bid);
        // App đang được vẽ lại thì hết là «giả vật liệu»: các thành phần chuẩn (thanh, bảng nhóm trong bảng nổi, hình trên nút)
        // cũng theo Glass 6 — ở bảng màu sáng, phần tối do bộ lọc của cửa sổ lo (xem G6UISkin.m). Không bật thì hình trên nút
        // của thanh vẫn trắng như trên thanh da cũ → mất hút trên nút sáng (đã gặp ở dấu cộng của Ghi chú).
        if (G6UISkinActive()) gAllowBars = gAllowTables = gAllowControls = YES;
        G6Log(@"Glass 6 %s nạp vào %@ (%@)%@", G6_VERSION, gProcess, bid,
              [policy[@"skeuomorphic"] boolValue] ? @" — app tự vẽ giao diện: giữ thanh và bảng" : @"");
        gLoadMs = G6NowMs() - t0;
        // Ở đây chỉ được dùng Foundation + runtime: chưa đụng UIFont, UIScreen, UIImage (xem đầu tệp)
        BOOL hooked = G6Hook([UIApplication class], @selector(setDelegate:), (IMP)repl_setDelegate, (IMP *)&orig_setDelegate);
        // Thanh trạng thái được tạo trong UIApplicationMain, trước setDelegate: → gắn ngay bây giờ để nó dựng đúng kiểu từ lần
        // đầu (hàm này lúc này chỉ đổi hàm + ghi cờ; xem G6StatusItems.m «gắn sớm, tra muộn»)
        @try {
            G6UIStatusBarApply();
        } @catch (NSException *e) {
            G6Log(@"thanh trạng thái: lỗi %@", e);
        }
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
        [nc addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:mainQueue
                    usingBlock:^(NSNotification *note) {
                        // Không móc được setDelegate: thì đặt kiểu muộn — view đã có phải gỡ – gắn lại mới nhận kiểu
                        if (!hooked) {
                            G6UIStart();
                            G6UIRefreshAppearance();
                        }
                        @try {
                            G6AlertInstall();
                            // Bảng chọn nằm trong cửa sổ của app → theo «tối / sáng» của app (app đang vẽ lại: luôn sáng)
                            G6AlertSetSheetDarkProvider(G6UIDark);
                        } @catch (NSException *e) {
                            G6Log(@"hộp thoại: lỗi %@", e);
                        }
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAppConfirmDelay * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                                           G6UIConfirm();
                                       });
                    }];
        // Người dùng thoát app trước khi đồng hồ kịp nổ: lui về nền được mà chưa sập cũng là chạy ổn
        [nc addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:mainQueue
                    usingBlock:^(NSNotification *note) {
                        G6UIConfirm();
                    }];
#if G6_DEBUG
        G6DebugStart();
#endif
    }
}
