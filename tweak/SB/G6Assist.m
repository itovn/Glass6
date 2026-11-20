// Nút AssistiveTouch của Glass 6 (thành phần «assist», mặc định tắt).
//
// Thay nút AssistiveTouch của iOS 6 bằng một nút nổi cùng cách dùng nhưng tuỳ biến được như các bản iOS sau này:
//   - bảng nút 1–9 ô, mỗi ô gán một chức năng (danh mục ở lõi: core/crates/g6-core/src/assist.rs); bảng tự đóng sau một
//     thời gian chờ không ai bấm (chỉnh được, 0 = không tự đóng); ô có trạng thái (khoá xoay, tắt tiếng, sáng / tối) hiện đúng
//     trạng thái thật của máy: nhãn nói việc lần bấm tới SẼ làm, ô sáng lên khi đang bật;
//   - thao tác trên chính nút: chạm một lần / chạm hai lần / nhấn giữ, mỗi thao tác gán một chức năng hoặc «mở bảng nút»;
//   - nút kéo đi được, thả ra thì hít vào mép trái / phải; vị trí nhớ ở G6_DIR/assist.plist; lúc nghỉ nút mờ bớt.
//
// Cấu trúc: một cửa sổ riêng mức 1070 (trên app, màn khoá, Control Center; dưới hộp thoại). Cửa sổ chỉ nhận chạm ở đúng chỗ
// nút — mọi chỗ khác lọt xuống dưới; lúc bảng nút mở thì nhận cả màn hình (chạm ra ngoài để đóng). Khung bên trong xoay theo
// hướng giao diện đang hiện. Bảng nút là tấm kính (bề mặt «hud», nền chụp màn hình một lần lúc mở).
//
// Nút của iOS: bật nút của Glass 6 thì tắt AssistiveTouch của hệ thống (kẻo có hai nút) và để dấu G6_DIR/assist.sysat; tắt nút
// của Glass 6 mà còn dấu đó thì bật lại nút của hệ thống. Hàm của libAccessibility tra lúc chạy, thiếu thì bỏ qua.
#import "G6Assist.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <unistd.h>

#import "G6ControlCenter.h"
#import "G6Core.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Guard.h"
#import "G6Hook.h"
#import "G6Lang.h"
#import "G6Log.h"
#import "G6Prefs.h"

static const CGFloat kButton = 58, kEdge = 6, kTile = 92, kPad = 16;
static const NSTimeInterval kIdleDelay = 3.0;
static NSString *const kStatePath = @G6_DIR "/assist.plist";
static const char *const kSystemMarker = G6_DIR "/assist.sysat";

@interface G6AssistWindow : UIWindow
@end

@interface G6AssistTarget : NSObject <UIAlertViewDelegate>
@end

static G6AssistWindow *gWindow;
static UIView *gRoot;           // khung xoay theo hướng giao diện, toạ độ = toạ độ giao diện
static UIImageView *gButton;
static UIView *gMenu;           // nil khi bảng nút đóng
static UIControl *gCatcher;
static BOOL gActive;
static NSString *gSignature;
static NSDictionary *gCatalog;  // mã → {title, short}
static NSString *gPendingConfirm;
static NSTimer *gIdleTimer;
static NSTimer *gMenuTimer;     // đếm thời gian chờ tự đóng bảng nút
// Vị trí nút: mép (0 trái, 1 phải) + tung độ theo tỉ lệ chiều cao giao diện
static int gEdgeSide = 1;
static CGFloat gYFraction = 0.45;

// ---- Tiện ích gọi hàm của SpringBoard ----

static id G6Shared(const char *className, NSString *selName) {
    Class cls = objc_getClass(className);
    SEL sel = NSSelectorFromString(selName);
    return [cls respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(cls, sel) : nil;
}

static BOOL G6Send(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return NO;
    ((void (*)(id, SEL))objc_msgSend)(obj, sel);
    return YES;
}

static BOOL G6GetBool(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    return [obj respondsToSelector:sel] ? ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel) : NO;
}

static NSDictionary *G6AssistConfig(void) {
    NSDictionary *a = G6Config()[@"assist"];
    return [a isKindOfClass:[NSDictionary class]] ? a : @{};
}

static NSDictionary *G6Catalog(void) {
    if (!gCatalog) {
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (NSDictionary *a in G6CoreCall(@{@"cmd" : @"assist.catalog"})[@"actions"]) {
            if ([a isKindOfClass:[NSDictionary class]] && a[@"id"]) map[a[@"id"]] = a;
        }
        gCatalog = map;
    }
    return gCatalog;
}

// ---- Hướng giao diện ----

static UIInterfaceOrientation G6AssistOrientation(void) {
    UIApplication *app = [UIApplication sharedApplication];
    // Hướng của app đang ở trước (SpringBoard biết); không có thì hướng thanh trạng thái của SpringBoard
    SEL sel = NSSelectorFromString(@"activeInterfaceOrientation");
    NSInteger o = [app respondsToSelector:sel] ? ((NSInteger (*)(id, SEL))objc_msgSend)(app, sel) : app.statusBarOrientation;
    return (o >= 1 && o <= 4) ? (UIInterfaceOrientation)o : UIInterfaceOrientationPortrait;
}

static CGSize G6AssistUISize(void) {
    CGSize full = [UIScreen mainScreen].bounds.size;  // iOS 6: luôn theo hệ dọc
    return UIInterfaceOrientationIsLandscape(G6AssistOrientation()) ? CGSizeMake(full.height, full.width) : full;
}

static CGPoint G6ButtonCenter(void) {
    CGSize ui = G6AssistUISize();
    CGFloat half = kButton / 2;
    CGFloat x = gEdgeSide ? ui.width - kEdge - half : kEdge + half;
    CGFloat y = MAX(20 + kEdge + half, MIN(ui.height - kEdge - half, gYFraction * ui.height));
    return CGPointMake(x, y);
}

static void G6AssistLayout(void) {
    if (!gWindow) return;
    CGSize full = [UIScreen mainScreen].bounds.size, ui = G6AssistUISize();
    static const CGFloat angles[5] = {0, 0, M_PI, M_PI_2, -M_PI_2};
    gRoot.transform = CGAffineTransformIdentity;
    gRoot.bounds = CGRectMake(0, 0, ui.width, ui.height);
    gRoot.center = CGPointMake(full.width / 2, full.height / 2);
    gRoot.transform = CGAffineTransformMakeRotation(angles[G6AssistOrientation()]);
    gButton.center = G6ButtonCenter();
}

// ---- Hình vẽ (khung 24×24, màu trắng) ----

static UIBezierPath *G6R(CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    return [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, w, h) cornerRadius:r];
}

static void G6Arc(CGFloat cx, CGFloat cy, CGFloat radius, CGFloat fromDeg, CGFloat toDeg, CGFloat width) {
    UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx, cy)
                                                       radius:radius
                                                   startAngle:fromDeg * M_PI / 180
                                                     endAngle:toDeg * M_PI / 180
                                                    clockwise:YES];
    arc.lineWidth = width;
    arc.lineCapStyle = kCGLineCapRound;
    [arc stroke];
}

static void G6Line(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat width) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x1, y1)];
    [p addLineToPoint:CGPointMake(x2, y2)];
    p.lineWidth = width;
    p.lineCapStyle = kCGLineCapRound;
    [p stroke];
}

static void G6Poly(const CGFloat *xy, int count) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(xy[0], xy[1])];
    for (int i = 1; i < count; i++) [p addLineToPoint:CGPointMake(xy[i * 2], xy[i * 2 + 1])];
    [p closePath];
    p.lineJoinStyle = kCGLineJoinRound;
    [p fill];
}

static void G6Speaker(void) {
    const CGFloat body[] = {2.6, 9.4, 6.6, 9.4, 11.6, 4.8, 11.6, 19.2, 6.6, 14.6, 2.6, 14.6};
    G6Poly(body, 6);
}

static void G6Sun(CGFloat radius, CGFloat rayFrom, CGFloat rayTo) {
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(12 - radius, 12 - radius, radius * 2, radius * 2)] fill];
    for (int i = 0; i < 8; i++) {
        CGFloat a = i * M_PI / 4;
        G6Line(12 + rayFrom * cos(a), 12 + rayFrom * sin(a), 12 + rayTo * cos(a), 12 + rayTo * sin(a), 2);
    }
}

// Mũi tên vòng (làm mới): cung 300° + đầu mũi tên
static void G6CircleArrow(CGFloat radius) {
    G6Arc(12, 12, radius, -60, 240, 2.2);
    CGFloat a = -60 * M_PI / 180, x = 12 + radius * cos(a), y = 12 + radius * sin(a);
    const CGFloat head[] = {x - 4.2, y - 1.2, x + 2.6, y - 3.2, x + 1.2, y + 3.8};
    G6Poly(head, 3);
}

static void G6DrawGlyph(NSString *name) {
    if ([name isEqualToString:@"home"]) {
        const CGFloat roof[] = {12, 3.2, 21.6, 11.6, 2.4, 11.6};
        G6Poly(roof, 3);
        UIBezierPath *body = G6R(5.2, 10.6, 13.6, 10.2, 1.6);
        [body appendPath:G6R(10, 14.6, 4, 6.4, 0.8)];
        body.usesEvenOddFillRule = YES;
        [body fill];
    } else if ([name isEqualToString:@"switcher"]) {
        UIBezierPath *back = G6R(8.4, 3.6, 12.4, 10.4, 2.2);
        back.lineWidth = 2;
        [back stroke];
        [G6R(3.2, 9.6, 13.2, 11, 2.4) fill];
    } else if ([name isEqualToString:@"notifications"]) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(4.4, 17.6)];
        [p addLineToPoint:CGPointMake(6.4, 15.2)];
        [p addCurveToPoint:CGPointMake(12, 4.6) controlPoint1:CGPointMake(6.4, 8.6) controlPoint2:CGPointMake(8.4, 4.6)];
        [p addCurveToPoint:CGPointMake(17.6, 15.2) controlPoint1:CGPointMake(15.6, 4.6) controlPoint2:CGPointMake(17.6, 8.6)];
        [p addLineToPoint:CGPointMake(19.6, 17.6)];
        [p closePath];
        p.lineJoinStyle = kCGLineJoinRound;
        [p fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10, 18.4, 4, 3.4)] fill];
    } else if ([name isEqualToString:@"controlcenter"]) {
        // Hai thanh gạt: rãnh + núm
        G6Line(3.6, 8, 20.4, 8, 2.2);
        G6Line(3.6, 16, 20.4, 16, 2.2);
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(12.6, 4.6, 6.8, 6.8)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(4.8, 12.6, 6.8, 6.8)] fill];
    } else if ([name isEqualToString:@"lock"]) {
        [G6R(5.2, 10.6, 13.6, 10.4, 2.6) fill];
        UIBezierPath *shackle = [UIBezierPath bezierPath];
        [shackle moveToPoint:CGPointMake(8.2, 11)];
        [shackle addLineToPoint:CGPointMake(8.2, 8)];
        [shackle addArcWithCenter:CGPointMake(12, 8) radius:3.8 startAngle:M_PI endAngle:0 clockwise:YES];
        [shackle addLineToPoint:CGPointMake(15.8, 11)];
        shackle.lineWidth = 2.2;
        [shackle stroke];
    } else if ([name isEqualToString:@"screenshot"]) {
        // Bốn góc khung ngắm + chấm giữa
        const CGFloat c[4][6] = {{3.4, 8.4, 3.4, 3.4, 8.4, 3.4}, {15.6, 3.4, 20.6, 3.4, 20.6, 8.4},
                                 {20.6, 15.6, 20.6, 20.6, 15.6, 20.6}, {8.4, 20.6, 3.4, 20.6, 3.4, 15.6}};
        for (int i = 0; i < 4; i++) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(c[i][0], c[i][1])];
            [p addLineToPoint:CGPointMake(c[i][2], c[i][3])];
            [p addLineToPoint:CGPointMake(c[i][4], c[i][5])];
            p.lineWidth = 2.2;
            p.lineCapStyle = kCGLineCapRound;
            p.lineJoinStyle = kCGLineJoinRound;
            [p stroke];
        }
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(8.6, 8.6, 6.8, 6.8)] fill];
    } else if ([name isEqualToString:@"volup"] || [name isEqualToString:@"voldown"]) {
        G6Speaker();
        G6Line(15, 12, 21.4, 12, 2.2);
        if ([name isEqualToString:@"volup"]) G6Line(18.2, 8.8, 18.2, 15.2, 2.2);
    } else if ([name isEqualToString:@"mute"]) {
        G6Speaker();
        G6Line(15.2, 9, 21.2, 15, 2.2);
        G6Line(21.2, 9, 15.2, 15, 2.2);
    } else if ([name isEqualToString:@"rotate"]) {
        G6CircleArrow(8.6);
        [G6R(8.8, 11.2, 6.4, 5.2, 1.2) fill];
        G6Arc(12, 11.2, 2, 180, 360, 1.5);
    } else if ([name isEqualToString:@"dark"]) {
        UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(3.6, 3.6, 16.8, 16.8)];
        ring.lineWidth = 2.2;
        [ring stroke];
        UIBezierPath *half = [UIBezierPath bezierPath];
        [half moveToPoint:CGPointMake(12, 3.6)];
        [half addArcWithCenter:CGPointMake(12, 12) radius:8.4 startAngle:-M_PI_2 endAngle:M_PI_2 clockwise:NO];
        [half closePath];
        [half fill];
    } else if ([name isEqualToString:@"brightup"]) {
        G6Sun(4.4, 7, 10);
    } else if ([name isEqualToString:@"brightdown"]) {
        G6Sun(3, 5.4, 7.2);
    } else if ([name isEqualToString:@"respring"]) {
        G6CircleArrow(8.2);
    } else if ([name isEqualToString:@"reboot"]) {
        G6CircleArrow(8.8);
        G6Line(12, 8.4, 12, 13, 2.2);
    } else if ([name isEqualToString:@"poweroff"]) {
        G6Arc(12, 12.6, 7.8, -55, 235, 2.4);
        G6Line(12, 3.4, 12, 11.4, 2.4);
    }
}

static UIImage *G6GlyphImage(NSString *name, CGFloat side) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), side / 24, side / 24);
    [[UIColor whiteColor] set];
    G6DrawGlyph(name);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// Mặt nút: ô bo góc sẫm trong mờ + các vòng tròn trắng đồng tâm (dáng quen thuộc của AssistiveTouch)
static UIImage *G6ButtonImage(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(kButton, kButton), NO, 0);
    CGRect body = CGRectMake(1, 1, kButton - 2, kButton - 2);
    UIBezierPath *plate = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:15];
    [[UIColor colorWithWhite:0.08 alpha:0.62] setFill];
    [plate fill];
    [[UIColor colorWithWhite:1 alpha:0.22] setStroke];
    plate.lineWidth = 1;
    [plate stroke];
    CGPoint c = CGPointMake(kButton / 2, kButton / 2);
    const CGFloat radii[3] = {20, 16, 12}, alphas[3] = {0.22, 0.42, 0.92};
    for (int i = 0; i < 3; i++) {
        [[UIColor colorWithWhite:1 alpha:alphas[i]] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - radii[i], c.y - radii[i], radii[i] * 2, radii[i] * 2)] fill];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// ---- Vị trí nút ----

static void G6LoadPosition(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kStatePath];
    if ([d[@"edge"] isKindOfClass:[NSNumber class]]) gEdgeSide = [d[@"edge"] intValue] ? 1 : 0;
    if ([d[@"y"] isKindOfClass:[NSNumber class]]) gYFraction = MAX(0.05, MIN(0.95, [d[@"y"] floatValue]));
}

static void G6SavePosition(void) {
    [@{@"edge" : @(gEdgeSide), @"y" : @(gYFraction)} writeToFile:kStatePath atomically:YES];
}

// ---- Lúc nghỉ ----

static void G6AssistWake(void) {
    [gIdleTimer invalidate];
    gIdleTimer = nil;
    if (!gButton) return;
    gButton.alpha = 1;
    gIdleTimer = [NSTimer scheduledTimerWithTimeInterval:kIdleDelay target:[G6AssistTarget class] selector:@selector(idle:) userInfo:nil repeats:NO];
}

// ---- Nút AssistiveTouch của hệ thống ----

static void G6SystemAssist(BOOL ours) {
    void *lib = dlopen("/usr/lib/libAccessibility.dylib", RTLD_LAZY);
    Boolean (*enabled)(void) = lib ? dlsym(lib, "_AXSAssistiveTouchEnabled") : NULL;
    void (*setEnabled)(Boolean) = lib ? dlsym(lib, "_AXSAssistiveTouchSetEnabled") : NULL;
    if (!enabled || !setEnabled) return;
    if (ours) {
        if (enabled()) {
            setEnabled(false);
            close(open(kSystemMarker, O_WRONLY | O_CREAT, 0644));
            G6Log(@"nút trợ năng: đã tắt AssistiveTouch của hệ thống (sẽ bật lại khi tắt nút của Glass 6)");
        }
    } else if (access(kSystemMarker, F_OK) == 0) {
        unlink(kSystemMarker);
        if (!enabled()) {
            setEnabled(true);
            G6Log(@"nút trợ năng: đã bật lại AssistiveTouch của hệ thống");
        }
    }
}

// ---- Chức năng ----

static void G6AssistCloseMenu(BOOL animated);

static void G6SetAppearance(BOOL dark) {
    NSString *path = @"/var/mobile/Library/Preferences/" G6_PREFS_DOMAIN ".plist";
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    prefs[@"appearance"] = @(dark ? 1 : 0);
    if ([prefs writeToFile:path atomically:YES]) notify_post(G6_PREFS_NOTE);
}

static void G6Confirm(NSString *actionId, NSString *title) {
    gPendingConfirm = actionId;
    [[[UIAlertView alloc] initWithTitle:title message:nil delegate:(id)[G6AssistTarget class] cancelButtonTitle:G6L(@"Huỷ") otherButtonTitles:G6L(@"Đồng ý"), nil] show];
}

// Chạy một chức năng. `confirmed`: đã qua hộp hỏi lại (việc khởi động lại / tắt máy).
static void G6AssistPerform(NSString *actionId, BOOL confirmed) {
    UIApplication *app = [UIApplication sharedApplication];
    id ui = G6Shared("SBUIController", @"sharedInstance");
    @try {
        if ([actionId isEqualToString:@"home"]) {
            SEL sel = NSSelectorFromString(@"clickedMenuButton");
            if ([ui respondsToSelector:sel]) ((BOOL (*)(id, SEL))objc_msgSend)(ui, sel);
        } else if ([actionId isEqualToString:@"switcher"]) {
            SEL sel = NSSelectorFromString(@"activateSwitcher");
            if ([ui respondsToSelector:sel]) ((BOOL (*)(id, SEL))objc_msgSend)(ui, sel);
        } else if ([actionId isEqualToString:@"notifications"]) {
            id list = G6Shared("SBBulletinListController", @"sharedInstance");
            SEL sel = NSSelectorFromString(@"showListViewAnimated:");
            if ([list respondsToSelector:sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(list, sel, YES);
        } else if ([actionId isEqualToString:@"controlcenter"]) {
            G6ControlCenterSetVisible(YES, YES);
        } else if ([actionId isEqualToString:@"lock"]) {
            SEL sel = NSSelectorFromString(@"lockFromSource:");
            if ([ui respondsToSelector:sel]) ((void (*)(id, SEL, int))objc_msgSend)(ui, sel, 0);
        } else if ([actionId isEqualToString:@"screenshot"]) {
            // Ẩn nút để nó không lọt vào ảnh chụp
            gWindow.hidden = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                id shooter = G6Shared("SBScreenShotter", @"sharedInstance");
                SEL sel = NSSelectorFromString(@"saveScreenshot:");
                if ([shooter respondsToSelector:sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(shooter, sel, YES);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    gWindow.hidden = !gActive;
                });
            });
        } else if ([actionId isEqualToString:@"volup"] || [actionId isEqualToString:@"voldown"]) {
            id vc = G6Shared("VolumeControl", @"sharedVolumeControl");
            G6Send(vc, [actionId isEqualToString:@"volup"] ? @"increaseVolume" : @"decreaseVolume");
            G6Send(vc, @"cancelVolumeEvent");
        } else if ([actionId isEqualToString:@"mute"]) {
            id media = G6Shared("SBMediaController", @"sharedInstance");
            SEL set = NSSelectorFromString(@"setRingerMuted:");
            if ([media respondsToSelector:set]) ((void (*)(id, SEL, BOOL))objc_msgSend)(media, set, !G6GetBool(media, @"isRingerMuted"));
        } else if ([actionId isEqualToString:@"rotate"]) {
            // Đang khoá thì mở, đang mở thì khoá theo hướng giao diện đang hiện
            G6SetRotationLocked(!G6RotationLocked());
        } else if ([actionId isEqualToString:@"dark"]) {
            G6SetAppearance(!G6IsDark());
        } else if ([actionId isEqualToString:@"brightup"] || [actionId isEqualToString:@"brightdown"]) {
            float (*current)(void) = dlsym(RTLD_DEFAULT, "BKSDisplayBrightnessGetCurrent");
            float level = current ? current() : 0.5f;
            level = MAX(0.02f, MIN(1.0f, level + ([actionId isEqualToString:@"brightup"] ? 0.1f : -0.1f)));
            id brightness = G6Shared("SBBrightnessController", @"sharedBrightnessController");
            SEL sel = NSSelectorFromString(@"setBrightnessLevel:");
            if ([brightness respondsToSelector:sel]) ((void (*)(id, SEL, float))objc_msgSend)(brightness, sel, level);
        } else if ([actionId isEqualToString:@"respring"]) {
            // Respring: làm ngay, không hỏi lại — bấm nhầm chỉ mất chừng mười giây, còn người dùng tweak thì cần nó nhanh
            G6Log(@"nút trợ năng: respring theo yêu cầu");
            if (!G6Send(app, @"relaunchSpringBoard")) G6Log(@"nút trợ năng: SpringBoard không có -relaunchSpringBoard");
        } else if ([actionId isEqualToString:@"reboot"] || [actionId isEqualToString:@"poweroff"]) {
            if (!confirmed) {
                G6Confirm(actionId, [actionId isEqualToString:@"reboot"] ? G6L(@"Khởi động lại máy?") : G6L(@"Tắt máy?"));
                return;
            }
            NSString *name = [actionId isEqualToString:@"reboot"] ? @"reboot" : @"powerDown";
            if (!G6Send(app, name)) G6Log(@"nút trợ năng: SpringBoard không có -%@", name);
        }
    } @catch (NSException *e) {
        G6Log(@"nút trợ năng: «%@» lỗi %@", actionId, e);
    }
}

// ---- Ô có trạng thái ----

// Trạng thái thật của máy cho ô bật / tắt; −1 = ô này không có trạng thái
static int G6AssistState(NSString *actionId) {
    if ([actionId isEqualToString:@"rotate"]) return G6RotationLocked() ? 1 : 0;
    if ([actionId isEqualToString:@"mute"]) return G6GetBool(G6Shared("SBMediaController", @"sharedInstance"), @"isRingerMuted") ? 1 : 0;
    if ([actionId isEqualToString:@"dark"]) return G6IsDark() ? 1 : 0;
    return -1;
}

// Nhãn của ô: với ô có trạng thái là việc lần bấm tới sẽ làm
static NSString *G6AssistTitle(NSString *actionId) {
    int state = G6AssistState(actionId);
    if ([actionId isEqualToString:@"rotate"]) return state ? G6L(@"Mở khoá xoay") : G6L(@"Khoá xoay");
    if ([actionId isEqualToString:@"mute"]) return state ? G6L(@"Bật tiếng") : G6L(@"Tắt tiếng");
    if ([actionId isEqualToString:@"dark"]) return state ? G6L(@"Chuyển sáng") : G6L(@"Chuyển tối");
    return G6L(G6Catalog()[actionId][@"short"]) ?: actionId;
}

static void G6AssistCloseMenu(BOOL animated);

// (Đặt lại) đồng hồ tự đóng bảng nút theo cấu hình
static void G6AssistArmMenuTimer(void) {
    [gMenuTimer invalidate];
    gMenuTimer = nil;
    NSInteger seconds = [G6AssistConfig()[@"menu_timeout"] integerValue];
    if (!gMenu || seconds <= 0) return;
    gMenuTimer = [NSTimer scheduledTimerWithTimeInterval:seconds target:[G6AssistTarget class] selector:@selector(menuTimeout:) userInfo:nil repeats:NO];
}

// Chức năng giữ bảng nút mở để bấm liên tiếp (âm lượng, độ sáng)
static BOOL G6KeepsMenuOpen(NSString *actionId) {
    return [@[@"volup", @"voldown", @"brightup", @"brightdown"] containsObject:actionId];
}

// ---- Bảng nút ----

// Vị trí các ô trong lưới 3×3 (0 = trên trái … 8 = dưới phải) theo số ô đang dùng: xếp đối xứng quanh tâm như iOS — 8 ô thì
// chừa ô giữa, 4 ô thành hình chữ thập, 1 ô nằm chính giữa. Nút 1, 2, 3… lần lượt vào các vị trí theo thứ tự đọc.
static const uint8_t *G6AssistCells(NSInteger count) {
    static const uint8_t layouts[10][9] = {
        {4},                          // (không dùng)
        {4},                          // 1: giữa
        {3, 5},                       // 2: trái – phải
        {1, 6, 8},                    // 3: tam giác
        {1, 3, 5, 7},                 // 4: chữ thập
        {1, 3, 5, 6, 8},              // 5: ngũ giác
        {0, 1, 2, 6, 7, 8},           // 6: hàng trên + hàng dưới
        {0, 1, 2, 4, 6, 7, 8},        // 7: như 6 + ô giữa
        {0, 1, 2, 3, 5, 6, 7, 8},     // 8: mọi ô trừ ô giữa
        {0, 1, 2, 3, 4, 5, 6, 7, 8},  // 9: kín lưới
    };
    return layouts[MAX(1, MIN(9, count))];
}

static void G6AssistOpenMenu(void) {
    if (gMenu || !gWindow) return;
    NSDictionary *cfg = G6AssistConfig();
    NSArray *slots = cfg[@"slots"];
    NSInteger count = MAX(1, MIN(9, [cfg[@"count"] integerValue]));
    NSMutableArray *ids = [NSMutableArray array];
    for (NSInteger i = 0; i < count && i < (NSInteger)slots.count; i++) {
        NSString *sid = slots[i];
        if ([sid isKindOfClass:[NSString class]] && ![sid isEqualToString:@"none"]) [ids addObject:sid];
    }
    if (ids.count == 0) return;
    @try {
        // Chụp màn hình làm nền kính trước khi bảng hiện (nút tạm ẩn để không lọt vào nền)
        gButton.hidden = YES;
        G6Backdrop *backdrop = [G6Backdrop backdropWithScreen:YES];
        // Bảng luôn là hình vuông 3×3 như AssistiveTouch của iOS đời sau; số ô ít hơn 9 thì xếp đối xứng quanh tâm
        NSInteger n = ids.count;
        const uint8_t *cells = G6AssistCells(n);
        CGSize ui = G6AssistUISize();
        CGSize size = CGSizeMake(3 * kTile + 2 * kPad, 3 * kTile + 2 * kPad);
        CGRect frame = CGRectMake(floor((ui.width - size.width) / 2), floor((ui.height - size.height) / 2), size.width, size.height);

        gCatcher = [[UIControl alloc] initWithFrame:gRoot.bounds];
        gCatcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [gCatcher addTarget:[G6AssistTarget class] action:@selector(dismiss:) forControlEvents:UIControlEventTouchDown];
        [gRoot insertSubview:gCatcher belowSubview:gButton];

        UIView *menu = [[UIView alloc] initWithFrame:frame];
        UIImageView *glass = [[UIImageView alloc] initWithFrame:menu.bounds];
        [menu addSubview:glass];
        [gRoot insertSubview:menu aboveSubview:gCatcher];
        glass.image = G6GlassImageForRect(@"hud", gRoot, frame, YES, backdrop);
        CGFloat shadowMargin = 0;
        UIImage *shadow = G6ShadowImage(@"hud", size, YES, &shadowMargin);
        if (shadow) {
            UIImageView *shadowView = [[UIImageView alloc] initWithFrame:CGRectInset(menu.bounds, -shadowMargin, -shadowMargin)];
            shadowView.image = shadow;
            [menu insertSubview:shadowView belowSubview:glass];
        }
        UIFont *font = G6Font(G6FontMedium, 11);
        for (NSInteger i = 0; i < n; i++) {
            // Ô thứ i nằm ở vị trí cells[i] của lưới (0–8, đọc từ trái sang phải, trên xuống dưới)
            NSInteger row = cells[i] / 3, col = cells[i] % 3;
            UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
            tile.frame = CGRectMake(kPad + col * kTile, kPad + row * kTile, kTile, kTile);
            tile.tag = i;
            tile.accessibilityLabel = ids[i];
            // Ô đang ở trạng thái «bật» (đang khoá xoay, đang tắt tiếng…): đĩa sáng sau hình
            if (G6AssistState(ids[i]) == 1) {
                UIView *on = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
                on.center = CGPointMake(kTile / 2, kTile / 2 - 10);
                on.backgroundColor = [UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:0.9];
                on.layer.cornerRadius = 25;
                on.userInteractionEnabled = NO;
                [tile addSubview:on];
            }
            UIImageView *glyph = [[UIImageView alloc] initWithImage:G6GlyphImage(ids[i], 36)];
            glyph.center = CGPointMake(kTile / 2, kTile / 2 - 10);
            glyph.userInteractionEnabled = NO;
            [tile addSubview:glyph];
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(2, kTile - 30, kTile - 4, 26)];
            label.backgroundColor = [UIColor clearColor];
            label.textColor = [UIColor colorWithWhite:1 alpha:0.92];
            label.font = font;
            label.textAlignment = NSTextAlignmentCenter;
            label.numberOfLines = 2;
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.8;
            label.text = G6AssistTitle(ids[i]);
            label.userInteractionEnabled = NO;
            [tile addSubview:label];
            [tile addTarget:[G6AssistTarget class] action:@selector(tile:) forControlEvents:UIControlEventTouchUpInside];
            [tile addTarget:[G6AssistTarget class] action:@selector(tileDown:) forControlEvents:UIControlEventTouchDown];
            [tile addTarget:[G6AssistTarget class] action:@selector(tileUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [menu addSubview:tile];
        }
        gMenu = menu;
        G6AssistArmMenuTimer();
        // Mở từ chỗ nút
        CGPoint from = G6ButtonCenter();
        menu.alpha = 0;
        menu.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.2, 0.2),
                                                 CGAffineTransformMakeTranslation(from.x - CGRectGetMidX(frame), from.y - CGRectGetMidY(frame)));
        [UIView animateWithDuration:0.22
                         animations:^{
                             menu.alpha = 1;
                             menu.transform = CGAffineTransformIdentity;
                         }];
    } @catch (NSException *e) {
        G6Log(@"nút trợ năng: mở bảng nút lỗi %@", e);
        G6AssistCloseMenu(NO);
    }
}

static void G6AssistCloseMenu(BOOL animated) {
    UIView *menu = gMenu;
    gMenu = nil;
    [gMenuTimer invalidate];
    gMenuTimer = nil;
    [gCatcher removeFromSuperview];
    gCatcher = nil;
    gButton.hidden = NO;
    G6AssistWake();
    if (!menu) return;
    if (!animated) {
        [menu removeFromSuperview];
        return;
    }
    CGPoint to = G6ButtonCenter();
    [UIView animateWithDuration:0.18
                     animations:^{
                         menu.alpha = 0;
                         menu.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.2, 0.2),
                                                                  CGAffineTransformMakeTranslation(to.x - menu.center.x, to.y - menu.center.y));
                     }
                     completion:^(BOOL finished) {
                         [menu removeFromSuperview];
                     }];
}

// Một thao tác trên nút (chạm / chạm hai lần / nhấn giữ) → chức năng đã gán
static void G6AssistGesture(NSString *key) {
    NSString *actionId = G6AssistConfig()[key];
    if (![actionId isKindOfClass:[NSString class]] || [actionId isEqualToString:@"none"]) return;
    G6AssistWake();
    if ([actionId isEqualToString:@"menu"]) G6AssistOpenMenu();
    else G6AssistPerform(actionId, NO);
}

// ---- Cửa sổ và đích của sự kiện ----

@implementation G6AssistWindow

// Chỉ nhận chạm ở nút (hoặc cả màn hình lúc bảng nút mở); chỗ khác lọt xuống cửa sổ bên dưới
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (gMenu) return [super hitTest:point withEvent:event];
    if (!gButton || gButton.hidden) return nil;
    CGPoint p = [gButton convertPoint:point fromView:self];
    return CGRectContainsPoint(gButton.bounds, p) ? gButton : nil;
}

@end

@implementation G6AssistTarget

+ (void)idle:(NSTimer *)timer {
    if (gMenu) return;
    CGFloat alpha = [G6AssistConfig()[@"idle"] floatValue];
    [UIView animateWithDuration:0.4
                     animations:^{
                         gButton.alpha = alpha > 0.1 ? alpha : 0.5;
                     }];
}

+ (void)dismiss:(id)sender {
    G6AssistCloseMenu(YES);
}

// Hết thời gian chờ mà không ai bấm: tự ẩn bảng nút
+ (void)menuTimeout:(NSTimer *)timer {
    gMenuTimer = nil;
    if (!gMenu) return;
    G6Log(@"nút trợ năng: bảng nút tự ẩn (hết thời gian chờ)");
    G6AssistCloseMenu(YES);
}

+ (void)tileDown:(UIButton *)tile {
    tile.alpha = 0.5;
    // Đang bấm: tính lại thời gian chờ từ đầu
    G6AssistArmMenuTimer();
}

+ (void)tileUp:(UIButton *)tile {
    tile.alpha = 1;
}

+ (void)tile:(UIButton *)tile {
    NSString *actionId = tile.accessibilityLabel;
    if (!actionId) return;
    if (G6KeepsMenuOpen(actionId)) {
        G6AssistPerform(actionId, NO);
        return;
    }
    G6AssistCloseMenu(YES);
    // Để bảng kịp đóng rồi mới làm (chụp màn hình, mở Control Center… không dính bảng nút)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        G6AssistPerform(actionId, NO);
    });
}

+ (void)tap:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) G6AssistGesture(@"tap");
}

+ (void)doubleTap:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) G6AssistGesture(@"double");
}

+ (void)hold:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) G6AssistGesture(@"hold");
}

+ (void)pan:(UIPanGestureRecognizer *)gesture {
    CGSize ui = G6AssistUISize();
    CGPoint p = [gesture locationInView:gRoot];
    CGFloat half = kButton / 2;
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        [gIdleTimer invalidate];
        gIdleTimer = nil;
        gButton.alpha = 1;
        gButton.center = CGPointMake(MAX(half, MIN(ui.width - half, p.x)), MAX(20 + half, MIN(ui.height - half, p.y)));
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        // Thả ra: hít vào mép gần hơn, nhớ vị trí
        gEdgeSide = gButton.center.x > ui.width / 2 ? 1 : 0;
        gYFraction = MAX(0.05, MIN(0.95, gButton.center.y / ui.height));
        G6SavePosition();
        [UIView animateWithDuration:0.25
                         animations:^{
                             gButton.center = G6ButtonCenter();
                         }];
        G6AssistWake();
    }
}

+ (void)orientationChanged:(NSNotification *)note {
    // Hướng giao diện đổi sau thông báo một nhịp
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gMenu) G6AssistCloseMenu(NO);
        [UIView animateWithDuration:0.2
                         animations:^{
                             G6AssistLayout();
                         }];
    });
}

+ (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
    NSString *actionId = gPendingConfirm;
    gPendingConfirm = nil;
    if (actionId && index != alertView.cancelButtonIndex) G6AssistPerform(actionId, YES);
}

@end

// ---- Dựng / gỡ ----

static void G6AssistBuild(void) {
    if (gWindow) return;
    G6LoadPosition();
    gWindow = [[G6AssistWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    gWindow.windowLevel = 1070;
    gWindow.backgroundColor = [UIColor clearColor];
    gRoot = [[UIView alloc] initWithFrame:CGRectZero];
    [gWindow addSubview:gRoot];
    gButton = [[UIImageView alloc] initWithImage:G6ButtonImage()];
    gButton.userInteractionEnabled = YES;
    [gRoot addSubview:gButton];

    Class target = [G6AssistTarget class];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:target action:@selector(pan:)];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(tap:)];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(hold:)];
    hold.minimumPressDuration = 0.55;
    [gButton addGestureRecognizer:pan];
    [gButton addGestureRecognizer:hold];
    // Chỉ chờ «chạm hai lần» khi nó có việc — không thì chạm một lần phản hồi ngay
    if (![G6AssistConfig()[@"double"] isEqual:@"none"]) {
        UITapGestureRecognizer *twice = [[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(doubleTap:)];
        twice.numberOfTapsRequired = 2;
        [gButton addGestureRecognizer:twice];
        [tap requireGestureRecognizerToFail:twice];
    }
    [gButton addGestureRecognizer:tap];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:target selector:@selector(orientationChanged:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    [nc addObserver:target selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:nil];
    [nc addObserver:target selector:@selector(orientationChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
    G6AssistLayout();
    gWindow.hidden = NO;
    G6AssistWake();
}

static void G6AssistTearDown(void) {
    if (!gWindow) return;
    G6AssistCloseMenu(NO);
    [gIdleTimer invalidate];
    gIdleTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:[G6AssistTarget class]];
    gWindow.hidden = YES;
    gWindow = nil;
    gRoot = nil;
    gButton = nil;
}

static void G6AssistApply(void) {
    NSDictionary *cfg = G6AssistConfig();
    BOOL active = G6Feature(@"assist");
    // Thao tác «chạm hai lần» có / không quyết định bộ nhận cử chỉ → đổi thì dựng lại nút
    NSString *signature = [NSString stringWithFormat:@"%d|%@", active, [cfg[@"double"] isEqual:@"none"] ? @"1" : @"2"];
    if ([signature isEqualToString:gSignature]) return;
    BOOL first = gSignature == nil;
    gSignature = signature;
    gActive = active;
    G6AssistTearDown();
    if (active) G6AssistBuild();
    if (active || !first) G6SystemAssist(active);
    if (active || !first) G6Log(@"nút trợ năng: %@", active ? @"bật" : @"tắt");
}

// Bấm nút Home lúc bảng nút đang mở: đóng bảng, không làm gì khác
static BOOL (*o_clickedMenuButton)(id, SEL);
static BOOL g6_clickedMenuButton(id self, SEL _cmd) {
    if (gMenu) {
        G6AssistCloseMenu(YES);
        return YES;
    }
    return o_clickedMenuButton(self, _cmd);
}

void G6AssistInstall(void) {
    G6HookNamed("SBUIController", NSSelectorFromString(@"clickedMenuButton"), (IMP)g6_clickedMenuButton, (IMP *)&o_clickedMenuButton);
    [[NSNotificationCenter defaultCenter] addObserverForName:G6ConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
                                                      @try {
                                                          G6AssistApply();
                                                      } @catch (NSException *e) {
                                                          G6Log(@"nút trợ năng: lỗi %@", e);
                                                      }
                                                  }];
    G6AssistApply();
}

#if G6_DEBUG
void G6AssistDebug(NSString *arg) {
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    if ([verb isEqualToString:@"menu"]) {
        if (value.intValue) G6AssistOpenMenu();
        else G6AssistCloseMenu(NO);
    } else if ([verb isEqualToString:@"do"]) {
        G6AssistPerform(value, NO);
    } else if ([verb isEqualToString:@"press"]) {
        // Bấm ô có mã `value` trong bảng nút đang mở
        for (UIView *sub in gMenu.subviews) {
            if ([sub isKindOfClass:[UIButton class]] && [sub.accessibilityLabel isEqualToString:value]) {
                [(UIButton *)sub sendActionsForControlEvents:UIControlEventTouchUpInside];
                break;
            }
        }
    } else if ([verb isEqualToString:@"tap"] || [verb isEqualToString:@"double"] || [verb isEqualToString:@"hold"]) {
        G6AssistGesture(verb);
    } else if ([verb isEqualToString:@"move"]) {
        // move <mép 0|1> <tung độ 0–1>
        gEdgeSide = value.intValue ? 1 : 0;
        if (parts.count > 2) gYFraction = MAX(0.05, MIN(0.95, [parts[2] floatValue]));
        G6SavePosition();
        G6AssistLayout();
    }
    NSMutableArray *tiles = [NSMutableArray array];
    for (UIView *sub in gMenu.subviews) {
        if ([sub isKindOfClass:[UIButton class]] && sub.accessibilityLabel) [tiles addObject:sub.accessibilityLabel];
    }
    G6Log(@"[thử] nút trợ năng: %@, cửa sổ %@, nút ở %@ (mép %d, y %.2f), hướng %ld, bảng %@ | khoá xoay %d, tắt tiếng %d, tự ẩn %@ giây",
          gActive ? @"bật" : @"tắt", gWindow ? @"có" : @"không", gButton ? NSStringFromCGPoint(gButton.center) : @"-", gEdgeSide,
          gYFraction, (long)G6AssistOrientation(), gMenu ? [tiles componentsJoinedByString:@","] : @"đóng", G6AssistState(@"rotate"),
          G6AssistState(@"mute"), G6AssistConfig()[@"menu_timeout"]);
}
#endif
