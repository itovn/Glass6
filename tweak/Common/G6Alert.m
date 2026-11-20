// Hộp thoại — iOS 6 → kính.
//
// iOS 6 (tra trên máy 19/11/2026, lệnh thử `alert 2`): cửa sổ _UIAlertNormalizingOverlayWindow (mức 1996)
//   UIImageView                     lớp tối quanh hộp thoại
//   UIAlertView
//     UIImageView (_backgroundImageView)   ảnh nền xanh bóng, kéo giãn
//     UILabel _titleLabel, _bodyTextLabel (và _subtitleLabel, _taglineTextLabel)   chữ trắng có bóng
//     UIAlertButton : UIButton × n (_buttons, theo thứ tự chỉ số nút)   ảnh nền kéo giãn + nhãn
// Bố cục do -_layoutPopupAlertWithOrientation:animated: đặt (hộp thoại dạng nổi), ngoài ra có -layout, -layoutAnimated:.
//
// Cách làm (không đổi bố cục, không đổi cách bấm):
//   - hộp thoại sắp vào cửa sổ (-willMoveToWindow:) → chụp màn hình một lần làm nền của kính (hộp thoại hiện trên app);
//   - sau mỗi lần xếp chỗ / -didMoveToWindow → ảnh nền = tấm kính (bề mặt `alert` — kính đậm để chữ luôn đọc được), dựng
//     theo khung CUỐI của hộp thoại (tâm + cỡ) chứ không theo khung đang bị co giãn bởi hiệu ứng «bật ra»;
//   - chữ: Inter, màu theo sáng / tối, bỏ bóng chữ; nút: nền viên bo tròn, nút Huỷ chữ thường, nút khác chữ màu nhấn.
// Hộp thoại sống ngắn nên không cần trả lại kiểu gốc: tắt thành phần thì hộp thoại kế tiếp là kiểu gốc.
#import "G6Alert.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static char kBackdropKey, kDrawnKey, kDarkKey, kSheetGlassKey;

static id G6Ivar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    return iv ? object_getIvar(obj, iv) : nil;
}

// Chế độ sáng / tối của một hộp thoại chốt một lần lúc bắt đầu dựng (để kính và chữ không lệch nhau nếu đổi giữa chừng)
static BOOL G6AlertIsDark(UIView *alert) {
    NSNumber *dark = objc_getAssociatedObject(alert, &kDarkKey);
    if (!dark) {
        dark = @(G6IsDark());
        objc_setAssociatedObject(alert, &kDarkKey, dark, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return dark.boolValue;
}

static UIColor *G6AlertTextColor(BOOL dark, BOOL secondary) {
    if (dark) return [UIColor colorWithWhite:1 alpha:secondary ? 0.86 : 1];
    return [UIColor colorWithWhite:secondary ? 0.20 : 0.06 alpha:1];
}

static UIColor *G6AlertAccentColor(BOOL dark) {
    return dark ? [UIColor colorWithRed:0.36 green:0.68 blue:1.0 alpha:1] : [UIColor colorWithRed:0.0 green:0.44 blue:0.95 alpha:1];
}

// Nền nút: viên bo tròn, kéo giãn được theo bề ngang. Nhớ theo chiều cao / chế độ / trạng thái bấm.
static UIImage *G6AlertButtonImage(CGFloat height, BOOL dark, BOOL highlighted) {
    static NSMutableDictionary *cache;
    if (height < 8) return nil;
    NSString *key = [NSString stringWithFormat:@"%.0f|%d|%d", height, dark, highlighted];
    UIImage *img = cache[key];
    if (img) return img;
    CGFloat radius = height / 2, width = ceil(radius) * 2 + 1;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 0);
    CGFloat alpha = dark ? (highlighted ? 0.30 : 0.15) : (highlighted ? 0.18 : 0.08);
    [[UIColor colorWithWhite:dark ? 1 : 0 alpha:alpha] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, width, height) cornerRadius:radius] fill];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    img = [img resizableImageWithCapInsets:UIEdgeInsetsMake(0, ceil(radius), 0, ceil(radius))];
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (img) cache[key] = img;
    return img;
}

static void G6AlertRestyleLabel(UILabel *label, G6FontWeight weight, UIColor *color) {
    if (![label isKindOfClass:[UILabel class]]) return;
    if (G6FontAvailable()) {
        UIFont *want = G6Font(weight, label.font.pointSize);
        if (want && ![label.font.fontName isEqualToString:want.fontName]) label.font = want;
    }
    label.textColor = color;
    label.shadowColor = nil;
}

static void G6AlertStyle(UIView *alert) {
    if (!G6Feature(@"alerts")) return;
    BOOL dark = G6AlertIsDark(alert);

    // Nền: tấm kính theo khung cuối của hộp thoại trong view cha (cửa sổ phủ, đứng yên)
    UIImageView *bg = G6Ivar(alert, "_backgroundImageView");
    UIView *host = alert.superview;
    CGSize size = alert.bounds.size;
    if ([bg isKindOfClass:[UIImageView class]] && alert.window && host && size.width > 8 && size.height > 8) {
        CGPoint c = alert.center;
        CGRect final = CGRectMake(c.x - size.width / 2, c.y - size.height / 2, size.width, size.height);
        G6Backdrop *backdrop = objc_getAssociatedObject(alert, &kBackdropKey);
        NSString *key = [NSString stringWithFormat:@"%@|%p", NSStringFromCGRect(final), backdrop];
        if (![key isEqualToString:objc_getAssociatedObject(alert, &kDrawnKey)]) {
            double t0 = G6NowMs();
            UIImage *glass = G6GlassImageForRect(@"alert", host, final, dark, backdrop);
            if (glass) {
                bg.image = glass;
                objc_setAssociatedObject(alert, &kDrawnKey, key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                G6Log(@"hộp thoại: kính %.0f×%.0f (%@, %@ nền) %.1f ms", size.width, size.height, dark ? @"tối" : @"sáng",
                      backdrop ? @"có" : @"KHÔNG", G6NowMs() - t0);
            }
        }
    }
    // Chưa có kính thì chưa đổi chữ: chữ tối trên hộp xanh gốc sẽ không đọc được
    if (!objc_getAssociatedObject(alert, &kDrawnKey)) return;

    G6AlertRestyleLabel(G6Ivar(alert, "_titleLabel"), G6FontSemiBold, G6AlertTextColor(dark, NO));
    for (NSString *name in @[@"_subtitleLabel", @"_bodyTextLabel", @"_taglineTextLabel"]) {
        G6AlertRestyleLabel(G6Ivar(alert, name.UTF8String), G6FontRegular, G6AlertTextColor(dark, YES));
    }

    NSArray *buttons = G6Ivar(alert, "_buttons");
    SEL cancelSel = NSSelectorFromString(@"cancelButtonIndex");
    NSInteger cancel = [alert respondsToSelector:cancelSel] ? ((NSInteger (*)(id, SEL))objc_msgSend)(alert, cancelSel) : -1;
    if (![buttons isKindOfClass:[NSArray class]]) return;
    NSInteger index = 0;
    for (UIButton *button in buttons) {
        BOOL isCancel = index++ == cancel;
        if (![button isKindOfClass:[UIButton class]]) continue;
        CGFloat h = button.bounds.size.height;
        UIImage *normal = G6AlertButtonImage(h, dark, NO), *pressed = G6AlertButtonImage(h, dark, YES);
        if (normal && [button backgroundImageForState:UIControlStateNormal] != normal) {
            [button setBackgroundImage:normal forState:UIControlStateNormal];
            [button setBackgroundImage:pressed forState:UIControlStateHighlighted];
        }
        UIColor *color = isCancel ? G6AlertTextColor(dark, NO) : G6AlertAccentColor(dark);
        for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
            [button setTitleColor:color forState:(UIControlState)state.unsignedIntegerValue];
            [button setTitleShadowColor:[UIColor clearColor] forState:(UIControlState)state.unsignedIntegerValue];
        }
        if (G6FontAvailable()) {
            UIFont *want = G6Font(isCancel ? G6FontMedium : G6FontSemiBold, button.titleLabel.font.pointSize);
            if (want && ![button.titleLabel.font.fontName isEqualToString:want.fontName]) button.titleLabel.font = want;
        }
    }
}

static void G6AlertStyleSafe(UIView *alert) {
    @try {
        G6AlertStyle(alert);
    } @catch (NSException *e) {
        G6Log(@"hộp thoại: lỗi khi dựng: %@", e);
    }
}

// ---- Hàm thay thế ----

static void (*o_willMoveToWindow)(id, SEL, id);
static void g6_willMoveToWindow(UIView *self, SEL _cmd, UIWindow *window) {
    @try {
        // Chụp màn hình khi hộp thoại chưa hiện — mỗi hộp thoại một lần
        if (window && !objc_getAssociatedObject(self, &kBackdropKey) && G6Feature(@"alerts")) {
            G6Backdrop *backdrop = [G6Backdrop backdropWithScreen:YES];
            if (backdrop) objc_setAssociatedObject(self, &kBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *e) {
    }
    o_willMoveToWindow(self, _cmd, window);
}

static void (*o_didMoveToWindow)(id, SEL);
static void g6_didMoveToWindow(UIView *self, SEL _cmd) {
    o_didMoveToWindow(self, _cmd);
    if (self.window) G6AlertStyleSafe(self);
}

static void (*o_layoutAnimated)(id, SEL, BOOL);
static void g6_layoutAnimated(UIView *self, SEL _cmd, BOOL animated) {
    o_layoutAnimated(self, _cmd, animated);
    G6AlertStyleSafe(self);
}

// Đường xếp chỗ thật của hộp thoại dạng nổi trên iOS 6 (-layoutAnimated: không được gọi trong đường này — đã thử)
static void (*o_layoutPopup)(id, SEL, int, BOOL);
static void g6_layoutPopup(UIView *self, SEL _cmd, int orientation, BOOL animated) {
    o_layoutPopup(self, _cmd, orientation, animated);
    G6AlertStyleSafe(self);
}

static void (*o_layout)(id, SEL);
static void g6_layout(UIView *self, SEL _cmd) {
    o_layout(self, _cmd);
    G6AlertStyleSafe(self);
}

// ---- Bảng chọn (UIActionSheet) ----
// Cùng họ nút với hộp thoại (UIAlertButton). Trên iPad bảng chọn nằm trong bảng nổi — khung do Glass6UI lo (G6UIPopover.m);
// ở đây chỉ đổi nút sang viên bo tròn và chữ: việc thường màu nhấn, «Huỷ» màu chữ thường, việc phá huỷ màu đỏ.
//
// iPhone (tra trên máy 20/11/2026, lệnh thử `sheet 1`): bảng chọn trượt từ đáy lên, rộng hết màn hình, nền xám do chính
// -[UIActionSheet drawRect:] vẽ; _shadowImageView là vệt bóng 3 điểm ở mép trên. Kiểu iOS 26: một tấm kính bo góc nổi, lùi
// vào hai bên và nhấc khỏi đáy. Không đổi bố cục của UIKit (nút 278 điểm đã nằm gọn trong tấm) — chỉ thay nền:
//   - bảng sắp vào cửa sổ → chụp màn hình một lần làm nền của kính;
//   - sau mỗi lần xếp chỗ: tấm kính (bề mặt `alert`) nằm dưới cùng của bảng, dựng theo vị trí CUỐI của bảng (đáy bảng chạm
//     đáy view cha) chứ không theo vị trí đang trượt;
//   - -drawRect: gốc không vẽ nữa khi đã có kính.

// Lề của tấm kính so với khung bảng chọn (điểm)
static const CGFloat kSheetInsetX = 8, kSheetInsetBottom = 8;

// Bảng chọn dạng trượt từ đáy của iPhone (không nằm trong bảng nổi)
static BOOL G6SheetIsBottomSheet(UIView *sheet) {
    return g6_device_is_phone() && !G6Ivar(sheet, "_popoverController");
}

// Xem G6Alert.h: app đang được vẽ lại trả lời thay cho G6IsDark()
static BOOL (*gSheetDark)(void);

void G6AlertSetSheetDarkProvider(BOOL (*provider)(void)) {
    gSheetDark = provider;
}

// Tấm kính của bảng chọn trên iPhone. Dựng lại khi cỡ bảng đổi (xoay máy).
static void G6SheetGlass(UIActionSheet *sheet, BOOL dark) {
    UIView *host = sheet.superview;
    CGSize size = sheet.bounds.size;
    if (!sheet.window || !host || size.width < 60 || size.height < 40 || !G6SheetIsBottomSheet(sheet)) return;
    CGRect mine = CGRectMake(kSheetInsetX, 0, size.width - 2 * kSheetInsetX, size.height - kSheetInsetBottom);
    // Vị trí cuối: bảng đang nằm ngoài đáy (sắp trượt lên) thì tính theo lúc đáy bảng chạm đáy view cha
    CGRect frame = sheet.frame;
    CGFloat hostH = host.bounds.size.height;
    if (CGRectGetMaxY(frame) > hostH + 0.5) frame.origin.y = hostH - frame.size.height;
    CGRect final = CGRectOffset(mine, frame.origin.x, frame.origin.y);
    G6Backdrop *backdrop = objc_getAssociatedObject(sheet, &kBackdropKey);
    NSString *key = [NSString stringWithFormat:@"%@|%d|%p", NSStringFromCGRect(final), dark, backdrop];
    UIImageView *glass = objc_getAssociatedObject(sheet, &kSheetGlassKey);
    if (glass && [key isEqualToString:objc_getAssociatedObject(sheet, &kDrawnKey)]) {
        if (!CGRectEqualToRect(glass.frame, mine)) glass.frame = mine;
        return;
    }
    double t0 = G6NowMs();
    UIImage *image = G6GlassImageForRect(@"alert", host, final, dark, backdrop);
    if (!image) return;
    if (!glass) {
        glass = [[UIImageView alloc] initWithFrame:mine];
        glass.userInteractionEnabled = NO;
        [sheet insertSubview:glass atIndex:0];
        objc_setAssociatedObject(sheet, &kSheetGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Nền xám gốc: vẽ lại để -drawRect: (đã móc) để trống; vệt bóng ở mép trên không còn chỗ bám
        [sheet setNeedsDisplay];
        UIView *shadow = G6Ivar(sheet, "_shadowImageView");
        if ([shadow isKindOfClass:[UIView class]]) shadow.hidden = YES;
    }
    glass.frame = mine;
    glass.image = image;
    objc_setAssociatedObject(sheet, &kDrawnKey, key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    G6Log(@"bảng chọn: kính %.0f×%.0f (%@, %@ nền) %.1f ms", mine.size.width, mine.size.height, dark ? @"tối" : @"sáng",
          backdrop ? @"có" : @"KHÔNG", G6NowMs() - t0);
}

static void G6SheetStyle(UIActionSheet *sheet) {
    if (!G6Feature(@"alerts")) return;
    // Bảng chọn trong bảng nổi (iPad) nằm trong cửa sổ của app → theo «tối / sáng» của app (app đang vẽ lại bằng bộ lọc: luôn
    // sáng, bộ lọc của cửa sổ lo phần tối). Bảng trượt từ đáy của iPhone nằm ở cửa sổ phủ riêng, không dính bộ lọc → theo
    // chế độ thật của máy.
    BOOL dark = gSheetDark && !G6SheetIsBottomSheet(sheet) ? gSheetDark() : G6IsDark();
    G6SheetGlass(sheet, dark);
    NSInteger cancel = sheet.cancelButtonIndex, destructive = sheet.destructiveButtonIndex;
    NSArray *buttons = G6Ivar(sheet, "_buttons");
    if (![buttons isKindOfClass:[NSArray class]]) return;
    NSInteger index = 0;
    for (UIButton *button in buttons) {
        NSInteger i = index++;
        if (![button isKindOfClass:[UIButton class]]) continue;
        CGFloat h = button.bounds.size.height;
        UIImage *normal = G6AlertButtonImage(h, dark, NO), *pressed = G6AlertButtonImage(h, dark, YES);
        if (normal && [button backgroundImageForState:UIControlStateNormal] != normal) {
            [button setBackgroundImage:normal forState:UIControlStateNormal];
            [button setBackgroundImage:pressed forState:UIControlStateHighlighted];
        }
        UIColor *color = G6AlertAccentColor(dark);
        if (i == cancel) color = G6AlertTextColor(dark, NO);
        if (i == destructive) color = dark ? [UIColor colorWithRed:1 green:0.27 blue:0.23 alpha:1] : [UIColor colorWithRed:0.92 green:0.18 blue:0.15 alpha:1];
        for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
            [button setTitleColor:color forState:(UIControlState)state.unsignedIntegerValue];
            [button setTitleShadowColor:[UIColor clearColor] forState:(UIControlState)state.unsignedIntegerValue];
        }
        if (G6FontAvailable()) {
            UIFont *want = G6Font(i == cancel ? G6FontMedium : G6FontSemiBold, button.titleLabel.font.pointSize);
            if (want && ![button.titleLabel.font.fontName isEqualToString:want.fontName]) button.titleLabel.font = want;
        }
    }
    UILabel *title = G6Ivar(sheet, "_titleLabel");
    if ([title isKindOfClass:[UILabel class]]) {
        title.textColor = G6AlertTextColor(dark, YES);
        title.shadowColor = nil;
        if (G6FontAvailable() && objc_getAssociatedObject(sheet, &kSheetGlassKey)) {
            UIFont *want = G6Font(G6FontMedium, title.font.pointSize);
            if (want && ![title.font.fontName isEqualToString:want.fontName]) title.font = want;
        }
    }
}

// Chụp màn hình khi bảng chọn chưa hiện — mỗi bảng một lần (chỉ bảng trượt từ đáy của iPhone mới cần nền kính)
static void (*o_sheetWillMove)(id, SEL, id);
static void g6_sheetWillMove(UIActionSheet *self, SEL _cmd, UIWindow *window) {
    @try {
        if (window && !objc_getAssociatedObject(self, &kBackdropKey) && G6Feature(@"alerts") && G6SheetIsBottomSheet(self)) {
            G6Backdrop *backdrop = [G6Backdrop backdropWithScreen:YES];
            if (backdrop) objc_setAssociatedObject(self, &kBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *e) {
    }
    o_sheetWillMove(self, _cmd, window);
}

// Đã có tấm kính thì nền xám gốc không vẽ nữa
static void (*o_sheetDrawRect)(id, SEL, CGRect);
static void g6_sheetDrawRect(UIActionSheet *self, SEL _cmd, CGRect rect) {
    if (objc_getAssociatedObject(self, &kSheetGlassKey)) return;
    o_sheetDrawRect(self, _cmd, rect);
}

static void (*o_sheetLayout)(id, SEL);
static void g6_sheetLayout(UIActionSheet *self, SEL _cmd) {
    o_sheetLayout(self, _cmd);
    @try {
        G6SheetStyle(self);
    } @catch (NSException *e) {
        G6Log(@"bảng chọn: lỗi khi dựng: %@", e);
    }
}

static void (*o_sheetDidMove)(id, SEL);
static void g6_sheetDidMove(UIActionSheet *self, SEL _cmd) {
    o_sheetDidMove(self, _cmd);
    @try {
        if (self.window) G6SheetStyle(self);
    } @catch (NSException *e) {
        G6Log(@"bảng chọn: lỗi khi dựng: %@", e);
    }
}

void G6AlertInstall(void) {
    Class alert = objc_getClass("UIAlertView");
    if (!alert || !class_getInstanceVariable(alert, "_backgroundImageView") || !class_getInstanceVariable(alert, "_buttons")) {
        G6Log(@"hộp thoại: UIAlertView không có _backgroundImageView / _buttons — bỏ qua");
        return;
    }
    if (!G6Hook(alert, NSSelectorFromString(@"_layoutPopupAlertWithOrientation:animated:"), (IMP)g6_layoutPopup, (IMP *)&o_layoutPopup)) return;
    G6Hook(alert, NSSelectorFromString(@"layoutAnimated:"), (IMP)g6_layoutAnimated, (IMP *)&o_layoutAnimated);
    G6Hook(alert, NSSelectorFromString(@"layout"), (IMP)g6_layout, (IMP *)&o_layout);
    G6Hook(alert, @selector(willMoveToWindow:), (IMP)g6_willMoveToWindow, (IMP *)&o_willMoveToWindow);
    G6Hook(alert, @selector(didMoveToWindow), (IMP)g6_didMoveToWindow, (IMP *)&o_didMoveToWindow);
    Class sheet = objc_getClass("UIActionSheet");
    if (sheet && class_getInstanceVariable(sheet, "_buttons")) {
        G6Hook(sheet, @selector(layoutSubviews), (IMP)g6_sheetLayout, (IMP *)&o_sheetLayout);
        G6Hook(sheet, @selector(didMoveToWindow), (IMP)g6_sheetDidMove, (IMP *)&o_sheetDidMove);
        if (g6_device_is_phone()) {
            G6Hook(sheet, @selector(willMoveToWindow:), (IMP)g6_sheetWillMove, (IMP *)&o_sheetWillMove);
            G6Hook(sheet, @selector(drawRect:), (IMP)g6_sheetDrawRect, (IMP *)&o_sheetDrawRect);
        }
    }
}
