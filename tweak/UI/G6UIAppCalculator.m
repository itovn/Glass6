// App Máy tính (com.apple.calculator) trên iPhone — kiểu iOS 26: nền đen, phím tròn (số: xám đậm, chức năng: xám nhạt chữ đen,
// phép tính: cam), màn hình số chữ trắng trên nền đen. Như iOS 26, app này không đổi theo chế độ sáng / tối.
//
// iOS 6 (tra trên máy 20/11/2026): UIView gốc (0 20; 320 548)
//   CalcDisplayView : UIImageView (0 0; 320 89)       ảnh nền kéo giãn (displayBackgroundSlice…); CalcValueView tự vẽ số trong
//                                                     -drawRect: bằng +[CalcValueView textColor] / +fontForSize:
//   UITransitionView (0 89; 320 459)
//     CalcKeypadView : UIImageView (0 0; 320 459)     MỘT ảnh cho cả bàn phím («basicKeypad», máy đứng: lưới 6 hàng × 4 cột,
//                                                     «0» chiếm hai cột, «=» chiếm hai hàng). Lưới: ivar _rows, _columns,
//                                                     _buttonSize, _keypadRect, _buttonTags (mã phím theo hàng rồi cột; phím
//                                                     gộp ô lặp lại cùng mã), phím đang bấm: _pressedTag. Hình thay thế đè lên
//                                                     một phím (dấu phẩy thập phân theo vùng): _alternateImageViews.
// Cách làm — lưới, vùng chạm, cách tính giữ nguyên, chỉ đổi hình:
//   - mỗi CalcKeypadView nhận một ảnh tự vẽ cùng cỡ theo đúng lưới đọc từ ivar. Có hai loại lưới 6 × 4:
//       «cơ bản»   (có phím gộp ô: «0» hai cột, «=» hai hàng) — máy đứng 320×459, và nửa PHẢI lúc máy nằm ngang 284×241;
//       «khoa học» (24 phím rời) — nửa TRÁI lúc máy nằm ngang, nằm trong một UIImageView nền da («landscapeBackground»).
//     Ô vuông vức thì phím là đĩa tròn; ô dẹt (máy ngang 71×40) thì phím là viên bo tròn gần kín ô;
//   - hình thay thế của app (-setShowingAlternateImage:withPath:forKey:onTag: — đo bằng công cụ chạm giả, 20/11/2026):
//     «comma» / «commaBasic» (dấu thập phân theo vùng), «2ndOn», «asin» «acos» «atan» «asinh» «acosh» «atanh» «log2» «2x»
//     (hàm thứ hai của phím), «deg» (phím Rad ↔ Deg), và «OperatorRing» (vòng báo phép tính đang chờ — đặt trên phím phép
//     tính đó). Các ảnh đó (ảnh phím kiểu cũ) bị ẩn; trạng thái của chúng được nhớ theo mã phím và VẼ vào ảnh bàn phím:
//     nhãn hàm thứ hai, phím «2nd» sáng lên, phím phép tính đang chờ đảo màu (nền trắng chữ cam như iOS);
//   - phím đang bấm: app đặt một UIImageView nhỏ (ảnh phím kiểu cũ ở trạng thái bấm) vào view GỐC, đè lên chỗ phím → sau
//     mỗi sự kiện chạm, view đó bị ẩn và thay bằng một lớp sáng mờ đúng hình phím, đặt theo _pressedTag;
//   - màn hình số: nền đen phẳng, chữ trắng phông Inter.
// Thuộc công tắc «app_skins»; tắt thì trả ảnh gốc ngay.
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"

static BOOL gActive;
static NSMutableDictionary *gImages;
static char kOriginalImageKey, kHighlightKey, kDisplaySavedKey, kHiddenByMeKey, kAlternatesKey, kBackgroundSavedKey, kMineKey;

// Nhãn theo hàng rồi cột. Cơ bản: «.» = dấu thập phân của vùng.
static NSString *const kBasicLabels[6][4] = {
    {@"mc", @"m+", @"m−", @"mr"},
    {@"C", @"±", @"÷", @"×"},
    {@"7", @"8", @"9", @"−"},
    {@"4", @"5", @"6", @"+"},
    {@"1", @"2", @"3", @"="},
    {@"0", @"0", @".", @"="},
};
static NSString *const kScientificLabels[6][4] = {
    {@"2nd", @"(", @")", @"%"},
    {@"1/x", @"x²", @"x³", @"yˣ"},
    {@"x!", @"√", @"ˣ√y", @"log"},
    {@"sin", @"cos", @"tan", @"ln"},
    {@"sinh", @"cosh", @"tanh", @"eˣ"},
    {@"Rad", @"π", @"EE", @"Rand"},
};

// Nhãn của phím khi app đang hiện hình thay thế mang khoá `key` trên phím đó (nil = không đổi nhãn)
static NSString *G6CalcAlternateLabel(NSString *key) {
    static NSDictionary *labels;
    if (!labels) {
        labels = @{@"asin" : @"sin⁻¹", @"acos" : @"cos⁻¹", @"atan" : @"tan⁻¹", @"asinh" : @"sinh⁻¹", @"acosh" : @"cosh⁻¹",
                   @"atanh" : @"tanh⁻¹", @"log2" : @"log₂", @"2x" : @"2ˣ", @"deg" : @"Deg"};
    }
    return labels[key];
}

// ---- Đọc lưới của CalcKeypadView ----

typedef struct {
    unsigned rows, columns;
    CGSize button;
    CGRect keypad;
    const int *tags;
    int pressed;
} G6CalcGrid;

static BOOL G6CalcReadIvar(id obj, const char *name, const char *prefix, void *out, size_t size) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!enc || strncmp(enc, prefix, strlen(prefix)) != 0) return NO;
    memcpy(out, (char *)(__bridge void *)obj + ivar_getOffset(iv), size);
    return YES;
}

static BOOL G6CalcReadGrid(UIView *keypad, G6CalcGrid *g) {
    memset(g, 0, sizeof(*g));
    if (!G6CalcReadIvar(keypad, "_rows", "I", &g->rows, sizeof(unsigned)) || !G6CalcReadIvar(keypad, "_columns", "I", &g->columns, sizeof(unsigned)) ||
        !G6CalcReadIvar(keypad, "_buttonSize", "{CGSize", &g->button, sizeof(CGSize)) ||
        !G6CalcReadIvar(keypad, "_keypadRect", "{CGRect", &g->keypad, sizeof(CGRect)) ||
        !G6CalcReadIvar(keypad, "_buttonTags", "r^i", &g->tags, sizeof(int *)) ||
        !G6CalcReadIvar(keypad, "_pressedTag", "i", &g->pressed, sizeof(int))) {
        return NO;
    }
    return g->tags && g->rows > 0 && g->columns > 0 && g->rows <= 12 && g->columns <= 12 && g->button.width > 8 && g->button.height > 8;
}

typedef enum { G6CalcOther = 0, G6CalcBasic, G6CalcScientific } G6CalcKind;

// Lưới 6 × 4: cơ bản nếu có phím gộp ô («0» chiếm hai ô đầu của hàng cuối), khoa học nếu 24 phím rời
static G6CalcKind G6CalcKindOf(const G6CalcGrid *g) {
    if (g->rows != 6 || g->columns != 4) return G6CalcOther;
    if (g->tags[20] == g->tags[21]) return G6CalcBasic;
    for (int i = 0; i < 24; i++) {
        for (int j = i + 1; j < 24; j++) {
            if (g->tags[i] == g->tags[j]) return G6CalcOther;
        }
    }
    return G6CalcScientific;
}

// Khung của phím mang mã `tag`: hợp các ô cùng mã. CGRectNull nếu không có.
static CGRect G6CalcKeyFrame(const G6CalcGrid *g, int tag) {
    CGRect frame = CGRectNull;
    for (unsigned r = 0; r < g->rows; r++) {
        for (unsigned c = 0; c < g->columns; c++) {
            if (g->tags[r * g->columns + c] != tag) continue;
            CGRect cell = CGRectMake(g->keypad.origin.x + c * g->button.width, g->keypad.origin.y + r * g->button.height, g->button.width,
                                     g->button.height);
            frame = CGRectIsNull(frame) ? cell : CGRectUnion(frame, cell);
        }
    }
    return frame;
}

// Hình phím trong khung `frame` (một ô hoặc nhiều ô gộp; `cell` = cỡ một ô). Ô vuông vức: mỗi ô một đĩa tròn đứng giữa ô,
// phím gộp ô là viên dài nối từ đĩa của ô đầu tới đĩa của ô cuối. Ô dẹt (máy nằm ngang): viên bo tròn gần kín ô.
static UIBezierPath *G6CalcKeyPath(CGRect frame, CGSize cell) {
    BOOL flat = cell.width > cell.height * 1.3;
    CGFloat d = flat ? cell.height - 7 : MIN(66, MIN(cell.width, cell.height) - 8);
    CGFloat insetX = flat ? 3.5 : (cell.width - d) / 2;
    CGRect body = CGRectInset(frame, insetX, (cell.height - d) / 2);
    return [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:d / 2];
}

static void G6CalcDrawCentered(NSString *text, UIFont *font, CGPoint center) {
    CGSize size = [text sizeWithFont:font];
    [text drawAtPoint:CGPointMake(round(center.x - size.width / 2), round(center.y - size.height / 2)) withFont:font];
}

// `alternates`: mã phím → khoá của hình thay thế app đang hiện trên phím đó (xem đầu tệp)
static UIImage *G6CalcKeypadImage(CGSize size, const G6CalcGrid *g, G6CalcKind kind, NSDictionary *alternates) {
    NSString *decimal = [[NSLocale currentLocale] objectForKey:NSLocaleDecimalSeparator] ?: @".";
    // Cỡ chữ theo chiều cao phím (máy đứng: phím 66; máy ngang: 33)
    CGFloat k = MIN(1, (g->button.height - 7) / 66);
    BOOL small = k < 0.8;
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIColor *orange = [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1];
    NSMutableSet *done = [NSMutableSet set];
    for (unsigned r = 0; r < g->rows; r++) {
        for (unsigned c = 0; c < g->columns; c++) {
            int tag = g->tags[r * g->columns + c];
            if ([done containsObject:@(tag)]) continue;
            [done addObject:@(tag)];
            CGRect frame = G6CalcKeyFrame(g, tag);
            NSString *alternate = alternates[@(tag)];
            NSString *label;
            UIColor *fill, *text = [UIColor whiteColor];
            UIFont *font;
            BOOL op = NO;
            if (kind == G6CalcBasic) {
                label = kBasicLabels[r][c];
                BOOL memory = r == 0, function = r == 1 && c < 2;
                op = (r == 1 && c >= 2) || (r >= 2 && c == 3);
                if (op) {
                    // Phép tính đang chờ (app đặt «vòng báo» lên phím): đảo màu
                    BOOL pending = [alternate isEqualToString:@"OperatorRing"];
                    fill = pending ? [UIColor whiteColor] : orange;
                    if (pending) text = orange;
                } else if (function || memory) {
                    fill = [UIColor colorWithWhite:0.65 alpha:1];
                    text = [UIColor blackColor];
                } else {
                    fill = [UIColor colorWithWhite:0.20 alpha:1];
                }
                font = memory ? G6Font(G6FontMedium, small ? 14 : 19) : (op ? G6Font(G6FontRegular, small ? 23 : 36) : G6Font(G6FontRegular, small ? 20 : 30));
                if ([label isEqualToString:@"."]) label = decimal;
            } else {
                label = G6CalcAlternateLabel(alternate) ?: kScientificLabels[r][c];
                // Phím «2nd» đang bật: sáng lên
                BOOL on = [alternate isEqualToString:@"2ndOn"];
                fill = on ? [UIColor colorWithWhite:0.65 alpha:1] : [UIColor colorWithWhite:0.13 alpha:1];
                if (on) text = [UIColor blackColor];
                font = G6Font(G6FontMedium, label.length > 4 ? 13 : 15);
            }
            [fill setFill];
            UIBezierPath *path = G6CalcKeyPath(frame, g->button);
            [path fill];
            [text setFill];
            CGPoint center = CGPointMake(CGRectGetMidX(path.bounds), CGRectGetMidY(path.bounds));
            // «0» gộp hai ô: chữ số đứng ở chỗ của ô bên trái như iOS; dấu phép tính của phông nằm hơi cao
            if (kind == G6CalcBasic && [label isEqualToString:@"0"] && frame.size.width > g->button.width * 1.5) {
                center.x = frame.origin.x + g->button.width / 2;
            }
            if (op) center.y -= small ? 1 : 2;
            G6CalcDrawCentered(label, font, center);
        }
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// ---- Bàn phím ----

static CALayer *G6CalcHighlightLayer(UIView *keypad, BOOL create) {
    CAShapeLayer *layer = objc_getAssociatedObject(keypad, &kHighlightKey);
    if (!layer && create) {
        layer = [CAShapeLayer layer];
        layer.fillColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;
        layer.hidden = YES;
        // Không hoạt hình ngầm: phím sáng lên / tắt ngay theo ngón tay
        layer.actions = @{@"hidden" : [NSNull null], @"path" : [NSNull null]};
        [keypad.layer addSublayer:layer];
        objc_setAssociatedObject(keypad, &kHighlightKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return layer;
}

// Ẩn / hiện lại những thứ app đặt đè lên bàn phím (hình thay thế, lớp làm tối phím đang bấm). Chỉ hiện lại thứ chính mình đã ẩn.
static void G6CalcHideForeign(UIView *keypad, BOOL hide) {
    CALayer *mine = objc_getAssociatedObject(keypad, &kHighlightKey);
    for (CALayer *layer in [keypad.layer.sublayers copy]) {
        if (layer == mine) continue;
        BOOL byMe = objc_getAssociatedObject(layer, &kHiddenByMeKey) != nil;
        if (hide && !layer.hidden) {
            layer.hidden = YES;
            objc_setAssociatedObject(layer, &kHiddenByMeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (!hide && byMe) {
            layer.hidden = NO;
            objc_setAssociatedObject(layer, &kHiddenByMeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

// Ảnh «phím đang bấm» kiểu cũ: UIImageView thuần là con trực tiếp của view gốc (view chứa CalcDisplayView). Ẩn mỗi lần app
// vừa hiện nó; tắt kiểu mới thì không đụng nữa (app tự hiện / ẩn nó ở lần bấm sau).
static void G6CalcHidePressedOverlay(UIView *keypad) {
    Class displayClass = objc_getClass("CalcDisplayView");
    UIView *root = nil;
    for (UIView *v = keypad.superview; v && !root; v = v.superview) {
        for (UIView *sub in v.subviews) {
            if (displayClass && [sub isKindOfClass:displayClass]) {
                root = v;
                break;
            }
        }
    }
    for (UIView *sub in root.subviews) {
        // Chỉ ảnh nhỏ, không có view con (máy nằm ngang: nửa bàn phím khoa học cũng nằm trong một UIImageView của view gốc)
        if (![sub isMemberOfClass:[UIImageView class]] || sub.hidden || sub.subviews.count > 0) continue;
        if (sub.bounds.size.width <= 120 && sub.bounds.size.height <= 120) sub.hidden = YES;
    }
}

static void G6CalcUpdateHighlight(UIView *keypad) {
    G6CalcGrid g;
    BOOL mine = gActive && G6CalcReadGrid(keypad, &g) && G6CalcKindOf(&g) != G6CalcOther && objc_getAssociatedObject(keypad, &kOriginalImageKey);
    CAShapeLayer *layer = (CAShapeLayer *)G6CalcHighlightLayer(keypad, mine);
    if (!mine) {
        layer.hidden = YES;
        return;
    }
    G6CalcHideForeign(keypad, YES);
    G6CalcHidePressedOverlay(keypad);
    CGRect frame = G6CalcKeyFrame(&g, g.pressed);
    if (CGRectIsNull(frame)) {
        layer.hidden = YES;
        return;
    }
    layer.path = G6CalcKeyPath(frame, g.button).CGPath;
    layer.hidden = NO;
    // Luôn nằm trên cùng
    if (keypad.layer.sublayers.lastObject != layer) {
        [layer removeFromSuperlayer];
        [keypad.layer addSublayer:layer];
    }
}

// Nền da quanh nửa bàn phím khoa học (UIImageView cha của nó) → đen
static void G6CalcStyleBackground(UIView *keypad, BOOL active) {
    UIImageView *background = (UIImageView *)keypad.superview;
    if (![background isMemberOfClass:[UIImageView class]]) return;
    NSDictionary *saved = objc_getAssociatedObject(background, &kBackgroundSavedKey);
    if (!active) {
        if (saved && background.image == saved[@"mine"]) background.image = saved[@"image"];
        objc_setAssociatedObject(background, &kBackgroundSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    UIImage *image = background.image;
    if (!image || (saved && image == saved[@"mine"])) return;
    // Cùng cỡ ảnh gốc (app có thể tính khung từ cỡ ảnh)
    UIGraphicsBeginImageContextWithOptions(image.size, YES, 1);
    [[UIColor blackColor] setFill];
    UIRectFill((CGRect){CGPointZero, image.size});
    UIImage *black = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!black) return;
    objc_setAssociatedObject(background, &kBackgroundSavedKey, @{@"image" : image, @"mine" : black}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    background.image = black;
}

static void G6CalcStyleKeypad(UIImageView *keypad) {
    G6CalcGrid g;
    G6CalcKind kind = G6CalcReadGrid(keypad, &g) ? G6CalcKindOf(&g) : G6CalcOther;
    UIImage *original = objc_getAssociatedObject(keypad, &kOriginalImageKey);
    if (!gActive || kind == G6CalcOther) {
        if (original) {
            keypad.image = original;
            objc_setAssociatedObject(keypad, &kOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            G6CalcHideForeign(keypad, NO);
            G6CalcHighlightLayer(keypad, NO).hidden = YES;
        }
        G6CalcStyleBackground(keypad, NO);
        return;
    }
    // Ảnh của ta luôn CÙNG CỠ với ảnh app đang đặt — KHÔNG theo cỡ view: lúc xoay máy app tạm co view về cỡ của nửa bàn phím
    // nằm ngang rồi tính khung mới từ cỡ ẢNH; dựng ảnh theo cỡ view lúc đó làm bố cục máy đứng hỏng sau khi xoay về (đã gặp).
    UIImage *current = keypad.image;
    if (current && !objc_getAssociatedObject(current, &kMineKey)) {
        // App vừa đặt ảnh mới (lần đầu, hoặc đổi ảnh): đó là ảnh gốc
        original = current;
        objc_setAssociatedObject(keypad, &kOriginalImageKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!original) return;
    CGSize size = original.size;
    if (size.width < 100 || size.height < 100) return;
    NSDictionary *alternates = objc_getAssociatedObject(keypad, &kAlternatesKey);
    // Khoá nhớ ảnh: cỡ + loại lưới + các hình thay thế đang hiện (theo thứ tự mã phím)
    NSMutableString *key = [NSMutableString stringWithFormat:@"%.0f|%.0f|%d", size.width, size.height, kind];
    for (NSNumber *tag in [alternates.allKeys sortedArrayUsingSelector:@selector(compare:)]) [key appendFormat:@"|%@=%@", tag, alternates[tag]];
    UIImage *image = gImages[key];
    if (!image) {
        image = G6CalcKeypadImage(size, &g, kind, alternates);
        if (!image) return;
        if (!gImages) gImages = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(image, &kMineKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (gImages.count > 40) [gImages removeAllObjects];
        gImages[key] = image;
    }
    if (keypad.image != image) keypad.image = image;
    if (kind == G6CalcScientific) G6CalcStyleBackground(keypad, YES);
    G6CalcUpdateHighlight(keypad);
}

static void G6CalcStyleKeypadSafe(UIImageView *keypad) {
    @try {
        G6CalcStyleKeypad(keypad);
    } @catch (NSException *e) {
        G6Log(@"máy tính: lỗi khi dựng bàn phím: %@", e);
    }
}

static void (*o_keypadLayout)(id, SEL);
static void g6_keypadLayout(UIImageView *self, SEL _cmd) {
    o_keypadLayout(self, _cmd);
    G6CalcStyleKeypadSafe(self);
}

// Sau mỗi sự kiện chạm: app vừa đổi _pressedTag (và có thể vừa thêm lớp làm tối phím)
#define G6_CALC_TOUCH_HOOK(name)                                             \
    static void (*o_##name)(id, SEL, id, id);                                \
    static void g6_##name(UIImageView *self, SEL _cmd, id touches, id event) { \
        o_##name(self, _cmd, touches, event);                                \
        @try {                                                               \
            G6CalcUpdateHighlight(self);                                     \
        } @catch (NSException *e) {                                          \
        }                                                                    \
    }
G6_CALC_TOUCH_HOOK(touchesBegan)
G6_CALC_TOUCH_HOOK(touchesMoved)
G6_CALC_TOUCH_HOOK(touchesEnded)
G6_CALC_TOUCH_HOOK(touchesCancelled)

static void (*o_touchesChanged)(id, SEL, id);
static void g6_touchesChanged(UIImageView *self, SEL _cmd, id event) {
    o_touchesChanged(self, _cmd, event);
    @try {
        G6CalcUpdateHighlight(self);
    } @catch (NSException *e) {
    }
}

static void (*o_showAlternate)(id, SEL, BOOL, id, id, int);
static void g6_showAlternate(UIImageView *self, SEL _cmd, BOOL showing, id path, id key, int tag) {
    o_showAlternate(self, _cmd, showing, path, key, tag);
    @try {
        // Nhớ «phím nào đang mang hình thay thế nào» để vẽ vào ảnh bàn phím (kể cả lúc kiểu mới đang tắt: bật lại là đúng ngay)
        if ([key isKindOfClass:[NSString class]]) {
            NSMutableDictionary *alternates = objc_getAssociatedObject(self, &kAlternatesKey);
            if (!alternates) {
                alternates = [NSMutableDictionary dictionary];
                objc_setAssociatedObject(self, &kAlternatesKey, alternates, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (showing) {
                // Vòng báo phép tính đang chờ chỉ nằm trên một phím
                if ([key isEqualToString:@"OperatorRing"]) {
                    for (NSNumber *t in [alternates allKeysForObject:key]) [alternates removeObjectForKey:t];
                }
                alternates[@(tag)] = key;
            } else if ([key isEqualToString:@"OperatorRing"]) {
                for (NSNumber *t in [alternates allKeysForObject:key]) [alternates removeObjectForKey:t];
            } else if ([alternates[@(tag)] isEqual:key]) {
                [alternates removeObjectForKey:@(tag)];
            }
        }
    } @catch (NSException *e) {
    }
    G6CalcStyleKeypadSafe(self);
}

// ---- Màn hình số ----

static UIImage *G6CalcFlatImage(CGFloat white) {
    NSString *key = [NSString stringWithFormat:@"flat|%.2f", white];
    UIImage *image = gImages[key];
    if (image) return image;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, 2), YES, 0);
    [[UIColor colorWithWhite:white alpha:1] setFill];
    UIRectFill(CGRectMake(0, 0, 2, 2));
    image = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsZero];
    UIGraphicsEndImageContext();
    if (!gImages) gImages = [NSMutableDictionary dictionary];
    if (image) gImages[key] = image;
    return image;
}

static void G6CalcStyleDisplay(UIImageView *display) {
    NSDictionary *saved = objc_getAssociatedObject(display, &kDisplaySavedKey);
    if (!gActive) {
        if (!saved) return;
        display.image = saved[@"image"] == [NSNull null] ? nil : saved[@"image"];
        display.highlightedImage = saved[@"highlighted"] == [NSNull null] ? nil : saved[@"highlighted"];
        objc_setAssociatedObject(display, &kDisplaySavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    UIImage *flat = G6CalcFlatImage(0), *selected = G6CalcFlatImage(0.16);
    if (display.image == flat) return;
    if (!saved) {
        saved = @{@"image" : display.image ?: (id)[NSNull null], @"highlighted" : display.highlightedImage ?: (id)[NSNull null]};
        objc_setAssociatedObject(display, &kDisplaySavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    display.image = flat;
    display.highlightedImage = selected;
}

static void (*o_displayLayout)(id, SEL);
static void g6_displayLayout(UIImageView *self, SEL _cmd) {
    o_displayLayout(self, _cmd);
    @try {
        G6CalcStyleDisplay(self);
    } @catch (NSException *e) {
        G6Log(@"máy tính: lỗi khi dựng màn hình số: %@", e);
    }
}

static id (*o_valueColor)(id, SEL);
static id g6_valueColor(id self, SEL _cmd) {
    return gActive ? [UIColor whiteColor] : o_valueColor(self, _cmd);
}

static id (*o_valueFont)(id, SEL, float);
static id g6_valueFont(id self, SEL _cmd, float size) {
    id font = o_valueFont(self, _cmd, size);
    if (!gActive || !G6FontAvailable()) return font;
    return G6Font(G6FontRegular, size) ?: font;
}

// ---- Cài / làm mới ----

static void G6CalcRefresh(UIView *view, Class keypadClass, Class displayClass, Class valueClass, int depth) {
    if ([view isKindOfClass:keypadClass]) G6CalcStyleKeypadSafe((UIImageView *)view);
    else if ([view isKindOfClass:displayClass]) G6CalcStyleDisplay((UIImageView *)view);
    else if ([view isKindOfClass:valueClass]) [view setNeedsDisplay];
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6CalcRefresh(sub, keypadClass, displayClass, valueClass, depth - 1);
}

void G6UIAppCalculatorApply(BOOL active) {
    static BOOL installed;
    Class keypad = objc_getClass("CalcKeypadView"), display = objc_getClass("CalcDisplayView"), value = objc_getClass("CalcValueView");
    active = active && g6_device_is_phone() && keypad && display && value;
    if (!installed && !active) return;
    if (!installed) {
        installed = YES;
        if (!class_getInstanceVariable(keypad, "_buttonTags") || !class_getInstanceVariable(keypad, "_pressedTag") ||
            ![keypad isSubclassOfClass:[UIImageView class]] || ![display isSubclassOfClass:[UIImageView class]] ||
            !G6Hook(keypad, @selector(layoutSubviews), (IMP)g6_keypadLayout, (IMP *)&o_keypadLayout)) {
            G6Log(@"máy tính: bàn phím không như đã tra — giữ kiểu gốc");
            return;
        }
        G6Hook(keypad, @selector(touchesBegan:withEvent:), (IMP)g6_touchesBegan, (IMP *)&o_touchesBegan);
        G6Hook(keypad, @selector(touchesMoved:withEvent:), (IMP)g6_touchesMoved, (IMP *)&o_touchesMoved);
        G6Hook(keypad, @selector(touchesEnded:withEvent:), (IMP)g6_touchesEnded, (IMP *)&o_touchesEnded);
        G6Hook(keypad, @selector(touchesCancelled:withEvent:), (IMP)g6_touchesCancelled, (IMP *)&o_touchesCancelled);
        SEL changed = NSSelectorFromString(@"touchesChangedWithEvent:");
        if (class_getInstanceMethod(keypad, changed)) G6Hook(keypad, changed, (IMP)g6_touchesChanged, (IMP *)&o_touchesChanged);
        SEL alternate = NSSelectorFromString(@"setShowingAlternateImage:withPath:forKey:onTag:");
        Method am = class_getInstanceMethod(keypad, alternate);
        if (am && strcmp(method_getTypeEncoding(am) ?: "", "v24@0:4c8@12@16i20") == 0) {
            G6Hook(keypad, alternate, (IMP)g6_showAlternate, (IMP *)&o_showAlternate);
        }
        G6Hook(display, @selector(layoutSubviews), (IMP)g6_displayLayout, (IMP *)&o_displayLayout);
        // Hàm của lớp: móc trên siêu lớp (metaclass)
        Class meta = object_getClass(value);
        SEL colorSel = NSSelectorFromString(@"textColor"), fontSel = NSSelectorFromString(@"fontForSize:");
        if (class_getClassMethod(value, colorSel)) G6Hook(meta, colorSel, (IMP)g6_valueColor, (IMP *)&o_valueColor);
        Method fm = class_getClassMethod(value, fontSel);
        if (fm && strcmp(method_getTypeEncoding(fm) ?: "", "@12@0:4f8") == 0) G6Hook(meta, fontSel, (IMP)g6_valueFont, (IMP *)&o_valueFont);
        G6Log(@"máy tính: vẽ lại bàn phím + màn hình số");
    }
    if (!o_keypadLayout) return;
    gActive = active;
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6CalcRefresh(window, keypad, display, value, 8);
}
