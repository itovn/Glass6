// App Điện thoại (com.apple.mobilephone) trên iPhone — bàn phím số kiểu iOS 26.
//
// Các thẻ Mục ưa thích / Gần đây / Danh bạ / Thư thoại là thanh + bảng chuẩn nên đã theo kiểu chung của Glass 6 (thanh thẻ nổi,
// thanh phẳng, bảng). Chỗ app tự vẽ là thẻ «Bàn phím» (tra trên máy 20/11/2026):
//   DialerView (320×499)
//     DialerLCDView (0 0; 320 113)        _backgroundView: UIImageView ảnh dải xanh (-_backgroundImage); _numberLabel: số đang gõ
//     DialerPhonePad : TPPhonePad (0 113; 320 308.5)   UIControl tự vẽ trong -drawRect: — vẽ nguyên ảnh -_keypadImage (cả 12
//                                         phím trong một ảnh), phím đang bấm thì vẽ đè phần tương ứng cắt từ -_pressedImage theo
//                                         -_rectForKey:
//     UIButton × 3 (hàng dưới, cao 78)    thêm vào danh bạ / gọi / xoá: ảnh nền kín nút (nút gọi thêm hình + chữ «Gọi»)
// Cách làm — không đổi khung, vùng chạm hay cách bấm của bất cứ thứ gì, chỉ đổi hình:
//   - -_keypadImage / -_pressedImage trả ảnh tự vẽ CÙNG CỠ ảnh gốc: nền phẳng + 12 phím tròn (chữ số Inter, hàng chữ cái
//     nhỏ bên dưới), tâm phím lấy từ chính -_rectForKey: (cột hai bên kéo lại gần cột giữa như iOS 26 nhưng vẫn nằm trọn
//     trong ô chạm của mình, nên phần «đang bấm» cắt theo ô vẫn khớp);
//   - ba nút hàng dưới: ảnh nền tự vẽ cùng cỡ nút — nút gọi là đĩa xanh lá có hình ống nghe (lấy hình gốc của app), hai nút
//     kia chỉ còn hình (người + dấu cộng, phím xoá) trên nền trong; chữ «Gọi» và hình gốc của nút gọi được làm trong suốt;
//   - nền LCD → màu nền phẳng, số đang gõ đổi màu chữ theo chế độ, bỏ bóng;
//   - chế độ tối: cả màn này nền đen (trùng lề của thanh thẻ nổi) → báo thanh trạng thái tô đen khi màn này đang hiện.
//   - thẻ «Thư thoại» khi không nối được hộp thư (VoicemailOutOfOrderView: hình + hai dòng chữ trên nền trắng): ở chế độ tối
//     mang bộ lọc «đảo sáng tối» như các bảng của app này (G6UITablesSetInvertCustomCells, bật ở main.m).
// Đi theo thành phần «bars» (bảng màu sáng / tối) + công tắc «app_skins». Tắt thì ảnh gốc được dùng lại ngay ở lượt vẽ sau.
// Màn hình đang gọi / cuộc gọi đến KHÔNG nằm trong phạm vi (xem docs/IPHONE.md 3.9).
#import "G6UI.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

// Đường kính phím tròn, khoảng cách giữa hai cột phím (mép tới mép)
static const CGFloat kKeySize = 65, kKeyGapX = 28;

static BOOL gActive;
static BOOL gDrawing;   // đang tự vẽ ảnh bàn phím (hỏi lại -_rectForKey: có thể vòng về -_keypadImage)
static NSMutableDictionary *gImages;
static char kButtonSavedKey;

static NSArray *G6PhoneDigits(void) {
    return @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"*", @"0", @"#"];
}

static NSArray *G6PhoneLetters(void) {
    return @[@"", @"ABC", @"DEF", @"GHI", @"JKL", @"MNO", @"PQRS", @"TUV", @"WXYZ", @"", @"+", @""];
}

static BOOL G6PhoneDark(void) {
    return G6UIBarsDark();
}

// Nền của cả màn bàn phím: sáng = màu mặt thanh (liền với thanh trạng thái và lề thanh thẻ), tối = đen
static UIColor *G6PhoneBackground(void) {
    return G6PhoneDark() ? [UIColor blackColor] : [UIColor colorWithWhite:G6UIBarSurfaceWhite() alpha:1];
}

static UIColor *G6PhoneTextColor(void) {
    return G6PhoneDark() ? [UIColor whiteColor] : [UIColor colorWithWhite:0.07 alpha:1];
}

static UIColor *G6PhoneKeyFill(BOOL pressed) {
    if (G6PhoneDark()) return [UIColor colorWithWhite:1 alpha:pressed ? 0.42 : 0.17];
    return [UIColor colorWithWhite:0 alpha:pressed ? 0.22 : 0.075];
}

static UIColor *G6PhoneGreen(BOOL pressed) {
    CGFloat k = pressed ? 0.80 : 1;
    return G6PhoneDark() ? [UIColor colorWithRed:0.19 * k green:0.82 * k blue:0.35 * k alpha:1]
                         : [UIColor colorWithRed:0.20 * k green:0.78 * k blue:0.35 * k alpha:1];
}

static void G6PhoneDrawCentered(NSString *text, UIFont *font, CGPoint center, CGFloat tracking) {
    if (!text.length) return;
    if (tracking <= 0 || text.length == 1) {
        CGSize size = [text sizeWithFont:font];
        [text drawAtPoint:CGPointMake(round(center.x - size.width / 2), round(center.y - size.height / 2)) withFont:font];
        return;
    }
    // Chữ cái giãn cách: vẽ từng chữ
    CGFloat total = -tracking;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < text.length; i++) {
        NSString *ch = [text substringWithRange:NSMakeRange(i, 1)];
        [parts addObject:ch];
        total += [ch sizeWithFont:font].width + tracking;
    }
    CGFloat x = center.x - total / 2, h = font.lineHeight;
    for (NSString *ch in parts) {
        [ch drawAtPoint:CGPointMake(x, round(center.y - h / 2)) withFont:font];
        x += [ch sizeWithFont:font].width + tracking;
    }
}

// Tâm phím tròn của ô chạm `cell` (toạ độ ảnh): cột giữa đứng giữa ô, hai cột bên kéo về phía cột giữa
static CGPoint G6PhoneKeyCenter(CGRect cell, CGFloat width) {
    CGFloat mid = width / 2, x = CGRectGetMidX(cell);
    CGFloat pitch = kKeySize + kKeyGapX;
    if (x < mid - 20) x = mid - pitch;
    else if (x > mid + 20) x = mid + pitch;
    else x = mid;
    // Không để phím tròn lọt ra ngoài ô chạm của mình
    x = MAX(CGRectGetMinX(cell) + kKeySize / 2, MIN(CGRectGetMaxX(cell) - kKeySize / 2, x));
    return CGPointMake(x, CGRectGetMidY(cell));
}

// Ảnh bàn phím (12 phím) cỡ `size`; `cells` = 12 ô chạm theo toạ độ ảnh, đã xếp theo hàng rồi cột
static UIImage *G6PhoneKeypadImage(CGSize size, NSArray *cells, BOOL pressed) {
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    [G6PhoneBackground() setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIFont *digitFont = G6Font(G6FontRegular, 31), *symbolFont = G6Font(G6FontRegular, 34), *letterFont = G6Font(G6FontSemiBold, 9.5);
    NSArray *digits = G6PhoneDigits(), *letters = G6PhoneLetters();
    for (NSUInteger i = 0; i < cells.count && i < digits.count; i++) {
        CGRect cell = [cells[i] CGRectValue];
        CGFloat d = MIN(kKeySize, MIN(cell.size.width, cell.size.height) - 4);
        CGPoint c = G6PhoneKeyCenter(cell, size.width);
        [G6PhoneKeyFill(pressed) setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - d / 2, c.y - d / 2, d, d)] fill];
        [G6PhoneTextColor() setFill];
        NSString *digit = digits[i], *sub = letters[i];
        BOOL symbol = [digit isEqualToString:@"*"] || [digit isEqualToString:@"#"];
        if (symbol) {
            // Dấu sao của phông nằm cao: hạ xuống cho cân giữa phím
            G6PhoneDrawCentered(digit, symbolFont, CGPointMake(c.x, c.y + ([digit isEqualToString:@"*"] ? 7 : 0)), 0);
        } else {
            G6PhoneDrawCentered(digit, digitFont, CGPointMake(c.x, c.y - 6), 0);
            [[G6PhoneTextColor() colorWithAlphaComponent:0.82] setFill];
            G6PhoneDrawCentered(sub, [sub isEqualToString:@"+"] ? G6Font(G6FontMedium, 12) : letterFont, CGPointMake(c.x, c.y + 16), 1.6);
        }
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// 12 ô chạm của bàn phím theo toạ độ ẢNH (trừ gốc ảnh), xếp theo hàng rồi cột. nil nếu không hỏi được.
static NSArray *G6PhoneCells(UIView *pad, CGSize imageSize) {
    SEL rectSel = NSSelectorFromString(@"_rectForKey:"), originSel = NSSelectorFromString(@"_keypadOrigin");
    if (![pad respondsToSelector:rectSel]) return nil;
    CGPoint origin = CGPointZero;
    // armv7: cấu trúc lớn hơn 4 byte (kể cả CGPoint) trả qua vùng nhớ → objc_msgSend_stret, gọi nhầm objc_msgSend là sập
    if ([pad respondsToSelector:originSel]) origin = ((CGPoint (*)(id, SEL))objc_msgSend_stret)(pad, originSel);
    NSMutableArray *cells = [NSMutableArray array];
    for (int i = 0; i < 12; i++) {
        CGRect r = ((CGRect (*)(id, SEL, int))objc_msgSend_stret)(pad, rectSel, i);
        r = CGRectOffset(r, -origin.x, -origin.y);
        if (r.size.width < 30 || r.size.height < 30 || !CGRectIntersectsRect(r, CGRectMake(0, 0, imageSize.width, imageSize.height))) return nil;
        [cells addObject:[NSValue valueWithCGRect:r]];
    }
    [cells sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        CGRect ra = a.CGRectValue, rb = b.CGRectValue;
        if (fabs(ra.origin.y - rb.origin.y) > 10) return ra.origin.y < rb.origin.y ? NSOrderedAscending : NSOrderedDescending;
        if (fabs(ra.origin.x - rb.origin.x) < 1) return NSOrderedSame;
        return ra.origin.x < rb.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    return cells;
}

static UIImage *G6PhonePadImage(UIView *pad, UIImage *original, BOOL pressed) {
    if (!gActive || gDrawing || !original) return original;
    CGSize size = original.size;
    NSString *key = [NSString stringWithFormat:@"pad|%d|%d|%.1f|%.1f", pressed, G6PhoneDark(), size.width, size.height];
    UIImage *image = gImages[key];
    if (image) return image;
    gDrawing = YES;
    @try {
        NSArray *cells = G6PhoneCells(pad, size);
        if (cells.count == 12) image = G6PhoneKeypadImage(size, cells, pressed);
    } @catch (NSException *e) {
        G6Log(@"điện thoại: lỗi khi vẽ bàn phím: %@", e);
    }
    gDrawing = NO;
    if (!image) return original;
    if (!gImages) gImages = [NSMutableDictionary dictionary];
    gImages[key] = image;
    return image;
}

static UIImage *(*o_keypadImage)(id, SEL);
static UIImage *g6_keypadImage(UIView *self, SEL _cmd) {
    return G6PhonePadImage(self, o_keypadImage(self, _cmd), NO);
}

static UIImage *(*o_pressedImage)(id, SEL);
static UIImage *g6_pressedImage(UIView *self, SEL _cmd) {
    return G6PhonePadImage(self, o_pressedImage(self, _cmd), YES);
}

// ---- Ba nút hàng dưới ----

// Hình «thêm vào danh bạ»: dấu cộng + người, tâm ở `c`
static void G6PhoneDrawAddContact(CGContextRef ctx, CGPoint c, UIColor *color) {
    [color setFill];
    [color setStroke];
    // Đầu + vai
    CGFloat px = c.x + 6;
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(px - 5.5, c.y - 12, 11, 11)] fill];
    UIBezierPath *body = [UIBezierPath bezierPath];
    [body moveToPoint:CGPointMake(px - 11.5, c.y + 12)];
    [body addCurveToPoint:CGPointMake(px, c.y + 1) controlPoint1:CGPointMake(px - 11.5, c.y + 4) controlPoint2:CGPointMake(px - 6, c.y + 1)];
    [body addCurveToPoint:CGPointMake(px + 11.5, c.y + 12) controlPoint1:CGPointMake(px + 6, c.y + 1) controlPoint2:CGPointMake(px + 11.5, c.y + 4)];
    [body closePath];
    [body fill];
    // Dấu cộng bên trái
    CGFloat sx = c.x - 13, sy = c.y - 3;
    CGContextSetLineWidth(ctx, 2);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextMoveToPoint(ctx, sx - 4.5, sy);
    CGContextAddLineToPoint(ctx, sx + 4.5, sy);
    CGContextMoveToPoint(ctx, sx, sy - 4.5);
    CGContextAddLineToPoint(ctx, sx, sy + 4.5);
    CGContextStrokePath(ctx);
}

// Hình phím xoá: mũi tên bo góc chỉ sang trái, dấu × khoét ở giữa
static void G6PhoneDrawDelete(CGContextRef ctx, CGPoint c, UIColor *color) {
    CGFloat w = 30, h = 21, tip = 10, r = 4;
    CGFloat x0 = c.x - w / 2, x1 = c.x + w / 2, y0 = c.y - h / 2, y1 = c.y + h / 2;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(x0, c.y)];
    [path addLineToPoint:CGPointMake(x0 + tip, y0)];
    [path addLineToPoint:CGPointMake(x1 - r, y0)];
    [path addQuadCurveToPoint:CGPointMake(x1, y0 + r) controlPoint:CGPointMake(x1, y0)];
    [path addLineToPoint:CGPointMake(x1, y1 - r)];
    [path addQuadCurveToPoint:CGPointMake(x1 - r, y1) controlPoint:CGPointMake(x1, y1)];
    [path addLineToPoint:CGPointMake(x0 + tip, y1)];
    [path closePath];
    path.lineJoinStyle = kCGLineJoinRound;
    // Tô + viền chồng lên nhau: vẽ đặc trong một lớp rồi mới áp độ trong của màu, kẻo mép đậm hơn ruột
    CGFloat alpha = CGColorGetAlpha(color.CGColor);
    UIColor *solid = [color colorWithAlphaComponent:1];
    CGContextSaveGState(ctx);
    CGContextSetAlpha(ctx, alpha);
    CGContextBeginTransparencyLayer(ctx, NULL);
    [solid setFill];
    [solid setStroke];
    path.lineWidth = 2;
    [path fill];
    [path stroke];
    // Dấu × khoét thủng
    CGContextSaveGState(ctx);
    CGContextSetBlendMode(ctx, kCGBlendModeClear);
    CGContextSetLineWidth(ctx, 2.2);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGFloat cx = c.x + tip / 2 - 1, d = 4.2;
    CGContextMoveToPoint(ctx, cx - d, c.y - d);
    CGContextAddLineToPoint(ctx, cx + d, c.y + d);
    CGContextMoveToPoint(ctx, cx + d, c.y - d);
    CGContextAddLineToPoint(ctx, cx - d, c.y + d);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);
    CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);
}

// Ảnh nền của một nút hàng dưới. kind: 0 = thêm vào danh bạ, 1 = gọi, 2 = xoá. `side`: nút nằm bên trái (−1) / phải (+1) màn
// hình → hình dời về phía cột phím cùng bên.
static UIImage *G6PhoneButtonImage(int kind, CGSize size, CGFloat screenWidth, CGFloat buttonX, BOOL pressed, UIImage *glyph) {
    NSString *key = [NSString stringWithFormat:@"btn|%d|%d|%d|%.1f|%.1f|%.1f", kind, pressed, G6PhoneDark(), size.width, size.height, buttonX];
    UIImage *image = gImages[key];
    if (image) return image;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat pitch = kKeySize + kKeyGapX, mid = screenWidth / 2;
    CGPoint c = CGPointMake(size.width / 2, size.height / 2);
    if (kind == 0) c.x = mid - pitch - buttonX;
    if (kind == 2) c.x = mid + pitch - buttonX;
    c.x = MAX(22, MIN(size.width - 22, c.x));
    if (kind == 1) {
        CGFloat d = MIN(kKeySize, size.height - 6);
        [G6PhoneGreen(pressed) setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - d / 2, c.y - d / 2, d, d)] fill];
        if (glyph) {
            // Hình ống nghe gốc của app (trắng), phóng lên một chút
            CGFloat k = 1.25;
            CGSize g = CGSizeMake(glyph.size.width * k, glyph.size.height * k);
            [glyph drawInRect:CGRectMake(c.x - g.width / 2, c.y - g.height / 2, g.width, g.height)];
        }
    } else {
        UIColor *color = [G6PhoneTextColor() colorWithAlphaComponent:pressed ? 0.40 : 0.82];
        if (kind == 0) G6PhoneDrawAddContact(ctx, c, color);
        else G6PhoneDrawDelete(ctx, c, color);
    }
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!gImages) gImages = [NSMutableDictionary dictionary];
    if (image) gImages[key] = image;
    return image;
}

static void G6PhoneStyleButton(UIButton *button, int kind, UIView *dialer) {
    if (![button isKindOfClass:[UIButton class]]) return;
    NSMutableDictionary *saved = objc_getAssociatedObject(button, &kButtonSavedKey);
    NSArray *states = @[@(UIControlStateNormal), @(UIControlStateHighlighted), @(UIControlStateDisabled)];
    if (!gActive) {
        if (!saved) return;
        for (NSNumber *state in states) {
            id image = saved[state];
            [button setBackgroundImage:image == [NSNull null] ? nil : image forState:(UIControlState)state.unsignedIntegerValue];
        }
        button.imageView.alpha = 1;
        button.titleLabel.alpha = 1;
        objc_setAssociatedObject(button, &kButtonSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    CGSize size = button.bounds.size;
    if (size.width < 30 || size.height < 30) return;
    if (!saved) {
        saved = [NSMutableDictionary dictionary];
        for (NSNumber *state in states) {
            UIControlState s = (UIControlState)state.unsignedIntegerValue;
            // Ảnh đặt riêng cho trạng thái này (trạng thái không đặt thì UIKit trả ảnh của trạng thái thường)
            UIImage *image = [button backgroundImageForState:s];
            if (s != UIControlStateNormal && image == [button backgroundImageForState:UIControlStateNormal]) image = nil;
            saved[state] = image ?: (id)[NSNull null];
        }
        objc_setAssociatedObject(button, &kButtonSavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIImage *glyph = nil;
    if (kind == 1) {
        SEL glyphSel = NSSelectorFromString(@"_callGlyphImage");
        id g = [dialer respondsToSelector:glyphSel] ? ((id (*)(id, SEL))objc_msgSend)(dialer, glyphSel) : nil;
        if ([g isKindOfClass:[UIImage class]]) glyph = g;
    }
    CGFloat screenWidth = dialer.bounds.size.width, x = button.frame.origin.x;
    UIImage *normal = G6PhoneButtonImage(kind, size, screenWidth, x, NO, glyph);
    UIImage *pressed = G6PhoneButtonImage(kind, size, screenWidth, x, YES, glyph);
    if (normal && [button backgroundImageForState:UIControlStateNormal] != normal) {
        [button setBackgroundImage:normal forState:UIControlStateNormal];
        [button setBackgroundImage:pressed forState:UIControlStateHighlighted];
        [button setBackgroundImage:normal forState:UIControlStateDisabled];
    }
    if (kind == 1) {
        // Hình + chữ «Gọi» gốc: đã có hình trong đĩa xanh
        if (button.imageView.alpha != 0) button.imageView.alpha = 0;
        if (button.titleLabel.alpha != 0) button.titleLabel.alpha = 0;
    }
}

// ---- Cả màn bàn phím ----

static id G6PhoneIvar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    return enc && enc[0] == '@' ? object_getIvar(obj, iv) : nil;
}

static char kLabelSavedKey, kDialerBgKey;

static void G6PhoneStyleLabel(UILabel *label, BOOL secondary) {
    if (![label isKindOfClass:[UILabel class]]) return;
    NSDictionary *saved = objc_getAssociatedObject(label, &kLabelSavedKey);
    if (!gActive) {
        if (!saved) return;
        label.textColor = saved[@"text"] == [NSNull null] ? nil : saved[@"text"];
        label.shadowColor = saved[@"shadow"] == [NSNull null] ? nil : saved[@"shadow"];
        objc_setAssociatedObject(label, &kLabelSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!saved) {
        saved = @{@"text" : label.textColor ?: (id)[NSNull null], @"shadow" : label.shadowColor ?: (id)[NSNull null]};
        objc_setAssociatedObject(label, &kLabelSavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *color = secondary ? [G6PhoneTextColor() colorWithAlphaComponent:0.6] : G6PhoneTextColor();
    if (![label.textColor isEqual:color]) label.textColor = color;
    if (label.shadowColor) label.shadowColor = nil;
}

static void G6PhoneStyleLabels(UIView *view, BOOL secondary, int depth) {
    if ([view isKindOfClass:[UILabel class]]) G6PhoneStyleLabel((UILabel *)view, secondary);
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6PhoneStyleLabels(sub, secondary, depth - 1);
}

static void G6PhoneStyleDialer(UIView *dialer) {
    UIView *lcd = G6PhoneIvar(dialer, "_lcdView"), *pad = G6PhoneIvar(dialer, "_phonePadView");
    // Nền của cả màn
    if (gActive) {
        if (!objc_getAssociatedObject(dialer, &kDialerBgKey)) {
            objc_setAssociatedObject(dialer, &kDialerBgKey, dialer.backgroundColor ?: (id)[NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIColor *bg = G6PhoneBackground();
        if (![dialer.backgroundColor isEqual:bg]) dialer.backgroundColor = bg;
    } else {
        id saved = objc_getAssociatedObject(dialer, &kDialerBgKey);
        if (saved) {
            dialer.backgroundColor = saved == [NSNull null] ? nil : saved;
            objc_setAssociatedObject(dialer, &kDialerBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    // LCD: ảnh dải xanh ẩn đi (nền của màn lộ ra), chữ theo chế độ
    UIView *lcdBackground = G6PhoneIvar(lcd, "_backgroundView");
    if ([lcdBackground isKindOfClass:[UIView class]] && lcdBackground.hidden != gActive) lcdBackground.hidden = gActive;
    G6PhoneStyleLabel(G6PhoneIvar(lcd, "_numberLabel"), NO);
    UIView *names = G6PhoneIvar(lcd, "_nameAndLabelView");
    if ([names isKindOfClass:[UIView class]]) G6PhoneStyleLabels(names, YES, 3);
    // Ba nút hàng dưới
    G6PhoneStyleButton(G6PhoneIvar(dialer, "_addContactButton"), 0, dialer);
    G6PhoneStyleButton(G6PhoneIvar(dialer, "_callButton"), 1, dialer);
    G6PhoneStyleButton(G6PhoneIvar(dialer, "_deleteButton"), 2, dialer);
    if ([pad isKindOfClass:[UIView class]]) [pad setNeedsDisplay];
}

// Màn bàn phím đang hiện ở chế độ tối: thanh trạng thái tô đen cho liền với màn
static void G6PhoneUpdateStatusBar(UIView *dialer) {
    BOOL showing = gActive && dialer.window != nil;
    G6UIStatusBarSetOverride(showing && G6PhoneDark() ? [UIColor blackColor] : nil);
}

static void (*o_dialerLayout)(id, SEL);
static void g6_dialerLayout(UIView *self, SEL _cmd) {
    o_dialerLayout(self, _cmd);
    @try {
        G6PhoneStyleDialer(self);
    } @catch (NSException *e) {
        G6Log(@"điện thoại: lỗi khi dựng bàn phím: %@", e);
    }
}

static void (*o_dialerMoved)(id, SEL);
static void g6_dialerMoved(UIView *self, SEL _cmd) {
    o_dialerMoved(self, _cmd);
    @try {
        G6PhoneUpdateStatusBar(self);
    } @catch (NSException *e) {
    }
}

// ---- View nền trắng không phải bảng: đảo màu ở chế độ tối ----

static char kPhoneInvertedKey;

static void G6PhoneInvertView(UIView *view) {
    BOOL want = gActive && G6IsDark(), has = objc_getAssociatedObject(view, &kPhoneInvertedKey) != nil;
    if (want && !has) {
        id filter = G6UISkinInvertFilter();
        if (!filter) return;
        view.layer.filters = @[filter];
        objc_setAssociatedObject(view, &kPhoneInvertedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!want && has) {
        view.layer.filters = nil;
        objc_setAssociatedObject(view, &kPhoneInvertedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*o_voicemailMoved)(id, SEL);
static void g6_voicemailMoved(UIView *self, SEL _cmd) {
    o_voicemailMoved(self, _cmd);
    @try {
        if (self.window) G6PhoneInvertView(self);
    } @catch (NSException *e) {
    }
}

static void G6PhoneRefresh(UIView *view, Class dialerClass, Class voicemailClass, int depth) {
    if ([view isKindOfClass:dialerClass]) {
        G6PhoneStyleDialer(view);
        G6PhoneUpdateStatusBar(view);
        [view setNeedsLayout];
        return;
    }
    if (voicemailClass && [view isKindOfClass:voicemailClass]) {
        G6PhoneInvertView(view);
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6PhoneRefresh(sub, dialerClass, voicemailClass, depth - 1);
}

void G6UIAppPhoneApply(BOOL active) {
    static BOOL installed;
    Class dialer = objc_getClass("DialerView"), pad = objc_getClass("DialerPhonePad");
    active = active && g6_device_is_phone() && dialer && pad && G6UIBarsActive();
    if (!installed && !active) return;
    if (!installed) {
        installed = YES;
        SEL keypadSel = NSSelectorFromString(@"_keypadImage"), pressedSel = NSSelectorFromString(@"_pressedImage");
        if (!class_getInstanceMethod(pad, NSSelectorFromString(@"_rectForKey:")) || !class_getInstanceVariable(dialer, "_phonePadView") ||
            !G6Hook(pad, keypadSel, (IMP)g6_keypadImage, (IMP *)&o_keypadImage)) {
            G6Log(@"điện thoại: bàn phím không như đã tra — giữ kiểu gốc");
            return;
        }
        G6Hook(pad, pressedSel, (IMP)g6_pressedImage, (IMP *)&o_pressedImage);
        G6Hook(dialer, @selector(layoutSubviews), (IMP)g6_dialerLayout, (IMP *)&o_dialerLayout);
        G6Hook(dialer, @selector(didMoveToWindow), (IMP)g6_dialerMoved, (IMP *)&o_dialerMoved);
        G6HookNamed("VoicemailOutOfOrderView", @selector(didMoveToWindow), (IMP)g6_voicemailMoved, (IMP *)&o_voicemailMoved);
        G6Log(@"điện thoại: vẽ lại bàn phím số");
    }
    if (!o_keypadImage || !o_pressedImage || !o_dialerLayout) return;
    gActive = active;
    // Đổi sáng ↔ tối / bật tắt lúc app đang chạy: ảnh vẽ theo bảng màu cũ bỏ đi, màn đang hiện dựng lại
    [gImages removeAllObjects];
    Class voicemail = objc_getClass("VoicemailOutOfOrderView");
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6PhoneRefresh(window, dialer, voicemail, 14);
}
