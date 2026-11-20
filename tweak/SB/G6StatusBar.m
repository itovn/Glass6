// Thanh trạng thái của SpringBoard — iOS 6 → kiểu iPadOS.
//
// iOS 6 trên iPad (tra trên máy 19/11/2026): cửa sổ UIStatusBarWindow (mức 999) › UIStatusBar (1024×20)
//   UIStatusBarBackgroundView   lớp vẽ mang ảnh nền kéo giãn 5×20 lấy từ -_baseImageForStyle: — dải đen mờ
//   UIStatusBarForegroundView   alpha 0,75; chứa các UIStatusBarItemView (tên mạng, Wi-Fi, giờ, pin…), mỗi cái tự vẽ thành ảnh
// Thanh của SpringBoard luôn ở kiểu 1, kể cả lúc có app đang mở (khi đó thanh của chính app nằm đè lên). Vậy đổi ở đây chỉ
// thấy ở màn hình chính, màn khoá, khay đa nhiệm và lúc chuyển cảnh.
//
// Cách làm (mọi hàm thay thế gọi hàm gốc trước, tắt thành phần thì trả đúng kết quả gốc):
//   - -[UIStatusBarBackgroundView _baseImageForStyle:] → ảnh cùng cỡ: đen nhạt dần từ mép trên xuống rồi trong suốt (đủ để
//     chữ trắng còn đọc được trên hình nền sáng, mà không thành một dải);
//   - -[UIStatusBar _foregroundAlphaForStatusBarStyle:] → 1 (chữ trắng rõ);
//   - Chữ Inter, giờ + mặt trăng sang bên trái (`statusTimeLeft`), hình pin vẽ lại (`statusBattery`): phần dùng chung với
//     thanh trạng thái trong app — tweak/Common/G6StatusItems.m. Giờ sang trái thì giữa thanh trống: chỗ cho dải hiệu suất
//     (G6Perf.m) — hàm G6StatusBarCenterFree đo chỗ trống đó, G6StatusBarDidReflowNotification báo khi các mục vừa xếp lại.
//   - Ẩn chữ «Không có SIM» (`statusHideNoSIM`): làm ở NGUỒN dữ liệu — SBStatusBarDataManager của SpringBoard phát trạng thái
//     cho thanh của mọi tiến trình, và nó bật mục «dịch vụ» qua -setStatusBarItem:enabled:. Móc hàm đó: máy đang không có SIM
//     thì đổi «bật» thành «tắt» → mọi thanh trạng thái (kể cả trong app ngoài phạm vi của Glass6UI) cùng mất chữ. Có SIM thì
//     tên nhà mạng hiện như cũ; các trạng thái SIM khác (khoá, lỗi) không đụng.
// Bật / tắt lúc đang chạy: gán lại ảnh nền, độ rõ, cho các mục xếp và vẽ lại.
#import "G6StatusBar.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6StatusItems.h"

NSString *const G6StatusBarDidReflowNotification = @"G6StatusBarDidReflowNotification";

// Độ đậm của lớp đen ở mép trên cùng (nhạt dần tới 0 ở mép dưới)
static const CGFloat kTopShade = 0.30;
// Trạng thái SIM của CoreTelephony khi khe SIM trống
static NSString *const kSIMNotInserted = @"kCTSIMSupportSIMStatusNotInserted";

static BOOL gActive;
static BOOL gHideCarrier;  // ẩn tên nhà mạng kể cả khi có SIM
// Đã gộp sẵn với gActive (thành phần tắt thì là NO)
static BOOL gHideNoSIM;

// Ảnh nền mới cùng cỡ với ảnh gốc. Mọi cột giống nhau nên SpringBoard kéo giãn kiểu nào cũng ra đúng.
static UIImage *G6StatusBarShade(UIImage *orig) {
    static NSMutableDictionary *cache;
    CGImageRef ocg = orig.CGImage;
    if (!ocg) return nil;
    uint32_t w = (uint32_t)CGImageGetWidth(ocg), h = (uint32_t)CGImageGetHeight(ocg);
    if (!w || !h || w > 256 || h > 256) return nil;
    NSString *key = [NSString stringWithFormat:@"%u|%u|%.0f", w, h, orig.scale];
    UIImage *img = cache[key];
    if (img) return img;
    NSMutableData *buf = [NSMutableData dataWithLength:(size_t)w * h * 4];
    uint8_t *p = buf.mutableBytes;
    for (uint32_t y = 0; y < h; y++) {
        // Nhạt nhanh ở nửa trên, tới mép dưới thì hết hẳn
        double t = 1.0 - (y + 0.5) / h;
        uint8_t a = (uint8_t)lround(255.0 * kTopShade * t * sqrt(t));
        // Đen nhân sẵn alpha: ba kênh màu bằng 0
        for (uint32_t x = 0; x < w; x++) p[((size_t)y * w + x) * 4 + 3] = a;
    }
    img = G6ImageFromPixels(buf, w, h, orig.scale >= 1 ? orig.scale : 1);
    if (!img) return nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    cache[key] = img;
    return img;
}

static UIView *G6FindSubview(UIView *parent, const char *className) {
    Class cls = objc_getClass(className);
    for (UIView *sub in parent.subviews) {
        if (cls && [sub isKindOfClass:cls]) return sub;
    }
    return nil;
}

// ---- Nền, độ rõ ----

static id (*o_baseImage)(id, SEL, int);
static id g6_baseImage(id self, SEL _cmd, int style) {
    UIImage *orig = o_baseImage(self, _cmd, style);
    if (!gActive || ![orig isKindOfClass:[UIImage class]]) return orig;
    return G6StatusBarShade(orig) ?: orig;
}

static float (*o_foregroundAlpha)(id, SEL, int);
static float g6_foregroundAlpha(id self, SEL _cmd, int style) {
    float orig = o_foregroundAlpha(self, _cmd, style);
    return gActive ? 1.0f : orig;
}

// Các mục vừa được xếp lại → báo cho bên đang nằm chen giữa thanh (gom các lần sát nhau thành một)
static BOOL gReflowNotePending;
static void (*o_reflow)(id, SEL, double, BOOL);
static void g6_reflow(id self, SEL _cmd, double duration, BOOL preserveHistory) {
    o_reflow(self, _cmd, duration, preserveHistory);
    if (gReflowNotePending) return;
    gReflowNotePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gReflowNotePending = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:G6StatusBarDidReflowNotification object:nil];
    });
}

// ---- Ẩn «Không có SIM» ----

static id G6SIMStatus(void) {
    Class cls = objc_getClass("SBTelephonyManager");
    SEL shared = NSSelectorFromString(@"sharedTelephonyManager"), status = NSSelectorFromString(@"SIMStatus");
    id manager = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    return [manager respondsToSelector:status] ? ((id (*)(id, SEL))objc_msgSend)(manager, status) : nil;
}

static BOOL G6ShouldHideService(void) {
    if (G6StatusItemsServiceType() < 0) return NO;
    // «Ẩn tên nhà mạng» (kiểu iOS 26 của iPhone): ẩn bất kể có SIM hay không
    if (gHideCarrier) return YES;
    if (!gHideNoSIM) return NO;
    id s = G6SIMStatus();
    return [s isKindOfClass:[NSString class]] && [s isEqualToString:kSIMNotInserted];
}

// Ai bật mục «dịch vụ» lúc đang phải ẩn thì đổi thành tắt
static BOOL gServiceHidden;
static BOOL (*o_setItemEnabled)(id, SEL, int, BOOL);
static BOOL g6_setItemEnabled(id self, SEL _cmd, int item, BOOL enabled) {
    @try {
        if (item >= 0 && item == G6StatusItemsServiceType()) {
            BOOL hide = enabled && G6ShouldHideService();
            if (hide) enabled = NO;
            if (hide != gServiceHidden) {
                gServiceHidden = hide;
                G6Log(@"thanh trạng thái: %@", hide ? (gHideCarrier ? @"đã ẩn tên nhà mạng" : @"đã ẩn chữ «Không có SIM»") : @"mục tên mạng hiện như cũ");
            }
        }
    } @catch (NSException *e) {
    }
    return o_setItemEnabled(self, _cmd, item, enabled);
}

// SpringBoard vừa tính lại mục «dịch vụ» (đổi trạng thái SIM, đổi mạng…): đang phải ẩn thì tắt mục đó
static void (*o_updateServiceItem)(id, SEL);
static void g6_updateServiceItem(id self, SEL _cmd) {
    o_updateServiceItem(self, _cmd);
    @try {
        // Đo trên máy: hàm gốc bật mục này qua setStatusBarItem:enabled: (đã bị hàm thay thế ở trên đổi thành tắt); dòng dưới
        // chỉ để phòng bản iOS khác bật bằng đường riêng
        if (o_setItemEnabled && G6ShouldHideService()) {
            o_setItemEnabled(self, NSSelectorFromString(@"setStatusBarItem:enabled:"), G6StatusItemsServiceType(), NO);
        }
    } @catch (NSException *e) {
    }
}

// Cho SpringBoard tính lại mục «dịch vụ» ngay (sau khi đổi tuỳ chọn ẩn)
static void G6StatusBarUpdateService(void) {
    if (!o_updateServiceItem) return;
    Class cls = objc_getClass("SBStatusBarDataManager");
    SEL shared = NSSelectorFromString(@"sharedDataManager"), update = NSSelectorFromString(@"_updateServiceItem");
    SEL begin = NSSelectorFromString(@"beginUpdateBlock"), end = NSSelectorFromString(@"endUpdateBlock");
    id manager = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    if (![manager respondsToSelector:update]) return;
    BOOL block = [manager respondsToSelector:begin] && [manager respondsToSelector:end];
    if (block) ((void (*)(id, SEL))objc_msgSend)(manager, begin);
    ((void (*)(id, SEL))objc_msgSend)(manager, update);
    if (block) ((void (*)(id, SEL))objc_msgSend)(manager, end);
}

// ---- Bật / tắt lúc đang chạy ----

// Ảnh nền và độ rõ của thanh đang hiện theo trạng thái hiện tại
static void G6StatusBarRefreshChrome(void) {
    UIView *bar = G6StatusBarView();
    if (!bar) return;
    UIView *bg = G6FindSubview(bar, "UIStatusBarBackgroundView"), *fg = G6StatusBarForeground();
    SEL styleSel = NSSelectorFromString(@"style"), baseSel = NSSelectorFromString(@"_baseImageForStyle:");
    if ([bg respondsToSelector:styleSel] && [bg respondsToSelector:baseSel]) {
        int style = ((int (*)(id, SEL))objc_msgSend)(bg, styleSel);
        UIImage *img = ((id (*)(id, SEL, int))objc_msgSend)(bg, baseSel, style);
        if ([img isKindOfClass:[UIImage class]]) bg.layer.contents = (__bridge id)img.CGImage;
    }
    SEL current = NSSelectorFromString(@"currentStyle"), alphaSel = NSSelectorFromString(@"_foregroundAlphaForStatusBarStyle:");
    if (fg && [bar respondsToSelector:current] && [bar respondsToSelector:alphaSel]) {
        int style = ((int (*)(id, SEL))objc_msgSend)(bar, current);
        fg.alpha = ((float (*)(id, SEL, int))objc_msgSend)(bar, alphaSel, style);
    }
}

static void G6StatusBarApply(BOOL initial) {
    BOOL active = G6Feature(@"status_bar");
    NSDictionary *cfg = G6Config();
    BOOL hideNoSIM = active && [cfg[@"status_hide_no_sim"] boolValue];
    BOOL hideCarrier = active && [cfg[@"status_hide_carrier"] boolValue];
    BOOL chrome = active != gActive, sim = hideNoSIM != gHideNoSIM || hideCarrier != gHideCarrier, layout = NO, look = NO;
    G6StatusItemsSet(active && [cfg[@"status_time_left"] boolValue], active && [cfg[@"status_signal_right"] boolValue],
                     active && [cfg[@"status_battery"] boolValue], active, &layout, &look);
    if (!initial && !chrome && !sim && !layout && !look) return;
    gActive = active;
    gHideNoSIM = hideNoSIM;
    gHideCarrier = hideCarrier;
    @try {
        if (initial || chrome) G6StatusBarRefreshChrome();
        if (initial || chrome || layout || look) G6StatusItemsRefresh(layout);
        if (initial || sim) G6StatusBarUpdateService();
    } @catch (NSException *e) {
        G6Log(@"thanh trạng thái: lỗi khi áp: %@", e);
    }
    if (!initial || active) {
        G6Log(@"thanh trạng thái: %@%@%@%@%@%@", active ? @"kiểu mới" : @"kiểu gốc", G6StatusItemsTimeLeft() ? @", giờ bên trái" : @"",
              G6StatusItemsSignalRight() ? @", sóng bên phải" : @"", G6StatusItemsBattery() ? @", pin vẽ lại" : @"",
              hideNoSIM ? @", ẩn «Không có SIM»" : @"", hideCarrier ? @", ẩn tên nhà mạng" : @"");
    }
}

BOOL G6StatusBarCenterFree(CGFloat *leftEdge, CGFloat *rightEdge) {
    if (!G6StatusItemsTimeLeft()) return NO;
    UIView *bar = G6StatusBarView(), *fg = G6StatusBarForeground();
    if (!fg || bar.hidden || !bar.window) return NO;
    Class itemClass = objc_getClass("UIStatusBarItemView");
    SEL visible = NSSelectorFromString(@"isVisible");
    CGFloat width = fg.bounds.size.width, mid = width / 2, left = 0, right = width;
    for (UIView *item in fg.subviews) {
        // View ẩn: mục đã chuyển vùng để lại (xem G6StatusItemsRefresh) — không tính
        if (!itemClass || ![item isKindOfClass:itemClass] || item.hidden) continue;
        if ([item respondsToSelector:visible] && !((BOOL (*)(id, SEL))objc_msgSend)(item, visible)) continue;
        CGRect f = item.frame;
        if (CGRectGetMaxX(f) <= mid) left = MAX(left, CGRectGetMaxX(f));
        else if (CGRectGetMinX(f) >= mid) right = MIN(right, CGRectGetMinX(f));
        else return NO;  // có mục nằm vắt qua tâm
    }
    if (leftEdge) *leftEdge = left;
    if (rightEdge) *rightEdge = right;
    return YES;
}

NSString *G6StatusBarDebugState(void) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"thanh trạng thái: bật=%d ẩn SIM=%d | SIM «%@» | %@", gActive, gHideNoSIM,
                                                             G6SIMStatus(), G6StatusItemsDescribe()];
    CGFloat l = 0, r = 0;
    if (G6StatusBarCenterFree(&l, &r)) [out appendFormat:@" | giữa trống %.0f–%.0f", l, r];
    else [out appendString:@" | giữa KHÔNG trống"];
    return out;
}

void G6StatusBarInstall(void) {
    Class bg = objc_getClass("UIStatusBarBackgroundView"), bar = objc_getClass("UIStatusBar");
    if (!bg || !bar) {
        G6Log(@"thanh trạng thái: thiếu lớp UIStatusBar / UIStatusBarBackgroundView — bỏ qua");
        return;
    }
    if (!G6Hook(bg, NSSelectorFromString(@"_baseImageForStyle:"), (IMP)g6_baseImage, (IMP *)&o_baseImage)) return;
    G6Hook(bar, NSSelectorFromString(@"_foregroundAlphaForStatusBarStyle:"), (IMP)g6_foregroundAlpha, (IMP *)&o_foregroundAlpha);
    // Chữ, vùng của giờ + mặt trăng, hình pin: phần dùng chung với app
    G6StatusItemsInstall();
    G6HookNamed("UIStatusBarForegroundView", NSSelectorFromString(@"_reflowItemViewsWithDuration:preserveHistory:"), (IMP)g6_reflow,
                (IMP *)&o_reflow);
    if (G6HookNamed("SBStatusBarDataManager", NSSelectorFromString(@"setStatusBarItem:enabled:"), (IMP)g6_setItemEnabled,
                    (IMP *)&o_setItemEnabled)) {
        G6HookNamed("SBStatusBarDataManager", NSSelectorFromString(@"_updateServiceItem"), (IMP)g6_updateServiceItem,
                    (IMP *)&o_updateServiceItem);
    }

    [[NSNotificationCenter defaultCenter] addObserverForName:G6ConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
                                                      G6StatusBarApply(NO);
                                                  }];
    G6StatusBarApply(YES);
}
