// Biểu tượng các mục trong app Cài đặt (thành phần «settings_icons», chỉ chạy trong com.apple.Preferences).
//
// iOS 6: mỗi mục một ảnh nhỏ 29×29 kiểu giả vật liệu. Kiểu mới (như iPadOS 26): ô màu bo góc liên tục, bên trong là hình trắng.
//   - Mục hệ thống (Máy bay, Wi-Fi, Bluetooth, Cài đặt chung…): Glass 6 TỰ VẼ ô màu + hình trắng bằng CoreGraphics — không
//     dùng hình của ai. Tra theo mã mục của Cài đặt (PSSpecifier.identifier).
//   - Mục của app (Ghi chú, Safari, Nhạc, app cài thêm, tweak…): giữ ảnh sẵn có, chỉ cắt lại theo cùng hình ô bo góc.
// Cả hai loại đều đi qua g6_icon_render của lõi (cắt hình bo góc liên tục + viền sáng + kiểu biểu tượng đang chọn ở màn hình
// chính), nên biểu tượng trong Cài đặt cùng một dáng với biểu tượng ngoài màn hình chính.
//
// Gắn: -[PSTableCell setIcon:] (mọi đường đặt biểu tượng của ô Cài đặt đều qua đây, kể cả biểu tượng nạp chậm của danh sách
// app) — đổi ảnh trước khi đưa cho hàm gốc. Tắt thành phần: bảo các ô đang hiện nạp lại nội dung, ảnh gốc trở về.
#import "G6UI.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Core.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static BOOL gActive, gDark;
static NSString *gSignature;
static NSMutableDictionary *gTiles;  // mã mục → UIImage đã dựng
static char kProcessedKey, kShapedKey;

// Cạnh ô biểu tượng (điểm) và khung vẽ hình bên trong: hình được vẽ trong hệ toạ độ 24×24 rồi thu vào giữa ô
static const CGFloat kTile = 29, kGlyphBox = 24, kGlyphSide = 19;

typedef void (^G6GlyphBlock)(CGContextRef ctx, UIColor *tile);

// ---- Hình: vẽ màu trắng trong khung 24×24, gốc ở góc trên trái ----

static UIBezierPath *G6Round(CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat r) {
    return [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, w, h) cornerRadius:r];
}

static void G6StrokeArc(CGPoint c, CGFloat radius, CGFloat fromDeg, CGFloat toDeg, CGFloat width) {
    UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:c radius:radius startAngle:fromDeg * M_PI / 180 endAngle:toDeg * M_PI / 180 clockwise:YES];
    arc.lineWidth = width;
    arc.lineCapStyle = kCGLineCapRound;
    [arc stroke];
}

static void G6Polygon(const CGFloat *xy, int count) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(xy[0], xy[1])];
    for (int i = 1; i < count; i++) [p addLineToPoint:CGPointMake(xy[i * 2], xy[i * 2 + 1])];
    [p closePath];
    p.lineJoinStyle = kCGLineJoinRound;
    [p fill];
}

static NSDictionary *G6Glyphs(void) {
    static NSDictionary *glyphs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Máy bay: thân, cánh, đuôi — xoay 45° cho mũi chếch lên phải
        G6GlyphBlock airplane = ^(CGContextRef ctx, UIColor *tile) {
            CGContextTranslateCTM(ctx, 12, 12);
            CGContextRotateCTM(ctx, M_PI_4);
            CGContextTranslateCTM(ctx, -12, -12);
            [G6Round(10.4, 1.5, 3.2, 20.5, 1.6) fill];
            const CGFloat wings[] = {12, 7, 22.5, 14.2, 22.5, 16.6, 13.6, 13.8, 10.4, 13.8, 1.5, 16.6, 1.5, 14.2};
            G6Polygon(wings, 7);
            const CGFloat tail[] = {12, 17, 16.8, 20.6, 16.8, 22.2, 12, 21, 7.2, 22.2, 7.2, 20.6};
            G6Polygon(tail, 6);
        };
        // Wi-Fi: ba cung + chấm
        G6GlyphBlock wifi = ^(CGContextRef ctx, UIColor *tile) {
            CGPoint c = CGPointMake(12, 19.2);
            G6StrokeArc(c, 14.2, 225, 315, 2.7);
            G6StrokeArc(c, 9.4, 225, 315, 2.7);
            G6StrokeArc(c, 4.7, 225, 315, 2.7);
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10.1, 17.3, 3.8, 3.8)] fill];
        };
        // Bluetooth: chữ rune
        G6GlyphBlock bluetooth = ^(CGContextRef ctx, UIColor *tile) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(6.8, 7.4)];
            [p addLineToPoint:CGPointMake(16.6, 16.4)];
            [p addLineToPoint:CGPointMake(12, 21)];
            [p addLineToPoint:CGPointMake(12, 3)];
            [p addLineToPoint:CGPointMake(16.6, 7.6)];
            [p addLineToPoint:CGPointMake(6.8, 16.6)];
            p.lineWidth = 2.1;
            p.lineJoinStyle = kCGLineJoinRound;
            p.lineCapStyle = kCGLineCapRound;
            [p stroke];
        };
        // Dữ liệu di động: bốn cột sóng cao dần
        G6GlyphBlock cellular = ^(CGContextRef ctx, UIColor *tile) {
            for (int i = 0; i < 4; i++) {
                CGFloat h = 5 + i * 4.3;
                [G6Round(3.2 + i * 4.9, 20.5 - h, 3.4, h, 1.2) fill];
            }
        };
        // Điểm truy cập cá nhân: hai mắt xích lồng nhau
        G6GlyphBlock hotspot = ^(CGContextRef ctx, UIColor *tile) {
            for (int i = 0; i < 2; i++) {
                UIBezierPath *ring = G6Round(2.6 + i * 7.6, 8.2, 11.2, 7.6, 3.8);
                ring.lineWidth = 2.3;
                [ring stroke];
            }
        };
        // VPN: ba chữ cái
        G6GlyphBlock vpn = ^(CGContextRef ctx, UIColor *tile) {
            UIFont *font = [UIFont boldSystemFontOfSize:10.5];
            CGSize size = [@"VPN" sizeWithFont:font];
            [@"VPN" drawAtPoint:CGPointMake(12 - size.width / 2, 12 - size.height / 2) withFont:font];
        };
        // Không làm phiền: trăng khuyết = đĩa tròn trừ đi một đĩa lệch
        G6GlyphBlock moon = ^(CGContextRef ctx, UIColor *tile) {
            CGContextSaveGState(ctx);
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(3.2, 3.2, 17.6, 17.6)] addClip];
            UIBezierPath *cut = [UIBezierPath bezierPathWithRect:CGRectMake(-10, -10, 44, 44)];
            [cut appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(8.6, 0.6, 15.4, 15.4)]];
            cut.usesEvenOddFillRule = YES;
            [cut fill];
            CGContextRestoreGState(ctx);
        };
        // Thông báo: chuông
        G6GlyphBlock bell = ^(CGContextRef ctx, UIColor *tile) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(4.4, 17.6)];
            [p addLineToPoint:CGPointMake(6.4, 15.2)];
            [p addCurveToPoint:CGPointMake(12, 4.6) controlPoint1:CGPointMake(6.4, 8.6) controlPoint2:CGPointMake(8.4, 4.6)];
            [p addCurveToPoint:CGPointMake(17.6, 15.2) controlPoint1:CGPointMake(15.6, 4.6) controlPoint2:CGPointMake(17.6, 8.6)];
            [p addLineToPoint:CGPointMake(19.6, 17.6)];
            [p closePath];
            p.lineJoinStyle = kCGLineJoinRound;
            [p fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10, 18.4, 4, 3.4)] fill];
            [G6Round(11.1, 2.6, 1.8, 3, 0.9) fill];
        };
        // Cài đặt chung: bánh răng 8 răng có lỗ giữa
        G6GlyphBlock gear = ^(CGContextRef ctx, UIColor *tile) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            CGFloat rOut = 10.2, rIn = 7.6;
            for (int i = 0; i < 8; i++) {
                CGFloat a = i * M_PI / 4;
                const CGFloat offsets[4] = {-0.26, -0.15, 0.15, 0.26};
                for (int k = 0; k < 4; k++) {
                    CGFloat r = (k == 0 || k == 3) ? rIn : rOut, angle = a + offsets[k];
                    CGPoint pt = CGPointMake(12 + r * cos(angle), 12 + r * sin(angle));
                    if (i == 0 && k == 0) [p moveToPoint:pt];
                    else [p addLineToPoint:pt];
                }
            }
            [p closePath];
            [p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(8.6, 8.6, 6.8, 6.8)]];
            p.usesEvenOddFillRule = YES;
            p.lineJoinStyle = kCGLineJoinRound;
            [p fill];
        };
        // Âm thanh: loa + hai vòng sóng
        G6GlyphBlock speaker = ^(CGContextRef ctx, UIColor *tile) {
            const CGFloat body[] = {3.2, 9.4, 7.2, 9.4, 12.4, 4.8, 12.4, 19.2, 7.2, 14.6, 3.2, 14.6};
            G6Polygon(body, 6);
            G6StrokeArc(CGPointMake(12.6, 12), 4.2, -48, 48, 2.1);
            G6StrokeArc(CGPointMake(12.6, 12), 8, -48, 48, 2.1);
        };
        // Độ sáng & hình nền: mặt trời
        G6GlyphBlock sun = ^(CGContextRef ctx, UIColor *tile) {
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(7.6, 7.6, 8.8, 8.8)] fill];
            for (int i = 0; i < 8; i++) {
                CGFloat a = i * M_PI / 4;
                UIBezierPath *ray = [UIBezierPath bezierPath];
                [ray moveToPoint:CGPointMake(12 + 6.9 * cos(a), 12 + 6.9 * sin(a))];
                [ray addLineToPoint:CGPointMake(12 + 9.8 * cos(a), 12 + 9.8 * sin(a))];
                ray.lineWidth = 2.1;
                ray.lineCapStyle = kCGLineCapRound;
                [ray stroke];
            }
        };
        // Khung ảnh: khung + núi + mặt trời nhỏ
        G6GlyphBlock frame = ^(CGContextRef ctx, UIColor *tile) {
            UIBezierPath *border = G6Round(2.8, 4.8, 18.4, 14.4, 2.6);
            border.lineWidth = 2.1;
            [border stroke];
            const CGFloat hill[] = {5.2, 16.8, 9.6, 11.2, 12.6, 14.6, 15, 12.4, 18.8, 16.8};
            G6Polygon(hill, 5);
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(14.6, 7.6, 3, 3)] fill];
        };
        // Bảo mật: bàn tay giơ lên
        G6GlyphBlock hand = ^(CGContextRef ctx, UIColor *tile) {
            [G6Round(7.2, 10.6, 10.8, 10.6, 3.6) fill];
            [G6Round(7.2, 5.6, 2.3, 9, 1.15) fill];
            [G6Round(10, 3.4, 2.3, 10, 1.15) fill];
            [G6Round(12.8, 3.8, 2.3, 10, 1.15) fill];
            [G6Round(15.6, 5.8, 2.3, 9, 1.15) fill];
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, 6.4, 16.2);
            CGContextRotateCTM(ctx, -0.62);
            [G6Round(-1.2, -5.6, 2.5, 7.4, 1.25) fill];
            CGContextRestoreGState(ctx);
        };
        // iCloud: đám mây
        G6GlyphBlock cloud = ^(CGContextRef ctx, UIColor *tile) {
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2.6, 10.4, 8.6, 8.6)] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(6.6, 5.6, 11.4, 11.4)] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(12.8, 9.6, 8.8, 8.8)] fill];
            [G6Round(6.8, 13.6, 10.8, 5.4, 2.4) fill];
        };
        // Mail, Danh bạ, Lịch: phong bì
        G6GlyphBlock envelope = ^(CGContextRef ctx, UIColor *tile) {
            [G6Round(2.8, 6, 18.4, 12.4, 2.4) fill];
            UIBezierPath *flap = [UIBezierPath bezierPath];
            [flap moveToPoint:CGPointMake(4.4, 7.8)];
            [flap addLineToPoint:CGPointMake(12, 13.6)];
            [flap addLineToPoint:CGPointMake(19.6, 7.8)];
            flap.lineWidth = 1.7;
            flap.lineJoinStyle = kCGLineJoinRound;
            flap.lineCapStyle = kCGLineCapRound;
            [tile setStroke];
            [flap stroke];
        };
        // Glass 6: số 6 đậm
        G6GlyphBlock six = ^(CGContextRef ctx, UIColor *tile) {
            UIFont *font = [UIFont boldSystemFontOfSize:23];
            CGSize size = [@"6" sizeWithFont:font];
            [@"6" drawAtPoint:CGPointMake(12 - size.width / 2, 12 - size.height / 2 - 0.5) withFont:font];
        };

        #define RGB(r, g, b) [UIColor colorWithRed:(r) / 255.0 green:(g) / 255.0 blue:(b) / 255.0 alpha:1]
        UIColor *blue = RGB(0, 122, 255), *green = RGB(52, 199, 89), *gray = RGB(142, 142, 147);
        glyphs = @{
            @"AIRPLANE_MODE" : @[RGB(255, 149, 0), [airplane copy]],
            @"WIFI" : @[blue, [wifi copy]],
            @"Bluetooth" : @[blue, [bluetooth copy]],
            @"MOBILE_DATA_SETTINGS_ID" : @[green, [cellular copy]],
            @"INTERNET_TETHERING" : @[green, [hotspot copy]],
            @"VPN" : @[blue, [vpn copy]],
            @"DND_TOP_LEVEL" : @[RGB(88, 86, 214), [moon copy]],
            @"NOTIFICATIONS_ID" : @[RGB(255, 59, 48), [bell copy]],
            @"General" : @[gray, [gear copy]],
            @"Sounds" : @[RGB(255, 45, 85), [speaker copy]],
            @"Wallpaper" : @[RGB(50, 173, 230), [sun copy]],
            @"PICTURE_FRAME" : @[RGB(48, 176, 199), [frame copy]],
            @"Privacy" : @[blue, [hand copy]],
            @"CASTLE" : @[RGB(61, 169, 252), [cloud copy]],
            @"ACCOUNT_SETTINGS" : @[blue, [envelope copy]],
            @"Glass 6" : @[RGB(72, 96, 200), [six copy]],
        };
        #undef RGB
    });
    return glyphs;
}

// ---- Dựng ô ----

// Vẽ `draw` vào ảnh BGRA cạnh kTile (điểm) rồi cho lõi cắt hình bo góc + viền + kiểu biểu tượng. nil nếu lõi lỗi.
static UIImage *G6FinishTile(void (^draw)(CGContextRef ctx, CGRect bounds)) {
    CGFloat scale = [UIScreen mainScreen].scale;
    uint32_t side = (uint32_t)lround(kTile * scale), stride = side * 4;
    NSMutableData *pixels = [NSMutableData dataWithLength:(NSUInteger)stride * side];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels.mutableBytes, side, side, 8, stride, space,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    // Hệ toạ độ như UIKit: gốc trên trái, đơn vị điểm
    CGContextTranslateCTM(ctx, 0, side);
    CGContextScaleCTM(ctx, scale, -scale);
    UIGraphicsPushContext(ctx);
    draw(ctx, CGRectMake(0, 0, kTile, kTile));
    UIGraphicsPopContext();
    CGContextRelease(ctx);
    if (G6CoreIconRender(pixels.mutableBytes, side, side, stride, (float)scale, gDark) != 0) return nil;
    UIImage *image = G6ImageFromPixels(pixels, side, side, scale);
    if (image) objc_setAssociatedObject(image, &kProcessedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return image;
}

// Ô màu + hình trắng cho một mục hệ thống; nil nếu Glass 6 không có hình cho mã này
static UIImage *G6TileForIdentifier(NSString *identifier) {
    if (!identifier.length) return nil;
    UIImage *cached = gTiles[identifier];
    if (cached) return cached;
    NSArray *entry = G6Glyphs()[identifier];
    if (!entry) return nil;
    UIColor *color = entry[0];
    G6GlyphBlock glyph = entry[1];
    UIImage *tile = G6FinishTile(^(CGContextRef ctx, CGRect bounds) {
        // Nền: dải màu dọc nhẹ (trên sáng hơn dưới một chút)
        CGFloat r = 0, g = 0, b = 0, a = 1;
        [color getRed:&r green:&g blue:&b alpha:&a];
        CGFloat comps[8] = {MIN(1, r * 1.06 + 0.05), MIN(1, g * 1.06 + 0.05), MIN(1, b * 1.06 + 0.05), 1, r * 0.90, g * 0.90, b * 0.90, 1};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, 0), CGPointMake(0, kTile), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        // Hình trắng: khung 24×24 thu vào giữa ô
        CGFloat inset = (kTile - kGlyphSide) / 2;
        CGContextTranslateCTM(ctx, inset, inset);
        CGContextScaleCTM(ctx, kGlyphSide / kGlyphBox, kGlyphSide / kGlyphBox);
        [[UIColor whiteColor] set];
        glyph(ctx, color);
    });
    if (tile) {
        if (!gTiles) gTiles = [NSMutableDictionary dictionary];
        gTiles[identifier] = tile;
    }
    return tile;
}

// Ảnh sẵn có của một mục (biểu tượng app thu nhỏ…) cắt lại theo hình ô. Nhớ kết quả theo ảnh gốc + kiểu hiện hành.
static UIImage *G6ShapedIcon(UIImage *image) {
    if (!image || objc_getAssociatedObject(image, &kProcessedKey)) return image;
    CGSize size = image.size;
    // Chỉ đụng ảnh cỡ biểu tượng mục (quanh 29 điểm, gần vuông)
    if (size.width < 20 || size.width > 40 || fabs(size.width - size.height) > 3) return image;
    NSDictionary *cache = objc_getAssociatedObject(image, &kShapedKey);
    if ([cache[@"signature"] isEqual:gSignature]) return cache[@"image"];
    UIImage *shaped = G6FinishTile(^(CGContextRef ctx, CGRect bounds) {
        // Phủ kín ô: ảnh gốc có góc trong suốt, phóng to thêm một chút để bốn góc không hở
        [image drawInRect:CGRectInset(bounds, -1.5, -1.5)];
    });
    if (!shaped) return image;
    objc_setAssociatedObject(image, &kShapedKey, @{@"signature" : gSignature ?: @"", @"image" : shaped}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return shaped;
}

static NSString *G6CellIdentifier(UITableViewCell *cell) {
    @try {
        id spec = [cell respondsToSelector:@selector(specifier)] ? [cell performSelector:@selector(specifier)] : nil;
        id ident = [spec respondsToSelector:@selector(identifier)] ? [spec performSelector:@selector(identifier)] : nil;
        return [ident isKindOfClass:[NSString class]] ? ident : nil;
    } @catch (NSException *e) {
        return nil;
    }
}

static void (*orig_setIcon)(UITableViewCell *, SEL, UIImage *);
static void repl_setIcon(UITableViewCell *self, SEL _cmd, UIImage *icon) {
    if (gActive) {
        @try {
            UIImage *tile = G6TileForIdentifier(G6CellIdentifier(self));
            icon = tile ?: G6ShapedIcon(icon);
        } @catch (NSException *e) {
            G6Log(@"biểu tượng Cài đặt: lỗi %@", e);
        }
    }
    orig_setIcon(self, _cmd, icon);
}

// Mục không có ảnh (vd mục của tweak không kèm biểu tượng) thì Cài đặt không gọi setIcon: — đặt ô của Glass 6 sau khi ô nạp
// xong nội dung
static void (*orig_refresh)(UITableViewCell *, SEL, id);
static void repl_refresh(UITableViewCell *self, SEL _cmd, id specifier) {
    orig_refresh(self, _cmd, specifier);
    if (!gActive) return;
    @try {
        UIImage *tile = G6TileForIdentifier(G6CellIdentifier(self));
        if (tile && self.imageView.image != tile) orig_setIcon(self, @selector(setIcon:), tile);
    } @catch (NSException *e) {
        G6Log(@"biểu tượng Cài đặt: lỗi %@", e);
    }
}

// Bảo mọi ô Cài đặt đang hiện nạp lại nội dung (biểu tượng đi lại qua setIcon:)
static void G6ReloadCells(UIView *view, Class cellClass) {
    if ([view isKindOfClass:cellClass]) {
        @try {
            id spec = [view performSelector:@selector(specifier)];
            if (spec) ((void (*)(id, SEL, id))objc_msgSend)(view, NSSelectorFromString(@"refreshCellContentsWithSpecifier:"), spec);
            [view setNeedsLayout];
        } @catch (NSException *e) {
        }
        return;
    }
    for (UIView *sub in view.subviews) G6ReloadCells(sub, cellClass);
}

void G6UISettingsIconsApply(void) {
    Class cellClass = objc_getClass("PSTableCell");
    if (!cellClass) return;  // không phải app Cài đặt
    NSDictionary *cfg = G6Config();
    BOOL active = G6Feature(@"apps") && G6Feature(@"settings_icons");
    BOOL dark = active && G6UIDark();
    NSString *signature = [NSString stringWithFormat:@"%d|%d|%@|%@|%@", active, dark, cfg[@"icon_style"], cfg[@"icon_tint"], cfg[@"rim"]];
    if ([signature isEqualToString:gSignature]) return;
    BOOL first = gSignature == nil;
    if (!active && first) {
        gSignature = signature;
        return;
    }
    static dispatch_once_t once;
    static BOOL hooked;
    dispatch_once(&once, ^{
        hooked = G6Hook(cellClass, NSSelectorFromString(@"setIcon:"), (IMP)repl_setIcon, (IMP *)&orig_setIcon);
        if (hooked) {
            G6Hook(cellClass, NSSelectorFromString(@"refreshCellContentsWithSpecifier:"), (IMP)repl_refresh, (IMP *)&orig_refresh);
        } else {
            G6Log(@"biểu tượng Cài đặt: không có -[PSTableCell setIcon:] — giữ biểu tượng cũ");
        }
    });
    if (!hooked) return;
    gSignature = signature;
    gActive = active;
    gDark = dark;
    [gTiles removeAllObjects];
    if (!first) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) G6ReloadCells(window, cellClass);
    }
    G6Log(@"biểu tượng Cài đặt: %@", active ? @"kiểu mới" : @"kiểu gốc");
}
