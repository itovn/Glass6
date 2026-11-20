// Viên «Tìm kiếm» trên dock của iPhone — kiểu iOS 26.
//
// iOS 26 trên iPhone: ngay trên dock là một viên kính nhỏ «Tìm kiếm»; lúc lật trang nó nhường chỗ cho hàng chấm trang rồi hiện
// lại. iOS 6 (đo trên iPhone 5, 19/11/2026): hàng chấm là SBIconListPageControl (0 4; 320 19) nằm trong view chứa dock, ngay
// trên SBDockIconListView; trang Tìm kiếm là trang −1 của khung cuộn biểu tượng.
//
// Cách làm (không đổi gì của SpringBoard ngoài độ mờ của hàng chấm):
//   - một UIControl nhỏ đặt đè lên giữa hàng chấm, trong cùng view cha (dock trượt đi đâu viên theo đó): nền là tấm kính
//     «capsule» dựng từ hình nền mờ, bên trong là kính lúp tự vẽ + chữ «Tìm kiếm»;
//   - màn hình chính đứng yên: viên hiện, hàng chấm ẩn (alpha 0). Đang lật trang (SBIconController -scrollViewDidScroll:):
//     viên ẩn, chấm hiện; ngừng lật ~0,9 giây thì đổi lại. Đang ở trang Tìm kiếm: chỉ hiện chấm;
//   - chạm viên: lật tới trang Tìm kiếm (-scrollToIconListAtIndex:animate: với −1 — đúng đường SpringBoard vẫn đi, bàn phím
//     tự bật như khi vuốt tay).
// Tắt thành phần: gỡ viên, hàng chấm hiện lại như cũ.
#import "G6SearchPill.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Lang.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Wallpaper.h"

static const CGFloat kPillHeight = 22, kPadX = 10, kGlyph = 10, kGlyphGap = 5;
// Ngừng lật trang chừng này giây thì viên hiện lại
static const NSTimeInterval kIdleDelay = 0.9;

static __weak UIView *gPageControl;
static __weak UIScrollView *gScroll;  // khung cuộn biểu tượng (nhận từ -scrollViewDidScroll:)
static UIControl *gPill;
static UIImageView *gGlass, *gGlyph;
static UILabel *gLabel;
static NSTimer *gIdleTimer;
static BOOL gScrolling;
static NSString *gDrawnKey;

@interface G6SearchPillTarget : NSObject
@end

static id G6PillIconController(void) {
    Class cls = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    return [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
}

// Kính lúp một màu trong ô vuông cạnh s
static UIImage *G6PillGlyph(CGFloat s, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [color set];
    CGFloat w = MAX(1.4, s * 0.14), r = s * 0.34;
    UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:CGPointMake(r + w / 2, r + w / 2) radius:r startAngle:0 endAngle:2 * M_PI clockwise:YES];
    ring.lineWidth = w;
    [ring stroke];
    UIBezierPath *handle = [UIBezierPath bezierPath];
    CGFloat d = r * 0.7071;
    [handle moveToPoint:CGPointMake(r + w / 2 + d + w * 0.3, r + w / 2 + d + w * 0.3)];
    [handle addLineToPoint:CGPointMake(s - w / 2, s - w / 2)];
    handle.lineWidth = w;
    handle.lineCapStyle = kCGLineCapRound;
    [handle stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// Trang Tìm kiếm đang hiện? (khung cuộn biểu tượng đang ở nửa đầu trang −1)
static BOOL G6PillOnSearchPage(void) {
    UIScrollView *scroll = gScroll;
    if (!scroll) {
        id ctl = G6PillIconController();
        SEL sel = NSSelectorFromString(@"scrollView");
        id found = [ctl respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(ctl, sel) : nil;
        if ([found isKindOfClass:[UIScrollView class]]) scroll = gScroll = found;
    }
    if (!scroll) return NO;
    return scroll.contentOffset.x < scroll.bounds.size.width / 2;
}

static void G6PillRemove(void) {
    [gIdleTimer invalidate];
    gIdleTimer = nil;
    [gPill removeFromSuperview];
    gPill = nil;
    gGlass = gGlyph = nil;
    gLabel = nil;
    gDrawnKey = nil;
    UIView *dots = gPageControl;
    if (dots) dots.alpha = 1;
}

static void G6PillShow(BOOL animated) {
    UIView *dots = gPageControl;
    if (!gPill || !dots) return;
    BOOL pill = !gScrolling && !G6PillOnSearchPage();
    void (^apply)(void) = ^{
        gPill.alpha = pill ? 1 : 0;
        dots.alpha = pill ? 0 : 1;
    };
    if (animated) [UIView animateWithDuration:0.18 animations:apply];
    else apply();
}

static void G6PillUpdate(void) {
    UIView *dots = gPageControl, *host = dots.superview;
    BOOL active = g6_device_is_phone() && G6Feature(@"search");
    if (!active || !dots || !host || !dots.window) {
        if (gPill) G6PillRemove();
        return;
    }
    BOOL dark = G6IsDark();
    if (!gPill || gPill.superview != host) {
        G6PillRemove();
        gPill = [[UIControl alloc] initWithFrame:CGRectZero];
        gGlass = [[UIImageView alloc] initWithFrame:CGRectZero];
        gGlyph = [[UIImageView alloc] initWithFrame:CGRectZero];
        gLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        gLabel.backgroundColor = [UIColor clearColor];
        gGlass.userInteractionEnabled = gGlyph.userInteractionEnabled = gLabel.userInteractionEnabled = NO;
        [gPill addSubview:gGlass];
        [gPill addSubview:gGlyph];
        [gPill addSubview:gLabel];
        [gPill addTarget:[G6SearchPillTarget class] action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
        [host insertSubview:gPill aboveSubview:dots];
    }
    UIFont *font = G6Font(G6FontMedium, 12) ?: [UIFont boldSystemFontOfSize:12];
    NSString *text = G6L(@"Tìm kiếm");
    CGSize textSize = [text sizeWithFont:font];
    CGFloat width = ceil(textSize.width) + kGlyph + kGlyphGap + 2 * kPadX;
    CGRect frame = CGRectMake(round(CGRectGetMidX(dots.frame) - width / 2), round(CGRectGetMidY(dots.frame) - kPillHeight / 2) - 1, width, kPillHeight);
    gPill.frame = frame;
    gGlass.frame = gPill.bounds;
    UIColor *ink = dark ? [UIColor colorWithWhite:1 alpha:0.92] : [UIColor colorWithWhite:0.08 alpha:0.86];
    gLabel.font = font;
    gLabel.text = text;
    gLabel.textColor = ink;
    gLabel.frame = CGRectMake(kPadX + kGlyph + kGlyphGap, floor((kPillHeight - font.lineHeight) / 2), ceil(textSize.width), ceil(font.lineHeight));
    gGlyph.frame = CGRectMake(kPadX, floor((kPillHeight - kGlyph) / 2), kGlyph, kGlyph);

    // Vị trí của viên trên màn hình (dock đang trượt lúc mở app thì khung trong cửa sổ đổi → chỉ dựng khi dock đứng ở chỗ nghỉ)
    CGRect onScreen = [gPill convertRect:gPill.bounds toView:nil];
    NSString *key = [NSString stringWithFormat:@"%@|%d|%lu|%@", NSStringFromCGRect(onScreen), dark, (unsigned long)G6WallpaperGeneration(), text];
    if (![key isEqualToString:gDrawnKey]) {
        UIImage *glass = G6GlassImageForView(@"capsule", gGlass, dark, G6WallpaperBackdrop());
        if (glass) {
            gGlass.image = glass;
            gGlyph.image = G6PillGlyph(kGlyph, ink);
            gDrawnKey = key;
        }
    }
    G6PillShow(NO);
}

static void G6PillUpdateSafe(void) {
    @try {
        G6PillUpdate();
    } @catch (NSException *e) {
        G6Log(@"viên tìm kiếm: lỗi %@", e);
    }
}

@implementation G6SearchPillTarget

+ (void)tap:(id)sender {
    id ctl = G6PillIconController();
    SEL sel = NSSelectorFromString(@"scrollToIconListAtIndex:animate:");
    if ([ctl respondsToSelector:sel]) ((void (*)(id, SEL, int, BOOL))objc_msgSend)(ctl, sel, -1, YES);
}

+ (void)idle:(NSTimer *)timer {
    gIdleTimer = nil;
    gScrolling = NO;
    G6PillShow(YES);
}

@end

// Đang lật trang: nhường chỗ cho chấm trang, hẹn hiện lại
static void (*o_didScroll)(id, SEL, id);
static void g6_didScroll(id self, SEL _cmd, id scrollView) {
    o_didScroll(self, _cmd, scrollView);
    if ([scrollView isKindOfClass:[UIScrollView class]]) gScroll = scrollView;
    if (!gPill) return;
    @try {
        if (!gScrolling) {
            gScrolling = YES;
            G6PillShow(YES);
        }
        [gIdleTimer invalidate];
        gIdleTimer = [NSTimer timerWithTimeInterval:kIdleDelay target:[G6SearchPillTarget class] selector:@selector(idle:) userInfo:nil repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:gIdleTimer forMode:NSRunLoopCommonModes];
    } @catch (NSException *e) {
    }
}

static void (*o_dotsDidMove)(UIView *, SEL);
static void g6_dotsDidMove(UIView *self, SEL _cmd) {
    o_dotsDidMove(self, _cmd);
    gPageControl = self;
    G6PillUpdateSafe();
}

static void (*o_dotsLayout)(UIView *, SEL);
static void g6_dotsLayout(UIView *self, SEL _cmd) {
    o_dotsLayout(self, _cmd);
    gPageControl = self;
    G6PillUpdateSafe();
}

void G6SearchPillInstall(void) {
    if (!g6_device_is_phone()) return;
    Class dots = objc_getClass("SBIconListPageControl"), controller = objc_getClass("SBIconController");
    if (!dots || !controller) {
        G6Log(@"viên tìm kiếm: thiếu SBIconListPageControl / SBIconController — bỏ qua");
        return;
    }
    G6WallpaperInstall();
    G6Hook(dots, @selector(didMoveToWindow), (IMP)g6_dotsDidMove, (IMP *)&o_dotsDidMove);
    G6Hook(dots, @selector(layoutSubviews), (IMP)g6_dotsLayout, (IMP *)&o_dotsLayout);
    G6Hook(controller, NSSelectorFromString(@"scrollViewDidScroll:"), (IMP)g6_didScroll, (IMP *)&o_didScroll);
    for (NSString *name in @[G6ConfigDidChangeNotification, G6WallpaperDidChangeNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6PillUpdateSafe();
                                                      }];
    }
    // Hàng chấm đã có sẵn (SpringBoard lên trước): tìm trong cây view
    if (!gPageControl) {
        UIView *dockHost = nil;
        id ctl = G6PillIconController();
        SEL sel = NSSelectorFromString(@"dockContainerView");
        if ([ctl respondsToSelector:sel]) dockHost = ((id (*)(id, SEL))objc_msgSend)(ctl, sel);
        for (UIView *sub in dockHost.subviews) {
            if ([sub isKindOfClass:dots]) gPageControl = sub;
        }
    }
    G6PillUpdateSafe();
}
