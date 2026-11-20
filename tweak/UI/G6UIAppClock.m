// App Đồng hồ (com.apple.mobiletimer) trên iPad — thanh thẻ dưới cùng.
//
// App Đồng hồ của iPad iOS 6 vốn đã phẳng và tối (bản đồ, lưới báo thức, mặt bấm giờ); thanh điều hướng trên cùng là thanh
// chuẩn nên đã theo kiểu Glass 6. Chỗ lệch tông là thanh dưới cùng (tra trên máy 19/11/2026):
//   UIImageView (0 710; 1024 38)              ảnh navigation_bg — dải kim loại sáng
//   ClockSegmentedControl (224 714; 576 30)   lớp con của UISegmentedControl: tự đặt ảnh nền / vách ngăn kiểu nút bạc
//                                             (navigation_tab_button…), tự vẽ đoạn đang chọn bằng một UIImageView riêng
//                                             (_segmentSelectionImageView) đè lên trên, và tự đặt ba vạch ngăn sáng rộng
//                                             2 điểm (UIImageView con trực tiếp của nút) giữa các thẻ
// Cách làm (mọi thứ làm ở lượt xếp của chính nút đó — không đổi ảnh trong gói app, không móc việc nạp ảnh):
//   - nút chọn thẻ: áp kiểu nút chọn đoạn của Glass 6 thẳng lên nút (G6UIControlsStyleSegmented), ẩn view «đoạn đang chọn» của
//     app và ba vạch ngăn của app — đoạn đang chọn do UIKit vẽ bằng ảnh trạng thái «đang chọn» của Glass 6;
//   - dải nền: thay ảnh bằng mặt thanh phẳng của Glass 6 (cùng màu với thanh điều hướng), nét mảnh ở mép trên.
// Theo chế độ sáng / tối như các thanh khác. Tắt thành phần thì trả ảnh và kiểu gốc.
//
// iPhone (tra trên máy 20/11/2026 bằng imglog + cây view) — app Đồng hồ bản iPhone còn giả vật liệu: nền sọc xanh
// («stripe_background»), hàng giờ quốc tế bóng («worldclock_row») trên bản đồ («map»), màn bấm giờ nền đen bóng
// («topbackground_whole») với nút xanh / bạc / đỏ («button_green», «button_silver», «button_red»), hàng vòng chạy
// («stopwatch_lap_row_background»), màn hẹn giờ («timer_mask» — tấm che có lỗ cho bánh xe, «timer_countdown_background»,
// «timer_button_inset», «timer_sound_lozenge», «timer_chevron»). Vẽ lại bằng khung chung G6UISkin (bảng màu sáng + bộ lọc
// tối của cửa sổ): nền phẳng, hàng phẳng, nút viên bo tròn (xanh / đỏ tô màu), tấm che bỏ. Thêm hai việc ngoài bảng hình:
//   - chữ TRẮNG app đặt cho nền tối của nó (số bấm giờ, số hẹn giờ, «Không có Báo thức») → màu chữ tối của bảng màu sáng
//     (-[UILabel setTextColor:] trong app này; chữ trong nút và trên các thanh không đi qua đây);
//   - mặt đồng hồ kim (AnalogClockView: mặt trắng = ban ngày, mặt đen = ban đêm) giữ đúng màu dưới bộ lọc tối.
#import "G6UI.h"

#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Hook.h"
#import "G6Log.h"

static BOOL gActive;
static char kBarOriginalKey;

static UIImage *G6ClockBarImage(CGFloat height) {
    static NSMutableDictionary *cache;
    NSString *key = [NSString stringWithFormat:@"%d|%.0f", G6UIBarsDark(), height];
    UIImage *image = cache[key];
    if (image) return image;
    image = G6UIBarSurfaceImage(height, YES);
    if (!image) return nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    cache[key] = image;
    return image;
}

// Dải nền của thanh thẻ: UIImageView anh em với nút, phủ kín chỗ nút nằm
static UIImageView *G6ClockBarView(UIView *control) {
    for (UIView *v in control.superview.subviews) {
        if (v == control || ![v isMemberOfClass:[UIImageView class]]) continue;
        if (CGRectContainsRect(CGRectInset(v.frame, 0, -1), control.frame)) return (UIImageView *)v;
    }
    return nil;
}

// Vạch ngăn của app: UIImageView hẹp (≤ 3 điểm) là con trực tiếp của nút (vạch của UIKit nằm trong từng UISegment)
static void G6ClockHideDividers(UIView *control, id selection, BOOL hide) {
    for (UIView *v in control.subviews) {
        if (v == selection || ![v isMemberOfClass:[UIImageView class]] || v.bounds.size.width > 3) continue;
        if (v.hidden != hide) v.hidden = hide;
    }
}

static void G6ClockStyleTabs(UISegmentedControl *control) {
    Ivar iv = class_getInstanceVariable([control class], "_segmentSelectionImageView");
    id selection = iv ? object_getIvar(control, iv) : nil;
    if (![selection isKindOfClass:[UIView class]]) selection = nil;
    G6ClockHideDividers(control, selection, gActive);
    UIImageView *bar = G6ClockBarView(control);
    UIImage *original = bar ? objc_getAssociatedObject(bar, &kBarOriginalKey) : nil;
    if (gActive) {
        G6UIControlsStyleSegmented(control, G6UIBarsDark());
        if (selection && ![selection isHidden]) [selection setHidden:YES];
        UIImage *mine = bar ? G6ClockBarImage(bar.bounds.size.height) : nil;
        if (mine && bar.image != mine) {
            if (!original && bar.image) objc_setAssociatedObject(bar, &kBarOriginalKey, bar.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            bar.image = mine;
        }
    } else {
        G6UIControlsRestoreSegmented(control);
        if (selection && [selection isHidden]) [selection setHidden:NO];
        if (original) {
            bar.image = original;
            objc_setAssociatedObject(bar, &kBarOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void (*orig_tabsLayout)(UISegmentedControl *, SEL);
static void repl_tabsLayout(UISegmentedControl *self, SEL _cmd) {
    orig_tabsLayout(self, _cmd);
    @try {
        G6ClockStyleTabs(self);
    } @catch (NSException *e) {
        G6Log(@"đồng hồ (app): lỗi khi xếp thanh thẻ: %@", e);
    }
}

// App dời / hiện lại view «đoạn đang chọn» của nó mỗi lần đổi thẻ
static void (*orig_tabsSelect)(UISegmentedControl *, SEL, int);
static void repl_tabsSelect(UISegmentedControl *self, SEL _cmd, int index) {
    orig_tabsSelect(self, _cmd, index);
    @try {
        G6ClockStyleTabs(self);
    } @catch (NSException *e) {
    }
}

static void G6ClockRefresh(UIView *view, Class tabsClass, int depth) {
    if ([view isKindOfClass:tabsClass]) {
        G6ClockStyleTabs((UISegmentedControl *)view);
        [view setNeedsLayout];
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6ClockRefresh(sub, tabsClass, depth - 1);
}

// ---- iPhone ----

static BOOL gPhoneActive;

// Viên bo tròn tô màu (nút Bắt đầu xanh, Dừng đỏ): ảnh kéo giãn 21×47
static G6SkinMaker G6ClockPillMaker(BOOL red, BOOL pressed) {
    return ^UIImage *(UIImage *original) {
        CGSize size = original.size;
        if (size.width < 2 || size.height < 2) return nil;
        UIGraphicsBeginImageContextWithOptions(size, NO, original.scale > 0 ? original.scale : 0);
        CGFloat k = pressed ? 0.8 : 1;
        UIColor *fill = red ? [UIColor colorWithRed:1.0 * k green:0.23 * k blue:0.19 * k alpha:1]
                            : [UIColor colorWithRed:0.20 * k green:0.78 * k blue:0.35 * k alpha:1];
        CGRect body = CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5, 2);
        [fill setFill];
        [[UIBezierPath bezierPathWithRoundedRect:body cornerRadius:MIN(10, MIN(body.size.width, body.size.height) / 2 - 0.5)] fill];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return image;
    };
}

void G6UIAppClockPrepare(void) {
    // Chỉ bản iPhone được vẽ lại bằng khung chung (bản iPad vốn đã phẳng và tối — khai bảng hình ở đó sẽ bật bộ lọc tối của
    // cửa sổ cho một app không cần)
    if (!g6_device_is_phone()) return;
    G6UISkinRegister(@{
        @"stripe_background" : @(G6SkinBackdrop),
        @"worldclock_row" : @(G6SkinBar),
        @"map" : @(G6SkinGlyph),
        @"topbackground_whole" : @(G6SkinBackdrop),
        @"stopwatch_lap_row_background" : @(G6SkinBar),
        @"button_silver" : @(G6SkinButton),
        @"button_silver_pressed" : @(G6SkinButtonDown),
        @"button_green" : G6ClockPillMaker(NO, NO),
        @"button_green_pressed" : G6ClockPillMaker(NO, YES),
        @"button_red" : G6ClockPillMaker(YES, NO),
        @"button_red_pressed" : G6ClockPillMaker(YES, YES),
        @"timer_mask" : @(G6SkinClear),
        @"timer_countdown_background" : @(G6SkinBackdrop),
        @"timer_button_inset" : @(G6SkinClear),
        @"timer_2_button_inset" : @(G6SkinClear),
        @"timer_sound_lozenge" : @(G6SkinButton),
        @"timer_sound_lozenge_selected" : @(G6SkinButtonDown),
        @"timer_chevron" : @(G6SkinGlyph),
        @"timer_chevron_selected" : @(G6SkinGlyph),
    });
}

// Chữ trắng (cho nền tối gốc của app) → màu chữ tối của bảng màu sáng
static void (*orig_clockLabelColor)(UILabel *, SEL, UIColor *);
static void repl_clockLabelColor(UILabel *self, SEL _cmd, UIColor *color) {
    @try {
        // Chữ của nút (UIButtonLabel) nằm trên viên màu → giữ trắng
        static Class buttonLabel;
        if (!buttonLabel) buttonLabel = objc_getClass("UIButtonLabel");
        if (gPhoneActive && G6UISkinActive() && color && !(buttonLabel && [self isKindOfClass:buttonLabel])) {
            CGFloat white = 0, alpha = 0, r = 0, g = 0, b = 0;
            BOOL isWhite = ([color getWhite:&white alpha:&alpha] && white > 0.93 && alpha > 0.85) ||
                           ([color getRed:&r green:&g blue:&b alpha:&alpha] && r > 0.93 && g > 0.93 && b > 0.93 && alpha > 0.85);
            if (isWhite) color = [UIColor colorWithWhite:0.10 alpha:1];
        }
    } @catch (NSException *e) {
    }
    orig_clockLabelColor(self, _cmd, color);
}

// Mặt đồng hồ kim: màu mặt là thông tin (ngày / đêm) → giữ đúng dưới bộ lọc tối
static void (*orig_analogMoved)(UIView *, SEL);
static void repl_analogMoved(UIView *self, SEL _cmd) {
    orig_analogMoved(self, _cmd);
    @try {
        if (self.window) G6UISkinKeepColors(self, gPhoneActive);
    } @catch (NSException *e) {
    }
}

// Màn hẹn giờ (TimerPhoneControlsView) tô nền bằng MÀU tối chứ không bằng hình → đổi sang màu nền của bảng màu sáng
static char kTimerBgKey;
static void (*orig_timerMoved)(UIView *, SEL);
static void repl_timerMoved(UIView *self, SEL _cmd) {
    orig_timerMoved(self, _cmd);
    @try {
        id saved = objc_getAssociatedObject(self, &kTimerBgKey);
        if (gPhoneActive && G6UISkinActive()) {
            if (!saved) objc_setAssociatedObject(self, &kTimerBgKey, self.backgroundColor ?: (id)[NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIColor *color = G6UISkinBackdropColor();
            if (![self.backgroundColor isEqual:color]) self.backgroundColor = color;
        } else if (saved) {
            self.backgroundColor = saved == [NSNull null] ? nil : saved;
            objc_setAssociatedObject(self, &kTimerBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *e) {
    }
}

static void G6ClockPhoneApply(BOOL active) {
    static BOOL installed;
    if (!installed && !active) return;
    if (!installed) {
        installed = YES;
        G6Hook([UILabel class], @selector(setTextColor:), (IMP)repl_clockLabelColor, (IMP *)&orig_clockLabelColor);
        G6HookNamed("AnalogClockView", @selector(didMoveToWindow), (IMP)repl_analogMoved, (IMP *)&orig_analogMoved);
        G6HookNamed("TimerPhoneControlsView", @selector(didMoveToWindow), (IMP)repl_timerMoved, (IMP *)&orig_timerMoved);
        G6Log(@"đồng hồ (app): vẽ lại bản iPhone");
    }
    gPhoneActive = active;
}

void G6UIAppClockApply(BOOL active) {
    if (g6_device_is_phone()) {
        G6ClockPhoneApply(active);
        return;
    }
    static BOOL installed;
    Class tabsClass = objc_getClass("ClockSegmentedControl");
    // Thanh thẻ đi theo bảng màu của các thanh: thành phần «bars» tắt thì phần này cũng thôi
    active = active && tabsClass && G6UIBarsActive();
    if (!installed && !active) return;
    if (!installed) {
        installed = YES;
        if (!G6Hook(tabsClass, @selector(layoutSubviews), (IMP)repl_tabsLayout, (IMP *)&orig_tabsLayout)) return;
        Method m = class_getInstanceMethod(tabsClass, @selector(setSelectedSegmentIndex:));
        if (m && strcmp(method_getTypeEncoding(m) ?: "", "v12@0:4i8") == 0) {
            G6Hook(tabsClass, @selector(setSelectedSegmentIndex:), (IMP)repl_tabsSelect, (IMP *)&orig_tabsSelect);
        }
        G6Log(@"đồng hồ (app): vẽ lại thanh thẻ");
    }
    if (!orig_tabsLayout) return;
    gActive = active;
    // Đổi cấu hình lúc app đang chạy (bật / tắt, sáng ↔ tối): thanh đang hiện đổi ngay
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6ClockRefresh(window, tabsClass, 12);
}
