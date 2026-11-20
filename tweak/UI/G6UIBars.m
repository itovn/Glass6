// Thanh điều hướng, thanh công cụ, thanh thẻ, ô tìm kiếm trong app (thành phần «bars»).
//
// Thanh xanh xám bóng của iOS 6 → mặt phẳng sáng (hoặc than, ở chế độ tối) có một nét mảnh ngăn với nội dung; nút trên thanh
// → viên kính bo tròn; chữ phông Inter, không bóng chữ.
//
// Cách làm: UIAppearance (có từ iOS 5) — đặt kiểu mặc định cho cả lớp, UIKit tự áp cho mọi thanh lúc thanh vào cửa sổ.
//   - App tự đặt ảnh nền cho thanh của mình (Ghi chú, Game Center…) thì kiểu của app thắng — đúng ý: không phá thiết kế riêng.
//   - Đổi lúc app đang chạy (bật / tắt, sáng ↔ tối): đặt lại kiểu rồi gỡ – gắn lại các view gốc để chúng nhận kiểu mới.
// Trong app không có nền động để làm kính thật (iOS 6 không có lớp làm mờ sống), nên vật liệu ở đây là ảnh phẳng vẽ bằng
// CoreGraphics, kéo giãn được — vài ảnh nhỏ, vẽ một lần mỗi khi kiểu đổi.
//
// Hình trên nút (dấu cộng, mũi tên chia sẻ…): iOS 6 tự tô trắng + bóng chìm cho hợp thanh tối màu của nó; trên thanh sáng thì
// không thấy gì → móc hàm tô hình của UIImage (xem «Tô lại hình trên nút») để tô theo màu chữ của Glass 6.
#import "G6UI.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

// SDK 9.3 định nghĩa UIToolbarPositionAny qua UIBarPositionAny (đánh dấu «từ iOS 7»); trên iOS 6 hằng này đã có sẵn với cùng
// giá trị 0 — dùng thẳng số 0 (cả tên kiểu cũng bị đánh dấu) để khỏi dính cảnh báo «chưa kiểm phiên bản».
#define G6ToolbarPositionAny 0

// Chiều cao ảnh nền của nút trên thanh (điểm) — UIKit kéo giãn theo chiều ngang, canh giữa theo chiều dọc
static const CGFloat kPillHeight = 30;

static BOOL gActive, gDark;
static NSString *gSignature;

typedef struct {
    CGFloat barWhite;       // màu mặt thanh (xám, 0–1)
    CGFloat hairWhite, hairAlpha;  // nét mảnh ngăn thanh với nội dung
    CGFloat textWhite;      // chữ tiêu đề và chữ trên nút
    CGFloat pillTop, pillBottom, pillAlpha;   // viên nút: dải màu trên → dưới
    CGFloat pillStrokeWhite, pillStrokeAlpha; // viền viên nút
    CGFloat pillShadowAlpha;                  // bóng đổ dưới viên nút
    CGFloat fieldWhite, fieldAlpha;           // nền ô tìm kiếm
} G6BarPalette;

static G6BarPalette G6Palette(BOOL dark) {
    if (dark) {
        return (G6BarPalette){0.11, 1, 0.12, 1.0, 1, 1, 0.16, 1, 0.14, 0.0, 1, 0.12};
    }
    return (G6BarPalette){0.972, 0, 0.16, 0.10, 1.0, 0.955, 1.0, 0, 0.11, 0.10, 0.46, 0.13};
}

// Màu nhấn (nút «Xong», thẻ đang chọn)
static UIColor *G6Accent(BOOL dark) {
    return dark ? [UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:1] : [UIColor colorWithRed:0 green:0.478 blue:1 alpha:1];
}

UIColor *G6UIBarTextColor(void) {
    return [UIColor colorWithWhite:G6Palette(gDark).textWhite alpha:gDark ? 0.96 : 0.88];
}

CGFloat G6UIBarSurfaceWhite(void) {
    return G6Palette(gDark).barWhite;
}

// ---- Vẽ ảnh ----

static UIImage *G6Draw(CGSize size, void (^draw)(CGContextRef ctx)) {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    draw(UIGraphicsGetCurrentContext());
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// Mặt thanh: một màu phẳng cao `height`, kéo giãn được
static UIImage *G6BarImage(G6BarPalette p, CGFloat height) {
    UIImage *image = G6Draw(CGSizeMake(3, height), ^(CGContextRef ctx) {
        [[UIColor colorWithWhite:p.barWhite alpha:1] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, 3, height));
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 1, 0, 1)];
}

BOOL G6UIBarsActive(void) {
    return gActive;
}

BOOL G6UIBarsDark(void) {
    return gDark;
}

UIImage *G6UIBarSurfaceImage(CGFloat height, BOOL hairlineOnTop) {
    G6BarPalette p = G6Palette(gDark);
    CGFloat hair = 1 / MAX([UIScreen mainScreen].scale, 1);
    UIImage *image = G6Draw(CGSizeMake(3, height), ^(CGContextRef ctx) {
        [[UIColor colorWithWhite:p.barWhite alpha:1] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, 3, height));
        [[UIColor colorWithWhite:p.hairWhite alpha:p.hairAlpha] setFill];
        CGContextFillRect(ctx, CGRectMake(0, hairlineOnTop ? 0 : height - hair, 3, hair));
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(hairlineOnTop ? 1 : 0, 1, hairlineOnTop ? 0 : 1, 1)];
}

// Nét mảnh (ảnh bóng của thanh): một hàng điểm ảnh
static UIImage *G6HairlineImage(G6BarPalette p) {
    CGFloat h = 1 / [UIScreen mainScreen].scale;
    return G6Draw(CGSizeMake(3, h), ^(CGContextRef ctx) {
        [[UIColor colorWithWhite:p.hairWhite alpha:p.hairAlpha] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, 3, h));
    });
}

// Viên nút bo tròn hết cỡ. `accent` khác nil: viên màu nhấn (nút «Xong»). `pressed`: đang bấm. `chevron`: nút lùi — có mũi
// tên «‹» ở mép trái.
// Chiều cao viên nút đang dựng: 30 cho thanh thường; 24 cho thanh thấp 32 điểm của iPhone nằm ngang (viên 30 điểm tràn mép
// trên của thanh thấp — đã gặp)
static CGFloat gPillHeightNow = 30;

static UIImage *G6PillImage(G6BarPalette p, BOOL dark, UIColor *accent, BOOL pressed, BOOL chevron) {
    BOOL small = gPillHeightNow < 28;
    CGFloat h = gPillHeightNow, left = chevron ? (small ? 21 : 24) : (small ? 12 : 15), right = small ? 12 : 15;
    CGSize size = CGSizeMake(left + right + 1, h);
    UIImage *image = G6Draw(size, ^(CGContextRef ctx) {
        // Chừa 1 điểm trên và 2 điểm dưới cho bóng đổ
        CGRect body = CGRectMake(0.5, 1.5, size.width - 1, h - 4);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:body.size.height / 2];
        if (p.pillShadowAlpha > 0 && !pressed) {
            CGContextSaveGState(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 1.5, [UIColor colorWithWhite:0 alpha:p.pillShadowAlpha].CGColor);
            [[UIColor colorWithWhite:1 alpha:1] setFill];
            [path fill];
            CGContextRestoreGState(ctx);
        }
        CGContextSaveGState(ctx);
        [path addClip];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat top[4], bottom[4];
        if (accent) {
            [accent getRed:&top[0] green:&top[1] blue:&top[2] alpha:&top[3]];
            for (int i = 0; i < 3; i++) {
                bottom[i] = top[i] * 0.92;
                top[i] = MIN(1, top[i] * 1.04 + 0.04);
            }
            bottom[3] = top[3] = 1;
        } else {
            for (int i = 0; i < 3; i++) {
                top[i] = p.pillTop;
                bottom[i] = p.pillBottom;
            }
            top[3] = bottom[3] = p.pillAlpha;
        }
        CGFloat comps[8] = {top[0], top[1], top[2], top[3], bottom[0], bottom[1], bottom[2], bottom[3]};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, CGRectGetMinY(body)), CGPointMake(0, CGRectGetMaxY(body)), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        if (pressed) {
            [[UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.14 : 0.10] setFill];
            CGContextFillRect(ctx, body);
        }
        CGContextRestoreGState(ctx);
        if (!accent) {
            [[UIColor colorWithWhite:p.pillStrokeWhite alpha:p.pillStrokeAlpha] setStroke];
            path.lineWidth = 1;
            [path stroke];
        }
        if (chevron) {
            // Mũi tên «‹»: hai nét 2 điểm, đầu tròn
            CGFloat cx = small ? 10 : 11, cy = CGRectGetMidY(body), arm = small ? 4 : 5;
            UIBezierPath *arrow = [UIBezierPath bezierPath];
            [arrow moveToPoint:CGPointMake(cx + arm * 0.55, cy - arm)];
            [arrow addLineToPoint:CGPointMake(cx - arm * 0.45, cy)];
            [arrow addLineToPoint:CGPointMake(cx + arm * 0.55, cy + arm)];
            arrow.lineWidth = 2;
            arrow.lineCapStyle = kCGLineCapRound;
            arrow.lineJoinStyle = kCGLineJoinRound;
            [(accent ? [UIColor whiteColor] : [UIColor colorWithWhite:p.textWhite alpha:dark ? 0.96 : 0.82]) setStroke];
            [arrow stroke];
        }
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, left, 0, right)];
}

// Nền ô tìm kiếm: viên xám nhạt
static UIImage *G6FieldImage(G6BarPalette p) {
    CGFloat h = 30;
    UIImage *image = G6Draw(CGSizeMake(31, h), ^(CGContextRef ctx) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 1, 31, h - 2) cornerRadius:(h - 2) / 2];
        [[UIColor colorWithWhite:p.fieldWhite alpha:p.fieldAlpha] setFill];
        [path fill];
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 15, 0, 15)];
}

static UIImage *G6ClearImage(void) {
    return G6Draw(CGSizeMake(1, 1), ^(CGContextRef ctx) {
    });
}

// ---- iPhone: thanh thẻ nổi ----
// iOS 26 trên iPhone: thanh thẻ là một viên kính bo tròn nổi ở đáy, mục đang chọn nằm trên một viên sáng hơn. iOS 6 không cho
// nội dung chui xuống dưới thanh thẻ nên không làm kính thật được: ảnh nền của thanh (cao 49 điểm, kéo giãn theo bề ngang) vẽ
// sẵn một viên bo tròn lùi vào hai bên, phần lề quanh viên tô màu nền (sáng: màu mặt thanh; tối: đen — trùng nền của bảng ở
// chế độ tối), không có nét mảnh ngăn với nội dung. Bố cục các mục của UIKit giữ nguyên (mục đầu / cuối vẫn nằm gọn trong viên).
// Viên gần kín chiều cao thanh: tên mục của iOS 6 nằm sát đáy thanh (đáy chữ ở y ≈ 47) — nhấc tên mục lên một chút
static const CGFloat kTabHeight = 49, kTabInsetX = 6, kTabInsetTop = 1.5, kTabInsetBottom = 2, kTabTitleLift = 2.5;
// Các mục dồn về giữa theo tỉ lệ này: tên mục đầu / cuối (thanh 5 mục) khỏi chờm ra phần bo tròn của viên
static const CGFloat kTabCompress = 0.90;
static char kTabCompressedKey;

// UIKit chia đều bề ngang cho các mục (tâm mục i = rộng × (i + ½) / n). Đặt lại tâm theo tỉ lệ `k` quanh giữa thanh.
static void G6TabPlaceItems(UITabBar *bar, CGFloat k) {
    Class buttonClass = objc_getClass("UITabBarButton");
    if (!buttonClass) return;
    NSMutableArray *buttons = [NSMutableArray array];
    for (UIView *v in bar.subviews) {
        if ([v isKindOfClass:buttonClass] && !v.hidden) [buttons addObject:v];
    }
    NSUInteger n = buttons.count;
    if (n < 2) return;
    [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (a.center.x == b.center.x) return NSOrderedSame;
        return a.center.x < b.center.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    CGFloat w = bar.bounds.size.width;
    for (NSUInteger i = 0; i < n; i++) {
        UIView *button = buttons[i];
        CGFloat x = w / 2 + (w * (i + 0.5) / n - w / 2) * k;
        if (fabs(button.center.x - x) > 0.25) button.center = CGPointMake(x, button.center.y);
    }
}

static UIImage *G6TabCapsuleImage(G6BarPalette p, BOOL dark) {
    CGFloat capsuleH = kTabHeight - kTabInsetTop - kTabInsetBottom, radius = capsuleH / 2;
    CGFloat cap = ceil(kTabInsetX + radius) + 1;
    CGSize size = CGSizeMake(cap * 2 + 1, kTabHeight);
    UIImage *image = G6Draw(size, ^(CGContextRef ctx) {
        [[UIColor colorWithWhite:dark ? 0 : p.barWhite alpha:1] setFill];
        CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));
        CGRect body = CGRectMake(kTabInsetX, kTabInsetTop, size.width - 2 * kTabInsetX, capsuleH);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:radius];
        if (!dark) {
            // Bóng đổ nhẹ dưới viên
            CGContextSaveGState(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 3, [UIColor colorWithWhite:0 alpha:0.16].CGColor);
            [[UIColor whiteColor] setFill];
            [path fill];
            CGContextRestoreGState(ctx);
        }
        [[UIColor colorWithWhite:dark ? 0.135 : 1 alpha:1] setFill];
        [path fill];
        CGFloat hair = 1 / MAX([UIScreen mainScreen].scale, 1);
        UIBezierPath *stroke = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(body, hair / 2, hair / 2) cornerRadius:radius - hair / 2];
        stroke.lineWidth = hair;
        [[UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.14 : 0.10] setStroke];
        [stroke stroke];
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, cap, 0, cap)];
}

// Viên dưới mục đang chọn (kéo giãn theo bề ngang)
static UIImage *G6TabSelectionImage(BOOL dark) {
    CGFloat h = kTabHeight - kTabInsetTop - kTabInsetBottom - 7, radius = h / 2;
    CGSize size = CGSizeMake(ceil(radius) * 2 + 1, kTabHeight);
    UIImage *image = G6Draw(size, ^(CGContextRef ctx) {
        CGRect body = CGRectMake(0, kTabInsetTop + 3.5, size.width, h);
        [[UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.13 : 0.065] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:body cornerRadius:radius] fill];
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, ceil(radius), 0, ceil(radius))];
}

// Sau mỗi lần UIKit xếp thanh thẻ: dồn các mục (đang bật) hoặc trả về chỗ chia đều (vừa tắt)
static void (*orig_tabLayout)(UITabBar *, SEL);
static void repl_tabLayout(UITabBar *self, SEL _cmd) {
    orig_tabLayout(self, _cmd);
    @try {
        BOOL compressed = objc_getAssociatedObject(self, &kTabCompressedKey) != nil;
        if (gActive) {
            G6TabPlaceItems(self, kTabCompress);
            if (!compressed) objc_setAssociatedObject(self, &kTabCompressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (compressed) {
            G6TabPlaceItems(self, 1);
            objc_setAssociatedObject(self, &kTabCompressedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *e) {
    }
}

// ---- Tô lại hình trên nút ----

// iOS 6 đưa hình của nút trên thanh (dấu cộng, mũi tên chia sẻ, thùng rác…) qua
// -[UIImage _bezeledImageWithShadowRed:green:blue:alpha:fillRed:green:blue:alpha:drawShadow:]: tô một màu (trắng cho nút có
// viền, xám cho nút trơn) + bóng chìm. Trên thanh sáng của Glass 6 hình trắng mất hút → tô bằng màu chữ của thanh, bỏ bóng.
// (Đặt lại ảnh sau -[UINavigationButton setImage:] không ăn: UIKit tự chạy lại hiệu ứng này mỗi lần xếp nút.)
static UIImage *(*orig_bezeled)(UIImage *, SEL, float, float, float, float, float, float, float, float, BOOL);
static UIImage *repl_bezeled(UIImage *self, SEL _cmd, float sr, float sg, float sb, float sa, float fr, float fg, float fb,
                             float fa, BOOL drawShadow) {
    if (!gActive) return orig_bezeled(self, _cmd, sr, sg, sb, sa, fr, fg, fb, fa, drawShadow);
    CGFloat w = 0, a = 1;
    [G6UIBarTextColor() getWhite:&w alpha:&a];
    // Giữ độ đục UIKit xin (trạng thái mờ đi khi nút bị tắt), chỉ đổi màu
    return orig_bezeled(self, _cmd, 0, 0, 0, 0, (float)w, (float)w, (float)w, (float)a * fa, NO);
}

// Nút trơn (không viền) trên thanh công cụ lấy hình qua -[UIImage _flatImageWithWhite:alpha:] — xám vừa, hợp thanh sáng nhưng
// chìm trên thanh tối → ở chế độ tối tô bằng màu chữ của thanh.
static UIImage *(*orig_flat)(UIImage *, SEL, float, float);
static UIImage *repl_flat(UIImage *self, SEL _cmd, float white, float alpha) {
    if (!gActive || !gDark) return orig_flat(self, _cmd, white, alpha);
    return orig_flat(self, _cmd, 1, alpha * 0.92f);
}

// Ô tìm kiếm: nền ô đã đổi (viên xám nhạt / xám đậm) nhưng chữ gõ vào vẫn đen → ở chế độ tối phải đổi sang sáng. Chỉ đụng ô
// đang dùng ảnh nền của Glass 6 (app tự đặt ảnh cho ô tìm kiếm thì để nguyên), nhớ màu gốc để trả lại.
static char kSearchTextKey;

static void G6StyleSearchField(UISearchBar *bar) {
    UITextField *field = nil;
    for (UIView *sub in bar.subviews) {
        if ([sub isKindOfClass:[UITextField class]]) field = (UITextField *)sub;
    }
    if (!field) return;
    UIColor *saved = objc_getAssociatedObject(field, &kSearchTextKey);
    BOOL ours = gActive && [bar searchFieldBackgroundImageForState:UIControlStateNormal] != nil;
    if (ours && gDark) {
        if (!saved) objc_setAssociatedObject(field, &kSearchTextKey, field.textColor ?: [UIColor blackColor], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIColor *text = [UIColor colorWithWhite:1 alpha:0.94];
        if (![field.textColor isEqual:text]) field.textColor = text;
    } else if (saved) {
        field.textColor = saved;
        objc_setAssociatedObject(field, &kSearchTextKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*orig_searchLayout)(UISearchBar *, SEL);
static void repl_searchLayout(UISearchBar *self, SEL _cmd) {
    orig_searchLayout(self, _cmd);
    @try {
        G6StyleSearchField(self);
    } @catch (NSException *e) {
        G6Log(@"thanh: ô tìm kiếm lỗi %@", e);
    }
}

// ---- Hình của nút trơn (không viền) trên thanh công cụ ----

UIImage *G6UITintedImage(UIImage *image, UIColor *color) {
    if (!image || !color || image.size.width < 1 || image.size.height < 1) return image;
    CGRect rect = {CGPointZero, image.size};
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, image.scale > 0 ? image.scale : 1);
    [image drawInRect:rect];
    [color set];
    // Giữ độ đục từng điểm ảnh, thay màu
    UIRectFillUsingBlendMode(rect, kCGBlendModeSourceIn);
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: image;
}

// Biến kiểu số nguyên / cờ của một đối tượng UIKit, đọc theo vị trí sau khi kiểm đúng kiểu
static BOOL G6ScalarIvar(id obj, const char *name, char type, int *value) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!enc || enc[0] != type) return NO;
    char *at = (char *)(__bridge void *)obj + ivar_getOffset(iv);
    *value = type == 'i' ? *(int *)at : *(signed char *)at;
    return YES;
}

// Nút trơn trên thanh công cụ (thùng rác, soạn thư, dấu trang…): UISwappableImageView tự dựng ảnh hiển thị từ hình gốc trong
// -updateImageIfNeededWithTintColor: — xám xanh có nét chìm, hợp thanh xám bóng của iOS 6 nhưng chìm trên thanh than (đo trên
// ảnh chụp: 108, 115, 122). Sau mỗi lần nó dựng xong, tô lại ảnh đang hiện bằng màu chữ của thanh — cùng màu với hình trên nút
// có viền. Ảnh lúc đang bấm (vầng sáng) để nguyên. Ảnh đã tô mang dấu chế độ (sáng / tối) để biết lúc nào phải tô lại.
static char kPlainTintKey;
static void (*orig_swappableUpdate)(UIImageView *, SEL, id);
static void repl_swappableUpdate(UIImageView *self, SEL _cmd, id tintColor) {
    orig_swappableUpdate(self, _cmd, tintColor);
    @try {
        UIImage *shown = self.image;
        if (!shown) return;
        NSString *mark = objc_getAssociatedObject(shown, &kPlainTintKey);
        if (!gActive) {
            // Thành phần vừa tắt mà ảnh đang hiện còn là ảnh ta tô: bắt UIKit dựng lại từ hình gốc
            Ivar iv = mark ? class_getInstanceVariable([self class], "_updateImage") : NULL;
            const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
            if (enc && enc[0] == 'c') {
                *((signed char *)(__bridge void *)self + ivar_getOffset(iv)) = 1;
                orig_swappableUpdate(self, _cmd, tintColor);
            }
            return;
        }
        int style = -1, alternate = 0;
        if (!G6ScalarIvar(self, "_barButtonItemStyle", 'i', &style) || style != UIBarButtonItemStylePlain) return;
        if (G6ScalarIvar(self, "_showAlternate", 'c', &alternate) && alternate) return;
        NSString *key = gDark ? @"tối" : @"sáng";
        if ([mark isEqualToString:key]) return;
        // Màu đặc (xem chỗ tô lại nút của thanh điều hướng): ảnh đang hiện có thể là ảnh ta đã tô ở chế độ trước
        UIImage *tinted = G6UITintedImage(shown, [G6UIBarTextColor() colorWithAlphaComponent:1]);
        if (!tinted || tinted == shown) return;
        objc_setAssociatedObject(tinted, &kPlainTintKey, key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Gán bằng hàm của UIImageView: -[UISwappableImageView setImage:] coi ảnh nhận vào là hình gốc mới
        static void (*setImage)(id, SEL, id);
        if (!setImage) setImage = (void (*)(id, SEL, id))class_getMethodImplementation([UIImageView class], @selector(setImage:));
        setImage(self, @selector(setImage:), tinted);
    } @catch (NSException *e) {
    }
}

// Nút «phá huỷ» trên thanh (vd «Xóa» lúc đang chọn ảnh trong app Ảnh): bản gốc là nút ĐỎ — kiểu nút riêng của UIKit, đo trên
// iPad mini 1 iOS 6.1.3: -[UINavigationButton _barButtonItemStyle] = 7 (nút thường 1, «Xong» 2). Viên nút của Glass 6 dùng
// chung cho mọi kiểu nên mất dấu hiệu đó → giữ viên trung tính, cho CHỮ màu đỏ. Chữ của nút do UIKit đặt lại ở mỗi lượt xếp
// chỗ (theo thuộc tính chữ của UIAppearance) nên đổi ngay sau lượt đó.
static const int kDestructiveItemStyle = 7;

static void (*orig_navButtonLayout)(UIButton *, SEL);
static void repl_navButtonLayout(UIButton *self, SEL _cmd) {
    orig_navButtonLayout(self, _cmd);
    if (!gActive) return;
    @try {
        int style = -1;
        if (!G6ScalarIvar(self, "_style", 'i', &style) || style < 0) return;
        SEL itemStyle = NSSelectorFromString(@"_barButtonItemStyle");
        if (![self respondsToSelector:itemStyle] || ((int (*)(id, SEL))objc_msgSend)(self, itemStyle) != kDestructiveItemStyle) return;
        UIColor *red = gDark ? [UIColor colorWithRed:1 green:0.27 blue:0.23 alpha:1] : [UIColor colorWithRed:0.92 green:0.18 blue:0.15 alpha:1];
        if (!self.enabled) red = [red colorWithAlphaComponent:0.35];
        else if (self.highlighted) red = [red colorWithAlphaComponent:0.5];
        UILabel *label = self.titleLabel;
        if (![label.textColor isEqual:red]) label.textColor = red;
    } @catch (NSException *e) {
    }
}

static void (*orig_navDidMove)(UINavigationBar *, SEL);
static void repl_navDidMove(UINavigationBar *self, SEL _cmd);

static void G6InstallHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        G6Hook([UISearchBar class], @selector(layoutSubviews), (IMP)repl_searchLayout, (IMP *)&orig_searchLayout);
        if (g6_device_is_phone()) G6Hook([UITabBar class], @selector(layoutSubviews), (IMP)repl_tabLayout, (IMP *)&orig_tabLayout);
        G6Hook([UINavigationBar class], @selector(didMoveToWindow), (IMP)repl_navDidMove, (IMP *)&orig_navDidMove);
        G6HookNamed("UINavigationButton", @selector(layoutSubviews), (IMP)repl_navButtonLayout, (IMP *)&orig_navButtonLayout);
        Class swappable = objc_getClass("UISwappableImageView");
        SEL update = NSSelectorFromString(@"updateImageIfNeededWithTintColor:");
        Method um = swappable ? class_getInstanceMethod(swappable, update) : NULL;
        if (um && strcmp(method_getTypeEncoding(um) ?: "", "v12@0:4@8") == 0) {
            G6Hook(swappable, update, (IMP)repl_swappableUpdate, (IMP *)&orig_swappableUpdate);
        }
        SEL flat = NSSelectorFromString(@"_flatImageWithWhite:alpha:");
        Method fm = class_getInstanceMethod([UIImage class], flat);
        if (fm && strcmp(method_getTypeEncoding(fm) ?: "", "@16@0:4f8f12") == 0) {
            G6Hook([UIImage class], flat, (IMP)repl_flat, (IMP *)&orig_flat);
        }
        SEL sel = NSSelectorFromString(@"_bezeledImageWithShadowRed:green:blue:alpha:fillRed:green:blue:alpha:drawShadow:");
        Method m = class_getInstanceMethod([UIImage class], sel);
        // Kiểm đúng chữ ký trước khi móc: 8 số thực + 1 cờ, gọi sai kiểu là hỏng ngăn xếp
        if (m && strcmp(method_getTypeEncoding(m) ?: "", "@44@0:4f8f12f16f20f24f28f32f36c40") == 0 &&
            G6Hook([UIImage class], sel, (IMP)repl_bezeled, (IMP *)&orig_bezeled)) {
            return;
        }
        G6Log(@"thanh: không có hàm tô hình nút như mong đợi — hình trên nút giữ kiểu cũ");
    });
}

// ---- Đặt / gỡ kiểu ----

static NSDictionary *G6TextAttributes(UIFont *font, UIColor *color) {
    return @{
        UITextAttributeFont : font,
        UITextAttributeTextColor : color,
        UITextAttributeTextShadowColor : [UIColor clearColor],
        UITextAttributeTextShadowOffset : [NSValue valueWithUIOffset:UIOffsetZero],
    };
}

static void G6ApplyStyle(BOOL dark) {
    G6BarPalette p = G6Palette(dark);
    UIColor *text = [UIColor colorWithWhite:p.textWhite alpha:dark ? 0.96 : 0.88];
    UIColor *accent = G6Accent(dark);
    UIImage *hair = G6HairlineImage(p);

    UINavigationBar *nav = [UINavigationBar appearance];
    [nav setBackgroundImage:G6BarImage(p, 44) forBarMetrics:UIBarMetricsDefault];
    [nav setBackgroundImage:G6BarImage(p, 32) forBarMetrics:UIBarMetricsLandscapePhone];
    [nav setShadowImage:hair];
    [nav setTitleTextAttributes:G6TextAttributes(G6Font(G6FontSemiBold, 18), text)];

    UIToolbar *toolbar = [UIToolbar appearance];
    [toolbar setBackgroundImage:G6BarImage(p, 44) forToolbarPosition:G6ToolbarPositionAny barMetrics:UIBarMetricsDefault];
    [toolbar setBackgroundImage:G6BarImage(p, 32) forToolbarPosition:G6ToolbarPositionAny barMetrics:UIBarMetricsLandscapePhone];
    [toolbar setShadowImage:hair forToolbarPosition:G6ToolbarPositionAny];

    UIBarButtonItem *item = [UIBarButtonItem appearance];
    UIImage *pill = G6PillImage(p, dark, nil, NO, NO), *pillDown = G6PillImage(p, dark, nil, YES, NO);
    [item setBackgroundImage:pill forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [item setBackgroundImage:pillDown forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [item setBackgroundImage:G6PillImage(p, dark, accent, NO, NO)
                    forState:UIControlStateNormal
                       style:UIBarButtonItemStyleDone
                  barMetrics:UIBarMetricsDefault];
    [item setBackgroundImage:G6PillImage(p, dark, accent, YES, NO)
                    forState:UIControlStateHighlighted
                       style:UIBarButtonItemStyleDone
                  barMetrics:UIBarMetricsDefault];
    [item setBackButtonBackgroundImage:G6PillImage(p, dark, nil, NO, YES) forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [item setBackButtonBackgroundImage:G6PillImage(p, dark, nil, YES, YES)
                              forState:UIControlStateHighlighted
                            barMetrics:UIBarMetricsDefault];
    [item setBackButtonTitlePositionAdjustment:UIOffsetMake(3, 0) forBarMetrics:UIBarMetricsDefault];
    if (g6_device_is_phone()) {
        // Thanh thấp của iPhone nằm ngang: bộ viên thấp hơn
        gPillHeightNow = 24;
        [item setBackgroundImage:G6PillImage(p, dark, nil, NO, NO) forState:UIControlStateNormal barMetrics:UIBarMetricsLandscapePhone];
        [item setBackgroundImage:G6PillImage(p, dark, nil, YES, NO) forState:UIControlStateHighlighted barMetrics:UIBarMetricsLandscapePhone];
        [item setBackgroundImage:G6PillImage(p, dark, accent, NO, NO)
                        forState:UIControlStateNormal
                           style:UIBarButtonItemStyleDone
                      barMetrics:UIBarMetricsLandscapePhone];
        [item setBackgroundImage:G6PillImage(p, dark, accent, YES, NO)
                        forState:UIControlStateHighlighted
                           style:UIBarButtonItemStyleDone
                      barMetrics:UIBarMetricsLandscapePhone];
        [item setBackButtonBackgroundImage:G6PillImage(p, dark, nil, NO, YES)
                                  forState:UIControlStateNormal
                                barMetrics:UIBarMetricsLandscapePhone];
        [item setBackButtonBackgroundImage:G6PillImage(p, dark, nil, YES, YES)
                                  forState:UIControlStateHighlighted
                                barMetrics:UIBarMetricsLandscapePhone];
        [item setBackButtonTitlePositionAdjustment:UIOffsetMake(3, 0) forBarMetrics:UIBarMetricsLandscapePhone];
        gPillHeightNow = kPillHeight;
    }
    UIFont *buttonFont = G6Font(G6FontMedium, 14);
    [item setTitleTextAttributes:G6TextAttributes(buttonFont, text) forState:UIControlStateNormal];
    [item setTitleTextAttributes:G6TextAttributes(buttonFont, [text colorWithAlphaComponent:0.45]) forState:UIControlStateHighlighted];
    [item setTitleTextAttributes:G6TextAttributes(buttonFont, [text colorWithAlphaComponent:0.30]) forState:UIControlStateDisabled];

    UITabBar *tab = [UITabBar appearance];
    if (g6_device_is_phone()) {
        [tab setBackgroundImage:G6TabCapsuleImage(p, dark)];
        [tab setShadowImage:G6ClearImage()];
        [tab setSelectionIndicatorImage:G6TabSelectionImage(dark)];
    } else {
        [tab setBackgroundImage:G6BarImage(p, 49)];
        [tab setShadowImage:hair];
        [tab setSelectionIndicatorImage:G6ClearImage()];
    }
    [tab setSelectedImageTintColor:accent];
    UITabBarItem *tabItem = [UITabBarItem appearance];
    UIFont *tabFont = G6Font(G6FontMedium, 10);
    [tabItem setTitleTextAttributes:G6TextAttributes(tabFont, [UIColor colorWithWhite:dark ? 0.62 : 0.50 alpha:1])
                           forState:UIControlStateNormal];
    [tabItem setTitleTextAttributes:G6TextAttributes(tabFont, accent) forState:UIControlStateSelected];
    [tabItem setTitlePositionAdjustment:UIOffsetMake(0, g6_device_is_phone() ? -kTabTitleLift : 0)];

    UISearchBar *search = [UISearchBar appearance];
    [search setBackgroundImage:G6BarImage(p, 44)];
    [search setSearchFieldBackgroundImage:G6FieldImage(p) forState:UIControlStateNormal];
}

// Trả mọi thứ về mặc định của iOS 6 (ảnh nil = kiểu gốc)
static void G6ResetStyle(void) {
    UINavigationBar *nav = [UINavigationBar appearance];
    [nav setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
    [nav setBackgroundImage:nil forBarMetrics:UIBarMetricsLandscapePhone];
    [nav setShadowImage:nil];
    [nav setTitleTextAttributes:nil];

    UIToolbar *toolbar = [UIToolbar appearance];
    [toolbar setBackgroundImage:nil forToolbarPosition:G6ToolbarPositionAny barMetrics:UIBarMetricsDefault];
    [toolbar setBackgroundImage:nil forToolbarPosition:G6ToolbarPositionAny barMetrics:UIBarMetricsLandscapePhone];
    [toolbar setShadowImage:nil forToolbarPosition:G6ToolbarPositionAny];

    UIBarButtonItem *item = [UIBarButtonItem appearance];
    for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
        UIControlState s = state.unsignedIntegerValue;
        [item setBackgroundImage:nil forState:s barMetrics:UIBarMetricsDefault];
        [item setBackgroundImage:nil forState:s style:UIBarButtonItemStyleDone barMetrics:UIBarMetricsDefault];
        [item setBackButtonBackgroundImage:nil forState:s barMetrics:UIBarMetricsDefault];
        [item setBackgroundImage:nil forState:s barMetrics:UIBarMetricsLandscapePhone];
        [item setBackgroundImage:nil forState:s style:UIBarButtonItemStyleDone barMetrics:UIBarMetricsLandscapePhone];
        [item setBackButtonBackgroundImage:nil forState:s barMetrics:UIBarMetricsLandscapePhone];
    }
    [item setBackButtonTitlePositionAdjustment:UIOffsetZero forBarMetrics:UIBarMetricsDefault];
    [item setBackButtonTitlePositionAdjustment:UIOffsetZero forBarMetrics:UIBarMetricsLandscapePhone];
    for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted), @(UIControlStateDisabled)]) {
        [item setTitleTextAttributes:nil forState:state.unsignedIntegerValue];
    }

    UITabBar *tab = [UITabBar appearance];
    [tab setBackgroundImage:nil];
    [tab setShadowImage:nil];
    [tab setSelectionIndicatorImage:nil];
    [tab setSelectedImageTintColor:nil];
    UITabBarItem *tabItem = [UITabBarItem appearance];
    [tabItem setTitleTextAttributes:nil forState:UIControlStateNormal];
    [tabItem setTitleTextAttributes:nil forState:UIControlStateSelected];
    [tabItem setTitlePositionAdjustment:UIOffsetZero];

    UISearchBar *search = [UISearchBar appearance];
    [search setBackgroundImage:nil];
    [search setSearchFieldBackgroundImage:nil forState:UIControlStateNormal];
}

// Tiêu đề trên thanh (UINavigationItemView) tự vẽ chữ và không vẽ lại khi kiểu chữ của thanh đổi: bảo nó vẽ lại
static void G6RedrawBarTitles(UIView *view, Class titleClass) {
    if ([view isKindOfClass:[UISearchBar class]]) {
        [view setNeedsLayout];
        return;
    }
    if ([view isKindOfClass:[UINavigationBar class]]) {
        [view setNeedsLayout];
        Class buttonClass = objc_getClass("UINavigationButton");
        for (UIView *sub in view.subviews) {
            if (titleClass && [sub isKindOfClass:titleClass]) [sub setNeedsDisplay];
            // Nút có hình (dấu cộng, mũi tên chia sẻ…): ảnh của nút đã được tô theo màu của chế độ cũ lúc nút sinh ra, UIKit không
            // tô lại nữa (đã gặp: tối → sáng, hình còn trắng trên viên nút sáng nên mất hút; bắt nút xếp lại cũng không ăn) → tô
            // lại chính ảnh đó bằng màu chữ hiện hành. Ảnh chỉ còn hình + độ đục (bóng chìm đã bỏ từ lúc tô đầu) nên tô lại là đúng.
            else if (buttonClass && [sub isKindOfClass:buttonClass] && [sub isKindOfClass:[UIButton class]]) {
                UIButton *button = (UIButton *)sub;
                UIImage *image = [button imageForState:UIControlStateNormal];
                if (image) {
                    // Màu đặc: độ đục của hình đã nằm sẵn trong ảnh — tô bằng màu có độ đục thì mỗi lần đổi chế độ hình nhạt thêm
                    UIColor *color = gActive ? [G6UIBarTextColor() colorWithAlphaComponent:1] : [UIColor whiteColor];
                    [button setImage:G6UITintedImage(image, color) forState:UIControlStateNormal];
                }
            }
        }
        return;
    }
    for (UIView *sub in view.subviews) G6RedrawBarTitles(sub, titleClass);
}

// Thanh điều hướng KHÔNG nằm trong cửa sổ lúc đổi kiểu (thẻ khác của thanh thẻ, màn nằm dưới một màn khác): lượt làm mới ở
// trên không tới được nó → tiêu đề còn màu của chế độ cũ (đã gặp trên iPhone: chữ tối trên thanh tối). Nhớ kiểu đã vẽ trên
// từng thanh; lúc thanh trở lại cửa sổ mà kiểu đã khác thì vẽ lại.
static char kBarSignatureKey;
static void (*orig_navDidMove)(UINavigationBar *, SEL);
static void repl_navDidMove(UINavigationBar *self, SEL _cmd) {
    orig_navDidMove(self, _cmd);
    @try {
        if (!self.window || !gSignature) return;
        NSString *drawn = objc_getAssociatedObject(self, &kBarSignatureKey);
        if (drawn && ![drawn isEqualToString:gSignature]) G6RedrawBarTitles(self, objc_getClass("UINavigationItemView"));
        objc_setAssociatedObject(self, &kBarSignatureKey, gSignature, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (NSException *e) {
    }
}

// View đang giữ con trỏ nhập (nếu có) trong cây con của `view`
static UIView *G6FirstResponderIn(UIView *view, int depth) {
    if (view.isFirstResponder) return view;
    if (depth <= 0) return nil;
    for (UIView *sub in view.subviews) {
        UIView *found = G6FirstResponderIn(sub, depth - 1);
        if (found) return found;
    }
    return nil;
}

void G6UIRefreshAppearance(void) {
    // UIAppearance chỉ áp vào view lúc view vào cửa sổ: gỡ từng view gốc ra rồi gắn lại đúng chỗ cũ
    Class titleClass = objc_getClass("UINavigationItemView");
    // Gỡ view khỏi cửa sổ là ô đang gõ mất con trỏ và bàn phím thu xuống (đã gặp khi đổi sáng ↔ tối lúc đang gõ) → nhớ ô đó,
    // gắn lại xong thì trả con trỏ
    // Thứ giữ con trỏ có thể KHÔNG phải view: màn trò chuyện của Tin nhắn để chính view controller làm «first responder» (để
    // thanh nhập — phụ kiện bàn phím — luôn hiện). Đã gặp: đổi sáng ↔ tối lúc đang mở cuộc trò chuyện là thanh nhập biến mất
    // cho tới khi chọn lại cuộc trò chuyện. → hỏi thẳng cửa sổ (hàm riêng -firstResponder của UIWindow), không có mới dò view.
    UIResponder *responder = nil;
    SEL firstResponderSel = NSSelectorFromString(@"firstResponder");
    Class textEffects = objc_getClass("UITextEffectsWindow");
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (responder) break;
        if ([window respondsToSelector:firstResponderSel]) {
            id found = ((id (*)(id, SEL))objc_msgSend)(window, firstResponderSel);
            if ([found isKindOfClass:[UIResponder class]]) responder = found;
        }
        if (!responder) responder = G6FirstResponderIn(window, 30);
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        // Cửa sổ của bàn phím / phụ kiện bàn phím: không gỡ – gắn (bàn phím có kiểu riêng, không qua UIAppearance; gỡ view gốc
        // của nó là phụ kiện đang hiện bị bỏ rơi)
        if (textEffects && [window isKindOfClass:textEffects]) continue;
        for (UIView *view in [window.subviews copy]) {
            NSUInteger index = [window.subviews indexOfObject:view];
            [view removeFromSuperview];
            [window insertSubview:view atIndex:index];
        }
        G6RedrawBarTitles(window, titleClass);
    }
    // View đã rời cửa sổ thì thôi; controller thì cứ trả lại (view của nó vừa được gắn lại ở trên)
    BOOL stillThere = [responder isKindOfClass:[UIView class]] ? ((UIView *)responder).window != nil : responder != nil;
    if (stillThere && !responder.isFirstResponder) [responder becomeFirstResponder];
}

BOOL G6UIBarsApply(BOOL allowed) {
    BOOL active = allowed && G6Feature(@"apps") && G6Feature(@"bars");
    BOOL dark = active && G6UIDark();
    NSString *signature = [NSString stringWithFormat:@"%d|%d", active, dark];
    if ([signature isEqualToString:gSignature]) return NO;
    BOOL first = gSignature == nil;
    gSignature = signature;
    gActive = active;
    gDark = dark;
    if (active) {
        G6InstallHooks();
        G6ApplyStyle(dark);
    } else if (!first) {
        G6ResetStyle();
    }
    G6Log(@"thanh: %@", active ? (dark ? @"kiểu mới (tối)" : @"kiểu mới (sáng)") : @"kiểu gốc");
    // Lần đầu (app chưa có view nào) thì không có gì để làm mới
    return !first;
}
