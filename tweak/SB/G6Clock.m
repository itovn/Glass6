// Biểu tượng Đồng hồ sống.
//
// iOS 6: biểu tượng app Đồng hồ (com.apple.mobiletimer) là ảnh tĩnh, kim vẽ chết ở 10:15. Từ iOS 7 kim chạy thật.
//
// Cách làm:
//   - Ảnh biểu tượng (mọi định dạng: màn hình chính, ô nhỏ trong thư mục, tìm kiếm…) → mặt đồng hồ tự vẽ bằng CoreGraphics,
//     kim đứng ở 10:09:30; qua cùng khâu cắt hình với mọi biểu tượng khác (G6IconImageFromSource).
//   - Trên mỗi SBIconView đang hiện biểu tượng Đồng hồ (màn hình chính, dock, khay đa nhiệm): thêm vào SBIconImageView một
//     lớp phủ = mặt đồng hồ không kim + ba lớp kim. Lớp phủ nằm TRONG lớp vẽ của ảnh biểu tượng nên mọi thứ SpringBoard làm
//     với ảnh (rung lúc sắp xếp, mờ đi, tối lại khi chạm) đều áp lên nó.
//   - Kim chạy: một NSTimer nhích ba kim theo giờ thật khoảng 10 lần mỗi giây (đủ để đầu kim giây mỗi lần đi không quá
//     ~0,3 điểm ảnh — mắt thấy trôi liền). Đã thử và đo trên iPad mini 1 (19/11/2026, công cụ tools/g6cpu), màn hình chính
//     đứng yên, không có đồng hồ thì backboardd 1,5% + SpringBoard 0,1% CPU:
//       · CABasicAnimation xoay đều lặp mãi: backboardd ~13% — chuyển động liên tục bắt tiến trình vẽ dựng lại cả màn hình
//         60 lần mỗi giây; giờ của CoreAnimation lại đứng khi máy ngủ nên còn phải chỉnh lại kim sau mỗi lần thức;
//       · CADisplayLink cách 6 khung hình: backboardd 4,9% nhưng SpringBoard 1,5% — nó vẫn đánh thức tiến trình ở mọi khung hình;
//       · NSTimer 10 lần / giây: cách đang dùng (số đo ghi ở docs/DECISIONS.md D13).
//     Đọc giờ thật ở mỗi lần nhích nên không bao giờ lệch.
//   - Chỉ chạy khi có người nhìn: view đang trong cửa sổ (SpringBoard gỡ hẳn màn hình chính khỏi cửa sổ lúc mở app), máy
//     không khoá, màn hình không tắt. Xét lại mỗi khi view vào / rời cửa sổ, khoá / mở khoá, tắt / sáng màn hình.
//   - «Giảm hiệu ứng»: bỏ kim giây, kim giờ / phút nhích mỗi phút một lần.
#import "G6Clock.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Icons.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Screen.h"

static NSString *const kClockBundleID = @"com.apple.mobiletimer";
// Định dạng ảnh của biểu tượng trên màn hình chính
static const int kHomeFormat = 2;
// Giờ kim đứng trong ảnh tĩnh: 10:09:30
static const double kStillSeconds = 10 * 3600 + 9 * 60 + 30;

// Đọc ở mọi luồng (lúc SpringBoard xin ảnh), chỉ ghi ở luồng chính
static volatile BOOL gActive;

// Chỉ dùng ở luồng chính
static BOOL gReduce;
static NSString *gSignature;
static NSHashTable *gViews;  // các SBIconView đang mang lớp phủ đồng hồ (giữ yếu)
static NSTimer *gMinuteTimer;
static NSTimer *gTickTimer;
static NSTimeInterval gTickInterval;
static BOOL gSyncPending;
static char kOverlayKey;

// ---- Số đo (theo cạnh S của biểu tượng) ----

typedef struct {
    CGFloat length, tail, width;
} G6Hand;

static CGFloat G6FaceRadius(CGFloat s) {
    return s * 0.43;
}

// which: 0 = giờ, 1 = phút, 2 = giây
static G6Hand G6HandMetrics(int which, CGFloat s) {
    CGFloat r = G6FaceRadius(s);
    switch (which) {
        case 0:
            return (G6Hand){r * 0.52, r * 0.11, s * 0.046};
        case 1:
            return (G6Hand){r * 0.84, r * 0.11, s * 0.034};
        default:
            return (G6Hand){r * 0.88, r * 0.22, s * 0.017};
    }
}

static void G6SetHandColor(CGContextRef ctx, int which) {
    // Kim giây màu cam của app Đồng hồ; kim giờ / phút đen
    if (which == 2) CGContextSetRGBStrokeColor(ctx, 1.0, 0.584, 0.0, 1);
    else CGContextSetRGBStrokeColor(ctx, 0.07, 0.07, 0.08, 1);
}

// Một kim chỉ lên trên, trục quay ở gốc toạ độ (trục y của ngữ cảnh hướng lên)
static void G6DrawHand(CGContextRef ctx, int which, CGFloat s) {
    G6Hand h = G6HandMetrics(which, s);
    G6SetHandColor(ctx, which);
    CGContextSetLineWidth(ctx, h.width);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextMoveToPoint(ctx, 0, -h.tail + h.width / 2);
    CGContextAddLineToPoint(ctx, 0, h.length - h.width / 2);
    CGContextStrokePath(ctx);
}

static void G6DrawCap(CGContextRef ctx, CGFloat s) {
    CGFloat r = G6FaceRadius(s), a = r * 0.085, b = r * 0.045;
    CGContextSetRGBFillColor(ctx, 0.07, 0.07, 0.08, 1);
    CGContextFillEllipseInRect(ctx, CGRectMake(-a, -a, a * 2, a * 2));
    CGContextSetRGBFillColor(ctx, 1.0, 0.584, 0.0, 1);
    CGContextFillEllipseInRect(ctx, CGRectMake(-b, -b, b * 2, b * 2));
}

static CGContextRef G6ClockContext(size_t w, size_t h) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    return ctx;
}

// Góc ba kim (radian, theo chiều kim đồng hồ từ số 12) ở giây thứ `t` trong ngày
static void G6AnglesAt(double t, double *hour, double *minute, double *second) {
    *second = fmod(t, 60.0) / 60.0 * 2 * M_PI;
    *minute = fmod(t, 3600.0) / 3600.0 * 2 * M_PI;
    *hour = fmod(t, 43200.0) / 43200.0 * 2 * M_PI;
}

// Mặt đồng hồ vuông `px × px` điểm ảnh (chưa cắt góc): nền tối, mặt trắng, 12 vạch giờ; `hands` = vẽ cả kim đứng ở 10:09:30.
// Chỉ dùng CoreGraphics → gọi được từ luồng nền.
static CGImageRef G6ClockCreateFace(int px, BOOL hands) CF_RETURNS_RETAINED {
    if (px < 8 || px > 1024) return NULL;
    CGContextRef ctx = G6ClockContext(px, px);
    if (!ctx) return NULL;
    CGFloat s = px;
    // Nền: xám than sáng dần lên phía trên
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat bg[] = {0.05, 0.05, 0.06, 1, 0.20, 0.20, 0.22, 1};
    CGGradientRef grad = CGGradientCreateWithColorComponents(cs, bg, NULL, 2);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, s), 0);
    CGGradientRelease(grad);
    // Từ đây gốc toạ độ ở tâm mặt đồng hồ
    CGContextTranslateCTM(ctx, s / 2, s / 2);
    CGFloat r = G6FaceRadius(s);
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, CGRectMake(-r, -r, r * 2, r * 2));
    CGContextClip(ctx);
    CGFloat face[] = {0.90, 0.90, 0.92, 1, 1, 1, 1, 1};
    grad = CGGradientCreateWithColorComponents(cs, face, NULL, 2);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, -r), CGPointMake(0, r), 0);
    CGGradientRelease(grad);
    CGContextRestoreGState(ctx);
    CGColorSpaceRelease(cs);
    // Vạch giờ: 12 / 3 / 6 / 9 dài và đậm hơn
    CGContextSetLineCap(ctx, kCGLineCapRound);
    for (int i = 0; i < 12; i++) {
        BOOL quarter = i % 3 == 0;
        CGContextSaveGState(ctx);
        CGContextRotateCTM(ctx, -i * M_PI / 6);
        CGContextSetRGBStrokeColor(ctx, 0.07, 0.07, 0.08, quarter ? 1 : 0.55);
        CGContextSetLineWidth(ctx, s * (quarter ? 0.030 : 0.018));
        CGContextMoveToPoint(ctx, 0, r * (quarter ? 0.76 : 0.83));
        CGContextAddLineToPoint(ctx, 0, r * 0.91);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }
    if (hands) {
        double a[3];
        G6AnglesAt(kStillSeconds, &a[0], &a[1], &a[2]);
        for (int which = 0; which < 3; which++) {
            CGContextSaveGState(ctx);
            // Trục y hướng lên: góc dương của CoreGraphics là ngược chiều kim đồng hồ
            CGContextRotateCTM(ctx, -a[which]);
            G6DrawHand(ctx, which, s);
            CGContextRestoreGState(ctx);
        }
        G6DrawCap(ctx, s);
    }
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return img;
}

UIImage *G6ClockIconImage(NSString *bundleID, int format, UIImage *orig) {
    if (!gActive || ![bundleID isKindOfClass:[NSString class]] || ![bundleID isEqualToString:kClockBundleID]) return nil;
    CGFloat scale = orig.scale >= 1 ? orig.scale : 1;
    int px = G6IconContentPixels(format, scale);
    if (px <= 0) return nil;
    CGImageRef face = G6ClockCreateFace(px, YES);
    if (!face) return nil;
    UIImage *img = G6IconImageFromSource(face, format, scale);
    CGImageRelease(face);
    // Phải đúng cỡ ảnh SpringBoard đang chờ
    CGImageRef ocg = orig.CGImage, mcg = img.CGImage;
    if (!ocg || !mcg || CGImageGetWidth(ocg) != CGImageGetWidth(mcg) || CGImageGetHeight(ocg) != CGImageGetHeight(mcg)) return nil;
    return img;
}

// ---- Lớp phủ trên SBIconView ----

// Mặt đồng hồ không kim, đã cắt hình, cỡ ảnh biểu tượng màn hình chính — nhớ lại tới khi cấu hình đổi
static UIImage *gFaceImage;

static UIImage *G6ClockFaceImage(void) {
    if (gFaceImage) return gFaceImage;
    CGFloat scale = MAX([UIScreen mainScreen].scale, 1);
    int px = G6IconContentPixels(kHomeFormat, scale);
    if (px <= 0) return nil;
    CGImageRef face = G6ClockCreateFace(px, NO);
    if (!face) return nil;
    gFaceImage = G6IconImageFromSource(face, kHomeFormat, scale);
    CGImageRelease(face);
    return gFaceImage;
}

// Ảnh một kim (chỉ lên trên) để làm nội dung lớp vẽ. Vẽ ở độ phân giải gấp đôi màn hình và chừa lề trong suốt: lúc xoay,
// mép kim được nội suy mượt thay vì răng cưa.
static CGImageRef G6ClockCreateHandImage(int which, CGFloat s, CGFloat pixelScale, CGSize *sizeOut, CGFloat *pivotOut) CF_RETURNS_RETAINED {
    G6Hand h = G6HandMetrics(which, s);
    const CGFloat pad = 2;
    CGFloat w = ceil(h.width) + pad * 2, height = ceil(h.length + h.tail) + pad * 2;
    CGContextRef ctx = G6ClockContext((size_t)lround(w * pixelScale), (size_t)lround(height * pixelScale));
    if (!ctx) return NULL;
    CGContextScaleCTM(ctx, pixelScale, pixelScale);
    // Trục quay cách đáy ảnh (đuôi kim + lề)
    CGContextTranslateCTM(ctx, w / 2, pad + h.tail);
    G6DrawHand(ctx, which, s);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    *sizeOut = CGSizeMake(w, height);
    // Vị trí trục quay tính từ mép TRÊN của lớp vẽ (toạ độ UIKit), theo tỉ lệ chiều cao
    *pivotOut = (height - pad - h.tail) / height;
    return img;
}

static void G6ClockSyncAll(void);
static void G6ClockTick(void);

@interface G6ClockOverlay : CALayer
@property (nonatomic, strong) CALayer *hourHand, *minuteHand, *secondHand, *cap;
// Cạnh biểu tượng (điểm) mà các kim đang được dựng cho
@property (nonatomic, assign) CGFloat builtSide;
// Đích của đồng hồ hẹn «đầu phút kế» (chế độ giảm hiệu ứng) và của nhịp nhích kim
+ (void)g6_minuteTick:(NSTimer *)timer;
+ (void)g6_tick:(NSTimer *)timer;
@end

@implementation G6ClockOverlay

// Không để CoreAnimation tự thêm chuyển động khi đổi khung / nội dung / góc kim
- (id<CAAction>)actionForKey:(NSString *)event {
    return nil;
}

+ (void)g6_minuteTick:(NSTimer *)timer {
    gMinuteTimer = nil;
    G6ClockSyncAll();
}

+ (void)g6_tick:(NSTimer *)timer {
    G6ClockTick();
}

@end

static CALayer *G6NewPlainLayer(void) {
    CALayer *layer = [CALayer layer];
    layer.actions = @{@"transform" : [NSNull null], @"position" : [NSNull null], @"bounds" : [NSNull null],
                      @"contents" : [NSNull null], @"hidden" : [NSNull null]};
    return layer;
}

// Dựng lại ba kim + chốt giữa cho biểu tượng cạnh `side` điểm, tâm mặt đồng hồ ở `center` (toạ độ của lớp phủ)
static void G6OverlayBuildHands(G6ClockOverlay *overlay, CGFloat side, CGPoint center) {
    CGFloat pixelScale = MAX([UIScreen mainScreen].scale, 1) * 2;
    NSArray *old = @[overlay.hourHand ?: (id)[NSNull null], overlay.minuteHand ?: (id)[NSNull null],
                     overlay.secondHand ?: (id)[NSNull null], overlay.cap ?: (id)[NSNull null]];
    for (id l in old) {
        if ([l isKindOfClass:[CALayer class]]) [(CALayer *)l removeFromSuperlayer];
    }
    CALayer *hands[3] = {nil, nil, nil};
    for (int which = 0; which < 3; which++) {
        CGSize size = CGSizeZero;
        CGFloat pivot = 0.5;
        CGImageRef img = G6ClockCreateHandImage(which, side, pixelScale, &size, &pivot);
        if (!img) continue;
        CALayer *layer = G6NewPlainLayer();
        layer.contents = (__bridge id)img;
        layer.contentsScale = pixelScale;
        layer.bounds = CGRectMake(0, 0, size.width, size.height);
        layer.anchorPoint = CGPointMake(0.5, pivot);
        layer.position = center;
        CGImageRelease(img);
        [overlay addSublayer:layer];
        hands[which] = layer;
    }
    // Chốt giữa đứng yên, nằm trên các kim
    CGFloat capSide = ceil(G6FaceRadius(side) * 0.085 * 2) + 4;
    CGContextRef ctx = G6ClockContext((size_t)lround(capSide * pixelScale), (size_t)lround(capSide * pixelScale));
    CALayer *cap = nil;
    if (ctx) {
        CGContextScaleCTM(ctx, pixelScale, pixelScale);
        CGContextTranslateCTM(ctx, capSide / 2, capSide / 2);
        G6DrawCap(ctx, side);
        CGImageRef img = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
        if (img) {
            cap = G6NewPlainLayer();
            cap.contents = (__bridge id)img;
            cap.contentsScale = pixelScale;
            cap.bounds = CGRectMake(0, 0, capSide, capSide);
            cap.position = center;
            CGImageRelease(img);
            [overlay addSublayer:cap];
        }
    }
    overlay.hourHand = hands[0];
    overlay.minuteHand = hands[1];
    overlay.secondHand = hands[2];
    overlay.cap = cap;
    overlay.builtSide = side;
}

// ---- Giờ ----

// Độ lệch múi giờ của máy so với UTC (giây), nhớ lại để mỗi nhịp nhích kim khỏi hỏi NSTimeZone. Tính lại ở mỗi lần đồng bộ
// (view vào cửa sổ, mở khoá, đổi giờ / múi giờ / giờ mùa hè — các việc này đều dẫn tới G6ClockSyncAll).
static double gZoneOffset;

static void G6RefreshZoneOffset(void) {
    gZoneOffset = [[NSTimeZone systemTimeZone] secondsFromGMTForDate:[NSDate date]];
}

// Giây thứ mấy trong ngày theo múi giờ của máy (có phần lẻ)
static double G6SecondsOfDay(void) {
    // Mốc tham chiếu của CFAbsoluteTime là nửa đêm UTC → cộng độ lệch múi giờ rồi lấy phần dư theo ngày
    double t = fmod(CFAbsoluteTimeGetCurrent() + gZoneOffset, 86400.0);
    return t < 0 ? t + 86400.0 : t;
}

// Đặt ba kim của một lớp phủ theo giờ hiện tại (lớp kim không có chuyển động ngầm — đổi là nhảy ngay)
static void G6OverlaySetTime(G6ClockOverlay *overlay, double t) {
    double hour, minute, second;
    G6AnglesAt(t, &hour, &minute, &second);
    overlay.hourHand.transform = CATransform3DMakeRotation((CGFloat)hour, 0, 0, 1);
    overlay.minuteHand.transform = CATransform3DMakeRotation((CGFloat)minute, 0, 0, 1);
    overlay.secondHand.transform = CATransform3DMakeRotation((CGFloat)second, 0, 0, 1);
}

// Cách bao lâu nhích kim một lần (giây). Đầu kim giây đi 2π·(chiều dài kim) điểm ảnh mỗi phút; nhích sao cho mỗi lần không
// quá ~0,3 điểm ảnh (iPad mini 1: 10 lần / giây), không dưới 6 và không quá 30 lần / giây.
static NSTimeInterval G6ClockTickInterval(void) {
    static NSTimeInterval interval;
    if (interval > 0) return interval;
    CGFloat scale = MAX([UIScreen mainScreen].scale, 1);
    CGRect content = G6IconContentRect(kHomeFormat, scale);
    CGFloat side = CGRectIsEmpty(content) ? 60 : MIN(content.size.width, content.size.height);
    double tipSpeed = 2 * M_PI * G6HandMetrics(2, side).length * scale / 60.0;
    interval = 1.0 / MIN(MAX(ceil(tipSpeed / 0.3), 6), 30);
    return interval;
}

static void G6ClockStopTicking(void) {
    [gTickTimer invalidate];
    gTickTimer = nil;
    gTickInterval = 0;
}

// Chạy nhịp nhích kim cách nhau `interval` giây (đang chạy đúng nhịp đó rồi thì thôi)
static void G6ClockStartTicking(NSTimeInterval interval) {
    if (gTickTimer && fabs(gTickInterval - interval) < 1e-6) return;
    [gTickTimer invalidate];
    gTickTimer = [NSTimer timerWithTimeInterval:interval target:[G6ClockOverlay class] selector:@selector(g6_tick:) userInfo:nil repeats:YES];
    gTickInterval = interval;
    // Chế độ chung: vẫn chạy trong lúc ngón tay đang kéo trang
    [[NSRunLoop mainRunLoop] addTimer:gTickTimer forMode:NSRunLoopCommonModes];
}

// ---- Gắn / gỡ / đồng bộ ----

static BOOL G6IsClockIconView(UIView *iconView) {
    id icon = [iconView respondsToSelector:@selector(icon)] ? ((id (*)(id, SEL))objc_msgSend)(iconView, @selector(icon)) : nil;
    SEL sel = NSSelectorFromString(@"applicationBundleID");
    id ident = [icon respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(icon, sel) : nil;
    return [ident isKindOfClass:[NSString class]] && [ident isEqualToString:kClockBundleID];
}

static void G6ClockDetach(UIView *iconView) {
    G6ClockOverlay *overlay = objc_getAssociatedObject(iconView, &kOverlayKey);
    if (!overlay) return;
    [overlay removeFromSuperlayer];
    objc_setAssociatedObject(iconView, &kOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gViews removeObject:iconView];
}

// Đưa một SBIconView về đúng trạng thái: có / không có lớp phủ, kim ở đúng giờ, chạy hay đứng.
static void G6ClockSyncView(UIView *iconView) {
    if (!iconView) return;
    if (!gActive || !G6IsClockIconView(iconView)) {
        G6ClockDetach(iconView);
        return;
    }
    UIView *imageView = [iconView respondsToSelector:NSSelectorFromString(@"iconImageView")]
                            ? ((id (*)(id, SEL))objc_msgSend)(iconView, NSSelectorFromString(@"iconImageView")) : nil;
    UIImage *face = G6ClockFaceImage();
    CGSize size = imageView.bounds.size;
    // Chỉ phủ khi ảnh biểu tượng đúng cỡ ảnh mặt đồng hồ (ảnh cỡ khác: để nguyên ảnh tĩnh)
    if (![imageView isKindOfClass:[UIView class]] || !face || fabs(face.size.width - size.width) > 0.5 ||
        fabs(face.size.height - size.height) > 0.5) {
        G6ClockDetach(iconView);
        return;
    }
    G6ClockOverlay *overlay = objc_getAssociatedObject(iconView, &kOverlayKey);
    if (!overlay) {
        overlay = [G6ClockOverlay layer];
        objc_setAssociatedObject(iconView, &kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gViews) gViews = [NSHashTable weakObjectsHashTable];
        [gViews addObject:iconView];
    }
    if (overlay.superlayer != imageView.layer) [imageView.layer addSublayer:overlay];
    overlay.frame = imageView.bounds;
    if (overlay.contents != (__bridge id)face.CGImage) {
        overlay.contents = (__bridge id)face.CGImage;
        overlay.contentsScale = face.scale;
        overlay.builtSide = 0;
    }
    // Vùng chứa biểu tượng trong ảnh (ảnh có lề + chỗ cho bóng vẽ liền của iOS 6)
    CGRect content = G6IconContentRect(kHomeFormat, face.scale);
    if (CGRectIsEmpty(content)) content = overlay.bounds;
    CGFloat side = MIN(content.size.width, content.size.height);
    if (fabs(overlay.builtSide - side) > 0.01) G6OverlayBuildHands(overlay, side, CGPointMake(CGRectGetMidX(content), CGRectGetMidY(content)));

    overlay.secondHand.hidden = gReduce;
    G6OverlaySetTime(overlay, G6SecondsOfDay());
}

// Biểu tượng có đang nằm trong vùng nhìn thấy của màn hình không (biểu tượng ở trang khác vẫn «trong cửa sổ» nhưng nằm ngoài)
static BOOL G6OnScreen(UIView *v) {
    UIWindow *window = v.window;
    if (!window) return NO;
    return CGRectIntersectsRect([v convertRect:v.bounds toView:window], window.bounds);
}

// Nhịp dò khi Đồng hồ đang ở trang khác: 4 lần / giây — đủ để kim đã đúng giờ lúc trang vừa trượt vào, mà không đổi gì trên
// màn hình nên tiến trình vẽ không phải làm việc
static const NSTimeInterval kIdleTickInterval = 0.25;

// Một nhịp: nhích kim của các biểu tượng Đồng hồ đang nằm trên màn hình. Không còn cái nào trong cửa sổ thì thôi chạy.
static void G6ClockTick(void) {
    double t = G6SecondsOfDay();
    BOOL inWindow = NO, onScreen = NO;
    for (UIView *v in gViews) {
        if (!v.window) continue;
        inWindow = YES;
        if (!G6OnScreen(v)) continue;
        G6ClockOverlay *overlay = objc_getAssociatedObject(v, &kOverlayKey);
        if (!overlay) continue;
        onScreen = YES;
        G6OverlaySetTime(overlay, t);
    }
    if (!inWindow) {
        G6ClockStopTicking();
        return;
    }
    G6ClockStartTicking(onScreen ? G6ClockTickInterval() : kIdleTickInterval);
}

static void G6ClockSyncAll(void) {
    G6RefreshZoneOffset();
    BOOL visible = NO;
    for (UIView *v in [gViews allObjects]) {
        @try {
            G6ClockSyncView(v);
            if (v.window) visible = YES;
        } @catch (NSException *e) {
            G6Log(@"đồng hồ: lỗi khi đồng bộ: %@", e);
        }
    }
#if G6_DEBUG
    // Bản thử: ghi lại mỗi lần đổi trạng thái chạy / đứng, để kiểm kim có dừng lúc không ai nhìn
    static int last = -1;
    int state = !gActive ? 0 : (visible && G6ScreenAwake() ? (gReduce ? 2 : 3) : 1);
    if (state != last) {
        last = state;
        NSArray *names = @[@"tắt", @"đứng (không ai nhìn)", @"nhích mỗi phút", @"kim chạy"];
        G6Log(@"đồng hồ: %@ (nhịp %.0f lần / giây)", names[state], 1.0 / G6ClockTickInterval());
    }
#endif
    BOOL watched = gActive && visible && G6ScreenAwake();
    // Kim chạy: nhịp nhích kim chỉ sống khi đang có người nhìn
    if (watched && !gReduce) {
        if (!gTickTimer) G6ClockStartTicking(G6ClockTickInterval());
    } else {
        G6ClockStopTicking();
    }
    // «Giảm hiệu ứng»: không có chuyển động liên tục — hẹn đúng đầu phút kế để nhích kim. Chỉ hẹn khi đang có người nhìn.
    [gMinuteTimer invalidate];
    gMinuteTimer = nil;
    if (watched && gReduce) {
        double wait = 60.0 - fmod(G6SecondsOfDay(), 60.0) + 0.05;
        gMinuteTimer = [NSTimer scheduledTimerWithTimeInterval:wait target:[G6ClockOverlay class] selector:@selector(g6_minuteTick:) userInfo:nil repeats:NO];
    }
}

// Gom nhiều lần báo sát nhau (mở khoá, sáng màn hình, view vào cửa sổ…) thành một lần đồng bộ ở vòng lặp kế
static void G6ClockScheduleSync(void) {
    if (gSyncPending) return;
    gSyncPending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gSyncPending = NO;
        G6ClockSyncAll();
    });
}

// ---- Hàm thay thế ----

static void (*o_setIcon)(id, SEL, id);
static void g6_setIcon(UIView *self, SEL _cmd, id icon) {
    o_setIcon(self, _cmd, icon);
    @try {
        G6ClockSyncView(self);
    } @catch (NSException *e) {
    }
}

static void (*o_iconImageDidUpdate)(id, SEL, id);
static void g6_iconImageDidUpdate(UIView *self, SEL _cmd, id icon) {
    o_iconImageDidUpdate(self, _cmd, icon);
    @try {
        G6ClockSyncView(self);
    } @catch (NSException *e) {
    }
}

// Vào / rời cửa sổ (về màn hình chính sau khi đóng app, mở app…): xét lại có ai nhìn không → chạy / dừng
static void (*o_didMoveToWindow)(id, SEL);
static void g6_didMoveToWindow(UIView *self, SEL _cmd) {
    o_didMoveToWindow(self, _cmd);
    if (objc_getAssociatedObject(self, &kOverlayKey)) G6ClockScheduleSync();
}

// ---- Cấu hình ----

static id G6ClockIcon(void) {
    Class cls = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance"), model = NSSelectorFromString(@"model");
    SEL find = NSSelectorFromString(@"leafIconForIdentifier:");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    id ctl = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    id m = [ctl respondsToSelector:model] ? ((id (*)(id, SEL))objc_msgSend)(ctl, model) : nil;
    return [m respondsToSelector:find] ? ((id (*)(id, SEL, id))objc_msgSend)(m, find, kClockBundleID) : nil;
}

static void G6CollectIconViews(UIView *view, Class cls, NSMutableArray *out) {
    if ([view isKindOfClass:cls]) {
        [out addObject:view];
        return;
    }
    for (UIView *sub in view.subviews) G6CollectIconViews(sub, cls, out);
}

static void G6ClockApply(BOOL initial) {
    BOOL active = G6Feature(@"clock");
    NSDictionary *cfg = G6Config();
    BOOL reduce = [cfg[@"reduce"] boolValue];
    // Thứ làm ảnh mặt đồng hồ đổi: bật / tắt, kiểu biểu tượng (hình cắt), viền sáng, sáng / tối
    NSString *signature = [NSString stringWithFormat:@"%d|%d|%@|%d|%@|%@", active, G6Feature(@"icons"), cfg[@"rim"], G6IsDark(),
                                                     cfg[@"icon_style"], cfg[@"icon_tint"]];
    BOOL changed = ![signature isEqualToString:gSignature];
    gSignature = signature;
    gActive = active;
    gReduce = reduce;
    if (changed) gFaceImage = nil;
    if (initial) return;
    if (changed) {
        // Ảnh tĩnh của biểu tượng Đồng hồ (G6Icons có thể vừa tạo lại — tạo lại lần nữa cũng chỉ một biểu tượng)
        id icon = G6ClockIcon();
        SEL reload = NSSelectorFromString(@"reloadIconImagePurgingImageCache:");
        if ([icon respondsToSelector:reload]) ((void (*)(id, SEL, BOOL))objc_msgSend)(icon, reload, YES);
        // Vừa bật: các SBIconView đang hiện chưa có lớp phủ
        if (active) {
            NSMutableArray *views = [NSMutableArray array];
            Class cls = objc_getClass("SBIconView");
            for (UIWindow *w in [UIApplication sharedApplication].windows) G6CollectIconViews(w, cls, views);
            for (UIView *v in views) G6ClockSyncView(v);
        }
        G6Log(@"đồng hồ: %@", active ? (reduce ? @"bật (giảm hiệu ứng: không kim giây, nhích mỗi phút)" : @"bật") : @"tắt");
    }
    G6ClockSyncAll();
}

void G6ClockInstall(void) {
    G6RefreshZoneOffset();
    Class iconView = objc_getClass("SBIconView");
    if (!iconView) {
        G6Log(@"đồng hồ: thiếu lớp SBIconView — bỏ qua");
        return;
    }
    G6ClockApply(YES);
    if (!G6Hook(iconView, NSSelectorFromString(@"setIcon:"), (IMP)g6_setIcon, (IMP *)&o_setIcon)) {
        gActive = NO;
        return;
    }
    G6Hook(iconView, NSSelectorFromString(@"iconImageDidUpdate:"), (IMP)g6_iconImageDidUpdate, (IMP *)&o_iconImageDidUpdate);
    G6Hook(iconView, @selector(didMoveToWindow), (IMP)g6_didMoveToWindow, (IMP *)&o_didMoveToWindow);
    // Khoá / mở khoá / tắt / sáng màn hình: xét lại có ai nhìn không → chạy / dừng
    G6ScreenWatchInstall();

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:G6ConfigDidChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                    // Ở vòng lặp kế: khi đó mọi thành phần (vd «Biểu tượng kiểu mới», thứ quyết định hình cắt của mặt đồng
                    // hồ) đã nhận xong cấu hình mới
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try {
                            G6ClockApply(NO);
                        } @catch (NSException *e) {
                            G6Log(@"đồng hồ: lỗi khi áp cấu hình: %@", e);
                        }
                    });
                }];
    [nc addObserverForName:G6ScreenStateDidChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                    if (gActive) G6ClockScheduleSync();
                }];
    // Đổi giờ, qua nửa đêm, đổi múi giờ
    for (NSString *name in @[UIApplicationSignificantTimeChangeNotification, NSSystemTimeZoneDidChangeNotification]) {
        [nc addObserverForName:name
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [NSTimeZone resetSystemTimeZone];
                        if (gActive) G6ClockScheduleSync();
                    }];
    }
}
