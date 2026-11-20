// App La bàn (com.apple.compass) trên iPhone — kiểu iOS 26: nền đen, mặt la bàn tối, vòng độ + hoa gió màu trắng, tam giác
// chỉ Bắc giữ màu đỏ. Như iOS 26, app này không đổi theo chế độ sáng / tối.
//
// iOS 6 (tra trên máy 20/11/2026, lệnh thử `imgdump`): cả giao diện nằm trong MainWindow.nib, hình nạp thẳng từ nib (không qua
// +[UIImage imageNamed:] nên khung thay hình theo tên của G6UISkin không bắt được). Các UIImageView, nhận ra theo cỡ ảnh (điểm):
//   320×568  Background          nền gỗ
//   293×293  CompassBezel        vành đồng
//   250×250  CompassFaceShadow   bóng đổ trong lòng mặt số (view 280×286)   | cùng cỡ ảnh, phân biệt theo cỡ view
//   250×250  CompassFace         mặt kem (view 250×250)                      |
//   160×102  CompassFaceHighlight   vệt sáng mặt kính
//   244×244  CompassFaceRim      vòng vạch + số độ (quay)
//   200×200  hoa gió             app tự vẽ lúc chạy, chữ hướng theo ngôn ngữ, tam giác Bắc đỏ (quay)
//   50×50    CompassPivot        núm đồng ở tâm
//   109×50   CompassRecalibrate  hình số 8 nằm (lúc bị nhiễu / cần hiệu chỉnh)
//   44×32    DeviceArrow         mũi tên gỗ chỉ hướng máy
//   11×30, 1×44, 1×3             viền nút, nền và bóng của thanh công cụ
// Cách làm: không vẽ lại gì theo toạ độ — đổi TẠI CHỖ ảnh của từng view bằng một bản biến đổi từ chính ảnh gốc (cùng cỡ, cùng
// độ đục), nên vị trí, phép quay và chữ hướng theo ngôn ngữ giữ nguyên:
//   nền → đen; vành, bóng, vệt sáng, núm, viền nút → trong suốt; mặt kem → đĩa than có viền mảnh; vòng độ, hình số 8, mũi tên
//   → tô trắng; hoa gió → phần nâu tô trắng, phần màu rõ (tam giác đỏ) giữ nguyên. Nhãn chữ nâu của màn «nhiễu sóng» → trắng.
// Áp lúc app vừa hiện và mỗi lần app trở lại (hoa gió có thể được vẽ lại). Thuộc công tắc «app_skins»; tắt thì trả ảnh gốc.
#import "G6UI.h"

#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Log.h"

static BOOL gActive;
static char kOriginalKey, kMineKey, kLabelSavedKey, kButtonSavedKey;

typedef enum {
    G6CompassKeep = 0,
    G6CompassBlack,     // nền đen đặc
    G6CompassClear,     // trong suốt
    G6CompassFace,      // đĩa than + viền mảnh
    G6CompassWhite,     // tô trắng, giữ độ đục
    G6CompassRose,      // tô trắng phần không màu, giữ phần màu rõ
} G6CompassRole;

static BOOL G6Near(CGSize a, CGFloat w, CGFloat h) {
    return fabs(a.width - w) < 1.5 && fabs(a.height - h) < 1.5;
}

static G6CompassRole G6CompassRoleFor(UIImageView *view, UIImage *image) {
    CGSize s = image.size, v = view.bounds.size;
    if (s.width >= 300 && s.height >= 440) return G6CompassBlack;
    if (G6Near(s, 293, 293)) return G6CompassClear;
    if (G6Near(s, 250, 250)) return G6Near(v, 250, 250) ? G6CompassFace : G6CompassClear;
    if (G6Near(s, 160, 102)) return G6CompassClear;
    if (G6Near(s, 244, 244)) return G6CompassWhite;
    if (G6Near(s, 200, 200)) return G6CompassRose;
    if (G6Near(s, 50, 50)) return G6CompassClear;
    if (G6Near(s, 109, 50) || G6Near(s, 44, 32)) return G6CompassWhite;
    // Thanh công cụ: nền (1×44) → đen cho liền với màn; bóng trên thanh (1×3) → bỏ. (Viền của hai nút do UIButton quản theo
    // trạng thái — xem G6CompassStyleButton.)
    if (G6Near(s, 1, 44)) return G6CompassBlack;
    if (G6Near(s, 1, 3)) return G6CompassClear;
    return G6CompassKeep;
}

// Bản biến đổi của `image` theo vai. Cùng cỡ điểm, cùng tỉ lệ, cùng phần kéo giãn.
static UIImage *G6CompassTransform(UIImage *image, G6CompassRole role) {
    CGSize size = image.size;
    if (size.width < 1 || size.height < 1) return nil;
    UIGraphicsBeginImageContextWithOptions(size, role == G6CompassBlack, image.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect all = CGRectMake(0, 0, size.width, size.height);
    switch (role) {
        case G6CompassBlack:
            [[UIColor blackColor] setFill];
            UIRectFill(all);
            break;
        case G6CompassClear:
            break;
        case G6CompassFace: {
            CGRect disc = CGRectInset(all, 1, 1);
            [[UIColor colorWithWhite:0.075 alpha:1] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:disc] fill];
            UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(disc, 0.5, 0.5)];
            ring.lineWidth = 1;
            [[UIColor colorWithWhite:1 alpha:0.16] setStroke];
            [ring stroke];
            break;
        }
        case G6CompassWhite:
            // Chỉ lấy độ đục của ảnh gốc
            [image drawInRect:all];
            CGContextSetBlendMode(ctx, kCGBlendModeSourceIn);
            [[UIColor whiteColor] setFill];
            CGContextFillRect(ctx, all);
            break;
        case G6CompassRose: {
            [image drawInRect:all];
            uint8_t *data = CGBitmapContextGetData(ctx);
            size_t w = CGBitmapContextGetWidth(ctx), h = CGBitmapContextGetHeight(ctx), stride = CGBitmapContextGetBytesPerRow(ctx);
            // Ngữ cảnh ảnh của UIKit: BGRA nhân sẵn alpha
            for (size_t y = 0; data && y < h; y++) {
                uint8_t *p = data + y * stride;
                for (size_t x = 0; x < w; x++, p += 4) {
                    float a = p[3];
                    if (a == 0) continue;
                    float k = 255.0f / a;
                    float b = MIN(255.0f, p[0] * k), g = MIN(255.0f, p[1] * k), r = MIN(255.0f, p[2] * k);
                    float mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
                    float sat = mx > 0 ? (mx - mn) / mx : 0;
                    // Đỏ của tam giác Bắc: bão hoà cao VÀ sáng; nâu sẫm của chữ / cánh hoa gió (cũng bão hoà nhưng tối) → trắng
                    float keep = MAX(0.0f, MIN(1.0f, (sat - 0.45f) / 0.25f)) * MAX(0.0f, MIN(1.0f, (mx - 110.0f) / 60.0f));
                    float outR = 255 + (r - 255) * keep, outG = 255 + (g - 255) * keep, outB = 255 + (b - 255) * keep;
                    float fa = a / 255.0f;
                    p[0] = (uint8_t)lroundf(outB * fa);
                    p[1] = (uint8_t)lroundf(outG * fa);
                    p[2] = (uint8_t)lroundf(outR * fa);
                }
            }
            break;
        }
        default:
            break;
    }
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!out) return nil;
    if (!UIEdgeInsetsEqualToEdgeInsets(image.capInsets, UIEdgeInsetsZero)) out = [out resizableImageWithCapInsets:image.capInsets];
    return out;
}

// Hai nút của thanh công cụ (định vị, thông tin): ảnh viền theo từng trạng thái do UIButton tự đặt lại mỗi lần xếp → đổi ngay
// ở nút: mọi trạng thái dùng ảnh trong suốt, chỉ còn hình trắng của nút.
static void G6CompassStyleButton(UIButton *button) {
    BOOL inToolbar = NO;
    for (UIView *v = button.superview; v && !inToolbar; v = v.superview) inToolbar = [v isKindOfClass:[UIToolbar class]];
    if (!inToolbar) return;
    NSArray *states = @[@(UIControlStateNormal), @(UIControlStateHighlighted), @(UIControlStateSelected),
                        @(UIControlStateSelected | UIControlStateHighlighted)];
    NSMutableDictionary *saved = objc_getAssociatedObject(button, &kButtonSavedKey);
    if (!gActive) {
        if (!saved) return;
        for (NSNumber *state in states) {
            id image = saved[state];
            [button setBackgroundImage:image == [NSNull null] ? nil : image forState:(UIControlState)state.unsignedIntegerValue];
        }
        objc_setAssociatedObject(button, &kButtonSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (saved) return;
    static UIImage *clear;
    if (!clear) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
        clear = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    if (!clear) return;
    saved = [NSMutableDictionary dictionary];
    UIImage *normal = [button backgroundImageForState:UIControlStateNormal];
    for (NSNumber *state in states) {
        UIControlState s = (UIControlState)state.unsignedIntegerValue;
        UIImage *image = [button backgroundImageForState:s];
        // Trạng thái không đặt riêng thì UIKit trả ảnh của trạng thái thường
        if (s != UIControlStateNormal && image == normal) image = nil;
        saved[state] = image ?: (id)[NSNull null];
    }
    objc_setAssociatedObject(button, &kButtonSavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSNumber *state in states) [button setBackgroundImage:clear forState:(UIControlState)state.unsignedIntegerValue];
}

static void G6CompassStyleImageView(UIImageView *view) {
    // Ảnh nằm trong nút do nút tự quản
    if ([view.superview isKindOfClass:[UIButton class]]) return;
    UIImage *current = view.image, *original = objc_getAssociatedObject(view, &kOriginalKey), *mine = objc_getAssociatedObject(view, &kMineKey);
    if (!gActive) {
        if (original && current == mine) view.image = original;
        objc_setAssociatedObject(view, &kOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kMineKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!current || current == mine) return;
    // Ảnh mới (lần đầu, hoặc app vừa đặt lại ảnh — hoa gió vẽ lại)
    G6CompassRole role = G6CompassRoleFor(view, current);
    if (role == G6CompassKeep) return;
    UIImage *made = G6CompassTransform(current, role);
    if (!made) return;
    objc_setAssociatedObject(view, &kOriginalKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kMineKey, made, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.image = made;
}

// Nhãn chữ nâu sẫm (màn «nhiễu sóng La bàn») → trắng; nhãn vốn sáng thì để nguyên
static void G6CompassStyleLabel(UILabel *label) {
    NSDictionary *saved = objc_getAssociatedObject(label, &kLabelSavedKey);
    if (!gActive) {
        if (!saved) return;
        label.textColor = saved[@"text"] == [NSNull null] ? nil : saved[@"text"];
        label.shadowColor = saved[@"shadow"] == [NSNull null] ? nil : saved[@"shadow"];
        objc_setAssociatedObject(label, &kLabelSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (saved) return;
    CGFloat r = 1, g = 1, b = 1, a = 1, white = 1;
    UIColor *color = label.textColor;
    if (![color getRed:&r green:&g blue:&b alpha:&a] && [color getWhite:&white alpha:&a]) r = g = b = white;
    if (0.299 * r + 0.587 * g + 0.114 * b > 0.5) return;
    saved = @{@"text" : color ?: (id)[NSNull null], @"shadow" : label.shadowColor ?: (id)[NSNull null]};
    objc_setAssociatedObject(label, &kLabelSavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    label.textColor = [UIColor colorWithWhite:1 alpha:0.92];
    label.shadowColor = nil;
}

static void G6CompassWalk(UIView *view, int depth) {
    if ([view isKindOfClass:[UIImageView class]]) G6CompassStyleImageView((UIImageView *)view);
    else if ([view isKindOfClass:[UILabel class]]) G6CompassStyleLabel((UILabel *)view);
    else if ([view isKindOfClass:[UIButton class]]) G6CompassStyleButton((UIButton *)view);
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6CompassWalk(sub, depth - 1);
}

static void G6CompassApplyAll(void) {
    @try {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if ([window isMemberOfClass:[UIWindow class]]) G6CompassWalk(window, 10);
        }
    } @catch (NSException *e) {
        G6Log(@"la bàn: lỗi khi đổi hình: %@", e);
    }
}

void G6UIAppCompassApply(BOOL active) {
    static BOOL watching;
    active = active && g6_device_is_phone();
    if (!watching && !active) return;
    if (!watching) {
        watching = YES;
        // Giao diện sinh ra từ nib sau lượt đặt kiểu đầu → áp lúc app vừa hiện, và mỗi lần app trở lại (ảnh có thể đã được đặt lại)
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidBecomeActiveNotification,
                                 UIWindowDidBecomeVisibleNotification]) {
            [nc addObserverForName:name
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                            G6CompassApplyAll();
                        }];
        }
        G6Log(@"la bàn: đổi hình tại chỗ");
    }
    gActive = active;
    G6CompassApplyAll();
}
