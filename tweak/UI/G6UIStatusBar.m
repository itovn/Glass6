// Thanh trạng thái bên trong app: cho giống thanh của SpringBoard — giờ + mặt trăng nằm bên trái, hình pin vẽ lại (tia sét
// xanh lá khi cắm sạc), chữ Inter.
//
// iOS 6: thanh trạng thái do từng app tự vẽ (SpringBoard chỉ phát dữ liệu). Không làm phần này thì cứ mở app là giờ «nhảy» từ
// góc trái về giữa, pin đổi về kiểu cũ. Mã đổi vùng / vẽ pin / phông dùng chung với SpringBoard: tweak/Common/G6StatusItems.m;
// ở đây chỉ đọc cấu hình rồi bật / tắt. Nền của thanh trong app trên iPad (dải đen) giữ nguyên.
//
// Cùng các khoá với SpringBoard: `featStatusBar` (công tắc chung), `statusTimeLeft`, `statusBattery`. Áp cho mọi app trong phạm
// vi của Glass6UI, kể cả app tự vẽ giao diện (thanh trạng thái là của hệ thống, không phải của app). Việc ẩn «Không có SIM»
// làm ở nguồn dữ liệu trong SpringBoard nên không cần gì ở đây.
// Chưa biết: gói xung đột về thanh trạng thái — SpringBoard quét và tự tắt thành phần `status_bar` của mình, nhưng kết quả
// quét chưa được báo cho app.
//
// iPhone — thanh trạng thái liền một mặt với thanh điều hướng (đi cùng thành phần «bars», không theo `featStatusBar`):
// iOS 6 trên iPhone (tra trên máy 20/11/2026, app Cài đặt): app xin kiểu mặc định (0) thì UIStatusBar dùng kiểu «nhuộm theo
// thanh điều hướng» (mã 107): UIStatusBarBackgroundView mang một ảnh dải màu kéo giãn + hai góc bo đen ở mép trên; các mục
// vẽ chữ / hình TRẮNG có bóng tối, cả lớp mục mờ 65%. Trên thanh phẳng sáng của Glass 6 thành ra một dải xám chữ trắng nhạt.
// Cách làm, chỉ khi app xin kiểu mặc định và thành phần «bars» đang bật trong app này (kiểu đen trong suốt / đen đặc của
// trình xem ảnh, máy ảnh… để nguyên; dải xanh «đang gọi» là kiểu khác nên cũng không bị đụng):
//   - nền: bỏ ảnh + góc bo, tô đúng màu mặt thanh của Glass 6 (app đang được vẽ lại bằng bộ lọc thì ở chế độ tối là màu
//     đảo của mặt thanh sáng — đúng thứ bộ lọc cho ra ở thanh điều hướng);
//   - lớp mục hết mờ (-_foregroundAlphaForStatusBarStyle: → 1);
//   - chế độ sáng: ảnh của từng mục (chữ, cột sóng, pin…) đổi từ «trắng + bóng tối» sang «tối, không bóng» bằng một phép
//     đổi màu theo điểm ảnh: phần trắng → màu chữ của thanh, phần bóng (tối) → trong suốt, phần có màu rõ (tia sét xanh, pin
//     đỏ) giữ nguyên. Làm trên ảnh đã vẽ xong của mục (layer.contents) nên đúng cho mọi loại mục, kể cả mục của tweak khác.
// Tắt / đổi chế độ lúc app đang chạy: nền, độ mờ, ảnh gốc của từng mục đều được trả lại.
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6StatusItems.h"

// ---- iPhone: thanh trạng thái liền với thanh điều hướng ----

// Muốn áp trong app này không (iPhone + thành phần «bars» đang bật)
static BOOL gFlatWanted;
// Ảnh của các mục đang được đổi sang màu tối (đang áp + chế độ sáng)
static BOOL gGlyphsDark;
static BOOL gFlatInstalled;
static char kBgStateKey, kFgAlphaKey, kItemStateKey;
// Ảnh gốc (giữ để con trỏ không bị dùng lại) → ảnh đã đổi màu, cho các hình lặp lại nhiều (cột sóng, Wi-Fi, trăng…)
static NSMutableDictionary *gGlyphCache;

static int G6UIIntIvar(id obj, const char *name, int fallback) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!enc || enc[0] != 'i') return fallback;
    return *(int *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}

static id G6UIIvar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    return enc && enc[0] == '@' ? object_getIvar(obj, iv) : nil;
}

// App báo: thanh trạng thái của app này luôn theo kiểu phẳng, dù app xin kiểu đen (app được vẽ lại từ kiểu tối sang kiểu
// sáng / tối theo máy — Ghi âm)
static BOOL gForceFlat;

// Thanh này có đang mang kiểu phẳng không: app xin kiểu mặc định (hoặc xin kiểu đen mà app đã báo luôn phẳng), và hệ thống
// KHÔNG đang phủ một kiểu đặc biệt lên (dải xanh «đang gọi», dải đỏ «đang ghi âm», chia sẻ mạng… — _styleOverrides ≠ 0):
// các dải đó mang nghĩa riêng, phải giữ nguyên màu.
static BOOL G6UIStatusBarIsFlat(id bar) {
    if (!gFlatWanted || G6UIIntIvar(bar, "_styleOverrides", 0) != 0) return NO;
    int requested = G6UIIntIvar(bar, "_requestedStyle", -1);
    return requested == 0 || (gForceFlat && (requested == 1 || requested == 2));
}

// Màu nền do một màn hình cụ thể của app yêu cầu (vd bàn phím số của app Điện thoại ở chế độ tối: nền đen); nil = theo thanh
static UIColor *gOverrideColor;

// Chế độ tối thật của máy (app đang được vẽ lại bằng bộ lọc vẫn «sáng» với các thành phần chuẩn, nhưng thanh trạng thái nằm
// ở cửa sổ khác, không dính bộ lọc)
static UIColor *G6UIStatusBarColor(void) {
    if (gOverrideColor) {
        // Màu được báo theo bảng màu của app; app đang vẽ lại bằng bộ lọc thì ở chế độ tối phải đảo như bộ lọc làm với màn đó
        CGFloat w = 0, a = 1;
        if (G6UISkinActive() && G6IsDark() && [gOverrideColor getWhite:&w alpha:&a]) return [UIColor colorWithWhite:1 - w alpha:1];
        return gOverrideColor;
    }
    CGFloat white = G6UIBarSurfaceWhite();
    if (G6UISkinActive() && G6IsDark()) white = 1 - white;
    return [UIColor colorWithWhite:white alpha:1];
}

// Ảnh của một mục: trắng → màu chữ tối, bóng tối → trong suốt, màu rõ → giữ nguyên
static id G6UIStatusDarken(id contents) {
    if (!contents || CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return nil;
    NSValue *key = [NSValue valueWithPointer:(__bridge void *)contents];
    NSArray *hit = gGlyphCache[key];
    if (hit) return hit[1];
    CGImageRef src = (__bridge CGImageRef)contents;
    size_t w = CGImageGetWidth(src), h = CGImageGetHeight(src);
    if (!w || !h || w > 2048 || h > 256) return nil;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), src);
    uint8_t *data = CGBitmapContextGetData(ctx);
    size_t stride = CGBitmapContextGetBytesPerRow(ctx);
    // Màu chữ trên thanh sáng của Glass 6 (gần đen, hơi trong)
    const float tr = 26, tg = 26, tb = 28, strength = 0.92f;
    for (size_t y = 0; data && y < h; y++) {
        uint8_t *p = data + y * stride;
        for (size_t x = 0; x < w; x++, p += 4) {
            float a = p[3];
            if (a == 0) continue;
            // Bỏ nhân sẵn alpha
            float k = 255.0f / a;
            float b = MIN(255.0f, p[0] * k), g = MIN(255.0f, p[1] * k), r = MIN(255.0f, p[2] * k);
            float mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
            float lum = mx / 255.0f, sat = mx > 0 ? (mx - mn) / mx : 0;
            // Màu rõ (bão hoà cao) thì giữ; trắng / xám thì đổi sang màu chữ, độ đục theo độ sáng (bóng tối → trong suốt)
            float keep = MAX(0.0f, MIN(1.0f, (sat - 0.25f) / 0.35f));
            float outA = (a / 255.0f) * (keep + (1 - keep) * lum * strength);
            float outR = tr + (r - tr) * keep, outG = tg + (g - tg) * keep, outB = tb + (b - tb) * keep;
            p[0] = (uint8_t)lroundf(outB * outA);
            p[1] = (uint8_t)lroundf(outG * outA);
            p[2] = (uint8_t)lroundf(outR * outA);
            p[3] = (uint8_t)lroundf(255.0f * outA);
        }
    }
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!out) return nil;
    id result = CFBridgingRelease(out);
    if (!gGlyphCache) gGlyphCache = [NSMutableDictionary dictionary];
    // Ảnh chữ (giờ, % pin) đổi liên tục: bộ nhớ đầy thì xoá sạch làm lại
    if (gGlyphCache.count > 80) [gGlyphCache removeAllObjects];
    gGlyphCache[key] = @[contents, result];
    return result;
}

// Đổi / trả ảnh của một mục. Trạng thái trên mục: @[ảnh gốc, ảnh đã đổi].
static void G6UIStatusTintItem(UIView *item, BOOL on) {
    CALayer *layer = item.layer;
    id contents = layer.contents;
    NSArray *state = objc_getAssociatedObject(item, &kItemStateKey);
    if (!on) {
        if (!state) return;
        if (contents == state[1]) layer.contents = state[0];
        objc_setAssociatedObject(item, &kItemStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!contents || (state && contents == state[1])) return;
    id dark = G6UIStatusDarken(contents);
    if (!dark) return;
    objc_setAssociatedObject(item, &kItemStateKey, @[contents, dark], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layer.contents = dark;
}

static void G6UIStatusTintForeground(UIView *foreground, BOOL on) {
    Class itemClass = objc_getClass("UIStatusBarItemView");
    if (!itemClass || ![foreground isKindOfClass:[UIView class]]) return;
    for (UIView *item in foreground.subviews) {
        if ([item isKindOfClass:itemClass]) G6UIStatusTintItem(item, on);
    }
}

// Nền: bỏ ảnh dải màu + góc bo, tô màu mặt thanh. Trạng thái: {contents, color, hidden: [view con đã ẩn]}.
static void G6UIStatusBackground(UIView *bg, BOOL flat, UIColor *color) {
    if (![bg isKindOfClass:[UIView class]]) return;
    NSMutableDictionary *state = objc_getAssociatedObject(bg, &kBgStateKey);
    if (!flat) {
        if (!state) return;
        bg.layer.contents = state[@"contents"];
        bg.backgroundColor = state[@"color"];
        for (UIView *sub in state[@"hidden"]) sub.hidden = NO;
        objc_setAssociatedObject(bg, &kBgStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!state) {
        state = [NSMutableDictionary dictionary];
        if (bg.backgroundColor) state[@"color"] = bg.backgroundColor;
        state[@"hidden"] = [NSMutableArray array];
        objc_setAssociatedObject(bg, &kBgStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (bg.layer.contents) {
        state[@"contents"] = bg.layer.contents;
        bg.layer.contents = nil;
    }
    for (UIView *sub in bg.subviews) {
        if (sub.hidden) continue;
        sub.hidden = YES;
        [state[@"hidden"] addObject:sub];
    }
    if (![bg.backgroundColor isEqual:color]) bg.backgroundColor = color;
}

static float (*o_foregroundAlpha)(id, SEL, int);

// Đưa một thanh trạng thái về đúng trạng thái hiện tại. Gọi bao nhiêu lần cũng được.
static void G6UIStatusBarRestyle(UIView *bar) {
    Class cls = objc_getClass("UIStatusBar");
    if (!cls || ![bar isKindOfClass:cls]) return;
    BOOL flat = G6UIStatusBarIsFlat(bar);
    BOOL glyphs = flat && !G6IsDark();
    gGlyphsDark = glyphs;
    UIColor *color = flat ? G6UIStatusBarColor() : nil;
    for (NSString *name in @[@"_backgroundView", @"_newStyleBackgroundView"]) {
        G6UIStatusBackground(G6UIIvar(bar, name.UTF8String), flat, color);
    }
    for (NSString *name in @[@"_foregroundView", @"_newStyleForegroundView"]) {
        UIView *fg = G6UIIvar(bar, name.UTF8String);
        if (![fg isKindOfClass:[UIView class]]) continue;
        NSNumber *saved = objc_getAssociatedObject(fg, &kFgAlphaKey);
        if (flat) {
            // Chỉ đụng lớp mục đang hiện đủ (đang mờ dần lúc đổi kiểu thì để hiệu ứng chạy)
            if (!saved && fg.alpha > 0.5 && fg.alpha < 0.99) {
                objc_setAssociatedObject(fg, &kFgAlphaKey, @(fg.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                fg.alpha = 1;
            }
        } else if (saved) {
            fg.alpha = saved.floatValue;
            objc_setAssociatedObject(fg, &kFgAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        G6UIStatusTintForeground(fg, glyphs);
    }
}

static void G6UIStatusBarRestyleSafe(id bar) {
    @try {
        G6UIStatusBarRestyle(bar);
    } @catch (NSException *e) {
        G6Log(@"thanh trạng thái: lỗi khi đổi kiểu trong app: %@", e);
    }
}

// ---- Hàm thay thế ----

static float g6_foregroundAlpha(id self, SEL _cmd, int style) {
    float alpha = o_foregroundAlpha(self, _cmd, style);
    return G6UIStatusBarIsFlat(self) && alpha > 0.5f ? 1.0f : alpha;
}

static void (*o_barLayout)(id, SEL);
static void g6_barLayout(id self, SEL _cmd) {
    o_barLayout(self, _cmd);
    G6UIStatusBarRestyleSafe(self);
}

static id (*o_prepareStyle)(id, SEL, int, int);
static id g6_prepareStyle(id self, SEL _cmd, int style, int animation) {
    id result = o_prepareStyle(self, _cmd, style, animation);
    G6UIStatusBarRestyleSafe(self);
    return result;
}

static void (*o_swapBackground)(id, SEL);
static void g6_swapBackground(id self, SEL _cmd) {
    o_swapBackground(self, _cmd);
    G6UIStatusBarRestyleSafe(self);
}

static void (*o_swapForeground)(id, SEL);
static void g6_swapForeground(id self, SEL _cmd) {
    o_swapForeground(self, _cmd);
    G6UIStatusBarRestyleSafe(self);
}

static void (*o_setTint)(id, SEL, id, double);
static void g6_setTint(id self, SEL _cmd, id color, double duration) {
    o_setTint(self, _cmd, color, duration);
    G6UIStatusBarRestyleSafe(self);
}

// Dữ liệu mới (giờ đổi, sóng đổi, mục mới hiện): các mục vừa vẽ lại ảnh
static void (*o_receiveData)(id, SEL, id, void *, int);
static void g6_receiveData(id self, SEL _cmd, id server, void *data, int actions) {
    o_receiveData(self, _cmd, server, data, actions);
    G6UIStatusBarRestyleSafe(self);
}

static void (*o_forceUpdate)(id, SEL, void *, BOOL);
static void g6_forceUpdate(id self, SEL _cmd, void *data, BOOL animated) {
    o_forceUpdate(self, _cmd, data, animated);
    G6UIStatusBarRestyleSafe(self);
}

// Hệ thống vừa phủ / gỡ một kiểu đặc biệt (đang gọi, đang ghi âm…)
static void (*o_receiveOverrides)(id, SEL, id, int);
static void g6_receiveOverrides(id self, SEL _cmd, id server, int overrides) {
    o_receiveOverrides(self, _cmd, server, overrides);
    G6UIStatusBarRestyleSafe(self);
}

// Một mục vừa vẽ lại ảnh của mình
static float (*o_itemUpdate)(id, SEL);
static float g6_itemUpdate(UIView *self, SEL _cmd) {
    float delta = o_itemUpdate(self, _cmd);
    @try {
        if (gGlyphsDark) G6UIStatusTintItem(self, YES);
    } @catch (NSException *e) {
    }
    return delta;
}

static void G6UIStatusFlatInstall(void) {
    Class bar = objc_getClass("UIStatusBar"), item = objc_getClass("UIStatusBarItemView");
    if (!bar || !item || !class_getInstanceVariable(bar, "_requestedStyle") || !class_getInstanceVariable(bar, "_backgroundView")) {
        G6Log(@"thanh trạng thái: UIStatusBar thiếu _requestedStyle / _backgroundView — giữ kiểu gốc trong app");
        return;
    }
    G6Hook(bar, NSSelectorFromString(@"_foregroundAlphaForStatusBarStyle:"), (IMP)g6_foregroundAlpha, (IMP *)&o_foregroundAlpha);
    G6Hook(bar, @selector(layoutSubviews), (IMP)g6_barLayout, (IMP *)&o_barLayout);
    G6Hook(bar, NSSelectorFromString(@"_prepareToSetStyle:animation:"), (IMP)g6_prepareStyle, (IMP *)&o_prepareStyle);
    G6Hook(bar, NSSelectorFromString(@"_swapToNewBackgroundView"), (IMP)g6_swapBackground, (IMP *)&o_swapBackground);
    G6Hook(bar, NSSelectorFromString(@"_swapToNewForegroundView"), (IMP)g6_swapForeground, (IMP *)&o_swapForeground);
    G6Hook(bar, NSSelectorFromString(@"setTintColor:withDuration:"), (IMP)g6_setTint, (IMP *)&o_setTint);
    G6Hook(bar, NSSelectorFromString(@"statusBarServer:didReceiveStatusBarData:withActions:"), (IMP)g6_receiveData, (IMP *)&o_receiveData);
    G6Hook(bar, NSSelectorFromString(@"forceUpdateToData:animated:"), (IMP)g6_forceUpdate, (IMP *)&o_forceUpdate);
    G6Hook(bar, NSSelectorFromString(@"statusBarServer:didReceiveStyleOverrides:"), (IMP)g6_receiveOverrides, (IMP *)&o_receiveOverrides);
    G6Hook(item, NSSelectorFromString(@"updateContentsAndWidth"), (IMP)g6_itemUpdate, (IMP *)&o_itemUpdate);
}

void G6UIStatusBarSetForceFlat(BOOL force) {
    if (gForceFlat == force) return;
    gForceFlat = force;
    if (!gFlatInstalled) return;
    UIView *bar = G6StatusBarView();
    if (bar) G6UIStatusBarRestyleSafe(bar);
}

void G6UIStatusBarSetOverride(UIColor *color) {
    if (gOverrideColor == color || [gOverrideColor isEqual:color]) return;
    gOverrideColor = color;
    if (!gFlatInstalled) return;
    UIView *bar = G6StatusBarView();
    if (bar) G6UIStatusBarRestyleSafe(bar);
}

// Gọi sau G6UIBarsApply (cần biết thành phần «bars» có đang bật và đang ở bảng màu nào)
static void G6UIStatusFlatApply(void) {
    if (!g6_device_is_phone()) return;
    BOOL wanted = G6UIBarsActive();
    // Chưa từng bật trong lần chạy này thì không gắn gì
    if (!gFlatInstalled && !wanted) return;
    if (!gFlatInstalled) {
        gFlatInstalled = YES;
        G6UIStatusFlatInstall();
    }
    gFlatWanted = wanted;
    UIView *bar = G6StatusBarView();
    if (bar) G6UIStatusBarRestyleSafe(bar);
}

void G6UIStatusBarApply(void) {
    static BOOL installed;
    BOOL active = G6Feature(@"status_bar");
    // Lần gọi đầu là từ hàm khởi tạo của thư viện (trước UIApplicationMain): chưa có UIApplication, chưa biết thành phần
    // «bars» → phần kiểu phẳng của iPhone chỉ chạy ở các lần gọi sau (từ lượt đặt kiểu)
    if ([UIApplication sharedApplication]) {
        @try {
            G6UIStatusFlatApply();
        } @catch (NSException *e) {
            G6Log(@"thanh trạng thái: lỗi khi áp kiểu phẳng: %@", e);
        }
    }
    // Chưa từng bật trong lần chạy này thì không gắn gì vào app
    if (!installed && !active) return;
    if (!installed) {
        installed = YES;
        G6StatusItemsInstall();
    }
    NSDictionary *cfg = G6Config();
    BOOL layout = NO, look = NO;
    G6StatusItemsSet(active && [cfg[@"status_time_left"] boolValue], active && [cfg[@"status_signal_right"] boolValue],
                     active && [cfg[@"status_battery"] boolValue], active, &layout, &look);
    // Lần gọi đầu là từ hàm khởi tạo của thư viện (trước UIApplicationMain): chưa có UIApplication nên hàm dưới không làm gì —
    // thanh sinh ra sau đó hỏi thẳng các hàm đã gắn. Các lần sau (đổi cấu hình lúc app đang chạy) mới thật sự xếp / vẽ lại.
    if (layout || look) G6StatusItemsRefresh(layout);
    // Các mục vừa vẽ lại ảnh (đổi kiểu pin, phông): đổi màu lại theo thanh phẳng
    if ((layout || look) && gFlatInstalled) {
        UIView *bar = G6StatusBarView();
        if (bar) G6UIStatusBarRestyleSafe(bar);
    }
}
