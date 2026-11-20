// Bánh xe chọn (UIPickerView, UIDatePicker) — thuộc thành phần «controls».
//
// iOS 6 (tra trên máy 19/11/2026 bằng cửa sổ trưng bày `gallery 4`): khung xanh than, bánh xe bạc bóng, thanh chọn kính xanh.
//   UIPickerView (UIDatePicker bọc một _UIDatePickerView là lớp con của UIPickerView)
//     UIView                         mặt nền, phủ kín
//     … cho mỗi cột:
//       _UIOnePartImageView          vạch ngăn cột
//       _UIPickerWheelView           mặt bánh xe bạc
//       _UIPickerViewSelectionBar    thanh chọn kính
//       UIPickerTableView            các dòng: UIPickerTableViewTitledCell (UILabel) hoặc UIPickerTableViewWrapperCell bọc
//                                    view của UIDatePicker (UIDatePickerContentView…) hay view do app cấp
//       _UIOnePartImageView ×2       bóng của bánh xe, bóng của thanh chọn
//     _UIPickerViewTopFrame          khung, phủ kín, nằm trên cùng
//
// Kiểu mới (như iPadOS): mặt phẳng một màu (trắng / than), không khung, không bóng bánh xe; dòng đang chọn nằm trên một viên
// bo góc mờ; mép trên và mép dưới mờ dần vào mặt nền; chữ theo chế độ. Cách làm, ở mỗi lượt xếp của bánh xe:
//   - ẩn khung, mặt bánh xe, thanh chọn, các vạch và bóng của iOS 6 (đánh dấu view nào do Glass 6 ẩn để hiện lại đúng);
//   - tô mặt nền; đặt viên chọn của Glass 6 ngay dưới bảng của từng cột; đặt hai dải mờ dần lên trên cùng;
//   - chữ của các dòng đổi ở lượt xếp của UIPickerTableView (dòng sinh ra và được UIKit đặt lại màu liên tục khi cuộn): chữ đen
//     / xám sẫm → màu chữ chính, xám vừa → màu chữ phụ, chữ có màu (dòng «Hôm nay») → xanh sáng ở chế độ tối.
// Hai trường hợp chừa ra:
//   - bánh xe mà app tự cấp view cho từng dòng (không phải nhãn chuẩn / view của UIDatePicker): Glass 6 không đổi được màu
//     chữ app tự vẽ → bánh xe đó LUÔN dùng mặt sáng, kể cả ở chế độ tối (chữ sẫm của app còn đọc được);
//   - bánh xe không còn khung / mặt nền của iOS 6 (app đã tự đặt nó lên hình riêng — vd thẻ Hẹn giờ của app Đồng hồ): để nguyên.
// Tắt thành phần thì trả lại nguyên trạng.
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

// Viên chọn hẹp hơn thanh chọn của iOS 6 chừng này mỗi phía (ngang, dọc)
static const CGFloat kPillInsetX = 3, kPillInsetY = 4, kPillRadius = 8;
// Chiều cao dải mờ dần ở mép trên / dưới
static const CGFloat kFadeHeight = 62;

static BOOL gActive, gDark;
static NSString *gSignature;
static char kHiddenKey, kStateKey, kLabelOriginalKey, kLabelMineKey, kLabelModeKey, kLabelShadowKey;

// Dải mờ dần: lớp vẽ là một dải chuyển màu
@interface G6PickerFadeView : UIView
@end

@implementation G6PickerFadeView
+ (Class)layerClass {
    return [CAGradientLayer class];
}
@end

static UIColor *G6PickerSurface(BOOL dark) {
    return [UIColor colorWithWhite:dark ? 0.11 : 1 alpha:1];
}

// ---- Chữ ----

// Màu mới cho một nhãn có màu gốc `original`
static UIColor *G6PickerTextColor(UIColor *original, BOOL dark) {
    CGFloat r = 0, g = 0, b = 0, a = 1, white = 0;
    if (![original getRed:&r green:&g blue:&b alpha:&a]) {
        if (![original getWhite:&white alpha:&a]) return original;
        r = g = b = white;
    }
    CGFloat hi = MAX(r, MAX(g, b)), lo = MIN(r, MIN(g, b)), saturation = hi > 0.01 ? (hi - lo) / hi : 0;
    CGFloat luma = 0.299 * r + 0.587 * g + 0.114 * b;
    if (saturation > 0.3) return dark ? [UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:a] : original;
    if (luma < 0.35) return [UIColor colorWithWhite:dark ? 1 : 0 alpha:(dark ? 0.94 : 0.88) * a];
    if (luma < 0.75) return [UIColor colorWithWhite:dark ? 1 : 0 alpha:(dark ? 0.55 : 0.5) * a];
    return original;
}

// mode: @"tối" / @"sáng" = đang được Glass 6 tô theo chế độ đó; nil = trả màu gốc
static void G6PickerStyleLabel(UILabel *label, NSString *mode) {
    UIColor *mine = objc_getAssociatedObject(label, &kLabelMineKey), *current = label.textColor;
    if (mode) {
        NSString *applied = objc_getAssociatedObject(label, &kLabelModeKey);
        BOOL untouched = mine && [current isEqual:mine];
        if (untouched && [applied isEqualToString:mode]) return;
        // Màu đang có khác màu ta đặt: UIKit vừa đặt lại cho dòng này (hoặc lần đầu gặp) → đó là màu gốc mới
        UIColor *original = untouched ? objc_getAssociatedObject(label, &kLabelOriginalKey) : current;
        if (!original) return;
        UIColor *color = G6PickerTextColor(original, [mode isEqualToString:@"tối"]);
        objc_setAssociatedObject(label, &kLabelOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, &kLabelMineKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, &kLabelModeKey, mode, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (![current isEqual:color]) label.textColor = color;
        if (label.shadowColor) {
            objc_setAssociatedObject(label, &kLabelShadowKey, label.shadowColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            label.shadowColor = nil;
        }
    } else if (mine) {
        UIColor *original = objc_getAssociatedObject(label, &kLabelOriginalKey), *shadow = objc_getAssociatedObject(label, &kLabelShadowKey);
        if (original && [current isEqual:mine]) label.textColor = original;
        if (shadow && !label.shadowColor) label.shadowColor = shadow;
        objc_setAssociatedObject(label, &kLabelOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, &kLabelMineKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, &kLabelModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(label, &kLabelShadowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void G6PickerStyleLabels(UIView *view, NSString *mode, int depth) {
    if ([view isKindOfClass:[UILabel class]]) {
        G6PickerStyleLabel((UILabel *)view, mode);
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6PickerStyleLabels(sub, mode, depth - 1);
}

// Dòng này có phải loại Glass 6 đổi màu chữ được không: dòng chữ chuẩn, hoặc dòng bọc view của UIDatePicker
static BOOL G6PickerRowIsStandard(UIView *cell) {
    Class wrapper = objc_getClass("UIPickerTableViewWrapperCell");
    if (!wrapper || ![cell isKindOfClass:wrapper]) return YES;
    for (UIView *sub in cell.subviews) {
        NSString *name = NSStringFromClass([sub class]);
        if ([name isEqualToString:@"UITableViewCellContentView"] || [name hasPrefix:@"UIDatePicker"]) continue;
        return NO;
    }
    return YES;
}

static UIPickerView *G6PickerOfTable(UIView *table) {
    UIView *v = table.superview;
    return [v isKindOfClass:[UIPickerView class]] ? (UIPickerView *)v : nil;
}

// Gọi ở mỗi lượt xếp của bảng một cột (tức mỗi khung hình lúc bánh xe đang quay): chỉ là vài phép so cho mỗi dòng đang hiện
static void G6PickerStyleRows(UIView *table) {
    UIPickerView *picker = G6PickerOfTable(table);
    if (!picker) return;
    NSMutableDictionary *state = objc_getAssociatedObject(picker, &kStateKey);
    NSString *mode = state[@"mode"];
    for (UIView *cell in table.subviews) {
        if (![cell isKindOfClass:[UITableViewCell class]]) continue;
        if (!G6PickerRowIsStandard(cell)) {
            // Gặp dòng app tự cấp view: bánh xe này chuyển hẳn sang mặt sáng (ở lượt xếp kế của bánh xe)
            if (state && !state[@"custom"]) {
                state[@"custom"] = @YES;
                [picker setNeedsLayout];
            }
            continue;
        }
        G6PickerStyleLabels(cell, mode, 3);
    }
}

// ---- Bánh xe ----

static void G6PickerHide(UIView *view) {
    if (view.hidden) return;
    view.hidden = YES;
    objc_setAssociatedObject(view, &kHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Khung và mặt nền của iOS 6. Thiếu một trong hai = app đã tự đặt bánh xe lên hình riêng → không đụng.
static BOOL G6PickerFindStock(UIPickerView *picker, UIView **background, UIView **frame) {
    Class frameClass = objc_getClass("_UIPickerViewTopFrame");
    UIView *bg = nil, *top = nil;
    for (UIView *v in picker.subviews) {
        if (frameClass && [v isKindOfClass:frameClass]) top = v;
        else if (!bg && [v isMemberOfClass:[UIView class]] && CGSizeEqualToSize(v.bounds.size, picker.bounds.size)) bg = v;
    }
    *background = bg;
    *frame = top;
    return bg && top;
}

static void G6PickerRestore(UIPickerView *picker, NSMutableDictionary *state, UIView *background) {
    for (UIView *v in picker.subviews) {
        if (objc_getAssociatedObject(v, &kHiddenKey)) {
            v.hidden = NO;
            objc_setAssociatedObject(v, &kHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    for (UIView *v in state[@"pills"]) [v removeFromSuperview];
    for (UIView *v in state[@"fades"]) [v removeFromSuperview];
    id original = state[@"background"];
    if (background && original) background.backgroundColor = original == [NSNull null] ? nil : original;
    objc_setAssociatedObject(picker, &kStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Chữ: các bảng và nhãn nằm thẳng trong bánh xe trả màu gốc
    Class tableClass = objc_getClass("UIPickerTableView");
    for (UIView *v in picker.subviews) {
        if (tableClass && [v isKindOfClass:tableClass]) G6PickerStyleRows(v);
        else if ([v isKindOfClass:[UILabel class]]) G6PickerStyleLabel((UILabel *)v, nil);
    }
}

static void G6PickerStyle(UIPickerView *picker) {
    NSMutableDictionary *state = objc_getAssociatedObject(picker, &kStateKey);
    UIView *background = nil, *frame = nil;
    BOOL stock = G6PickerFindStock(picker, &background, &frame);
    if (!gActive || !stock) {
        if (state) G6PickerRestore(picker, state, background);
        return;
    }
    if (!state) {
        state = [NSMutableDictionary dictionary];
        state[@"background"] = background.backgroundColor ?: (id)[NSNull null];
        state[@"pills"] = [NSMutableArray array];
        objc_setAssociatedObject(picker, &kStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Bánh xe có dòng app tự vẽ: luôn mặt sáng
    BOOL dark = gDark && !state[@"custom"];
    NSString *mode = dark ? @"tối" : @"sáng";
    BOOL modeChanged = ![mode isEqualToString:state[@"mode"]];
    state[@"mode"] = mode;

    // 1. Phần của iOS 6: khung, mặt bánh xe, vạch, bóng, thanh chọn → ẩn. Nhớ thanh chọn nào đang hiện (để đặt viên chọn).
    Class wheelClass = objc_getClass("_UIPickerWheelView"), partClass = objc_getClass("_UIOnePartImageView");
    Class barClass = objc_getClass("_UIPickerViewSelectionBar"), tableClass = objc_getClass("UIPickerTableView");
    NSMutableArray *bars = [NSMutableArray array], *tables = [NSMutableArray array];
    for (UIView *v in picker.subviews) {
        if (v == frame || (wheelClass && [v isKindOfClass:wheelClass]) || (partClass && [v isKindOfClass:partClass])) {
            G6PickerHide(v);
        } else if (barClass && [v isKindOfClass:barClass]) {
            G6PickerHide(v);
            // Thanh chọn mà UIKit tự ẩn (bánh xe không hiện dòng chọn) thì không có dấu của Glass 6 → không đặt viên chọn
            if (objc_getAssociatedObject(v, &kHiddenKey)) [bars addObject:v];
        } else if (tableClass && [v isKindOfClass:tableClass]) {
            [tables addObject:v];
        } else if ([v isKindOfClass:[UILabel class]]) {
            // Nhãn đứng yên của bánh xe hẹn giờ («giờ», «phút»)
            G6PickerStyleLabel((UILabel *)v, mode);
        }
    }

    // 2. Mặt nền
    UIColor *surface = G6PickerSurface(dark);
    if (![background.backgroundColor isEqual:surface]) background.backgroundColor = surface;

    // 3. Viên chọn: mỗi cột một viên, nằm ngay dưới bảng của cột (chữ đè lên viên)
    NSMutableArray *pills = state[@"pills"];
    while (pills.count > bars.count) {
        [pills.lastObject removeFromSuperview];
        [pills removeLastObject];
    }
    while (pills.count < bars.count) {
        UIView *pill = [[UIView alloc] initWithFrame:CGRectZero];
        pill.userInteractionEnabled = NO;
        pill.layer.cornerRadius = kPillRadius;
        [pills addObject:pill];
    }
    UIColor *pillColor = [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.13 : 0.06];
    for (NSUInteger i = 0; i < pills.count; i++) {
        UIView *pill = pills[i], *bar = bars[i];
        CGRect f = CGRectInset(bar.frame, kPillInsetX, kPillInsetY);
        if (!CGRectEqualToRect(pill.frame, f)) pill.frame = f;
        if (![pill.backgroundColor isEqual:pillColor]) pill.backgroundColor = pillColor;
        if (pill.superview != picker) {
            // Bảng của cột này là bảng đầu tiên nằm sau thanh chọn trong thứ tự view
            NSUInteger at = [picker.subviews indexOfObject:bar];
            UIView *table = nil;
            for (NSUInteger k = at == NSNotFound ? 0 : at; k < picker.subviews.count && !table; k++) {
                UIView *v = picker.subviews[k];
                if (tableClass && [v isKindOfClass:tableClass]) table = v;
            }
            if (table) [picker insertSubview:pill belowSubview:table];
            else [picker insertSubview:pill aboveSubview:background];
        }
    }

    // 4. Hai dải mờ dần vào mặt nền, trên cùng
    NSArray *fades = state[@"fades"];
    if (!fades) {
        G6PickerFadeView *top = [[G6PickerFadeView alloc] initWithFrame:CGRectZero], *bottom = [[G6PickerFadeView alloc] initWithFrame:CGRectZero];
        top.userInteractionEnabled = bottom.userInteractionEnabled = NO;
        fades = @[top, bottom];
        state[@"fades"] = fades;
    }
    CGSize size = picker.bounds.size;
    CGFloat fade = MIN(kFadeHeight, size.height * 0.3);
    NSArray *frames = @[[NSValue valueWithCGRect:CGRectMake(0, 0, size.width, fade)],
                        [NSValue valueWithCGRect:CGRectMake(0, size.height - fade, size.width, fade)]];
    for (NSUInteger i = 0; i < 2; i++) {
        UIView *v = fades[i];
        CGRect f = [frames[i] CGRectValue];
        if (!CGRectEqualToRect(v.frame, f)) v.frame = f;
        if (modeChanged || v.superview != picker) {
            CAGradientLayer *layer = (CAGradientLayer *)v.layer;
            id solid = (__bridge id)surface.CGColor, clear = (__bridge id)[surface colorWithAlphaComponent:0].CGColor;
            layer.colors = i == 0 ? @[solid, clear] : @[clear, solid];
        }
        if (v.superview != picker || picker.subviews.lastObject != fades[1]) [picker addSubview:v];
    }

    // 5. Chữ của các dòng: chế độ vừa đổi thì các bảng xếp lại để đổi ngay
    if (modeChanged) {
        for (UIView *table in tables) G6PickerStyleRows(table);
    }
}

// ---- Hàm thay thế ----

static void (*orig_pickerLayout)(UIPickerView *, SEL);
static void repl_pickerLayout(UIPickerView *self, SEL _cmd) {
    orig_pickerLayout(self, _cmd);
    @try {
        G6PickerStyle(self);
    } @catch (NSException *e) {
        G6Log(@"bánh xe chọn: lỗi %@", e);
    }
}

static void (*orig_pickerTableLayout)(UIView *, SEL);
static void repl_pickerTableLayout(UIView *self, SEL _cmd) {
    orig_pickerTableLayout(self, _cmd);
    @try {
        G6PickerStyleRows(self);
    } @catch (NSException *e) {
    }
}

static void G6PickerRefresh(UIView *view, int depth) {
    if ([view isKindOfClass:[UIPickerView class]]) {
        G6PickerStyle((UIPickerView *)view);
        [view setNeedsLayout];
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6PickerRefresh(sub, depth - 1);
}

void G6UIPickersApply(BOOL allowed) {
    BOOL active = allowed && G6Feature(@"apps") && G6Feature(@"controls");
    BOOL dark = active && G6UIDark();
    NSString *signature = [NSString stringWithFormat:@"%d|%d", active, dark];
    if ([signature isEqualToString:gSignature]) return;
    BOOL first = gSignature == nil;
    gSignature = signature;
    if (active && !orig_pickerLayout) {
        Class tableClass = objc_getClass("UIPickerTableView");
        // Thiếu lớp bảng của bánh xe (bản iOS khác) thì không gắn gì: chữ không đổi được mà nền lại đổi thì hỏng
        if (!tableClass || !G6Hook(tableClass, @selector(layoutSubviews), (IMP)repl_pickerTableLayout, (IMP *)&orig_pickerTableLayout)) return;
        G6Hook([UIPickerView class], @selector(layoutSubviews), (IMP)repl_pickerLayout, (IMP *)&orig_pickerLayout);
    }
    if (!orig_pickerLayout) return;
    gActive = active;
    gDark = dark;
    if (first) return;
    // Đổi cấu hình lúc app đang chạy: bánh xe đang hiện đổi ngay
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6PickerRefresh(window, 24);
}
