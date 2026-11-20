// Nút điều khiển chuẩn của UIKit trong app (thành phần «controls»): công tắc, thanh trượt, nút chọn đoạn, thanh tiến độ.
//
// Đều qua UIAppearance (xem G6UIBars.m): đặt kiểu mặc định cho cả lớp; nút mà app tự đặt màu / ảnh riêng thì giữ kiểu của app.
//   - Công tắc: màu bật xanh lục, bỏ chữ «I / O».
//   - Thanh trượt: rãnh mảnh màu nhấn, núm tròn trắng có bóng.
//   - Nút chọn đoạn: rãnh xám bo tròn, đoạn đang chọn là viên trắng nổi (ở chế độ tối: viên xám sáng). Ảnh của từng đoạn
//     không tự bo được hai đầu nút → bo cả nút bằng lớp vẽ lúc nút vào cửa sổ (móc -didMoveToWindow).
//   - Thanh tiến độ: màu nhấn trên rãnh xám.
//   - Nút tăng giảm (UIStepper): viên xám bo tròn, dấu «−» «+» theo màu chữ.
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static NSString *gSignature;
static BOOL gActive, gDark;
static char kSegmentRoundedKey;

static UIImage *G6Draw(CGSize size, void (^draw)(CGContextRef ctx)) {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    draw(UIGraphicsGetCurrentContext());
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIColor *G6Accent(BOOL dark) {
    return dark ? [UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:1] : [UIColor colorWithRed:0 green:0.478 blue:1 alpha:1];
}

// Núm thanh trượt: đĩa trắng có bóng mềm
static UIImage *G6ThumbImage(BOOL pressed) {
    CGFloat d = 24, pad = 4;
    return G6Draw(CGSizeMake(d + 2 * pad, d + 2 * pad), ^(CGContextRef ctx) {
        CGRect disc = CGRectMake(pad, pad - 1, d, d);
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1.5), 3, [UIColor colorWithWhite:0 alpha:0.28].CGColor);
        [[UIColor colorWithWhite:pressed ? 0.93 : 1 alpha:1] setFill];
        CGContextFillEllipseInRect(ctx, disc);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        [[UIColor colorWithWhite:0 alpha:0.10] setStroke];
        CGContextSetLineWidth(ctx, 0.5);
        CGContextStrokeEllipseInRect(ctx, CGRectInset(disc, 0.25, 0.25));
    });
}

// Rãnh thanh trượt: thanh bo tròn cao 4 điểm trong ảnh cao 10 (UIKit canh giữa theo chiều dọc)
static UIImage *G6TrackImage(UIColor *color) {
    UIImage *image = G6Draw(CGSizeMake(9, 10), ^(CGContextRef ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 3, 9, 4) cornerRadius:2] fill];
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 4, 0, 4)];
}

// Bo hai đầu nút chọn đoạn (ảnh nền của từng đoạn là hình chữ nhật). Chỉ đụng nút đang dùng ảnh nền của Glass 6.
static void G6RoundSegmented(UISegmentedControl *control) {
    BOOL ours = gActive && [control backgroundImageForState:UIControlStateNormal barMetrics:UIBarMetricsDefault] != nil;
    BOOL rounded = objc_getAssociatedObject(control, &kSegmentRoundedKey) != nil;
    if (ours) {
        control.layer.cornerRadius = MIN(control.bounds.size.height / 2, 15);
        control.layer.masksToBounds = YES;
        if (!rounded) objc_setAssociatedObject(control, &kSegmentRoundedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (rounded) {
        control.layer.cornerRadius = 0;
        control.layer.masksToBounds = NO;
        objc_setAssociatedObject(control, &kSegmentRoundedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*orig_segmentedLayout)(UISegmentedControl *, SEL);
static void repl_segmentedLayout(UISegmentedControl *self, SEL _cmd) {
    orig_segmentedLayout(self, _cmd);
    G6RoundSegmented(self);
}

// Ảnh của nút chọn đoạn. UIKit chỉ dùng mép trái / phải của ảnh nền ở HAI ĐẦU NÚT; các đoạn ở giữa lấy phần giữa của ảnh
// (kéo giãn), còn chỗ hai đoạn giáp nhau là ảnh vách ngăn. Vì thế viên chọn được ghép từ ba mảnh:
//   - ảnh nền «đang chọn»: thân viên (phần giữa) + đầu tròn ở mép ảnh (khi đoạn chọn nằm ở đầu nút);
//   - vách ngăn «chọn | thường»: đầu tròn bên phải của viên; vách «thường | chọn»: đầu tròn bên trái.
// `part`: 0 = ảnh nền, −1 = vách có viên ở bên trái (chọn | thường), +1 = vách có viên ở bên phải (thường | chọn),
// 2 = vách giữa hai đoạn thường. Ảnh kéo giãn được cả hai chiều (nút trong ô Cài đặt cao 44 điểm).
static const CGFloat kSegmentDivider = 14;

static UIImage *G6SegmentImage(BOOL dark, BOOL selected, BOOL pressed, int part) {
    CGFloat h = 30, w = part == 0 ? 31 : kSegmentDivider;
    UIColor *track = dark ? [UIColor colorWithWhite:1 alpha:pressed ? 0.20 : 0.13] : [UIColor colorWithWhite:0.46 alpha:pressed ? 0.24 : 0.16];
    UIImage *image = G6Draw(CGSizeMake(w, h), ^(CGContextRef ctx) {
        [track setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
        CGRect pill = CGRectZero;
        if (part == 0 && selected) pill = CGRectMake(2, 2, w - 4, h - 4.5);
        // Viên chạy ra ngoài mép ảnh về phía đoạn đang chọn, đầu tròn dừng cách mép kia 2 điểm
        if (part == -1) pill = CGRectMake(-40, 2, 40 + w - 2, h - 4.5);
        if (part == 1) pill = CGRectMake(2, 2, 40 + w, h - 4.5);
        if (CGRectIsEmpty(pill)) return;
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:pill.size.height / 2];
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 1.5, [UIColor colorWithWhite:0 alpha:dark ? 0.35 : 0.16].CGColor);
        [(dark ? [UIColor colorWithWhite:0.42 alpha:1] : [UIColor whiteColor]) setFill];
        [path fill];
        CGContextRestoreGState(ctx);
    });
    if (part != 0) return [image resizableImageWithCapInsets:UIEdgeInsetsMake(14, 0, 15, 0)];
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(14, 15, 15, 15)];
}

// Nền nút tăng giảm: viên bo tròn màu rãnh
static UIImage *G6StepperImage(BOOL dark, BOOL pressed) {
    CGFloat h = 27;
    UIImage *image = G6Draw(CGSizeMake(29, h), ^(CGContextRef ctx) {
        [(dark ? [UIColor colorWithWhite:1 alpha:pressed ? 0.24 : 0.15] : [UIColor colorWithWhite:0.46 alpha:pressed ? 0.28 : 0.17]) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 29, h) cornerRadius:h / 2] fill];
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 14, 0, 14)];
}

// Dấu «+» / «−» của nút tăng giảm
static UIImage *G6StepperGlyph(BOOL plus, UIColor *color) {
    return G6Draw(CGSizeMake(15, 15), ^(CGContextRef ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(1.5, 6.5, 12, 2) cornerRadius:1] fill];
        if (plus) [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(6.5, 1.5, 2, 12) cornerRadius:1] fill];
    });
}

static UIImage *G6ClearImage(CGSize size) {
    return G6Draw(size, ^(CGContextRef ctx) {
    });
}

static NSDictionary *G6TextAttributes(UIFont *font, UIColor *color) {
    return @{
        UITextAttributeFont : font,
        UITextAttributeTextColor : color,
        UITextAttributeTextShadowColor : [UIColor clearColor],
        UITextAttributeTextShadowOffset : [NSValue valueWithUIOffset:UIOffsetZero],
    };
}

// ---- Ô nhập bo góc (UITextBorderStyleRoundedRect) ở chế độ tối ----
// Nền của ô là UITextFieldRoundedRectBackgroundView gồm ba UIImageView: đầu trái 8 điểm, khúc giữa kéo giãn, đầu phải 8 điểm
// (tra trên máy 19/11/2026) — trắng, có bóng chìm. Ở chế độ tối thay ba ảnh bằng ba mảnh của một viên bo góc màu than viền
// mờ; chữ đang sẫm thì đổi sáng (nhớ màu gốc). Trả lại: cho UIKit nạp lại ảnh của nó (-_updateImages) và gán lại màu chữ.

static char kFieldStyledKey, kFieldTextKey;
static void (*orig_fieldLayout)(UIView *, SEL);
static void (*orig_fieldUpdateImages)(UIView *, SEL);

// [đầu trái 8×h, khúc giữa 1×h, đầu phải 8×h]
static NSArray *G6FieldImages(CGFloat height) {
    static NSMutableDictionary *cache;
    if (height < 12 || height > 200) return nil;
    NSNumber *key = @(lround(height * 2));
    NSArray *images = cache[key];
    if (images) return images;
    const CGFloat cap = 8;
    CGSize size = CGSizeMake(cap * 2 + 1, height);
    UIImage *whole = G6Draw(size, ^(CGContextRef ctx) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5, 0.5, size.width - 1, size.height - 1) cornerRadius:6];
        [[UIColor colorWithWhite:0.17 alpha:1] setFill];
        [path fill];
        [[UIColor colorWithWhite:1 alpha:0.16] setStroke];
        path.lineWidth = 1;
        [path stroke];
    });
    CGFloat scale = whole.scale > 0 ? whole.scale : 1;
    UIImage * (^part)(CGFloat, CGFloat) = ^UIImage *(CGFloat x, CGFloat w) {
        CGImageRef cg = CGImageCreateWithImageInRect(whole.CGImage, CGRectMake(x * scale, 0, w * scale, height * scale));
        UIImage *img = cg ? [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp] : nil;
        if (cg) CGImageRelease(cg);
        return img;
    };
    UIImage *left = part(0, cap), *center = part(cap, 1), *right = part(cap + 1, cap);
    if (!left || !center || !right) return nil;
    images = @[left, center, right];
    if (!cache) cache = [NSMutableDictionary dictionary];
    cache[key] = images;
    return images;
}

static UIImageView *G6FieldPart(UIView *background, const char *name) {
    Ivar iv = class_getInstanceVariable([background class], name);
    id v = iv ? object_getIvar(background, iv) : nil;
    return [v isKindOfClass:[UIImageView class]] ? v : nil;
}

static BOOL G6ColorIsDark(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1, white = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) return a > 0.3 && 0.299 * r + 0.587 * g + 0.114 * b < 0.4;
    if ([color getWhite:&white alpha:&a]) return a > 0.3 && white < 0.4;
    return NO;
}

static void G6StyleRoundedField(UIView *background) {
    UIImageView *left = G6FieldPart(background, "_leftCap"), *center = G6FieldPart(background, "_center");
    UIImageView *right = G6FieldPart(background, "_rightCap");
    if (!left || !center || !right) return;
    UITextField *field = [background.superview isKindOfClass:[UITextField class]] ? (UITextField *)background.superview : nil;
    BOOL styled = objc_getAssociatedObject(background, &kFieldStyledKey) != nil;
    if (gActive && gDark) {
        NSArray *mine = G6FieldImages(background.bounds.size.height);
        if (!mine) return;
        if (left.image != mine[0]) left.image = mine[0];
        if (center.image != mine[1]) center.image = mine[1];
        if (right.image != mine[2]) right.image = mine[2];
        if (!styled) objc_setAssociatedObject(background, &kFieldStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (field && !objc_getAssociatedObject(field, &kFieldTextKey)) {
            UIColor *color = field.textColor ?: [UIColor blackColor];
            if (G6ColorIsDark(color)) {
                objc_setAssociatedObject(field, &kFieldTextKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                field.textColor = [UIColor colorWithWhite:1 alpha:0.94];
            }
        }
    } else if (styled) {
        objc_setAssociatedObject(background, &kFieldStyledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Hàm gốc nạp lại ba ảnh của UIKit
        if (orig_fieldUpdateImages) orig_fieldUpdateImages(background, NSSelectorFromString(@"_updateImages"));
        UIColor *color = field ? objc_getAssociatedObject(field, &kFieldTextKey) : nil;
        if (color) {
            objc_setAssociatedObject(field, &kFieldTextKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            field.textColor = color;
        }
    }
}

static void repl_fieldLayout(UIView *self, SEL _cmd) {
    orig_fieldLayout(self, _cmd);
    @try {
        G6StyleRoundedField(self);
    } @catch (NSException *e) {
    }
}

// UIKit nạp lại ảnh nền (ô vừa bật / tắt…): đè lại ảnh của Glass 6
static void repl_fieldUpdateImages(UIView *self, SEL _cmd) {
    orig_fieldUpdateImages(self, _cmd);
    @try {
        G6StyleRoundedField(self);
    } @catch (NSException *e) {
    }
}

// Sáng ↔ tối lúc app đang chạy: các ô nhập đang hiện đổi ngay
static void G6RefreshFields(UIView *view, Class backgroundClass, int depth) {
    if ([view isKindOfClass:backgroundClass]) {
        G6StyleRoundedField(view);
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6RefreshFields(sub, backgroundClass, depth - 1);
}

// Kiểu nút chọn đoạn của Glass 6 cho `seg` — bản mẫu chung của cả lớp (UIAppearance) hoặc một nút cụ thể
static NSArray *G6SegmentStates(void) {
    return @[@(UIControlStateNormal), @(UIControlStateSelected), @(UIControlStateHighlighted)];
}

static void G6StyleSegmentedTarget(UISegmentedControl *seg, BOOL dark) {
    [seg setBackgroundImage:G6SegmentImage(dark, NO, NO, 0) forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [seg setBackgroundImage:G6SegmentImage(dark, NO, YES, 0) forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [seg setBackgroundImage:G6SegmentImage(dark, YES, NO, 0) forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
    // Vách ngăn theo trạng thái của đoạn bên trái / bên phải nó (đoạn đang bấm coi như đoạn thường)
    for (NSNumber *left in G6SegmentStates()) {
        for (NSNumber *right in G6SegmentStates()) {
            BOOL leftSelected = left.unsignedIntegerValue == UIControlStateSelected;
            BOOL rightSelected = right.unsignedIntegerValue == UIControlStateSelected;
            int part = leftSelected == rightSelected ? 2 : (leftSelected ? -1 : 1);
            [seg setDividerImage:G6SegmentImage(dark, NO, NO, part)
                forLeftSegmentState:left.unsignedIntegerValue
                  rightSegmentState:right.unsignedIntegerValue
                         barMetrics:UIBarMetricsDefault];
        }
    }
    UIFont *font = G6Font(G6FontMedium, 13);
    UIColor *text = [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.92 : 0.82];
    [seg setTitleTextAttributes:G6TextAttributes(font, [text colorWithAlphaComponent:dark ? 0.70 : 0.62]) forState:UIControlStateNormal];
    [seg setTitleTextAttributes:G6TextAttributes(G6Font(G6FontSemiBold, 13), text) forState:UIControlStateSelected];
}

// Một nút chọn đoạn mà app tự đặt ảnh riêng (kiểu chung của lớp không tới được): áp kiểu Glass 6 thẳng lên nút đó. Ảnh nền,
// vách ngăn và kiểu chữ gốc được cất trên chính nút để G6UIControlsRestoreSegmented trả lại.
static char kSegmentSavedKey, kSegmentModeKey;

void G6UIControlsStyleSegmented(UISegmentedControl *control, BOOL dark) {
    NSNumber *mode = objc_getAssociatedObject(control, &kSegmentModeKey);
    if (mode && mode.boolValue == dark) return;
    if (!objc_getAssociatedObject(control, &kSegmentSavedKey)) {
        NSMutableDictionary *saved = [NSMutableDictionary dictionary];
        for (NSNumber *state in G6SegmentStates()) {
            NSUInteger s = state.unsignedIntegerValue;
            saved[[NSString stringWithFormat:@"nền %lu", (unsigned long)s]] =
                [control backgroundImageForState:s barMetrics:UIBarMetricsDefault] ?: (id)[NSNull null];
            saved[[NSString stringWithFormat:@"chữ %lu", (unsigned long)s]] = [control titleTextAttributesForState:s] ?: (id)[NSNull null];
            for (NSNumber *right in G6SegmentStates()) {
                NSUInteger r = right.unsignedIntegerValue;
                saved[[NSString stringWithFormat:@"vách %lu %lu", (unsigned long)s, (unsigned long)r]] =
                    [control dividerImageForLeftSegmentState:s rightSegmentState:r barMetrics:UIBarMetricsDefault] ?: (id)[NSNull null];
            }
        }
        objc_setAssociatedObject(control, &kSegmentSavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    G6StyleSegmentedTarget(control, dark);
    objc_setAssociatedObject(control, &kSegmentModeKey, @(dark), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control setNeedsLayout];
}

void G6UIControlsRestoreSegmented(UISegmentedControl *control) {
    NSDictionary *saved = objc_getAssociatedObject(control, &kSegmentSavedKey);
    if (!saved) return;
    id (^value)(NSString *) = ^id(NSString *key) {
        id v = saved[key];
        return v == [NSNull null] ? nil : v;
    };
    for (NSNumber *state in G6SegmentStates()) {
        NSUInteger s = state.unsignedIntegerValue;
        [control setBackgroundImage:value([NSString stringWithFormat:@"nền %lu", (unsigned long)s]) forState:s barMetrics:UIBarMetricsDefault];
        [control setTitleTextAttributes:value([NSString stringWithFormat:@"chữ %lu", (unsigned long)s]) forState:s];
        for (NSNumber *right in G6SegmentStates()) {
            NSUInteger r = right.unsignedIntegerValue;
            [control setDividerImage:value([NSString stringWithFormat:@"vách %lu %lu", (unsigned long)s, (unsigned long)r])
                 forLeftSegmentState:s
                   rightSegmentState:r
                          barMetrics:UIBarMetricsDefault];
        }
    }
    objc_setAssociatedObject(control, &kSegmentSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(control, &kSegmentModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control setNeedsLayout];
}

static void G6ApplyStyle(BOOL dark) {
    UIColor *accent = G6Accent(dark);
    UIColor *rail = dark ? [UIColor colorWithWhite:1 alpha:0.22] : [UIColor colorWithWhite:0.47 alpha:0.28];

    UISwitch *sw = [UISwitch appearance];
    [sw setOnTintColor:[UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1]];
    // Công tắc đang tắt: rãnh trắng của iOS 6 chói trên nền tối → rãnh xám than; chế độ sáng giữ rãnh gốc. Màu rãnh kéo núm
    // xám theo (đo trên ảnh chụp) → đặt luôn màu núm là trắng.
    [sw setTintColor:dark ? [UIColor colorWithWhite:0.26 alpha:1] : nil];
    [sw setThumbTintColor:dark ? [UIColor whiteColor] : nil];
    // Ảnh rỗng thay cho chữ «I» / «O» trên công tắc
    UIImage *blank = G6ClearImage(CGSizeMake(2, 2));
    [sw setOnImage:blank];
    [sw setOffImage:blank];

    UISlider *slider = [UISlider appearance];
    [slider setMinimumTrackImage:G6TrackImage(accent) forState:UIControlStateNormal];
    [slider setMaximumTrackImage:G6TrackImage(rail) forState:UIControlStateNormal];
    [slider setThumbImage:G6ThumbImage(NO) forState:UIControlStateNormal];
    [slider setThumbImage:G6ThumbImage(YES) forState:UIControlStateHighlighted];

    G6StyleSegmentedTarget([UISegmentedControl appearance], dark);
    UIColor *text = [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.92 : 0.82];

    UIProgressView *progress = [UIProgressView appearance];
    [progress setProgressTintColor:accent];
    [progress setTrackTintColor:rail];

    UIStepper *stepper = [UIStepper appearance];
    [stepper setBackgroundImage:G6StepperImage(dark, NO) forState:UIControlStateNormal];
    [stepper setBackgroundImage:G6StepperImage(dark, YES) forState:UIControlStateHighlighted];
    [stepper setBackgroundImage:G6StepperImage(dark, NO) forState:UIControlStateDisabled];
    UIImage *line = G6Draw(CGSizeMake(1, 27), ^(CGContextRef ctx) {
        [[UIColor colorWithWhite:dark ? 1 : 0 alpha:0.18] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 6, 1, 15));
    });
    for (NSNumber *left in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
        for (NSNumber *right in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
            [stepper setDividerImage:line forLeftSegmentState:left.unsignedIntegerValue rightSegmentState:right.unsignedIntegerValue];
        }
    }
    [stepper setIncrementImage:G6StepperGlyph(YES, text) forState:UIControlStateNormal];
    [stepper setDecrementImage:G6StepperGlyph(NO, text) forState:UIControlStateNormal];
    [stepper setIncrementImage:G6StepperGlyph(YES, [text colorWithAlphaComponent:0.3]) forState:UIControlStateDisabled];
    [stepper setDecrementImage:G6StepperGlyph(NO, [text colorWithAlphaComponent:0.3]) forState:UIControlStateDisabled];
}

static void G6ResetStyle(void) {
    UISwitch *sw = [UISwitch appearance];
    [sw setOnTintColor:nil];
    [sw setTintColor:nil];
    [sw setThumbTintColor:nil];
    [sw setOnImage:nil];
    [sw setOffImage:nil];

    UISlider *slider = [UISlider appearance];
    [slider setMinimumTrackImage:nil forState:UIControlStateNormal];
    [slider setMaximumTrackImage:nil forState:UIControlStateNormal];
    [slider setThumbImage:nil forState:UIControlStateNormal];
    [slider setThumbImage:nil forState:UIControlStateHighlighted];

    UISegmentedControl *seg = [UISegmentedControl appearance];
    for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateSelected), @(UIControlStateHighlighted)]) {
        [seg setBackgroundImage:nil forState:state.unsignedIntegerValue barMetrics:UIBarMetricsDefault];
        for (NSNumber *right in @[@(UIControlStateNormal), @(UIControlStateSelected), @(UIControlStateHighlighted)]) {
            [seg setDividerImage:nil
                forLeftSegmentState:state.unsignedIntegerValue
                  rightSegmentState:right.unsignedIntegerValue
                         barMetrics:UIBarMetricsDefault];
        }
    }
    [seg setTitleTextAttributes:nil forState:UIControlStateNormal];
    [seg setTitleTextAttributes:nil forState:UIControlStateSelected];

    UIProgressView *progress = [UIProgressView appearance];
    [progress setProgressTintColor:nil];
    [progress setTrackTintColor:nil];

    UIStepper *stepper = [UIStepper appearance];
    for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted), @(UIControlStateDisabled)]) {
        [stepper setBackgroundImage:nil forState:state.unsignedIntegerValue];
        [stepper setIncrementImage:nil forState:state.unsignedIntegerValue];
        [stepper setDecrementImage:nil forState:state.unsignedIntegerValue];
    }
    for (NSNumber *left in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
        for (NSNumber *right in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
            [stepper setDividerImage:nil forLeftSegmentState:left.unsignedIntegerValue rightSegmentState:right.unsignedIntegerValue];
        }
    }
}

BOOL G6UIControlsApply(BOOL allowed) {
    BOOL active = allowed && G6Feature(@"apps") && G6Feature(@"controls");
    BOOL dark = active && G6UIDark();
    NSString *signature = [NSString stringWithFormat:@"%d|%d", active, dark];
    if ([signature isEqualToString:gSignature]) return NO;
    BOOL first = gSignature == nil;
    gSignature = signature;
    gActive = active;
    gDark = dark;
    Class fieldBackground = objc_getClass("UITextFieldRoundedRectBackgroundView");
    if (active) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            G6Hook([UISegmentedControl class], @selector(layoutSubviews), (IMP)repl_segmentedLayout, (IMP *)&orig_segmentedLayout);
            if (fieldBackground && G6Hook(fieldBackground, NSSelectorFromString(@"_updateImages"), (IMP)repl_fieldUpdateImages,
                                          (IMP *)&orig_fieldUpdateImages)) {
                G6Hook(fieldBackground, @selector(layoutSubviews), (IMP)repl_fieldLayout, (IMP *)&orig_fieldLayout);
            }
        });
        G6ApplyStyle(dark);
    } else if (!first) {
        G6ResetStyle();
    }
    if (!first && fieldBackground && orig_fieldLayout) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) G6RefreshFields(window, fieldBackground, 24);
    }
    G6Log(@"nút điều khiển: %@", active ? (dark ? @"kiểu mới (tối)" : @"kiểu mới (sáng)") : @"kiểu gốc");
    return !first;
}
