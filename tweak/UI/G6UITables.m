// Bảng kiểu nhóm trong app (thành phần «tables»): nền, ô, chữ trong ô.
//
// iOS 6: nền sọc / xám xanh, ô trắng viền xám có bóng chìm. Kiểu mới: nền phẳng, ô phẳng bo góc rộng hơn, không viền, nét ngăn
// mảnh. Ở chế độ tối, nền đen và ô màu than — khi đó chữ sẫm trong ô (đen, xanh xám) phải đổi sang sáng mới đọc được.
//
// Cách làm (lớp riêng của UIKit, tra lúc chạy — thiếu thì phần đó tự bỏ qua):
//   - UIGroupTableViewCellBackground vẽ nền ô theo các hàm màu `_fillColor`, `_sectionBorderColor`, `_separatorColor`,
//     `_topShadowColor`, `_bottomShadowColor` và hình `_roundedRectBezierPathInRect:…` → ghi đè các hàm đó. Ảnh nền ô được nhớ
//     theo khoá: đổi kiểu thì bảo lớp xoá bộ nhớ (`+_flushCacheOnNotification:`) rồi vẽ lại các ô đang hiện.
//   - UITableViewBackgroundView (nền của bảng nhóm) chứa một UIImageView → ẩn ảnh, đặt màu nền.
//   - Chữ: lúc ô xếp lại con (`-[UITableViewCell layoutSubviews]`), nhãn và ô nhập trong ô có màu chữ sẫm được đổi sang màu
//     sáng tương ứng (giữ sắc độ), màu gốc được nhớ để trả lại khi về chế độ sáng. Chỉ áp cho ô của bảng nhóm (ô có nền là
//     UIGroupTableViewCellBackground) — ô tự vẽ của app không bị đụng.
//   - Nền của nhãn: iOS 6 tô sẵn nền đục cho nhãn trong ô bằng màu nền của ô (`-[UITableViewCell _contentBackgroundColor]`,
//     trắng) để vẽ nhanh → ở chế độ tối phải trả màu than, kẻo mỗi nhãn là một hộp trắng.
//   - Hình nhỏ một màu sẫm trong ô (ổ khoá, vạch sóng Wi-Fi, dấu chọn) được đổi thành bản màu sáng — xem G6LightGlyph.
//   - Bảng THƯỜNG (không chia nhóm) ở chế độ tối: bảng nền trắng đục thành nền đen, ô đen, nét ngăn sáng mờ, chữ trong ô đổi
//     sáng — nhưng CHỈ khi mọi ô đang hiện của bảng chỉ gồm thành phần chuẩn của UIKit (nhãn, ảnh, nút). Gặp một ô có view
//     của riêng app (app tự vẽ chữ, Glass 6 không đổi màu được) thì cả bảng đó được trả về sáng và không đụng nữa: thà sáng
//     đều còn hơn nền đen chữ đen. Bảng trong suốt / có màu riêng không bị đụng.
//     App đã thử và bật G6UITablesSetInvertCustomCells (iPhone: app Điện thoại…): ở chế độ tối, MỌI bảng của app đó — bảng
//     thường nền trắng lẫn bảng nhóm — được dựng theo bảng màu SÁNG như thường lệ rồi cả bảng mang một bộ lọc «đảo sáng tối,
//     giữ sắc màu»: nền trắng → đen, chữ đen → sáng, chữ xanh vẫn xanh, kể cả chữ app / thư viện tự vẽ (ô của Gần đây, trang
//     chi tiết liên hệ của AddressBookUI). (Đã thử gắn bộ lọc vào từng ô còn nền bảng tô đen: iOS 6 lan màu nền của bảng
//     xuống ô nên ô đảo xong lại thành trắng.) Thứ nằm trong bảng mà đã theo kiểu tối chuẩn (ô tìm kiếm ở đầu bảng) và ảnh
//     thật (UIImageView cỡ ≥ 28 điểm không phải ảnh kéo giãn, view ảnh riêng của thư viện) mang thêm một lần lọc nữa để về
//     đúng màu; bảng lồng trong một bảng đã đảo thì không đảo thêm.
//   - Riêng app Cài đặt trên iPad: cột trái là bảng thường nằm trên PSGradientView (dải màu xám xanh). Ở chế độ tối cột đó
//     cũng phải tối, nên với app này ô của bảng thường cũng được đổi chữ và dải màu được thay (G6UITablesSetSidebar).
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static BOOL gActive, gDark;
// App Cài đặt: đổi cả ô của bảng thường (cột trái) và dải màu nền của cột đó
static BOOL gSidebar;
static NSString *gSignature;
static Class gCellBackgroundClass, gTableBackgroundClass;

// Bo góc của ô nhóm rộng thêm chừng này điểm so với iOS 6
static const CGFloat kExtraRadius = 3;

static char kOriginalColorKey, kOriginalShadowKey, kOriginalBackgroundKey, kOriginalGradientKey;
// Bảng thường: trạng thái (1 = Glass 6 đang tô tối, 2 = có ô tự vẽ → bỏ qua), màu nền / nét ngăn gốc; ô: màu nền gốc
// (trạng thái 3 = cả bảng mang bộ lọc đảo — xem G6UITablesSetInvertCustomCells)
static char kPlainStateKey, kPlainBackgroundKey, kPlainSeparatorKey, kPlainCellKey, kInvertedCellKey, kInvertKeepKey;

static UIColor *G6GroupBackgroundColor(void) {
    return gDark ? [UIColor blackColor] : [UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1];
}

static UIColor *G6CellFill(BOOL dark) {
    return dark ? [UIColor colorWithRed:0.11 green:0.11 blue:0.118 alpha:1] : [UIColor whiteColor];
}

static UIColor *G6CellFillColor(void) {
    return G6CellFill(gDark);
}

// Nền bảng thường và ô của nó ở chế độ tối
static UIColor *G6PlainFill(void) {
    return [UIColor blackColor];
}

static UIColor *G6SeparatorColor(void) {
    return gDark ? [UIColor colorWithWhite:1 alpha:0.14] : [UIColor colorWithWhite:0 alpha:0.14];
}

// ---- Nền ô nhóm ----

// Thành phần đỏ / lục / lam của một màu, dù màu ở hệ RGB hay hệ xám (getWhite: không đọc được màu RGB và ngược lại)
static BOOL G6ColorRGBA(UIColor *color, CGFloat *r, CGFloat *g, CGFloat *b, CGFloat *a) {
    if ([color getRed:r green:g blue:b alpha:a]) return YES;
    CGFloat w = 0;
    if (![color getWhite:&w alpha:a]) return NO;
    *r = *g = *b = w;
    return YES;
}

static UIColor *(*orig_fillColor)(id, SEL);
static UIColor *repl_fillColor(id self, SEL _cmd) {
    UIColor *own = orig_fillColor(self, _cmd);
    if (!gActive) return own;
    // Chỉ thay màu trắng mặc định của ô; ô đang được chọn / ô app tự đặt màu: để nguyên
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (G6ColorRGBA(own, &r, &g, &b, &a) && r > 0.94 && g > 0.94 && b > 0.94 && a > 0.99) return G6CellFillColor();
    return own;
}

static UIColor *(*orig_borderColor)(id, SEL);
static UIColor *repl_borderColor(id self, SEL _cmd) {
    return gActive ? [UIColor clearColor] : orig_borderColor(self, _cmd);
}

static UIColor *(*orig_separatorColor)(id, SEL);
static UIColor *repl_separatorColor(id self, SEL _cmd) {
    return gActive ? G6SeparatorColor() : orig_separatorColor(self, _cmd);
}

static UIColor *(*orig_topShadowColor)(id, SEL);
static UIColor *repl_topShadowColor(id self, SEL _cmd) {
    return gActive ? [UIColor clearColor] : orig_topShadowColor(self, _cmd);
}

static UIColor *(*orig_bottomShadowColor)(id, SEL);
static UIColor *repl_bottomShadowColor(id self, SEL _cmd) {
    return gActive ? [UIColor clearColor] : orig_bottomShadowColor(self, _cmd);
}

static id (*orig_roundedPath)(id, SEL, CGRect, int, BOOL, float);
static id repl_roundedPath(id self, SEL _cmd, CGRect rect, int location, BOOL border, float adjustment) {
    return orig_roundedPath(self, _cmd, rect, location, border, gActive ? adjustment + kExtraRadius : adjustment);
}

// iPhone: bảng nhóm của iOS 6 dùng nét ngăn «chạm khắc» (UITableViewCellSeparatorStyleSingleLineEtched = 2): dưới mỗi nét
// ngăn có thêm một nét trắng — trên ô trắng thì không thấy, trên ô tối thành một vạch trắng. Kiểu mới chỉ dùng nét đơn (1).
static void (*orig_setSeparatorStyle)(id, SEL, int);
static void repl_setSeparatorStyle(id self, SEL _cmd, int style) {
    orig_setSeparatorStyle(self, _cmd, gActive && style == 2 ? 1 : style);
}

// ---- Nền của bảng nhóm ----

static void G6StyleTableBackground(UIView *view) {
    // iPad: một UIImageView (dải màu). iPhone: thêm một UIView tô màu hoa văn sọc dọc của iOS 6 — ẩn cả hai.
    for (UIView *sub in view.subviews) sub.hidden = gActive;
    view.backgroundColor = gActive ? G6GroupBackgroundColor() : [UIColor clearColor];
}

static void (*orig_tableBgLayout)(UIView *, SEL);
static void repl_tableBgLayout(UIView *self, SEL _cmd) {
    orig_tableBgLayout(self, _cmd);
    G6StyleTableBackground(self);
}

// ---- Chữ trong ô ở chế độ tối ----

// Màu chữ sẫm → màu sáng cùng sắc độ; màu đã sáng thì trả nil (để nguyên)
static UIColor *G6LightenedTextColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!G6ColorRGBA(color, &r, &g, &b, &a)) return nil;
    CGFloat luma = 0.299 * r + 0.587 * g + 0.114 * b;
    if (luma > 0.55 || a < 0.05) return nil;
    CGFloat h = 0, s = 0, v = 0;
    [[UIColor colorWithRed:r green:g blue:b alpha:1] getHue:&h saturation:&s brightness:&v alpha:NULL];
    // Chữ gần đen → gần trắng; chữ có màu (xanh xám của ô giá trị) → cùng màu nhưng sáng và nhạt hơn
    return [UIColor colorWithHue:h saturation:s * 0.55 brightness:1 - 0.18 * luma alpha:a];
}

static BOOL G6ColorNear(UIColor *x, UIColor *y) {
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0, r2 = 0, g2 = 0, b2 = 0, a2 = 0;
    if (!G6ColorRGBA(x, &r1, &g1, &b1, &a1) || !G6ColorRGBA(y, &r2, &g2, &b2, &a2)) return NO;
    return fabs(r1 - r2) < 0.015 && fabs(g1 - g2) < 0.015 && fabs(b1 - b2) < 0.015 && fabs(a1 - a2) < 0.015;
}

// Nền đục của nhãn trong ô nhóm. iOS 6 tô sẵn cho nhãn màu nền của ô (xám rất nhạt 0,97) để vẽ nhanh; ô của Glass 6 lại màu
// khác (trắng tinh ở chế độ sáng, than ở chế độ tối) → nền nhãn phải đổi theo ở CẢ HAI chế độ, không thì sau chữ lộ một dải
// lệch màu. Nền gốc được nhớ để trả lại khi tắt thành phần.
static void G6FixLabelBackground(UIView *view, UIColor *fill) {
    UIColor *saved = objc_getAssociatedObject(view, &kOriginalBackgroundKey);
    // fill = nil: ô không còn do Glass 6 tô (tắt thành phần, bảng thường về sáng) → trả nền gốc
    if (!fill) {
        if (saved) {
            view.backgroundColor = saved;
            objc_setAssociatedObject(view, &kOriginalBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    UIColor *bg = view.backgroundColor;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    // Nền trong suốt (ô đang được chọn…): để nguyên
    if (!bg || !G6ColorRGBA(bg, &r, &g, &b, &a) || a < 0.99 || G6ColorNear(bg, fill)) return;
    BOOL stock = r > 0.85 && g > 0.85 && b > 0.85;
    // Màu ô Glass 6 đã đặt ở chế độ / kiểu bảng khác (vừa đổi sáng ↔ tối)
    BOOL ours = G6ColorNear(bg, G6CellFill(YES)) || G6ColorNear(bg, G6CellFill(NO)) || G6ColorNear(bg, G6PlainFill());
    if (!stock && !ours) return;
    if (!saved && !ours) objc_setAssociatedObject(view, &kOriginalBackgroundKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = fill;
}

// `fixBackground`: nhãn nằm trong ô mà nền do ta đổi màu (ô nhóm, ô bảng thường đang tô tối) — nền đục của nhãn phải theo màu
// `fill` (nil = trả nền gốc). Ô của cột trái Cài đặt thì không đụng nền nhãn: UIKit tự đưa chúng về trong suốt, ta mà nhớ «nền
// gốc» lúc đó là nhớ nhầm màu trắng tạm.
// `lighten`: ô này đang được Glass 6 tô tối → chữ sẫm đổi sang sáng; NO → trả màu chữ gốc (ô không còn được tô: chế độ sáng,
// bảng thường bị bỏ qua vì có ô tự vẽ…).
static void G6RecolorTextView(UIView *view, BOOL fixBackground, UIColor *fill, BOOL lighten) {
    BOOL isLabel = [view isKindOfClass:[UILabel class]];
    if (!isLabel && ![view isKindOfClass:[UITextField class]]) return;
    UILabel *label = (UILabel *)view;  // UITextField cũng có textColor / setTextColor:
    if (isLabel && fixBackground) G6FixLabelBackground(view, fill);
    UIColor *original = objc_getAssociatedObject(view, &kOriginalColorKey);
    if (lighten) {
        UIColor *current = label.textColor;
        // Màu hiện tại khác màu ta đã đặt lần trước = app vừa đặt lại (ô dùng lại) → đó là màu gốc mới
        UIColor *applied = original ? G6LightenedTextColor(original) : nil;
        if (!applied || ![current isEqual:applied]) {
            UIColor *lighter = G6LightenedTextColor(current);
            if (!lighter) return;
            objc_setAssociatedObject(view, &kOriginalColorKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            label.textColor = lighter;
        }
        // Bóng chữ trắng của iOS 6 (tiêu đề nhóm, chú thích) dưới chữ sáng thành vệt nhoè: bỏ ở mọi lượt, vì UIKit / app có
        // thể đặt lại bóng sau lượt đầu
        if (isLabel && label.shadowColor && objc_getAssociatedObject(view, &kOriginalColorKey)) {
            objc_setAssociatedObject(view, &kOriginalShadowKey, label.shadowColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            label.shadowColor = nil;
        }
    } else if (original) {
        // Xoá dấu «màu gốc» TRƯỚC khi gán lại: hàm móc setTextColor: / setShadowColor: thấy nhãn còn dấu (và máy đang ở chế
        // độ tối) sẽ làm sáng màu vừa trả — ô của bảng bị bỏ qua thành chữ trắng trên nền trắng
        UIColor *shadow = objc_getAssociatedObject(view, &kOriginalShadowKey);
        objc_setAssociatedObject(view, &kOriginalColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kOriginalShadowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        label.textColor = original;
        if (isLabel && shadow) label.shadowColor = shadow;
    }
}

// App đặt lại màu chữ cho một nhãn ta đã đổi (ô dùng lại, mạng Wi-Fi đổi trạng thái…) mà không xếp lại ô: đổi tiếp ngay tại
// đây. Chỉ đụng nhãn đã từng được đổi (có màu gốc đang nhớ) — nhãn khác đi thẳng.
static void (*orig_labelSetTextColor)(UILabel *, SEL, UIColor *);
static void repl_labelSetTextColor(UILabel *self, SEL _cmd, UIColor *color) {
    if (gActive && gDark && color && objc_getAssociatedObject(self, &kOriginalColorKey)) {
        UIColor *lighter = G6LightenedTextColor(color);
        if (lighter) {
            objc_setAssociatedObject(self, &kOriginalColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            orig_labelSetTextColor(self, _cmd, lighter);
            return;
        }
    }
    orig_labelSetTextColor(self, _cmd, color);
}

// Như trên cho bóng chữ: nhãn đã đổi sang chữ sáng thì không nhận lại bóng (nhớ để trả khi về sáng)
static void (*orig_labelSetShadowColor)(UILabel *, SEL, UIColor *);
static void repl_labelSetShadowColor(UILabel *self, SEL _cmd, UIColor *color) {
    if (gActive && gDark && color && objc_getAssociatedObject(self, &kOriginalColorKey)) {
        objc_setAssociatedObject(self, &kOriginalShadowKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        orig_labelSetShadowColor(self, _cmd, nil);
        return;
    }
    orig_labelSetShadowColor(self, _cmd, color);
}

static void G6RecolorTree(UIView *view, int depth, BOOL fixBackground, UIColor *fill, BOOL lighten) {
    G6RecolorTextView(view, fixBackground, fill, lighten);
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6RecolorTree(sub, depth - 1, fixBackground, fill, lighten);
}

// ---- Hình nhỏ một màu sẫm trong ô (ổ khoá, vạch sóng Wi-Fi, dấu chọn…) ở chế độ tối ----
// iOS 6 vẽ các hình này màu đen có viền sáng chìm bên dưới — trên ô màu than gần như không thấy. Hình nhỏ (≤ 24 điểm mỗi
// chiều) mà phần lớn điểm ảnh sẫm thì đổi thành cùng hình màu sáng (bỏ luôn viền sáng chìm). Biểu tượng nhiều màu, hình xám
// vừa (mũi tên chỉ sang), hình đã có màu sáng thì để nguyên. Kết quả nhớ theo từng UIImage (các ô dùng chung một ảnh).

static char kLightGlyphKey, kOriginalImageKey;
static const CGFloat kGlyphMaxSide = 24;

// Ảnh sáng của một hình sẫm; nil nếu ảnh không phải hình một màu sẫm
static UIImage *G6LightGlyph(UIImage *image) {
    id cached = objc_getAssociatedObject(image, &kLightGlyphKey);
    if (cached) return cached == [NSNull null] ? nil : cached;
    UIImage *result = nil;
    CGSize size = image.size;
    CGFloat scale = image.scale > 0 ? image.scale : 1;
    size_t w = (size_t)lround(size.width * scale), h = (size_t)lround(size.height * scale);
    if (w >= 4 && h >= 4 && size.width <= kGlyphMaxSide && size.height <= kGlyphMaxSide && image.CGImage) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSMutableData *data = [NSMutableData dataWithLength:w * h * 4];
        CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, w, h, 8, w * 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        if (ctx) {
            CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image.CGImage);
            uint8_t *px = data.mutableBytes;
            double dark = 0, total = 0;
            for (size_t i = 0; i < w * h; i++) {
                double a = px[i * 4 + 3] / 255.0;
                if (a < 0.15) continue;
                // Điểm ảnh nhân sẵn alpha → màu thật
                double luma = (0.299 * px[i * 4] + 0.587 * px[i * 4 + 1] + 0.114 * px[i * 4 + 2]) / 255.0 / a;
                total += a;
                if (luma < 0.35) dark += a;
            }
            if (total > 0 && dark / total >= 0.6) {
                for (size_t i = 0; i < w * h; i++) {
                    double a = px[i * 4 + 3] / 255.0;
                    double luma = a > 0.01 ? (0.299 * px[i * 4] + 0.587 * px[i * 4 + 1] + 0.114 * px[i * 4 + 2]) / 255.0 / a : 1;
                    // Điểm sẫm → sáng, giữ độ đục; điểm sáng (viền chìm) → trong suốt
                    double keep = a * MAX(0, MIN(1, (0.6 - luma) / 0.3));
                    uint8_t v = (uint8_t)lround(238 * keep);
                    px[i * 4] = px[i * 4 + 1] = px[i * 4 + 2] = v;
                    px[i * 4 + 3] = (uint8_t)lround(255 * keep);
                }
                CGImageRef out = CGBitmapContextCreateImage(ctx);
                if (out) {
                    result = [UIImage imageWithCGImage:out scale:scale orientation:image.imageOrientation];
                    CGImageRelease(out);
                }
            }
            CGContextRelease(ctx);
        }
        CGColorSpaceRelease(space);
    }
    objc_setAssociatedObject(image, &kLightGlyphKey, result ?: (id)[NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

static void (*orig_imageViewSetImage)(UIImageView *, SEL, UIImage *);

// Gán ảnh không qua hàm móc setImage: của chính tệp này (kẻo nó đổi / xoá dấu «ảnh gốc» lần nữa)
static void G6SetImageDirect(UIImageView *view, UIImage *image) {
    if (orig_imageViewSetImage) orig_imageViewSetImage(view, @selector(setImage:), image);
    else view.image = image;
}

static void G6RecolorGlyph(UIImageView *view, BOOL lighten) {
    UIImage *original = objc_getAssociatedObject(view, &kOriginalImageKey);
    UIImage *current = view.image;
    if (lighten) {
        if (!current) return;
        // Ảnh đang hiện chính là bản sáng ta đặt lần trước: xong
        if (original && current == G6LightGlyph(original)) return;
        UIImage *light = G6LightGlyph(current);
        if (!light) {
            if (original) objc_setAssociatedObject(view, &kOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        objc_setAssociatedObject(view, &kOriginalImageKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        G6SetImageDirect(view, light);
    } else if (original) {
        objc_setAssociatedObject(view, &kOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (current == G6LightGlyph(original)) G6SetImageDirect(view, original);
    }
}

// App gán ảnh mới cho một hình nhỏ nằm trong ô mà không xếp lại ô (danh sách Wi-Fi cập nhật vạch sóng, ổ khoá): đổi ngay tại
// đây. Ảnh lớn hơn cỡ hình nhỏ, hoặc view không nằm trong ô của bảng, đi thẳng.
static void repl_imageViewSetImage(UIImageView *self, SEL _cmd, UIImage *image) {
    if (gActive && gDark && image && image.size.width <= kGlyphMaxSide && image.size.height <= kGlyphMaxSide) {
        // Chỉ trong ô đang được Glass 6 tô tối (ô có dấu «đang quản»): ô để sáng thì hình sẫm phải giữ nguyên
        BOOL inCell = NO;
        UIView *v = self.superview;
        for (int i = 0; v && i < 4 && !inCell; i++, v = v.superview) {
            if ([v isKindOfClass:[UIControl class]]) break;
            if ([v isKindOfClass:[UITableViewCell class]]) {
                inCell = objc_getAssociatedObject(v, &kOriginalColorKey) != nil;
                break;
            }
        }
        UIImage *light = inCell ? G6LightGlyph(image) : nil;
        if (light) {
            objc_setAssociatedObject(self, &kOriginalImageKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            orig_imageViewSetImage(self, _cmd, light);
            return;
        }
    }
    if (image && objc_getAssociatedObject(self, &kOriginalImageKey)) {
        objc_setAssociatedObject(self, &kOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    orig_imageViewSetImage(self, _cmd, image);
}

// Đi cây con của ô tìm UIImageView nhỏ; không vào công tắc, nút, nền ô
static void G6RecolorGlyphs(UIView *view, int depth, BOOL lighten) {
    if ([view isKindOfClass:[UIImageView class]]) {
        G6RecolorGlyph((UIImageView *)view, lighten);
        return;
    }
    if (depth <= 0 || [view isKindOfClass:[UIControl class]]) return;
    if (gCellBackgroundClass && [view isKindOfClass:gCellBackgroundClass]) return;
    for (UIView *sub in view.subviews) G6RecolorGlyphs(sub, depth - 1, lighten);
}

// ---- Phụ kiện chuẩn của ô (mũi tên chỉ sang, dấu chọn) ở chế độ tối ----
// UIKit đặt phụ kiện chuẩn trong một UIButton không nhận chạm, con trực tiếp của ô (tra trên máy 19/11/2026); hình là ảnh của
// nút ở trạng thái thường. Phần «hình nhỏ» ở trên cố ý không vào nút nên hai hình này còn nguyên: dấu chọn xanh sẫm
// (50, 79, 133) và mũi tên trên ô đen gần như mất. Đổi ảnh của nút: hình có màu → xanh sáng, hình xám / đen → trắng mờ; viền
// sáng chìm bỏ. Nút «chi tiết» (hình tròn xanh, nhận chạm) không đụng.

static char kAccessoryGlyphKey, kAccessoryOriginalKey;

// Ảnh phụ kiện cho ô tối; nil nếu ảnh quá lớn hoặc không có điểm ảnh nào dùng được. Nhớ theo từng UIImage.
static UIImage *G6AccessoryGlyph(UIImage *image) {
    id cached = objc_getAssociatedObject(image, &kAccessoryGlyphKey);
    if (cached) return cached == [NSNull null] ? nil : cached;
    UIImage *result = nil;
    CGSize size = image.size;
    CGFloat scale = image.scale > 0 ? image.scale : 1;
    size_t w = (size_t)lround(size.width * scale), h = (size_t)lround(size.height * scale);
    if (w >= 4 && h >= 4 && size.width <= kGlyphMaxSide && size.height <= kGlyphMaxSide && image.CGImage) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSMutableData *data = [NSMutableData dataWithLength:w * h * 4];
        CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, w, h, 8, w * 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        if (ctx) {
            CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image.CGImage);
            uint8_t *px = data.mutableBytes;
            // Lượt 1: hình này có màu (dấu chọn) hay xám / đen (mũi tên)? Chỉ xét phần nét, bỏ viền sáng chìm.
            double saturation = 0, total = 0;
            for (size_t i = 0; i < w * h; i++) {
                double a = px[i * 4 + 3] / 255.0;
                if (a < 0.15) continue;
                double r = px[i * 4] / 255.0 / a, g = px[i * 4 + 1] / 255.0 / a, b = px[i * 4 + 2] / 255.0 / a;
                if (0.299 * r + 0.587 * g + 0.114 * b > 0.8) continue;
                double hi = MAX(r, MAX(g, b)), lo = MIN(r, MIN(g, b));
                saturation += a * (hi > 0.01 ? (hi - lo) / hi : 0);
                total += a;
            }
            if (total > 0) {
                BOOL colorful = saturation / total > 0.3;
                // Xanh sáng của chế độ tối / trắng mờ (như mũi tên của iPadOS)
                double tr = colorful ? 0.04 : 1, tg = colorful ? 0.52 : 1, tb = 1, gain = colorful ? 1.0 : 0.42;
                for (size_t i = 0; i < w * h; i++) {
                    double a = px[i * 4 + 3] / 255.0;
                    double luma = a > 0.01 ? (0.299 * px[i * 4] + 0.587 * px[i * 4 + 1] + 0.114 * px[i * 4 + 2]) / 255.0 / a : 1;
                    // Nét (sẫm hoặc xám vừa) giữ độ đục; viền sáng chìm → trong suốt
                    double keep = a * MAX(0, MIN(1, (0.85 - luma) / 0.25)) * gain;
                    px[i * 4] = (uint8_t)lround(255 * tr * keep);
                    px[i * 4 + 1] = (uint8_t)lround(255 * tg * keep);
                    px[i * 4 + 2] = (uint8_t)lround(255 * tb * keep);
                    px[i * 4 + 3] = (uint8_t)lround(255 * keep);
                }
                CGImageRef out = CGBitmapContextCreateImage(ctx);
                if (out) {
                    result = [UIImage imageWithCGImage:out scale:scale orientation:image.imageOrientation];
                    CGImageRelease(out);
                }
            }
            CGContextRelease(ctx);
        }
        CGColorSpaceRelease(space);
    }
    objc_setAssociatedObject(image, &kAccessoryGlyphKey, result ?: (id)[NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

static void G6RecolorAccessory(UITableViewCell *cell, BOOL lighten) {
    for (UIView *sub in cell.subviews) {
        if (![sub isMemberOfClass:[UIButton class]] || sub.userInteractionEnabled) continue;
        UIButton *button = (UIButton *)sub;
        UIImage *original = objc_getAssociatedObject(button, &kAccessoryOriginalKey);
        UIImage *current = [button imageForState:UIControlStateNormal];
        if (lighten) {
            if (!current) continue;
            // Ảnh đang có chính là bản ta đặt lần trước: xong
            if (original && current == G6AccessoryGlyph(original)) continue;
            UIImage *light = G6AccessoryGlyph(current);
            objc_setAssociatedObject(button, &kAccessoryOriginalKey, light ? current : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (light) [button setImage:light forState:UIControlStateNormal];
        } else if (original) {
            objc_setAssociatedObject(button, &kAccessoryOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (current == G6AccessoryGlyph(original)) [button setImage:original forState:UIControlStateNormal];
        }
    }
}

// ---- Nút bo góc (UIButtonTypeRoundedRect) ở chế độ tối ----
// Nền của nút này chính là một UIGroupTableViewCellBackground nên đã theo màu ô (than) nhờ các hàm ở đầu tệp; còn chữ vẫn xanh
// sẫm mặc định (0,22 – 0,33 – 0,53) → gần như không đọc được. Chữ đang đúng màu mặc định thì đổi sang xanh sáng; app tự đặt
// màu khác thì để nguyên.
static char kButtonTitleKey;
static void (*orig_roundedButtonLayout)(UIButton *, SEL);
static void repl_roundedButtonLayout(UIButton *self, SEL _cmd) {
    orig_roundedButtonLayout(self, _cmd);
    @try {
        UIColor *saved = objc_getAssociatedObject(self, &kButtonTitleKey);
        if (gActive && gDark) {
            if (saved) return;
            UIColor *current = [self titleColorForState:UIControlStateNormal];
            if (!G6ColorNear(current, [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1])) return;
            objc_setAssociatedObject(self, &kButtonTitleKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self setTitleColor:[UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:1] forState:UIControlStateNormal];
        } else if (saved) {
            objc_setAssociatedObject(self, &kButtonTitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self setTitleColor:saved forState:UIControlStateNormal];
        }
    } @catch (NSException *e) {
    }
}

static BOOL G6IsGroupedCell(UITableViewCell *cell) {
    return gCellBackgroundClass && [cell.backgroundView isKindOfClass:gCellBackgroundClass];
}

// Màu nền UIKit tô sẵn cho các view con đục của ô (nhãn…): với ô nhóm là màu ô của Glass 6 (cả sáng lẫn tối)
static UIColor *(*orig_contentBackgroundColor)(UITableViewCell *, SEL);
static UIColor *repl_contentBackgroundColor(UITableViewCell *self, SEL _cmd) {
    if (gActive && G6IsGroupedCell(self)) return G6CellFillColor();
    if (gActive && gDark && objc_getAssociatedObject(self, &kPlainCellKey)) return G6PlainFill();
    return orig_contentBackgroundColor(self, _cmd);
}

// ---- Bảng thường (không chia nhóm) ở chế độ tối ----

static BOOL gPlainAllowed = YES;
// Chế độ tối bằng cách đảo màu cả bảng thay vì tô lại từng thứ (bật theo app, xem G6UI.h); gInvertAll = đang có hiệu lực
// (app đã bật + đang ở chế độ tối + máy có bộ lọc) — khi đó gDark là NO: mọi thứ trong bảng dựng theo bảng màu sáng.
static BOOL gInvertCustom, gInvertAll;

// Gắn / gỡ lần lọc thứ hai cho một view nằm trong bảng đang đảo màu (để nó về đúng màu của mình)
static void G6InvertKeepView(UIView *view, BOOL keep) {
    if (![view isKindOfClass:[UIView class]]) return;
    BOOL has = objc_getAssociatedObject(view, &kInvertKeepKey) != nil;
    if (keep && !has) {
        id filter = G6UISkinInvertFilter();
        if (!filter) return;
        view.layer.filters = @[filter];
        objc_setAssociatedObject(view, &kInvertKeepKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!keep && has) {
        view.layer.filters = nil;
        objc_setAssociatedObject(view, &kInvertKeepKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL G6TableIsInverted(UIView *table) {
    return table && objc_getAssociatedObject(table, &kInvertedCellKey) != nil;
}

// Ảnh thật trong vùng đang đảo màu: đảo thêm lần nữa để về đúng màu. Ảnh nhỏ (hình một màu: ống nghe, mũi tên…) và ảnh kéo
// giãn (nền, viền) thì để đảo theo bảng. View ảnh riêng của thư viện (tên lớp «…ImageView» mà không phải UIImageView — vd ảnh
// chân dung ABPersonImageView) cũng giữ màu; đã giữ cả view thì không xét con của nó nữa.
static void G6InvertKeepImages(UIView *view, BOOL on, int depth) {
    for (UIView *sub in view.subviews) {
        // Bảng lồng bên trong tự lo phần của nó
        if ([sub isKindOfClass:[UITableView class]]) continue;
        BOOL custom = ![sub isKindOfClass:[UIImageView class]] && [NSStringFromClass([sub class]) hasSuffix:@"ImageView"];
        if (custom) {
            G6InvertKeepView(sub, on);
            continue;
        }
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImage *image = [(UIImageView *)sub image];
            BOOL photo = on && image && image.size.width >= 28 && image.size.height >= 28 &&
                         UIEdgeInsetsEqualToEdgeInsets(image.capInsets, UIEdgeInsetsZero);
            G6InvertKeepView(sub, photo);
        }
        if (depth > 0) G6InvertKeepImages(sub, on, depth - 1);
    }
}

// Ô tìm kiếm (đã theo kiểu tối chuẩn) trong đầu bảng
static UIView *G6FindSearchBar(UIView *view, int depth) {
    if (!view) return nil;
    if ([view isKindOfClass:[UISearchBar class]]) return view;
    if (depth <= 0) return nil;
    for (UIView *sub in view.subviews) {
        UIView *found = G6FindSearchBar(sub, depth - 1);
        if (found) return found;
    }
    return nil;
}

// Gắn / gỡ bộ lọc đảo của cả bảng. Trong đầu / cuối bảng: ô tìm kiếm và ảnh thật giữ đúng màu.
static void G6InvertTable(UITableView *table, BOOL on) {
    // Bảng nằm trong một bảng đã đảo: không đảo thêm (hai lần đảo là về sáng)
    for (UIView *v = table.superview; on && v; v = v.superview) {
        if ([v isKindOfClass:[UITableView class]] && G6TableIsInverted(v)) on = NO;
    }
    BOOL has = G6TableIsInverted(table);
    if (on && !has) {
        id filter = G6UISkinInvertFilter();
        if (!filter) return;
        table.layer.filters = @[filter];
        objc_setAssociatedObject(table, &kInvertedCellKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!on && has) {
        table.layer.filters = nil;
        objc_setAssociatedObject(table, &kInvertedCellKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!on && !has) return;
    for (UIView *edge in @[table.tableHeaderView ?: (id)[NSNull null], table.tableFooterView ?: (id)[NSNull null]]) {
        if (![edge isKindOfClass:[UIView class]]) continue;
        UIView *search = G6FindSearchBar(edge, 2);
        if (search) G6InvertKeepView(search, on);
        else G6InvertKeepImages(edge, on, 4);
    }
}

// Ô của bảng đang đảo màu: chỉ lo ảnh thật trong ô (dấu trên ô để biết lúc nào phải gỡ)
static void G6InvertCell(UITableViewCell *cell, BOOL on) {
    BOOL has = objc_getAssociatedObject(cell, &kInvertedCellKey) != nil;
    if (!on && !has) return;
    objc_setAssociatedObject(cell, &kInvertedCellKey, on ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    G6InvertKeepImages(cell, on, 4);
}

static UITableView *G6TableOfCell(UIView *cell) {
    UIView *v = cell.superview;
    for (int i = 0; v && i < 3; i++, v = v.superview) {
        if ([v isKindOfClass:[UITableView class]]) return (UITableView *)v;
    }
    return nil;
}

// Mọi view con (tới 3 tầng) đều là lớp của chính UIKit? Lớp của app / thư viện khác có thể tự vẽ chữ — không đổi màu được.
static BOOL G6StandardSubviews(UIView *view, int depth) {
    static NSBundle *uikit;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        uikit = [NSBundle bundleForClass:[UIView class]];
    });
    for (UIView *sub in view.subviews) {
        if ([NSBundle bundleForClass:[sub class]] != uikit) return NO;
        if (depth > 0 && !G6StandardSubviews(sub, depth - 1)) return NO;
    }
    return YES;
}

// Ô mà Glass 6 tô tối được: không tự vẽ (drawRect: của lớp con), nội dung chỉ gồm thành phần chuẩn
static BOOL G6CellIsStandard(UITableViewCell *cell) {
    if ([cell methodForSelector:@selector(drawRect:)] != [UITableViewCell instanceMethodForSelector:@selector(drawRect:)]) return NO;
    return G6StandardSubviews(cell.contentView, 3);
}

// Ô của bảng thường. iOS 6 tự lan màu nền của bảng xuống ô (và xuống nền nhãn của ô), nên ở đây KHÔNG đặt màu nền ô — từng
// thử «nhớ màu gốc rồi đặt đen» thì màu gốc nhớ được đã là màu đen vừa lan xuống, trả lại thành tô đen lần nữa. Chỉ để dấu
// «ô đang được tô tối» và lo nền của contentView nếu app đặt riêng màu trắng cho nó.
static void G6StylePlainCell(UITableViewCell *cell, BOOL on) {
    BOOL marked = objc_getAssociatedObject(cell, &kPlainCellKey) != nil;
    if (on) {
        if (!marked) objc_setAssociatedObject(cell, &kPlainCellKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        G6FixLabelBackground(cell.contentView, G6PlainFill());
    } else if (marked) {
        objc_setAssociatedObject(cell, &kPlainCellKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        G6FixLabelBackground(cell.contentView, nil);
    }
}

static void G6RestorePlainTable(UITableView *table) {
    UIColor *bg = objc_getAssociatedObject(table, &kPlainBackgroundKey), *sep = objc_getAssociatedObject(table, &kPlainSeparatorKey);
    if (bg) table.backgroundColor = bg;
    if (sep) table.separatorColor = sep;
    objc_setAssociatedObject(table, &kPlainBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(table, &kPlainSeparatorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Bảng nền sáng đục (mặc định là trắng)? Bảng trong suốt nằm trên nền riêng của app hay bảng có màu riêng thì không.
static BOOL G6PlainTableIsWhite(UITableView *table) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    UIColor *bg = table.backgroundColor;
    return bg && G6ColorRGBA(bg, &r, &g, &b, &a) && a >= 0.99 && r >= 0.9 && g >= 0.9 && b >= 0.9;
}

// Gọi mỗi lần bảng thường xếp lại: quyết định bảng này có tô tối không
static void G6StylePlainTable(UITableView *table) {
    int state = [objc_getAssociatedObject(table, &kPlainStateKey) intValue];
    if (gActive && gInvertAll) {
        // App đã bật «đảo cả bảng»: bảng giữ kiểu sáng gốc và mang bộ lọc (đầu bảng có thể được gắn sau → lần xếp nào cũng kiểm)
        if (state == 1) G6RestorePlainTable(table);
        if (state != 3) {
            BOOL white = G6PlainTableIsWhite(table);
            objc_setAssociatedObject(table, &kPlainStateKey, white ? @3 : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!white) return;
        }
        G6InvertTable(table, YES);
        return;
    }
    if (state == 3) {
        G6InvertTable(table, NO);
        objc_setAssociatedObject(table, &kPlainStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state = 0;
    }
    BOOL want = gActive && gDark && gPlainAllowed;
    if (!want) {
        if (state == 1) G6RestorePlainTable(table);
        if (state) objc_setAssociatedObject(table, &kPlainStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (state == 2) return;  // có ô tự vẽ: để sáng
    if (state != 1) {
        // Chỉ nhận bảng nền sáng đục (mặc định là trắng); bảng trong suốt nằm trên nền riêng của app hay bảng có màu riêng: thôi
        CGFloat r = 0, g = 0, b = 0, a = 0;
        UIColor *bg = table.backgroundColor;
        if (!bg || !G6ColorRGBA(bg, &r, &g, &b, &a) || a < 0.99 || r < 0.9 || g < 0.9 || b < 0.9) return;
        objc_setAssociatedObject(table, &kPlainBackgroundKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (table.separatorColor) objc_setAssociatedObject(table, &kPlainSeparatorKey, table.separatorColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(table, &kPlainStateKey, @1, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        table.backgroundColor = G6PlainFill();
        table.separatorColor = [UIColor colorWithWhite:1 alpha:0.16];
    }
}

// ---- Thanh tiêu đề nhóm của bảng thường ở chế độ tối ----
// iOS 6 (tra trên máy 19/11/2026): UITableViewHeaderFooterView = nền _UITableViewHeaderFooterViewBackground (dải xám xanh
// nhạt) + nhãn chữ trắng đậm có bóng. Trên bảng đã tô đen, dải nhạt này chói.
//   - Nền: che nền gốc (ẩn đi) bằng một view phẳng màu than của Glass 6 đặt dưới cùng. Đã thử thuộc tính tintColor có sẵn của
//     lớp này: iOS 6 dựng từ màu đó một dải BÓNG chuyển màu (mép dưới sáng lên gần xám vừa) — không ra mặt phẳng.
//   - Chữ: xám sáng, bỏ bóng.
// Chỉ làm với bảng thường đang được Glass 6 tô tối; hết tô thì gỡ view của mình, hiện lại nền gốc, trả màu chữ.
// (textLabel gọi qua tên hàm: lớp này có từ iOS 6, SDK 9.3 đánh dấu nó «chưa kiểm phiên bản».)
// Chế độ sáng (thêm 20/11/2026): dải xám xanh bóng + chữ trắng có bóng của iOS 6 lạc với mọi thứ phẳng xung quanh → cùng cách
// làm, dải phẳng xám rất nhạt + chữ xám đậm. Chỉ với bảng nền trắng đục (bảng trong suốt / có màu riêng của app: để nguyên).
static char kHeaderSavedKey, kHeaderBandKey, kPlainHeadersKey;

static UIView *G6HeaderStockBackground(UIView *header) {
    Class cls = objc_getClass("_UITableViewHeaderFooterViewBackground");
    for (UIView *v in header.subviews) {
        if (cls && [v isKindOfClass:cls]) return v;
    }
    return nil;
}

static void G6StylePlainHeaders(UITableView *table) {
    Class headerClass = objc_getClass("UITableViewHeaderFooterView");
    int plainState = [objc_getAssociatedObject(table, &kPlainStateKey) intValue];
    BOOL darkOn = gActive && gDark && plainState == 1;
    BOOL lightOn = NO;
    // (Bảng đang đảo màu — trạng thái 3 — thì gDark là NO: tiêu đề dựng theo kiểu sáng, bộ lọc của bảng đảo thành tối)
    if (gActive && !gDark) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        UIColor *bg = table.backgroundColor;
        lightOn = bg && G6ColorRGBA(bg, &r, &g, &b, &a) && a >= 0.99 && r >= 0.9 && g >= 0.9 && b >= 0.9;
    }
    BOOL dark = darkOn || lightOn;
    if (!headerClass || (!dark && !objc_getAssociatedObject(table, &kPlainHeadersKey))) return;
    SEL labelSel = NSSelectorFromString(@"textLabel");
    UIColor *text = darkOn ? [UIColor colorWithRed:0.92 green:0.92 blue:0.96 alpha:0.62] : [UIColor colorWithRed:0.24 green:0.24 blue:0.26 alpha:0.78];
    UIColor *bandColor = darkOn ? [UIColor colorWithWhite:0.11 alpha:1] : [UIColor colorWithWhite:0.955 alpha:1];
    for (UIView *sub in table.subviews) {
        if (![sub isKindOfClass:headerClass]) continue;
        id label = [sub respondsToSelector:labelSel] ? ((id (*)(id, SEL))objc_msgSend)(sub, labelSel) : nil;
        if (![label isKindOfClass:[UILabel class]]) label = nil;
        NSDictionary *saved = objc_getAssociatedObject(sub, &kHeaderSavedKey);
        UIView *band = objc_getAssociatedObject(sub, &kHeaderBandKey), *stock = G6HeaderStockBackground(sub);
        if (dark) {
            // Không thấy nền gốc (bản iOS khác / app tự đặt nền riêng): không đụng thanh này
            if (!stock && !band) continue;
            if (!saved) {
                // Cất màu chữ gốc (NSNull = không đặt)
                saved = @{@"text" : [label textColor] ?: (id)[NSNull null], @"shadow" : [label shadowColor] ?: (id)[NSNull null]};
                objc_setAssociatedObject(sub, &kHeaderSavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (!band) {
                band = [[UIView alloc] initWithFrame:sub.bounds];
                band.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                band.userInteractionEnabled = NO;
                objc_setAssociatedObject(sub, &kHeaderBandKey, band, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (![band.backgroundColor isEqual:bandColor]) band.backgroundColor = bandColor;
            if (band.superview != sub) [sub insertSubview:band atIndex:0];
            // UIKit có thể hiện lại nền / đặt lại màu khi dùng lại thanh cho nhóm khác → lần xếp nào cũng kiểm
            if (stock && !stock.hidden) stock.hidden = YES;
            if (label && ![[label textColor] isEqual:text]) [label setTextColor:text];
            if (label && [label shadowColor]) [label setShadowColor:nil];
        } else if (saved) {
            id color = saved[@"text"], shadow = saved[@"shadow"];
            [band removeFromSuperview];
            objc_setAssociatedObject(sub, &kHeaderBandKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            stock.hidden = NO;
            if (label && color != [NSNull null]) [label setTextColor:color];
            if (label) [label setShadowColor:shadow == [NSNull null] ? nil : shadow];
            objc_setAssociatedObject(sub, &kHeaderSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    objc_setAssociatedObject(table, &kPlainHeadersKey, dark ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void G6ApplyCell(UITableViewCell *cell);

// Bảng có ô tự vẽ: trả cả bảng về sáng, đánh dấu để không thử lại; các ô đã lỡ tô tối được trả ngay (không chờ lượt xếp sau)
static void G6SkipPlainTable(UITableView *table) {
    objc_setAssociatedObject(table, &kPlainStateKey, @2, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    G6RestorePlainTable(table);
    G6StylePlainHeaders(table);
    for (UIView *sub in table.subviews) {
        if ([sub isKindOfClass:[UITableViewCell class]]) G6ApplyCell((UITableViewCell *)sub);
    }
}

void G6UITablesSetPlainAllowed(BOOL allowed) {
    gPlainAllowed = allowed;
}

void G6UITablesSetInvertCustomCells(BOOL on) {
    gInvertCustom = on;
}

// ---- Cột trái của app Cài đặt (iPad) ----

// PSGradientView: nền dải màu của cột trái. Tối: thay bằng dải than; sáng: trả dải gốc.
static void G6StyleSidebarGradient(UIView *view) {
    if (![view.layer isKindOfClass:[CAGradientLayer class]]) return;
    CAGradientLayer *layer = (CAGradientLayer *)view.layer;
    NSArray *saved = objc_getAssociatedObject(view, &kOriginalGradientKey);
    if (gActive && gDark) {
        if (!saved && layer.colors) objc_setAssociatedObject(view, &kOriginalGradientKey, layer.colors, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        layer.colors = @[
            (__bridge id)[UIColor colorWithRed:0.11 green:0.11 blue:0.118 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.085 green:0.085 blue:0.09 alpha:1].CGColor
        ];
    } else if (saved) {
        layer.colors = saved;
        objc_setAssociatedObject(view, &kOriginalGradientKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*orig_gradientLayout)(UIView *, SEL);
static void repl_gradientLayout(UIView *self, SEL _cmd) {
    orig_gradientLayout(self, _cmd);
    G6StyleSidebarGradient(self);
}

void G6UITablesSetSidebar(BOOL on) {
    gSidebar = on;
}

// Bảng của cột trái app Cài đặt: bảng thường nền trong suốt nằm trên dải màu
static BOOL G6IsSidebarTable(UITableView *table) {
    if (!gSidebar || !table || table.style != UITableViewStylePlain) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    UIColor *bg = table.backgroundColor;
    return !bg || !G6ColorRGBA(bg, &r, &g, &b, &a) || a < 0.5;
}

// Một ô có đang được Glass 6 «quản» không, theo loại nào; rồi đổi / trả màu nền, chữ, hình nhỏ của ô cho khớp.
//   - ô nhóm: quản khi thành phần bật (sáng: chỉ sửa nền nhãn; tối: thêm chữ sáng, hình sáng);
//   - ô bảng thường: quản khi đang tối, bảng nhận tô tối và ô chỉ gồm thành phần chuẩn;
//   - ô cột trái Cài đặt: quản khi đang tối (chỉ đổi chữ và hình, không đụng nền nhãn);
//   - còn lại: không quản — nếu trước đó từng đổi thì trả về gốc.
static void G6ApplyCell(UITableViewCell *cell) {
    BOOL grouped = G6IsGroupedCell(cell), plain = NO, sidebar = NO;
    UITableView *table = G6TableOfCell(cell);
    // Bảng đang đảo màu (thường hay nhóm): ô giữ kiểu sáng; ảnh thật trong ô giữ đúng màu
    G6InvertCell(cell, G6TableIsInverted(table));
    if (!grouped) {
        int state = table ? [objc_getAssociatedObject(table, &kPlainStateKey) intValue] : 0;
        if (state == 1 && gActive && gDark) {
            if (G6CellIsStandard(cell)) {
                plain = YES;
            } else {
                // Ô tự vẽ: cả bảng về sáng (hàm này sẽ gọi lại G6ApplyCell cho mọi ô, kể cả ô này, với trạng thái «bỏ qua»)
                G6SkipPlainTable(table);
                return;
            }
        }
        if (plain || objc_getAssociatedObject(cell, &kPlainCellKey)) G6StylePlainCell(cell, plain);
        sidebar = !plain && gActive && gDark && G6IsSidebarTable(table);
    }
    BOOL managed = gActive && (grouped || plain || sidebar);
    if (!managed && !objc_getAssociatedObject(cell, &kOriginalColorKey)) return;
    BOOL lighten = managed && gDark;
    // Nền nhãn: theo màu ô (ô nhóm / ô bảng thường tô tối); cột trái: không đụng; hết được quản: trả nền gốc (fill = nil)
    UIColor *fill = !managed ? nil : (grouped ? G6CellFillColor() : (plain ? G6PlainFill() : nil));
    // Đặt dấu «đang quản» TRƯỚC khi đổi hình: hàm móc setImage: dựa vào dấu này
    objc_setAssociatedObject(cell, &kOriginalColorKey, managed ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    G6RecolorTree(cell.contentView, 3, !sidebar, fill, lighten);
    G6RecolorGlyphs(cell, 3, lighten);
    G6RecolorAccessory(cell, lighten);
}

// iPhone: nét «chạm khắc» còn một nửa nằm ở chính ô — _topShadowView, một vạch trắng 1 điểm ở mép trên của ô (trên ô trắng
// không thấy, trên ô tối thành vạch trắng). Ẩn khi kiểu mới đang bật; UIKit tự đặt lại màu / khung của nó, cờ ẩn
// thì không ai đụng nên trả lại được khi tắt.
static void G6HideTopShadow(UITableViewCell *cell) {
    static Ivar iv;
    static BOOL looked;
    if (!looked) {
        looked = YES;
        Ivar found = class_getInstanceVariable([UITableViewCell class], "_topShadowView");
        const char *enc = found ? ivar_getTypeEncoding(found) : NULL;
        if (enc && enc[0] == '@') iv = found;
    }
    if (!iv) return;
    UIView *shadow = object_getIvar(cell, iv);
    if ([shadow isKindOfClass:[UIView class]] && shadow.hidden != gActive) shadow.hidden = gActive;
}

static void (*orig_cellLayout)(UITableViewCell *, SEL);
static void repl_cellLayout(UITableViewCell *self, SEL _cmd) {
    orig_cellLayout(self, _cmd);
    G6HideTopShadow(self);
    G6ApplyCell(self);
}

// ---- Tiêu đề / chú thích của nhóm ----

// Nhãn nằm thẳng trong bảng nhóm (không thuộc ô nào) là tiêu đề / chú thích nhóm: iOS 6 vẽ chữ xanh xám có bóng trắng
static void G6StyleSectionLabels(UITableView *table) {
    if (table.style != UITableViewStyleGrouped) return;
    for (UIView *sub in table.subviews) {
        if ([sub isKindOfClass:[UITableViewCell class]]) continue;
        if (gTableBackgroundClass && [sub isKindOfClass:gTableBackgroundClass]) continue;
        // Hàm này chỉ được gọi khi đang tối hoặc bảng còn màu phải trả lại: nhãn có thể nằm trong view bọc (tiêu đề nhóm),
        // nên luôn đi hết cây con — lượt trả màu mà bỏ view bọc thì chữ sáng còn sót trên nền sáng
        G6RecolorTree(sub, 2, NO, nil, gActive && gDark);
    }
}

static void (*orig_tableLayout)(UITableView *, SEL);
static void repl_tableLayout(UITableView *self, SEL _cmd) {
    orig_tableLayout(self, _cmd);
    if (self.style == UITableViewStylePlain) {
        G6StylePlainTable(self);
        G6StylePlainHeaders(self);
    } else {
        // Bảng nhóm của app đã bật «đảo cả bảng»
        BOOL invert = gActive && gInvertAll;
        if (invert || G6TableIsInverted(self)) G6InvertTable(self, invert);
    }
    if ((gActive && gDark) || objc_getAssociatedObject(self, &kOriginalColorKey)) {
        G6StyleSectionLabels(self);
        objc_setAssociatedObject(self, &kOriginalColorKey, (gActive && gDark) ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Tiêu đề / chú thích nhóm (iOS 6: UITableViewHeaderFooterView › view bọc › nhãn) tạo và tô màu nhãn trong lượt xếp CỦA
// CHÍNH NÓ — sau lượt xếp của bảng. Bảng vừa nạp lại (reloadData) mà không cuộn thì bảng không xếp thêm lượt nào: nhãn mới
// giữ chữ xanh xám + bóng trắng của iOS 6 trên nền tối (gặp ở Cài đặt › Glass 6 sau «Kiểm bản mới»). Đổi màu ngay ở đây.
// Chỉ bảng nhóm: tiêu đề của bảng thường có phần riêng (G6StylePlainHeaders).
static void (*orig_headerLayout)(UIView *, SEL);
static void repl_headerLayout(UIView *self, SEL _cmd) {
    orig_headerLayout(self, _cmd);
    UITableView *table = (UITableView *)self.superview;
    if (![table isKindOfClass:[UITableView class]] || table.style != UITableViewStyleGrouped) return;
    if ((gActive && gDark) || objc_getAssociatedObject(table, &kOriginalColorKey)) G6RecolorTree(self, 2, NO, nil, gActive && gDark);
}

// ---- Cài / làm mới ----

static void G6InstallHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gCellBackgroundClass = objc_getClass("UIGroupTableViewCellBackground");
        gTableBackgroundClass = objc_getClass("UITableViewBackgroundView");
        int ok = 0;
        if (gCellBackgroundClass) {
            ok += G6Hook(gCellBackgroundClass, NSSelectorFromString(@"_fillColor"), (IMP)repl_fillColor, (IMP *)&orig_fillColor);
            // Không tính vào `ok`: thiếu hàm này thì chỉ mất phần bỏ nét chạm khắc
            G6Hook(gCellBackgroundClass, NSSelectorFromString(@"setSeparatorStyle:"), (IMP)repl_setSeparatorStyle,
                   (IMP *)&orig_setSeparatorStyle);
            ok += G6Hook(gCellBackgroundClass, NSSelectorFromString(@"_sectionBorderColor"), (IMP)repl_borderColor,
                         (IMP *)&orig_borderColor);
            ok += G6Hook(gCellBackgroundClass, NSSelectorFromString(@"_separatorColor"), (IMP)repl_separatorColor,
                         (IMP *)&orig_separatorColor);
            ok += G6Hook(gCellBackgroundClass, NSSelectorFromString(@"_topShadowColor"), (IMP)repl_topShadowColor,
                         (IMP *)&orig_topShadowColor);
            ok += G6Hook(gCellBackgroundClass, NSSelectorFromString(@"_bottomShadowColor"), (IMP)repl_bottomShadowColor,
                         (IMP *)&orig_bottomShadowColor);
            // Kiểm đúng chữ ký trước khi móc: hàm nhận struct + số thực, gọi sai kiểu là hỏng ngăn xếp
            SEL pathSel = NSSelectorFromString(@"_roundedRectBezierPathInRect:withSectionLocation:forBorder:cornerRadiusAdjustment:");
            Method m = class_getInstanceMethod(gCellBackgroundClass, pathSel);
            if (m && strcmp(method_getTypeEncoding(m) ?: "", "@36@0:4{CGRect={CGPoint=ff}{CGSize=ff}}8i24c28f32") == 0) {
                ok += G6Hook(gCellBackgroundClass, pathSel, (IMP)repl_roundedPath, (IMP *)&orig_roundedPath);
            }
        }
        if (gTableBackgroundClass) {
            ok += G6Hook(gTableBackgroundClass, @selector(layoutSubviews), (IMP)repl_tableBgLayout, (IMP *)&orig_tableBgLayout);
        }
        ok += G6Hook([UITableViewCell class], @selector(layoutSubviews), (IMP)repl_cellLayout, (IMP *)&orig_cellLayout);
        ok += G6Hook([UITableView class], @selector(layoutSubviews), (IMP)repl_tableLayout, (IMP *)&orig_tableLayout);
        ok += G6Hook([UITableViewCell class], NSSelectorFromString(@"_contentBackgroundColor"), (IMP)repl_contentBackgroundColor,
                     (IMP *)&orig_contentBackgroundColor);
        ok += G6Hook([UILabel class], @selector(setTextColor:), (IMP)repl_labelSetTextColor, (IMP *)&orig_labelSetTextColor);
        ok += G6Hook([UILabel class], @selector(setShadowColor:), (IMP)repl_labelSetShadowColor, (IMP *)&orig_labelSetShadowColor);
        ok += G6Hook([UIImageView class], @selector(setImage:), (IMP)repl_imageViewSetImage, (IMP *)&orig_imageViewSetImage);
        G6Log(@"bảng: gắn %d / 13 hàm", ok);
        // Không tính vào `ok`: thiếu lớp này thì chỉ mất phần đổi màu tiêu đề nhóm ngay sau khi bảng nạp lại
        G6HookNamed("UITableViewHeaderFooterView", @selector(layoutSubviews), (IMP)repl_headerLayout, (IMP *)&orig_headerLayout);
        G6HookNamed("UIRoundedRectButton", @selector(layoutSubviews), (IMP)repl_roundedButtonLayout, (IMP *)&orig_roundedButtonLayout);
        if (gSidebar && !G6HookNamed("PSGradientView", @selector(layoutSubviews), (IMP)repl_gradientLayout, (IMP *)&orig_gradientLayout)) {
            G6Log(@"bảng: không có PSGradientView — cột trái của Cài đặt giữ màu cũ");
        }
    });
}

static void G6RefreshTree(UIView *view) {
    if (gCellBackgroundClass && [view isKindOfClass:gCellBackgroundClass]) {
        [view setNeedsLayout];
        [view setNeedsDisplay];
        [view.layer setNeedsDisplay];
    } else if (gTableBackgroundClass && [view isKindOfClass:gTableBackgroundClass]) {
        G6StyleTableBackground(view);
    } else if ([view isKindOfClass:[UITableViewCell class]] || [view isKindOfClass:[UITableView class]]) {
        [view setNeedsLayout];
    } else if ([view isKindOfClass:[UIButton class]] && orig_roundedButtonLayout &&
               [view isKindOfClass:objc_getClass("UIRoundedRectButton")]) {
        // Nút bo góc: màu chữ đổi / trả ở lượt xếp của nút
        [view setNeedsLayout];
    } else if (gSidebar && [view isKindOfClass:objc_getClass("PSGradientView")]) {
        // Đúng lớp PSGradientView mới đụng: trước đây nhận mọi view có lớp vẽ chuyển màu → tô đặc luôn hai dải mờ dần của
        // bánh xe chọn (G6UIPickers) lúc đổi sáng → tối trong app Cài đặt
        G6StyleSidebarGradient(view);
    }
    for (UIView *sub in view.subviews) G6RefreshTree(sub);
}

void G6UITablesApply(BOOL allowed) {
    BOOL active = allowed && G6Feature(@"apps") && G6Feature(@"tables");
    BOOL dark = active && G6UIDark();
    // App đã bật «đảo cả bảng»: phần tối do bộ lọc lo, mọi thứ trong bảng dựng theo bảng màu sáng
    BOOL invert = dark && gInvertCustom && G6UISkinInvertFilter() != nil;
    if (invert) dark = NO;
    NSString *signature = [NSString stringWithFormat:@"%d|%d|%d", active, dark, invert];
    if ([signature isEqualToString:gSignature]) return;
    BOOL first = gSignature == nil;
    gSignature = signature;
    if (!active && first) return;  // chưa từng bật: không gắn gì
    gActive = active;
    gDark = dark;
    gInvertAll = invert;
    G6InstallHooks();
    // Ảnh nền ô được nhớ theo khoá của UIKit: xoá để ô vẽ lại theo màu mới
    SEL flush = NSSelectorFromString(@"_flushCacheOnNotification:");
    if (gCellBackgroundClass && [gCellBackgroundClass respondsToSelector:flush]) {
        ((void (*)(id, SEL, id))objc_msgSend)(gCellBackgroundClass, flush, nil);
    }
    if (!first) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) G6RefreshTree(window);
    }
    G6Log(@"bảng: %@", active ? (invert ? @"kiểu mới (tối, đảo cả bảng)" : (dark ? @"kiểu mới (tối)" : @"kiểu mới (sáng)")) : @"kiểu gốc");
}
