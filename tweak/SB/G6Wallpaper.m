#import "G6Wallpaper.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

NSString *const G6WallpaperDidChangeNotification = @"G6WallpaperDidChangeNotification";

static NSUInteger gGeneration;
static G6Backdrop *gBackdrop;
static NSUInteger gBackdropGeneration;
static int gBackdropOrientation = -1;
// Nền hiện có được dựng lúc hình nền đang hiện trên màn hình (chứ không phải tự vẽ từ ảnh)
static BOOL gBackdropLive;
static BOOL gNotifyPending;

// Hình nền chính của màn hình chính (-[SBUIController wallpaperView]). Lúc mở thư mục SpringBoard tạo thêm vài bản sao
// SBWallpaperView cho hai nửa màn hình — không phải cái này.
static UIView *G6MainWallpaperView(void) {
    Class cls = objc_getClass("SBUIController");
    SEL shared = NSSelectorFromString(@"sharedInstance"), sel = NSSelectorFromString(@"wallpaperView");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    id ctl = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
    if (![ctl respondsToSelector:sel]) return nil;
    id v = ((id (*)(id, SEL))objc_msgSend)(ctl, sel);
    return [v isKindOfClass:[UIView class]] ? v : nil;
}

NSUInteger G6WallpaperGeneration(void) {
    return gGeneration;
}

// Vẽ hình nền vào ảnh nhỏ hơn màn hình kPre lần theo hệ toạ độ khung hình, rồi nhờ lõi làm mờ.
// Vẽ thẳng cỡ nhỏ (đằng nào cũng làm mờ): vẽ đủ cỡ 768×1024 rồi mới thu mất ~185 ms trên A5.
static G6Backdrop *G6RenderWallpaper(UIView *wallpaper, int orientation) {
    UIScreen *screen = [UIScreen mainScreen];
    CGFloat scale = screen.scale;
    const uint32_t kPre = 4;
    // bounds của UIScreen trên iOS 6 luôn theo hệ dọc
    CGSize full = screen.bounds.size;
    size_t w = (size_t)lround(full.width * scale) / kPre, h = (size_t)lround(full.height * scale) / kPre;
    if (!w || !h) return nil;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    // Toạ độ kiểu UIKit (gốc trên trái) tính bằng điểm
    CGContextTranslateCTM(ctx, 0, h);
    CGContextScaleCTM(ctx, scale / kPre, -scale / kPre);
    // Ảnh này sắp bị làm mờ: nội suy mức thấp là đủ, vẽ nhanh hơn hẳn
    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    UIWindow *window = wallpaper.window;
    BOOL drawn = NO;
    if (window) {
        // Đang hiện: vẽ đúng thứ trên màn hình (cả hai dải tối trên / dưới của SBWallpaperView). View nằm trong khung đang
        // xoay theo máy → đổi toạ độ của nó sang toạ độ màn hình.
        CGPoint (^toScreen)(CGPoint) = ^(CGPoint p) {
            return [window convertPoint:[wallpaper convertPoint:p toView:nil] toWindow:nil];
        };
        CGPoint o = toScreen(CGPointZero), x = toScreen(CGPointMake(1, 0)), y = toScreen(CGPointMake(0, 1));
        CGContextConcatCTM(ctx, CGAffineTransformMake(x.x - o.x, x.y - o.y, y.x - o.x, y.y - o.y, o.x, o.y));
        [wallpaper.layer renderInContext:ctx];
        drawn = YES;
    } else if ([wallpaper isKindOfClass:[UIImageView class]]) {
        // Không trong cửa sổ (đang ở trong app — SpringBoard đã gỡ màn hình chính): tự vẽ ảnh của hình nền, đặt giữa màn hình
        // và xoay theo hướng giao diện như SpringBoard vẫn làm
        UIImage *image = [(UIImageView *)wallpaper image];
        if (image) {
            static const CGFloat angles[5] = {0, 0, M_PI, M_PI_2, -M_PI_2};  // theo UIInterfaceOrientation
            CGContextTranslateCTM(ctx, full.width / 2, full.height / 2);
            CGContextRotateCTM(ctx, angles[(orientation >= 1 && orientation <= 4) ? orientation : 1]);
            UIGraphicsPushContext(ctx);
            [image drawInRect:CGRectMake(-image.size.width / 2, -image.size.height / 2, image.size.width, image.size.height)];
            UIGraphicsPopContext();
            drawn = YES;
        }
    }
    G6Backdrop *b = drawn ? [G6Backdrop backdropWithPixels:CGBitmapContextGetData(ctx)
                                                     width:(uint32_t)w
                                                    height:(uint32_t)h
                                                    stride:(uint32_t)CGBitmapContextGetBytesPerRow(ctx)
                                                      fast:NO
                                                  prescale:kPre]
                          : nil;
    CGContextRelease(ctx);
    return b;
}

G6Backdrop *G6WallpaperRender(UIView *wallpaperView) {
    if (!wallpaperView) return nil;
    return G6RenderWallpaper(wallpaperView, (int)[UIApplication sharedApplication].statusBarOrientation);
}

G6Backdrop *G6WallpaperBackdrop(void) {
    int orientation = (int)[UIApplication sharedApplication].statusBarOrientation;
    UIView *wallpaper = G6MainWallpaperView();
    BOOL live = wallpaper.window != nil;
    // Nền dựng lúc hình nền đang hiện là nền «thật»; nền tự vẽ lúc ở trong app chỉ dùng tạm tới khi về màn hình chính
    if (gBackdrop && gBackdropGeneration == gGeneration && gBackdropOrientation == orientation && (gBackdropLive || !live)) {
        return gBackdrop;
    }
    if (!wallpaper) return nil;
    double t0 = G6NowMs();
    G6Backdrop *b = G6RenderWallpaper(wallpaper, orientation);
    if (!b) return nil;
    // Thay nền tự vẽ bằng nền thật (vừa về màn hình chính): tấm kính nào đã dựng trên nền tự vẽ phải dựng lại
    if (gBackdrop && gBackdropGeneration == gGeneration && gBackdropOrientation == orientation && live && !gBackdropLive) gGeneration++;
    gBackdrop = b;
    gBackdropGeneration = gGeneration;
    gBackdropOrientation = orientation;
    gBackdropLive = live;
    G6Log(@"hình nền: vẽ + làm mờ %.1f ms%@", G6NowMs() - t0, live ? @"" : @" (tự vẽ từ ảnh, hình nền không ở trong cửa sổ)");
    return b;
}

// Gom nhiều lần báo sát nhau thành một thông báo ở vòng lặp kế
static void G6WallpaperNotify(BOOL stale) {
    if (stale) gGeneration++;
    if (gNotifyPending) return;
    gNotifyPending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gNotifyPending = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:G6WallpaperDidChangeNotification object:nil];
    });
}

static void (*o_wallpaperChanged)(id, SEL);
static void g6_wallpaperChanged(id self, SEL _cmd) {
    o_wallpaperChanged(self, _cmd);
    G6WallpaperNotify(YES);
}

// Hình nền vào / rời cửa sổ (vd lần đầu mở khoá sau khi SpringBoard lên): lúc này mới vẽ được nó làm nền cho kính
static void (*o_wallpaperMoved)(id, SEL);
static void g6_wallpaperMoved(id self, SEL _cmd) {
    o_wallpaperMoved(self, _cmd);
    if (self == G6MainWallpaperView()) G6WallpaperNotify(NO);
}

void G6WallpaperInstall(void) {
    static BOOL installed;
    if (installed) return;
    installed = YES;
    G6HookNamed("SBWallpaperView", NSSelectorFromString(@"_wallpaperChanged"), (IMP)g6_wallpaperChanged, (IMP *)&o_wallpaperChanged);
    G6HookNamed("SBWallpaperView", @selector(didMoveToWindow), (IMP)g6_wallpaperMoved, (IMP *)&o_wallpaperMoved);
    // Nền mờ chỉ phụ thuộc hai số của cấu hình: độ mờ và độ bão hoà (theme::backdrop_plan). Cấu hình đổi thứ khác (gạt một
    // công tắc thành phần…) thì nền cũ vẫn đúng — không dựng lại (mỗi lần dựng ~65 ms trên iPad mini 1).
    NSString * (^signature)(void) = ^NSString * {
        NSDictionary *cfg = G6Config();
        return [NSString stringWithFormat:@"%@|%@", cfg[@"blur"], cfg[@"vibrancy"]];
    };
    __block NSString *last = signature();
    [[NSNotificationCenter defaultCenter] addObserverForName:G6ConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
                                                      NSString *now = signature();
                                                      if ([now isEqualToString:last]) return;
                                                      last = now;
                                                      G6WallpaperNotify(YES);
                                                  }];
}
