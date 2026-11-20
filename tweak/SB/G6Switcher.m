// Khay đa nhiệm — iOS 6 → kính.
//
// iOS 6 (tra trên máy 19/11/2026): cửa sổ SBShowcaseWindow (mức 2005) › … › SBShowcaseClippingView
//   SBAppSwitcherBarView (1024×116)
//     UIView (_contentView)
//       SBLinenView (_backgroundView)   nền vải
//       SBAppSwitcherScrollView         các trang: biểu tượng app đang chạy, điều khiển nhạc / độ sáng / âm lượng
// Màn hình đang hiện (màn hình chính hoặc app) trượt lên, để lộ khay nằm bên dưới. Phía sau khay không có gì → phủ kính lên
// nền vải, nền của kính là hình nền màn hình chính đã mờ đúng chỗ khay nằm (kể cả khi mở khay trong app: G6Wallpaper tự vẽ
// lại hình nền từ ảnh).
#import "G6Switcher.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6GlassFill.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Wallpaper.h"

// Khay đang có (SpringBoard giữ một cái dùng lại) — để cập nhật khi đổi cấu hình / hình nền
static __weak UIView *gBar;

static void G6SwitcherUpdate(UIView *bar) {
    if (!bar) return;
    @try {
        Ivar iv = class_getInstanceVariable([bar class], "_backgroundView");
        UIView *bg = iv ? object_getIvar(bar, iv) : nil;
        if ([bg isKindOfClass:[UIView class]]) G6GlassFill(bg, G6Feature(@"switcher"), @"bar");
    } @catch (NSException *e) {
        G6Log(@"khay đa nhiệm: lỗi khi dựng: %@", e);
    }
}

static void (*o_layoutSubviews)(id, SEL);
static void g6_layoutSubviews(UIView *self, SEL _cmd) {
    o_layoutSubviews(self, _cmd);
    gBar = self;
    G6SwitcherUpdate(self);
}

// Vào cửa sổ: giờ mới biết khay nằm ở đâu trên màn hình → dựng kính ngay, và dựng lại ở vòng lặp kế nếu khung còn đổi
static void (*o_didMoveToWindow)(id, SEL);
static void g6_didMoveToWindow(UIView *self, SEL _cmd) {
    o_didMoveToWindow(self, _cmd);
    if (!self.window) return;
    gBar = self;
    G6SwitcherUpdate(self);
    __weak UIView *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        G6SwitcherUpdate(weak);
    });
}

void G6SwitcherInstall(void) {
    Class bar = objc_getClass("SBAppSwitcherBarView");
    if (!bar || !class_getInstanceVariable(bar, "_backgroundView")) {
        G6Log(@"khay đa nhiệm: thiếu SBAppSwitcherBarView / _backgroundView — bỏ qua");
        return;
    }
    G6WallpaperInstall();
    if (!G6Hook(bar, @selector(layoutSubviews), (IMP)g6_layoutSubviews, (IMP *)&o_layoutSubviews)) return;
    G6Hook(bar, @selector(didMoveToWindow), (IMP)g6_didMoveToWindow, (IMP *)&o_didMoveToWindow);
    for (NSString *name in @[G6ConfigDidChangeNotification, G6WallpaperDidChangeNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6SwitcherUpdate(gBar);
                                                      }];
    }
}
