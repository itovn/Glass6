// App Lịch (com.apple.mobilecal) trên iPad — bỏ da và «cuốn sổ».
//
// Bố cục iOS 6 (tra 19/11/2026 bằng `imglog` + cây view đã bỏ chữ; chế độ xem Ngày, máy ngang):
//   CalendarNavigationArea 1024×44   thanh da trên: nền «Calendar-<kiểu>-Nav-LS», nút «button-normal» (chữ trắng), bộ chọn
//                                    Ngày / Tuần / Tháng / Năm / D.sách (CalendarNonTrackingSegmentedControl, ảnh «Switcher…»),
//                                    ô tìm kiếm («SearchField»)
//   CalendarToolbar 1024×44          thanh da dưới: nền «Calendar-<kiểu>-Toolbar-LS», nút «H.nay», nút «+», thanh trượt ngày
//                                    (CalendarTimeScrubber, ảnh «TimeScrubber…», nhãn CalendarFadeRightLabel), hai mũi tên
//   Calendar…BookView                khung sổ: bốn mép «Calendar-<kiểu>-Top/Left/Right/Bottom-LS», hai trang giấy
//                                    «Calendar-<kiểu>-Page-Left/Right-LS»
// <kiểu> = Day, Pad (Tuần / Tháng / Năm), List; mỗi hình có bản «-LS» (ngang) và «-PT» (đứng).
//
// Vẽ lại: hai thanh phẳng, nút bo tròn, mép sổ thành màu nền, trang trắng. Chữ trên hai thanh vốn trắng (hợp da nâu) → đổi
// sang tối ở lượt xếp của hai thanh; bộ chọn chế độ xem nhận kiểu nút chọn đoạn của Glass 6. Phần tối do bộ lọc của khung
// chung lo. Mới soi kỹ chế độ xem Ngày; Tuần / Tháng / Năm / D.sách khai theo tên hình cùng quy tắc, chưa soi từng cái.
#import "G6UI.h"

#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"

static BOOL gActive;
static char kTitleKey, kLabelKey, kDroppedTitleKey;

void G6UIAppCalendarPrepare(void) {
    NSMutableDictionary *images = [@{
        @"button-normal" : @(G6SkinButton),
        @"button-pressed" : @(G6SkinButtonDown),
        @"EditButton" : @(G6SkinButton),
        @"EditButton_Pressed" : @(G6SkinButtonDown),
        @"InvitationButton" : @(G6SkinButton),
        @"InvitationButtonPressed" : @(G6SkinButtonDown),
        @"CalendarButton" : @(G6SkinButton),
        @"SearchField" : @(G6SkinField),
        @"arrow-left" : @(G6SkinGlyph),
        @"arrow-right" : @(G6SkinGlyph),
        @"arrow-left-pressed" : @(G6SkinGlyph),
        @"arrow-right-pressed" : @(G6SkinGlyph),
        // Thanh trượt ngày: bỏ rãnh da, giữ núm; ô «hôm nay» là lớp phủ mờ
        @"TimeScrubberBackground" : @(G6SkinClear),
        @"TimeScrubberSlotBackground" : @(G6SkinClear),
        @"TimeScrubberLeftCap" : @(G6SkinClear),
        @"TimeScrubberRightCap" : @(G6SkinClear),
        @"TimeScrubberLeftCapFade" : @(G6SkinClear),
        @"TimeScrubberRightCapFade" : @(G6SkinClear),
        @"TimeScrubberLabelRightFade" : @(G6SkinClear),
        @"TimeScrubberDivider" : @(G6SkinHairline),
        @"TimeScrubberTodayBackground" : @(G6SkinHighlight),
        @"TimeScrubberTodayBackgroundLandscape" : @(G6SkinHighlight),
        @"timeLineFaderNoiseTop" : @(G6SkinClear),
        @"timeLineFaderNoiseBottom" : @(G6SkinClear),
        // Núm của thanh trượt ngày (vàng da) → viên mờ
        @"TimeScrubberThumb" : @(G6SkinChip),
        @"TimeScrubberThumbPT" : @(G6SkinChip),
        @"TimeScrubberThumbBlue" : @(G6SkinChip),
        @"TimeScrubberThumbToday" : @(G6SkinChip),
        @"TimeScrubberThumbTodayPT" : @(G6SkinChip),
        // Thanh ngày của chế độ D.sách: view của nó nền ĐEN, ảnh gốc đục — thay bằng lớp phủ mờ thì lộ nền đen (đo bằng
        // thống kê màu điểm ảnh: các dải 24 điểm màu (0,0,0) ở chế độ sáng) → phải là mặt đục
        @"list-header" : @(G6SkinBackdrop),
        // Hình trên nút (nâu, hợp da) → một màu
        @"UIButtonBarCalendars" : @(G6SkinGlyph),
        @"UIButtonBarInvites" : @(G6SkinGlyph),
        @"UIButtonBarNew" : @(G6SkinGlyph),
    } mutableCopy];
    for (NSString *o in @[@"LS", @"PT"]) {
        void (^add)(NSString *, int) = ^(NSString *stem, int kind) {
            images[[NSString stringWithFormat:@"Calendar-%@-%@", stem, o]] = @(kind);
        };
        for (NSString *view in @[@"Day", @"Pad", @"List"]) {
            add([view stringByAppendingString:@"-Nav"], G6SkinBar);
            add([view stringByAppendingString:@"-Toolbar"], G6SkinBarBottom);
        }
        add(@"List-Nav-Down", G6SkinBar);
        // Mép của khung sổ → màu nền
        for (NSString *stem in @[@"Day-Top", @"Day-Left", @"Day-Right", @"Day-Bottom", @"Pad-Top", @"Pad-Left", @"Pad-Right", @"Pad-Bottom",
                                 @"Month-Pad-Top", @"Year-Pad-Top", @"List-Left", @"List-Right", @"List-Center", @"List-Bottom-Left",
                                 @"List-Right-Bottom", @"List-Top-Left", @"List-Top-Left-Down", @"List-Top-Right"]) {
            add(stem, G6SkinBackdrop);
        }
        // Trang giấy → mặt trắng
        for (NSString *stem in @[@"Day-Page-Left", @"Day-Page-Right", @"Pad-Page-Top", @"Pad-Page-Left", @"Pad-Page-Right",
                                 @"Pad-Page-Bottom", @"Month-Pad-Page-Top", @"Year-Pad-Page-Top", @"List-Page-Top", @"List-Page-Bottom",
                                 @"List-PageWhiteRight-Left", @"List-PageWhiteRight-Right"]) {
            add(stem, G6SkinSurface);
        }
    }
    G6UISkinRegister(images);
}

static BOOL G6CalendarColorIsLight(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1, white = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) return a > 0.3 && 0.299 * r + 0.587 * g + 0.114 * b > 0.6;
    if ([color getWhite:&white alpha:&a]) return a > 0.3 && white > 0.6;
    return NO;
}

// Chữ trên hai thanh: nút (chữ trắng có bóng, hợp da nâu) và nhãn của thanh trượt ngày → chữ tối, không bóng. Nhớ màu gốc.
static void G6CalendarStyleBarText(UIView *view, int depth) {
    if ([view isKindOfClass:[UISegmentedControl class]]) {
        if (gActive) G6UIControlsStyleSegmented((UISegmentedControl *)view, NO);
        else G6UIControlsRestoreSegmented((UISegmentedControl *)view);
        return;
    }
    if ([view isKindOfClass:[UISearchBar class]]) return;  // ô tìm kiếm vốn chữ tối trên nền sáng
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        NSArray *saved = objc_getAssociatedObject(button, &kTitleKey);
        // Nút vừa có hình vừa có chữ (nút «Lịch»): khi nút trên thanh mang kiểu Glass 6, UIKit chỉ giữ hình và thu nhãn về bề
        // rộng 0 mà vẫn chừa chỗ — nút rộng 58 điểm, hình lệch trái (đo bằng `inspect`: nhãn (40 5; 0 18)). Bỏ hẳn chữ của nút
        // (nhớ lại để trả) và cho nút co về đúng cỡ nút chỉ có hình.
        NSString *dropped = objc_getAssociatedObject(button, &kDroppedTitleKey);
        NSString *text = [button titleForState:UIControlStateNormal];
        if (gActive && !dropped && text.length && [button imageForState:UIControlStateNormal] && !button.titleLabel.hidden &&
            button.titleLabel.bounds.size.width < 1 && button.bounds.size.width > 1) {
            objc_setAssociatedObject(button, &kDroppedTitleKey, text, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [button setTitle:nil forState:UIControlStateNormal];
            CGRect f = button.frame;
            CGSize fit = [button sizeThatFits:f.size];
            if (fit.width > 20 && fabs(fit.width - f.size.width) > 0.5) {
                f.size.width = fit.width;
                button.frame = f;
            }
            [view.superview setNeedsLayout];
        } else if (!gActive && dropped) {
            [button setTitle:dropped forState:UIControlStateNormal];
            objc_setAssociatedObject(button, &kDroppedTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [view.superview setNeedsLayout];
        }
        if (gActive) {
            // Xét ở MỌI lượt xếp, và xét cả màu của chính nhãn: nút vừa có hình vừa có chữ (nút «Lịch») không nhận màu đặt qua
            // setTitleColor: ở lượt đầu — chữ vẫn trắng trên viên nút trắng (đã gặp)
            UIColor *title = [button titleColorForState:UIControlStateNormal];
            UILabel *label = button.titleLabel;
            UIColor *dark = [UIColor colorWithWhite:0.12 alpha:1];
            if (G6CalendarColorIsLight(title)) {
                if (!saved) {
                    saved = @[title, [button titleShadowColorForState:UIControlStateNormal] ?: (id)[NSNull null]];
                    objc_setAssociatedObject(button, &kTitleKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                [button setTitleColor:dark forState:UIControlStateNormal];
                [button setTitleShadowColor:[UIColor clearColor] forState:UIControlStateNormal];
            }
            if (label && G6CalendarColorIsLight(label.textColor)) {
                if (!saved) {
                    saved = @[label.textColor, [NSNull null]];
                    objc_setAssociatedObject(button, &kTitleKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                label.textColor = dark;
                label.shadowColor = nil;
            }
        } else if (saved) {
            [button setTitleColor:saved[0] forState:UIControlStateNormal];
            [button setTitleShadowColor:saved[1] == [NSNull null] ? nil : saved[1] forState:UIControlStateNormal];
            objc_setAssociatedObject(button, &kTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        NSArray *saved = objc_getAssociatedObject(label, &kLabelKey);
        if (gActive && !saved && G6CalendarColorIsLight(label.textColor)) {
            objc_setAssociatedObject(label, &kLabelKey, @[label.textColor, label.shadowColor ?: (id)[NSNull null]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            label.textColor = [UIColor colorWithWhite:0.25 alpha:1];
            label.shadowColor = nil;
        } else if (!gActive && saved) {
            label.textColor = saved[0];
            label.shadowColor = saved[1] == [NSNull null] ? nil : saved[1];
            objc_setAssociatedObject(label, &kLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6CalendarStyleBarText(sub, depth - 1);
}

static void (*orig_navLayout)(UIView *, SEL);
static void repl_navLayout(UIView *self, SEL _cmd) {
    orig_navLayout(self, _cmd);
    @try {
        G6CalendarStyleBarText(self, 6);
    } @catch (NSException *e) {
    }
}

static void (*orig_toolbarLayout)(UIView *, SEL);
static void repl_toolbarLayout(UIView *self, SEL _cmd) {
    orig_toolbarLayout(self, _cmd);
    @try {
        G6CalendarStyleBarText(self, 6);
    } @catch (NSException *e) {
    }
}

static void G6CalendarRefresh(UIView *view, Class nav, Class toolbar, int depth) {
    if ((nav && [view isKindOfClass:nav]) || (toolbar && [view isKindOfClass:toolbar])) {
        G6CalendarStyleBarText(view, 6);
        [view setNeedsLayout];
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6CalendarRefresh(sub, nav, toolbar, depth - 1);
}

void G6UIAppCalendarApply(BOOL active) {
    Class nav = objc_getClass("CalendarNavigationArea"), toolbar = objc_getClass("CalendarToolbar");
    if (!nav && !toolbar) return;
    if (!orig_navLayout && !orig_toolbarLayout) {
        if (!active) return;
        if (nav) G6Hook(nav, @selector(layoutSubviews), (IMP)repl_navLayout, (IMP *)&orig_navLayout);
        if (toolbar) G6Hook(toolbar, @selector(layoutSubviews), (IMP)repl_toolbarLayout, (IMP *)&orig_toolbarLayout);
        G6Log(@"lịch (app): vẽ lại");
    }
    gActive = active;
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6CalendarRefresh(window, nav, toolbar, 10);
}
