// Bảng âm lượng (HUD) — iOS 6 → kính.
//
// iOS 6 (tra trên máy 19/11/2026): SBHUDController (+sharedHUDController) giữ cửa sổ SBHUDWindow và một SBHUDView
// (lớp con SBVolumeHUDView…). SBHUDView tự vẽ trong -drawRect: nền đen bo góc + các nấc (qua -drawBlockForValue:point:);
// tên («Âm lượng», «Chuông») và hình loa là view con, màu trắng.
//
// Cách làm:
//   - -[SBHUDController presentHUDView:autoDismissWithDelay:] → TRƯỚC khi HUD hiện, chụp màn hình một lần làm nền (HUD nổi
//     trên app nên không dùng hình nền được); HUD đang hiện mà bấm tiếp thì dùng lại ảnh chụp cũ (chụp lại sẽ dính chính nó);
//   - -[SBHUDView drawRect:] → vẽ tấm kính (bề mặt `hud` — kính đậm, luôn tối: chữ và hình loa của máy màu trắng, trên kính
//     sáng hoặc kính nhạt nằm trên app nền trắng sẽ không đọc được) rồi tự vẽ các nấc, không gọi hàm gốc.
// Tắt thành phần: drawRect gọi hàm gốc như cũ.
#import "G6HUD.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static G6Backdrop *gBackdrop;
static char kGlassKey;

// Dựng tấm kính cho HUD (đã nằm trong cửa sổ) và cất trên chính nó; nil = về kiểu gốc
static void G6HUDStyle(UIView *hud, BOOL active) {
    if (![hud isKindOfClass:[UIView class]]) return;
    UIImage *glass = nil;
    if (active && hud.window && hud.bounds.size.width > 2 && hud.bounds.size.height > 2) {
        double t0 = G6NowMs();
        glass = G6GlassImageForView(@"hud", hud, YES, gBackdrop);
        if (glass) G6Log(@"bảng âm lượng: kính %.0f×%.0f (%@ nền) %.1f ms", hud.bounds.size.width, hud.bounds.size.height,
                         gBackdrop ? @"có" : @"KHÔNG", G6NowMs() - t0);
    }
    objc_setAssociatedObject(hud, &kGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [hud setNeedsDisplay];
}

static void (*o_present)(id, SEL, id, double);
static void g6_present(id self, SEL _cmd, UIView *hud, double delay) {
    BOOL active = NO;
    @try {
        active = G6Feature(@"hud");
        if (active) {
            SEL visibleSel = NSSelectorFromString(@"visibleOrFadingHUDView");
            id visible = [self respondsToSelector:visibleSel] ? ((id (*)(id, SEL))objc_msgSend)(self, visibleSel) : nil;
            if (!visible || !gBackdrop) gBackdrop = [G6Backdrop backdropWithScreen:YES];
        }
    } @catch (NSException *e) {
        G6Log(@"bảng âm lượng: lỗi khi chụp nền: %@", e);
    }
    o_present(self, _cmd, hud, delay);
    @try {
        G6HUDStyle(hud, active);
    } @catch (NSException *e) {
        G6Log(@"bảng âm lượng: lỗi khi dựng: %@", e);
    }
}

static void (*o_drawRect)(id, SEL, CGRect);
static void g6_drawRect(UIView *self, SEL _cmd, CGRect rect) {
    UIImage *glass = objc_getAssociatedObject(self, &kGlassKey);
    if (!glass) {
        o_drawRect(self, _cmd, rect);
        return;
    }
    CGRect bounds = self.bounds;
    [glass drawInRect:bounds];
    // Các nấc: một hàng ô bo tròn sát đáy — ô đã đạt trắng rõ, ô chưa đạt trắng mờ
    SEL showsSel = NSSelectorFromString(@"showsProgress"), progressSel = NSSelectorFromString(@"progress");
    SEL stepsSel = NSSelectorFromString(@"numberOfProgressIndicatorSteps");
    if (![self respondsToSelector:showsSel] || !((BOOL (*)(id, SEL))objc_msgSend)(self, showsSel)) return;
    float progress = [self respondsToSelector:progressSel] ? ((float (*)(id, SEL))objc_msgSend)(self, progressSel) : 0;
    int steps = [[self class] respondsToSelector:stepsSel] ? ((int (*)(id, SEL))objc_msgSend)([self class], stepsSel) : 16;
    if (steps < 1 || steps > 64) steps = 16;
    const CGFloat margin = 26, gap = 2, height = 7;
    CGFloat blockW = floor((bounds.size.width - 2 * margin - (steps - 1) * gap) / steps);
    if (blockW < 2) return;
    CGFloat x = floor((bounds.size.width - (blockW * steps + gap * (steps - 1))) / 2), y = bounds.size.height - 32;
    int filled = (int)lroundf(progress * steps);
    for (int i = 0; i < steps; i++) {
        [[UIColor colorWithWhite:1 alpha:i < filled ? 0.95 : 0.22] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x + i * (blockW + gap), y, blockW, height) cornerRadius:2] fill];
    }
}

void G6HUDInstall(void) {
    Class ctl = objc_getClass("SBHUDController"), view = objc_getClass("SBHUDView");
    if (!ctl || !view) {
        G6Log(@"bảng âm lượng: thiếu lớp SBHUDController / SBHUDView — bỏ qua");
        return;
    }
    // Chỉ đổi cách vẽ khi móc được cả chỗ chụp nền
    if (!G6Hook(ctl, NSSelectorFromString(@"presentHUDView:autoDismissWithDelay:"), (IMP)g6_present, (IMP *)&o_present)) return;
    G6Hook(view, @selector(drawRect:), (IMP)g6_drawRect, (IMP *)&o_drawRect);
}
