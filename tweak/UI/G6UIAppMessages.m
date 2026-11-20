// App Tin nhắn (com.apple.MobileSMS) — khung ChatKit của iOS 6.
//
// Tra trên iPad mini 1 iOS 6.1.3 (19/11/2026) bằng cây view đã bỏ chữ + bảng hàm của lớp + thống kê màu — KHÔNG đọc tên người
// hay nội dung tin nhắn nào:
//   cột trái   UITableView › CKConversationListCell (`_fromLabel`, `_summaryLabel`, `_dateLabel`; nền trắng ở cả sáng lẫn tối)
//   cột phải   UINavigationBar chuẩn + CKTranscriptToolbarView (hai nút hình `_editButton`, `_contactButton`)
//              CKTranscriptTableView (nền xanh xám 212, 218, 228 ở cả sáng lẫn tối) › CKMessageCell › bong bóng
//                CKColoredBalloonView : CKBalloonView : UIImageView — ảnh bóng kéo giãn đặt trong -updateImage /
//                -updateHighlightedImage theo `orientation` (đuôi trái / phải) và `outgoingColor` (lục SMS / lam iMessage);
//                chữ: -[_CKTextBalloonView textColor] / -textShadowColor, áp bằng -updateTextColor
//              CKTimestampCell, CKMessageStatusCell (nhãn xám có bóng trắng kiểu khắc chìm)
//   đáy        CKMessageEntryView : UIImageView (dải xám bóng) — `_inputFieldCover` (khung ô nhập: ảnh có lỗ trong suốt bo
//              góc), `_inputFieldBackground` (nền trắng sau chữ), `_photoButton`, `_sendButton` (viên lam / lục bóng)
// App không nạp hình qua +[UIImage imageNamed:] nên không dùng khung thay hình (D32); không dùng bộ lọc đảo màu (bong bóng
// ảnh là ảnh của người dùng).
//
// Việc làm (thành phần «app_skins»):
//   - bong bóng chữ: ảnh phẳng CÙNG CỠ, CÙNG MÉP KÉO GIÃN với ảnh gốc (bố cục chữ của ChatKit không đổi); loại bóng (xám /
//     lam / lục) suy từ màu trung bình của chính ảnh gốc, bên có đuôi suy từ lề nội dung của ChatKit — không dựa vào giá trị
//     số của `outgoingColor` / `orientation`. Chữ: trắng trên bóng màu; trên bóng xám thì đen (sáng) / trắng (tối); bỏ bóng chữ;
//   - nền trò chuyện: trắng (sáng) / đen (tối); bỏ hai dải bóng đổ ở mép trên và mép trái;
//   - ô thời gian / ô dịch vụ («Tin nhắn Văn bản»): nhãn nền trong chữ xám, ẩn vạch chấm; hàng nút đầu trò chuyện (iPhone: «Gọi»,
//     «Thêm vào Danh bạ»…): viên phẳng, chữ màu nhấn;
//   - chế độ Sửa: «Xóa» / «Chuyển tiếp» ở thanh dưới thành viên phẳng chữ đỏ / màu nhấn; Tin nhắn Mới: hàng «Đến:» theo nền trò
//     chuyện, nút «+» là vòng tròn màu nhấn;
//   - cột trái: ở chế độ tối ô, nền bảng, chữ đổi sang bảng màu tối (chế độ sáng trả về màu gốc);
//   - thanh nhập: mặt thanh của Glass 6, khung ô nhập phẳng, nút máy ảnh một màu, nút «Gửi» là viên màu. Ô nhập ở chế độ tối
//     vẫn là viên SÁNG chữ đen: chữ đang gõ là nội dung của người dùng — không đổi màu của nó;
//   - hai nút hình trên thanh cột phải: tô theo màu chữ của thanh.
// Tắt công tắc lúc app đang mở: thứ đã đổi giữ tới lần mở app sau (như các app khác); đổi sáng ↔ tối thì đổi ngay.
#import "G6UI.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static BOOL gActive;
static char kKindKey, kOursKey, kSavedKey, kModeKey, kImagesKey;

static UIImage *G6SMSPill(CGSize size, UIColor *fill, UIEdgeInsets caps);

typedef enum { G6BalloonGray = 0, G6BalloonBlue, G6BalloonGreen } G6BalloonKind;

static BOOL G6SMSDark(void) {
    return G6IsDark();
}

static id G6SMSIvar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    const char *type = iv ? ivar_getTypeEncoding(iv) : NULL;
    return (type && type[0] == '@') ? object_getIvar(obj, iv) : nil;
}

// ---- Đọc ảnh gốc ----

// Vẽ ảnh vào vùng nhớ RGBA (nhân sẵn độ đục); bên gọi free. NULL nếu ảnh quá lớn / lỗi.
static uint8_t *G6SMSPixels(UIImage *image, size_t *w, size_t *h) {
    CGImageRef cg = image.CGImage;
    *w = cg ? CGImageGetWidth(cg) : 0;
    *h = cg ? CGImageGetHeight(cg) : 0;
    if (*w == 0 || *h == 0 || *w > 600 || *h > 600) return NULL;
    uint8_t *buf = calloc(*w * *h, 4);
    if (!buf) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, *w, *h, 8, *w * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) {
        free(buf);
        return NULL;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, *w, *h), cg);
    CGContextRelease(ctx);
    return buf;
}

// Loại màu của một ảnh nền (bóng tin nhắn, nút «Gửi»): theo màu trung bình của các điểm đục
static G6BalloonKind G6SMSKindOfImage(UIImage *image) {
    NSNumber *known = objc_getAssociatedObject(image, &kKindKey);
    if (known) return (G6BalloonKind)known.intValue;
    G6BalloonKind kind = G6BalloonGray;
    size_t w, h;
    uint8_t *px = G6SMSPixels(image, &w, &h);
    if (px) {
        double r = 0, g = 0, b = 0, a = 0;
        for (size_t i = 0; i < w * h; i++) {
            if (px[i * 4 + 3] < 128) continue;
            r += px[i * 4];
            g += px[i * 4 + 1];
            b += px[i * 4 + 2];
            a += px[i * 4 + 3];
        }
        free(px);
        if (a > 0) {
            // màu đã nhân độ đục → chia lại theo tổng độ đục, thang 0–255
            r = r * 255 / a;
            g = g * 255 / a;
            b = b * 255 / a;
            if (b > r + 25 && b > g + 8) kind = G6BalloonBlue;
            else if (g > r + 20 && g > b + 20) kind = G6BalloonGreen;
        }
    }
    objc_setAssociatedObject(image, &kKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return kind;
}

// Khung bao các điểm đục (điểm ảnh → điểm) của ảnh; `transparent` = YES: khung bao các điểm TRONG SUỐT (lỗ của khung ô nhập)
static CGRect G6SMSBounds(UIImage *image, BOOL transparent) {
    size_t w, h;
    uint8_t *px = G6SMSPixels(image, &w, &h);
    if (!px) return CGRectZero;
    size_t minX = w, minY = h, maxX = 0, maxY = 0;
    BOOL any = NO;
    for (size_t y = 0; y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            BOOL opaque = px[(y * w + x) * 4 + 3] >= 128;
            if (opaque == transparent) continue;
            any = YES;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
        }
    }
    free(px);
    if (!any) return CGRectZero;
    CGFloat scale = image.scale > 0 ? image.scale : 1;
    return CGRectMake(minX / scale, minY / scale, (maxX - minX + 1) / scale, (maxY - minY + 1) / scale);
}

// ---- Bong bóng ----

static UIColor *G6SMSBalloonColor(G6BalloonKind kind, BOOL dark, BOOL highlighted) {
    switch (kind) {
        case G6BalloonBlue:
            return highlighted ? [UIColor colorWithRed:0.03 green:0.42 blue:0.85 alpha:1] : [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1];
        case G6BalloonGreen:
            return highlighted ? [UIColor colorWithRed:0.16 green:0.64 blue:0.29 alpha:1] : [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1];
        default:
            if (dark) return [UIColor colorWithWhite:highlighted ? 0.24 : 0.16 alpha:1];
            return [UIColor colorWithWhite:highlighted ? 0.84 : 0.915 alpha:1];
    }
}

// Ảnh bóng phẳng: cùng cỡ + cùng mép kéo giãn với ảnh gốc; thân bo tròn nằm trong khung bao phần đục của ảnh gốc, đuôi nhỏ
// ở góc dưới phía `tailLeft`.
static UIImage *G6SMSBalloonImage(UIImage *original, G6BalloonKind kind, BOOL tailLeft, BOOL dark, BOOL highlighted) {
    static NSMutableDictionary *cache;
    UIEdgeInsets caps = original.capInsets;
    NSString *key = [NSString stringWithFormat:@"%@|%@|%d|%d|%d|%d", NSStringFromCGSize(original.size), NSStringFromUIEdgeInsets(caps), kind,
                                               tailLeft, dark, highlighted];
    UIImage *made = cache[key];
    if (made) return made;
    CGRect body = G6SMSBounds(original, NO);
    if (body.size.width < 16 || body.size.height < 16) return nil;
    const CGFloat tail = 6;
    CGRect r = body;
    r.size.width -= tail;
    if (tailLeft) r.origin.x += tail;
    CGFloat radius = MIN(15, MIN(r.size.width, r.size.height) / 2);
    UIGraphicsBeginImageContextWithOptions(original.size, NO, original.scale > 0 ? original.scale : 1);
    [G6SMSBalloonColor(kind, dark, highlighted) setFill];
    [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius] fill];
    // Đuôi: một nêm cong nhỏ từ cạnh bên xuống góc dưới ngoài cùng của khung bao
    CGFloat bottom = CGRectGetMaxY(r), side = tailLeft ? CGRectGetMinX(r) : CGRectGetMaxX(r), tip = tailLeft ? CGRectGetMinX(body) : CGRectGetMaxX(body);
    CGFloat dir = tailLeft ? 1 : -1;
    UIBezierPath *wedge = [UIBezierPath bezierPath];
    [wedge moveToPoint:CGPointMake(side + dir * 1, bottom - 13)];
    [wedge addQuadCurveToPoint:CGPointMake(tip, bottom - 0.5) controlPoint:CGPointMake(side + dir * 0.5, bottom - 3)];
    [wedge addQuadCurveToPoint:CGPointMake(side + dir * 11, bottom - 3) controlPoint:CGPointMake(side + dir * 4, bottom)];
    [wedge closePath];
    [wedge fill];
    made = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!made) return nil;
    made = [made resizableImageWithCapInsets:caps];
    objc_setAssociatedObject(made, &kOursKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(made, &kKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!cache) cache = [NSMutableDictionary dictionary];
    cache[key] = made;
    return made;
}

// Bên có đuôi: lề nội dung của ChatKit phía nào rộng hơn thì đuôi nằm phía đó
static BOOL G6SMSTailLeft(UIImageView *balloon) {
    SEL orientationSel = NSSelectorFromString(@"orientation"), insetsSel = NSSelectorFromString(@"contentInsetsForBalloonOrientation:");
    Class cls = [balloon class];
    if (![balloon respondsToSelector:orientationSel] || ![cls respondsToSelector:insetsSel]) return YES;
    int orientation = ((int (*)(id, SEL))objc_msgSend)(balloon, orientationSel);
    NSMethodSignature *sig = [cls methodSignatureForSelector:insetsSel];
    if (!sig || strcmp(sig.methodReturnType, @encode(UIEdgeInsets)) != 0) return YES;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = cls;
    inv.selector = insetsSel;
    [inv setArgument:&orientation atIndex:2];
    [inv invoke];
    UIEdgeInsets insets = UIEdgeInsetsZero;
    [inv getReturnValue:&insets];
    return insets.left >= insets.right;
}

// Thay ảnh đang đặt (thường hoặc lúc đang chọn) của một bóng bằng ảnh phẳng
static void G6SMSFlattenBalloon(UIImageView *balloon, BOOL highlightedImage) {
    UIImage *current = highlightedImage ? balloon.highlightedImage : balloon.image;
    if (!current) return;
    BOOL dark = G6SMSDark();
    if (objc_getAssociatedObject(current, &kOursKey)) {
        // Ảnh của ta từ chế độ trước: dựng lại theo chế độ hiện hành từ ảnh gốc đã nhớ
        UIImage *original = objc_getAssociatedObject(balloon, highlightedImage ? (void *)&kSavedKey : (void *)&kModeKey);
        if (!original) return;
        current = original;
    } else {
        objc_setAssociatedObject(balloon, highlightedImage ? (void *)&kSavedKey : (void *)&kModeKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    G6BalloonKind kind = G6SMSKindOfImage(current);
    if (!highlightedImage) objc_setAssociatedObject(balloon, &kKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImage *flat = G6SMSBalloonImage(current, kind, G6SMSTailLeft(balloon), dark, highlightedImage);
    if (!flat) return;
    if (highlightedImage) balloon.highlightedImage = flat;
    else balloon.image = flat;
}

static void (*orig_updateImage)(UIImageView *, SEL);
static void repl_updateImage(UIImageView *self, SEL _cmd) {
    orig_updateImage(self, _cmd);
    if (!gActive) return;
    @try {
        G6SMSFlattenBalloon(self, NO);
        SEL updateText = NSSelectorFromString(@"updateTextColor");
        if ([self respondsToSelector:updateText]) ((void (*)(id, SEL))objc_msgSend)(self, updateText);
    } @catch (NSException *e) {
        G6Log(@"tin nhắn: lỗi khi dựng bóng: %@", e);
    }
}

static void (*orig_updateHighlighted)(UIImageView *, SEL);
static void repl_updateHighlighted(UIImageView *self, SEL _cmd) {
    orig_updateHighlighted(self, _cmd);
    if (!gActive) return;
    @try {
        G6SMSFlattenBalloon(self, YES);
    } @catch (NSException *e) {
    }
}

static id (*orig_textColor)(id, SEL);
static id repl_textColor(id self, SEL _cmd) {
    NSNumber *kind = gActive ? objc_getAssociatedObject(self, &kKindKey) : nil;
    if (!kind) return orig_textColor(self, _cmd);
    if (kind.intValue != G6BalloonGray) return [UIColor whiteColor];
    return G6SMSDark() ? [UIColor whiteColor] : [UIColor blackColor];
}

static id (*orig_textShadowColor)(id, SEL);
static id repl_textShadowColor(id self, SEL _cmd) {
    if (gActive && objc_getAssociatedObject(self, &kKindKey)) return [UIColor clearColor];
    return orig_textShadowColor(self, _cmd);
}

// ---- Nền / màu chữ có ghi nhớ ----

// Đặt màu nền theo chế độ, nhớ màu gốc lần đầu; `color` = nil: trả về màu gốc
static void G6SMSSetBackground(UIView *view, UIColor *color) {
    if (!view) return;
    id saved = objc_getAssociatedObject(view, &kSavedKey);
    if (color) {
        if (!saved) objc_setAssociatedObject(view, &kSavedKey, view.backgroundColor ?: (id)[NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (![view.backgroundColor isEqual:color]) view.backgroundColor = color;
    } else if (saved) {
        view.backgroundColor = saved == [NSNull null] ? nil : saved;
        objc_setAssociatedObject(view, &kSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void G6SMSSetLabel(UILabel *label, UIColor *color, BOOL clearBackground) {
    if (![label isKindOfClass:[UILabel class]]) return;
    NSDictionary *saved = objc_getAssociatedObject(label, &kSavedKey);
    if (color) {
        if (!saved) {
            saved = @{
                @"text" : label.textColor ?: [UIColor blackColor],
                @"back" : label.backgroundColor ?: [UIColor clearColor],
                @"opaque" : @(label.opaque),
            };
            objc_setAssociatedObject(label, &kSavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![label.textColor isEqual:color]) label.textColor = color;
        if (clearBackground && label.opaque) {
            label.backgroundColor = [UIColor clearColor];
            label.opaque = NO;
        }
    } else if (saved) {
        label.textColor = saved[@"text"];
        label.backgroundColor = saved[@"back"];
        label.opaque = [saved[@"opaque"] boolValue];
        objc_setAssociatedObject(label, &kSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// ---- Màn trò chuyện ----

static void G6SMSStyleTranscript(UITableView *table) {
    UIColor *backdrop = gActive ? (G6SMSDark() ? [UIColor blackColor] : [UIColor whiteColor]) : nil;
    G6SMSSetBackground(table, backdrop);
    UIView *holder = table.superview;
    if (!holder || [holder isKindOfClass:[UIWindow class]]) return;
    G6SMSSetBackground(holder, backdrop);
    // Hai dải bóng đổ (mép trên dưới thanh, mép trái cạnh cột danh sách): ảnh mỏng nằm cùng cấp với bảng
    for (UIView *sibling in holder.subviews) {
        if (![sibling isMemberOfClass:[UIImageView class]]) continue;
        if (sibling.bounds.size.height <= 12 || sibling.bounds.size.width <= 12) sibling.hidden = gActive;
    }
}

static void (*orig_transcriptLayout)(UITableView *, SEL);
static void repl_transcriptLayout(UITableView *self, SEL _cmd) {
    orig_transcriptLayout(self, _cmd);
    @try {
        if (self.window) G6SMSStyleTranscript(self);
    } @catch (NSException *e) {
    }
}

// Ô thời gian, ô trạng thái, ô dịch vụ («Tin nhắn Văn bản» + vạch chấm, CKServiceCell). iPhone (đo 20/11/2026, máy anh báo lỗi):
// nhãn của ô thời gian rộng hết bảng và nhãn ô dịch vụ mang NỀN ĐẶC màu nền trò chuyện gốc (219, 226, 237) → thành một dải / một
// khung sáng trên nền đen của Glass 6 (và lệch màu trên nền trắng). Kiểu mới: nhãn nền trong, chữ xám phụ, bỏ bóng trắng «khắc
// chìm» (thành viền sáng quanh chữ trên nền tối, nhoè trên nền trắng); ẩn vạch chấm (CKDashedLineView — kiểu iOS 6). Có ghi nhớ.
static void G6SMSCollect(UIView *view, Class cls, NSMutableArray *out, int depth) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:cls]) [out addObject:sub];
        if (depth > 0) G6SMSCollect(sub, cls, out, depth - 1);
    }
}

static void G6SMSStyleStampCell(UIView *cell) {
    NSMutableArray *labels = [NSMutableArray array];
    G6SMSCollect(cell, [UILabel class], labels, 2);
    UIColor *text = gActive ? [UIColor colorWithWhite:G6SMSDark() ? 0.58 : 0.50 alpha:1] : nil;
    for (UILabel *label in labels) {
        if (gActive && label.shadowColor) {
            objc_setAssociatedObject(label, &kModeKey, label.shadowColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            label.shadowColor = nil;
        } else if (!gActive && !label.shadowColor) {
            UIColor *shadow = objc_getAssociatedObject(label, &kModeKey);
            if (shadow) label.shadowColor = shadow;
        }
        G6SMSSetLabel(label, text, YES);
    }
    Class dashed = objc_getClass("CKDashedLineView");
    if (!dashed) return;
    NSMutableArray *lines = [NSMutableArray array];
    G6SMSCollect(cell, dashed, lines, 2);
    for (UIView *line in lines) {
        if (gActive && !line.hidden) {
            objc_setAssociatedObject(line, &kModeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            line.hidden = YES;
        } else if (!gActive && objc_getAssociatedObject(line, &kModeKey)) {
            line.hidden = NO;
            objc_setAssociatedObject(line, &kModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

// ---- Hàng nút đầu cuộc trò chuyện: «Gọi», «FaceTime», «Thêm vào Danh bạ», «Tải tin nhắn cũ hơn» (CKTranscriptHeaderView ›
// _UIShortPlacardButton) ----
// Bản gốc: viên sáng bóng kiểu iOS 6, chữ xanh xám có bóng trắng — sáng chói trên nền đen (máy anh báo lỗi 20/11/2026). Kiểu mới:
// viên phẳng bo tròn (xám đậm ở chế độ tối, xám nhạt ở chế độ sáng), chữ màu nhấn Inter SemiBold, không bóng chữ. Có ghi nhớ.
static UIColor *G6SMSAccent(BOOL dark) {
    return dark ? [UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:1] : [UIColor colorWithRed:0 green:0.478 blue:1 alpha:1];
}

static void G6SMSStyleHeaderButton(UIButton *button) {
    BOOL dark = G6SMSDark();
    NSDictionary *saved = objc_getAssociatedObject(button, &kSavedKey);
    if (!gActive) {
        if (!saved) return;
        UIControlState states[] = {UIControlStateNormal, UIControlStateHighlighted};
        for (int i = 0; i < 2; i++) {
            NSString *k = i ? @"h" : @"n";
            id image = saved[[@"image" stringByAppendingString:k]], title = saved[[@"title" stringByAppendingString:k]];
            id shadow = saved[[@"shadow" stringByAppendingString:k]];
            [button setBackgroundImage:image == [NSNull null] ? nil : image forState:states[i]];
            [button setTitleColor:title == [NSNull null] ? nil : title forState:states[i]];
            [button setTitleShadowColor:shadow == [NSNull null] ? nil : shadow forState:states[i]];
        }
        if (saved[@"font"]) button.titleLabel.font = saved[@"font"];
        button.titleLabel.shadowOffset = [saved[@"offset"] CGSizeValue];
        objc_setAssociatedObject(button, &kSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button, &kModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    CGFloat h = button.bounds.size.height;
    if (h < 16) return;
    // Đã đổi đúng chế độ và đúng chiều cao này rồi thì thôi
    NSString *mode = [NSString stringWithFormat:@"%d-%.0f", dark, h];
    if ([objc_getAssociatedObject(button, &kModeKey) isEqual:mode]) return;
    if (!saved) {
        NSMutableDictionary *s = [NSMutableDictionary dictionary];
        UIControlState states[] = {UIControlStateNormal, UIControlStateHighlighted};
        for (int i = 0; i < 2; i++) {
            NSString *k = i ? @"h" : @"n";
            s[[@"image" stringByAppendingString:k]] = [button backgroundImageForState:states[i]] ?: (id)[NSNull null];
            s[[@"title" stringByAppendingString:k]] = [button titleColorForState:states[i]] ?: (id)[NSNull null];
            s[[@"shadow" stringByAppendingString:k]] = [button titleShadowColorForState:states[i]] ?: (id)[NSNull null];
        }
        if (button.titleLabel.font) s[@"font"] = button.titleLabel.font;
        s[@"offset"] = [NSValue valueWithCGSize:button.titleLabel.shadowOffset];
        objc_setAssociatedObject(button, &kSavedKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        saved = s;
    }
    UIEdgeInsets caps = UIEdgeInsetsMake(0, ceil(h / 2), 0, ceil(h / 2));
    CGSize size = CGSizeMake(ceil(h) + 2, h);
    UIImage *normal = G6SMSPill(size, [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.14 : 0.06], caps);
    UIImage *pressed = G6SMSPill(size, [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.26 : 0.13], caps);
    if (!normal || !pressed) return;
    [button setBackgroundImage:normal forState:UIControlStateNormal];
    [button setBackgroundImage:pressed forState:UIControlStateHighlighted];
    UIColor *accent = G6SMSAccent(dark);
    [button setTitleColor:accent forState:UIControlStateNormal];
    [button setTitleColor:[accent colorWithAlphaComponent:0.6] forState:UIControlStateHighlighted];
    [button setTitleShadowColor:[UIColor clearColor] forState:UIControlStateNormal];
    [button setTitleShadowColor:[UIColor clearColor] forState:UIControlStateHighlighted];
    button.titleLabel.shadowOffset = CGSizeZero;
    UIFont *font = saved[@"font"];
    if (font) button.titleLabel.font = G6Font(G6FontSemiBold, font.pointSize);
    objc_setAssociatedObject(button, &kModeKey, mode, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void G6SMSStyleHeader(UIView *header) {
    for (UIView *sub in header.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) G6SMSStyleHeaderButton((UIButton *)sub);
    }
}

static void (*orig_headerLayout)(UIView *, SEL);
static void repl_headerLayout(UIView *self, SEL _cmd) {
    orig_headerLayout(self, _cmd);
    @try {
        G6SMSStyleHeader(self);
    } @catch (NSException *e) {
    }
}

// ---- Chế độ Sửa của trò chuyện: «Xóa» / «Chuyển tiếp» ở thanh dưới (MailToolbarButton của MessageUI) ----
// Bản gốc: viên bóng đỏ / xanh xám kiểu iOS 6 (đo trên iPhone 20/11/2026). Kiểu mới: viên phẳng xám như hàng nút đầu trò chuyện,
// chữ + hình màu đỏ cho nút xoá (cờ `_isRed` của chính nút), màu nhấn cho nút còn lại. Lúc chưa chọn tin nào, nút tự mờ đi (độ
// đục 0,5 của nhãn / hình) như bản gốc. Có ghi nhớ.
static BOOL G6SMSCharIvar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    const char *type = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!type || (type[0] != 'c' && type[0] != 'B')) return NO;
    return *((char *)(__bridge void *)obj + ivar_getOffset(iv)) != 0;
}

static void G6SMSStyleToolbarButton(UIButton *button) {
    UILabel *label = G6SMSIvar(button, "_titleLabel");
    UIImageView *icon = G6SMSIvar(button, "_iconView");
    NSDictionary *saved = objc_getAssociatedObject(button, &kSavedKey);
    UIControlState states[] = {UIControlStateNormal, UIControlStateHighlighted, UIControlStateDisabled};
    if (!gActive) {
        if (!saved) return;
        for (int i = 0; i < 3; i++) {
            id image = saved[[NSString stringWithFormat:@"bg%d", i]];
            [button setBackgroundImage:image == [NSNull null] ? nil : image forState:states[i]];
        }
        if ([label isKindOfClass:[UILabel class]]) {
            label.textColor = saved[@"text"];
            label.shadowColor = saved[@"shadow"] == [NSNull null] ? nil : saved[@"shadow"];
        }
        if ([icon isKindOfClass:[UIImageView class]] && saved[@"icon"] != [NSNull null]) icon.image = saved[@"icon"];
        objc_setAssociatedObject(button, &kSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button, &kModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    CGFloat h = button.bounds.size.height;
    if (h < 16) return;
    BOOL dark = G6SMSDark();
    if (!saved) {
        NSMutableDictionary *s = [NSMutableDictionary dictionary];
        for (int i = 0; i < 3; i++) s[[NSString stringWithFormat:@"bg%d", i]] = [button backgroundImageForState:states[i]] ?: (id)[NSNull null];
        s[@"text"] = label.textColor ?: [UIColor whiteColor];
        s[@"shadow"] = label.shadowColor ?: (id)[NSNull null];
        s[@"icon"] = icon.image ?: (id)[NSNull null];
        objc_setAssociatedObject(button, &kSavedKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        saved = s;
    }
    BOOL red = G6SMSCharIvar(button, "_isRed");
    UIColor *tint = red ? (dark ? [UIColor colorWithRed:1 green:0.27 blue:0.23 alpha:1] : [UIColor colorWithRed:1 green:0.23 blue:0.19 alpha:1])
                        : G6SMSAccent(dark);
    NSString *mode = [NSString stringWithFormat:@"%d-%.0f", dark, h];
    UIImage *current = [button backgroundImageForState:UIControlStateNormal];
    if (![objc_getAssociatedObject(button, &kModeKey) isEqual:mode] || !objc_getAssociatedObject(current, &kOursKey)) {
        UIEdgeInsets caps = UIEdgeInsetsMake(0, ceil(h / 2), 0, ceil(h / 2));
        CGSize size = CGSizeMake(ceil(h) + 2, h);
        UIImage *normal = G6SMSPill(size, [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.14 : 0.06], caps);
        UIImage *pressed = G6SMSPill(size, [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.26 : 0.13], caps);
        if (!normal || !pressed) return;
        [button setBackgroundImage:normal forState:UIControlStateNormal];
        [button setBackgroundImage:pressed forState:UIControlStateHighlighted];
        [button setBackgroundImage:normal forState:UIControlStateDisabled];
        objc_setAssociatedObject(button, &kModeKey, mode, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([label isKindOfClass:[UILabel class]]) {
        if (![label.textColor isEqual:tint]) label.textColor = tint;
        label.shadowColor = nil;
    }
    // Hình (thùng rác / mũi tên): ảnh trắng của app → tô theo màu nút; app đặt ảnh mới thì tô lại từ ảnh đó
    if ([icon isKindOfClass:[UIImageView class]] && icon.image) {
        UIImage *source = objc_getAssociatedObject(icon.image, &kOursKey) ? objc_getAssociatedObject(icon, &kSavedKey) : icon.image;
        NSNumber *iconMode = objc_getAssociatedObject(icon, &kModeKey);
        if (source && (!objc_getAssociatedObject(icon.image, &kOursKey) || iconMode.intValue != (red ? 2 : 0) + dark)) {
            UIImage *tinted = G6UITintedImage(source, tint);
            if (tinted) {
                objc_setAssociatedObject(tinted, &kOursKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(icon, &kSavedKey, source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(icon, &kModeKey, @((red ? 2 : 0) + dark), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                icon.image = tinted;
            }
        }
    }
}

static void (*orig_toolbarButtonLayout)(UIButton *, SEL);
static void repl_toolbarButtonLayout(UIButton *self, SEL _cmd) {
    orig_toolbarButtonLayout(self, _cmd);
    @try {
        G6SMSStyleToolbarButton(self);
    } @catch (NSException *e) {
    }
}

// ---- Tin nhắn Mới: hàng «Đến:» (CKComposeRecipientView) ----
// Bản gốc: nền trắng ở cả hai chế độ, nút «+» là viên xanh bóng kiểu iOS 6 (đo trên iPhone 20/11/2026). Kiểu mới: nền theo nền trò
// chuyện (đen / trắng), vạch ngăn mảnh, chữ đang gõ trắng ở chế độ tối; nút «+» là hình tròn viền màu nhấn có dấu cộng. Có ghi nhớ.
static UIImage *G6SMSAddGlyph(CGSize size, UIColor *color) {
    if (size.width < 12 || size.height < 12) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGFloat d = MIN(size.width, size.height) - 7, line = 1.5;
    CGRect circle = CGRectMake((size.width - d) / 2, (size.height - d) / 2, d, d);
    [color set];
    UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(circle, line / 2, line / 2)];
    ring.lineWidth = line;
    [ring stroke];
    CGFloat arm = d * 0.26;
    CGPoint c = CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle));
    UIBezierPath *plus = [UIBezierPath bezierPath];
    [plus moveToPoint:CGPointMake(c.x - arm, c.y)];
    [plus addLineToPoint:CGPointMake(c.x + arm, c.y)];
    [plus moveToPoint:CGPointMake(c.x, c.y - arm)];
    [plus addLineToPoint:CGPointMake(c.x, c.y + arm)];
    plus.lineWidth = line;
    plus.lineCapStyle = kCGLineCapRound;
    [plus stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) objc_setAssociatedObject(image, &kOursKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return image;
}

static void G6SMSStyleRecipients(UIView *view) {
    BOOL dark = G6SMSDark();
    UIColor *backdrop = gActive ? (dark ? [UIColor blackColor] : [UIColor whiteColor]) : nil;
    // Nền: chính hàng «Đến:» và tối đa hai view cha (khung cuộn khi có nhiều người nhận, CKRecipientSelectionView) — dừng ở
    // CKRecipientSelectionView, không bao giờ lên tới cửa sổ
    UIView *v = view;
    for (int i = 0; v && i < 3 && ![v isKindOfClass:[UIWindow class]]; i++, v = v.superview) {
        G6SMSSetBackground(v, backdrop);
        if ([NSStringFromClass([v class]) isEqualToString:@"CKRecipientSelectionView"]) break;
    }
    for (UIView *sub in view.subviews) {
        // Nhãn «Đến:» (MFHeaderLabelView) và nút «+» mang nền trắng riêng (đo 20/11/2026) → theo nền hàng; cả nhãn con bên trong
        NSString *name = NSStringFromClass([sub class]);
        if ([name rangeOfString:@"HeaderLabel"].location != NSNotFound || [name rangeOfString:@"AddContact"].location != NSNotFound) {
            if (sub.backgroundColor || objc_getAssociatedObject(sub, &kSavedKey)) G6SMSSetBackground(sub, backdrop);
            // Nhãn tự vẽ chữ bằng -labelColor (xem repl_headerLabelColor): đổi chế độ thì vẽ lại
            NSNumber *drawn = objc_getAssociatedObject(sub, &kModeKey);
            int want = gActive ? 1 + dark : 0;
            if ([name rangeOfString:@"HeaderLabel"].location != NSNotFound && drawn.intValue != want) {
                objc_setAssociatedObject(sub, &kModeKey, @(want), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [sub setNeedsDisplay];
            }
            for (UIView *inner in sub.subviews) {
                if ([inner isKindOfClass:[UILabel class]] && (inner.backgroundColor || objc_getAssociatedObject(inner, &kSavedKey))) {
                    G6SMSSetBackground(inner, backdrop);
                }
            }
        }
        // Vạch ngăn mảnh ở đáy hàng
        if ([sub isMemberOfClass:[UIView class]] && sub.bounds.size.height <= 1.5) {
            G6SMSSetBackground(sub, gActive ? [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.16 : 0.18] : nil);
        } else if ([sub isKindOfClass:[UITextField class]]) {
            UITextField *field = (UITextField *)sub;
            NSDictionary *saved = objc_getAssociatedObject(field, &kSavedKey);
            if (gActive) {
                if (!saved) objc_setAssociatedObject(field, &kSavedKey, @{@"text" : field.textColor ?: [UIColor blackColor]}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                UIColor *text = dark ? [UIColor whiteColor] : [UIColor blackColor];
                if (![field.textColor isEqual:text]) field.textColor = text;
            } else if (saved) {
                field.textColor = saved[@"text"];
                objc_setAssociatedObject(field, &kSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else if ([sub isKindOfClass:[UIButton class]] && [NSStringFromClass([sub class]) rangeOfString:@"AddContact"].location != NSNotFound) {
            UIButton *add = (UIButton *)sub;
            NSDictionary *saved = objc_getAssociatedObject(add, &kImagesKey);
            if (gActive) {
                if (!saved) {
                    saved = @{
                        @"n" : [add imageForState:UIControlStateNormal] ?: (id)[NSNull null],
                        @"h" : [add imageForState:UIControlStateHighlighted] ?: (id)[NSNull null],
                    };
                    objc_setAssociatedObject(add, &kImagesKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                NSNumber *mode = objc_getAssociatedObject(add, &kModeKey);
                if (mode && mode.boolValue == dark && objc_getAssociatedObject([add imageForState:UIControlStateNormal], &kOursKey)) continue;
                CGSize size = add.bounds.size;
                UIImage *normal = G6SMSAddGlyph(size, G6SMSAccent(dark));
                UIImage *pressed = G6SMSAddGlyph(size, [G6SMSAccent(dark) colorWithAlphaComponent:0.5]);
                if (!normal || !pressed) continue;
                [add setImage:normal forState:UIControlStateNormal];
                [add setImage:pressed forState:UIControlStateHighlighted];
                objc_setAssociatedObject(add, &kModeKey, @(dark), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else if (saved) {
                [add setImage:saved[@"n"] == [NSNull null] ? nil : saved[@"n"] forState:UIControlStateNormal];
                [add setImage:saved[@"h"] == [NSNull null] ? nil : saved[@"h"] forState:UIControlStateHighlighted];
                objc_setAssociatedObject(add, &kImagesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(add, &kModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}

// Chữ «Đến:» (MFHeaderLabelView tự vẽ trong -drawRect:) lấy màu từ -labelColor: màu tối có độ trong — trên nền trắng thành xám,
// trên nền đen của chế độ tối thì chìm mất (đo 20/11/2026) → chế độ tối trả xám sáng
static CGColorRef (*orig_headerLabelColor)(id, SEL);
static CGColorRef repl_headerLabelColor(id self, SEL _cmd) {
    if (gActive && G6SMSDark()) {
        static UIColor *light;
        if (!light) light = [UIColor colorWithWhite:0.56 alpha:1];
        return light.CGColor;
    }
    return orig_headerLabelColor(self, _cmd);
}

static void (*orig_recipientsLayout)(UIView *, SEL);
static void repl_recipientsLayout(UIView *self, SEL _cmd) {
    orig_recipientsLayout(self, _cmd);
    @try {
        G6SMSStyleRecipients(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_serviceLayout)(UIView *, SEL);
static void repl_serviceLayout(UIView *self, SEL _cmd) {
    orig_serviceLayout(self, _cmd);
    @try {
        G6SMSStyleStampCell(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_stampLayout)(UIView *, SEL);
static void repl_stampLayout(UIView *self, SEL _cmd) {
    orig_stampLayout(self, _cmd);
    @try {
        G6SMSStyleStampCell(self);
    } @catch (NSException *e) {
    }
}

// ---- Cột danh sách ----

static UIColor *G6SMSListBackdrop(void) {
    return (gActive && G6SMSDark()) ? [UIColor colorWithWhite:0.07 alpha:1] : nil;
}

static void G6SMSStyleListCell(UITableViewCell *cell) {
    BOOL dark = gActive && G6SMSDark();
    UIColor *backdrop = G6SMSListBackdrop();
    G6SMSSetBackground(cell, backdrop);
    G6SMSSetBackground(cell.contentView, backdrop);
    G6SMSSetLabel(G6SMSIvar(cell, "_fromLabel"), dark ? [UIColor whiteColor] : nil, YES);
    G6SMSSetLabel(G6SMSIvar(cell, "_summaryLabel"), dark ? [UIColor colorWithWhite:0.62 alpha:1] : nil, YES);
    G6SMSSetLabel(G6SMSIvar(cell, "_backupSummaryLabel"), dark ? [UIColor colorWithWhite:0.62 alpha:1] : nil, YES);
    G6SMSSetLabel(G6SMSIvar(cell, "_dateLabel"), dark ? [UIColor colorWithRed:0.36 green:0.68 blue:1 alpha:1] : nil, YES);
    // Vạch ngăn riêng của ô: view cao 1 điểm nằm thẳng trong ô
    for (UIView *sub in cell.subviews) {
        if ([sub isMemberOfClass:[UIView class]] && sub.bounds.size.height <= 1.5 && sub != cell.contentView) {
            G6SMSSetBackground(sub, dark ? [UIColor colorWithWhite:0.20 alpha:1] : nil);
        }
    }
    // Bảng chứa ô + tấm phủ phía trên bảng (lộ ra khi kéo quá đầu danh sách)
    UIView *table = cell.superview;
    while (table && ![table isKindOfClass:[UITableView class]]) table = table.superview;
    if (table) {
        G6SMSSetBackground(table, backdrop);
        for (UIView *sub in table.subviews) {
            if ([sub isMemberOfClass:[UIView class]] && sub.frame.origin.y < 0 && sub.bounds.size.height > 200) G6SMSSetBackground(sub, backdrop);
        }
        UITableView *t = (UITableView *)table;
        UIColor *savedLine = objc_getAssociatedObject(t, &kModeKey);
        if (dark && !savedLine) {
            objc_setAssociatedObject(t, &kModeKey, t.separatorColor ?: [UIColor lightGrayColor], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            t.separatorColor = [UIColor colorWithWhite:0.20 alpha:1];
        } else if (!dark && savedLine) {
            t.separatorColor = savedLine;
            objc_setAssociatedObject(t, &kModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void (*orig_listCellLayout)(UITableViewCell *, SEL);
static void repl_listCellLayout(UITableViewCell *self, SEL _cmd) {
    orig_listCellLayout(self, _cmd);
    @try {
        G6SMSStyleListCell(self);
    } @catch (NSException *e) {
    }
}

// ---- Thanh nhập ----

static UIImage *G6SMSPill(CGSize size, UIColor *fill, UIEdgeInsets caps) {
    if (size.width < 8 || size.height < 8) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [fill setFill];
    [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:size.height / 2] fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImage *pill = [image resizableImageWithCapInsets:caps];
    if (pill) objc_setAssociatedObject(pill, &kOursKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return pill;
}

// Khung ô nhập: phủ kín bằng màu thanh, chừa lỗ bo tròn đúng chỗ lỗ trong suốt của ảnh gốc, viền mảnh quanh lỗ
static UIImage *G6SMSFieldCover(UIImage *original, BOOL dark) {
    CGRect hole = G6SMSBounds(original, YES);
    if (hole.size.width < 10 || hole.size.height < 10) return nil;
    // Phải đúng là «khung có lỗ ở giữa»: lỗ nằm lọt trong ảnh, còn viền đục bao quanh. Không phải thì để ảnh gốc.
    // iPhone (đo 20/11/2026): ảnh khung hẹp 32×40 kéo giãn, lỗ chạm sát mép TRÁI của ảnh (ô nhập bắt đầu ngay sau nút máy ảnh)
    // → chỉ đòi viền đục ở trên / dưới; lỗ chạm mép trái / phải thì lùi vào nửa điểm cho nét viền không bị cắt.
    if (hole.origin.y < 1 || CGRectGetMaxY(hole) > original.size.height - 1) return nil;
    if (g6_device_is_phone()) {
        CGFloat left = MAX(hole.origin.x, 0.5), right = MIN(CGRectGetMaxX(hole), original.size.width - 0.5);
        hole = CGRectMake(left, hole.origin.y, right - left, hole.size.height);
    } else if (hole.origin.x < 1 || CGRectGetMaxX(hole) > original.size.width - 1) {
        return nil;
    }
    UIGraphicsBeginImageContextWithOptions(original.size, NO, original.scale > 0 ? original.scale : 1);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect all = (CGRect){CGPointZero, original.size};
    [[UIColor colorWithWhite:G6UIBarsDark() ? 0.11 : 0.972 alpha:1] setFill];
    UIBezierPath *frame = [UIBezierPath bezierPathWithRect:all];
    // Ảnh hẹp kéo giãn: hai cung bo góc phải nằm gọn trong hai phần không kéo giãn
    CGFloat radius = MIN(MIN(14, hole.size.height / 2), MAX(4, hole.size.width / 2 - 3));
    UIBezierPath *cut = [UIBezierPath bezierPathWithRoundedRect:hole cornerRadius:radius];
    [frame appendPath:cut];
    frame.usesEvenOddFillRule = YES;
    [frame fill];
    CGFloat hair = 1 / MAX([UIScreen mainScreen].scale, 1);
    // Nét mảnh ở mép trên của thanh chạy liền qua khung này (khung phủ lên mặt thanh)
    [[UIColor colorWithWhite:G6UIBarsDark() ? 1 : 0 alpha:G6UIBarsDark() ? 0.12 : 0.16] setFill];
    CGContextFillRect(ctx, CGRectMake(0, 0, original.size.width, hair));
    cut.lineWidth = hair;
    [[UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.22 : 0.18] setStroke];
    CGContextSaveGState(ctx);
    [cut stroke];
    CGContextRestoreGState(ctx);
    UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!made) return nil;
    made = [made resizableImageWithCapInsets:original.capInsets];
    objc_setAssociatedObject(made, &kOursKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return made;
}

// Nút máy ảnh: ảnh gốc là cả một nút tròn bóng (đĩa đục có hình máy ảnh bên trong) — tô theo kênh đục thì thành đĩa đặc (đã
// thử). → tự vẽ hình máy ảnh một màu, cùng cỡ với ảnh gốc.
static UIImage *G6SMSCameraGlyph(CGSize size, UIColor *color) {
    if (size.width < 12 || size.height < 12) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat w = size.width, h = size.height;
    [color set];
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(w * 0.10, h * 0.30, w * 0.80, h * 0.48) cornerRadius:w * 0.10];
    [body appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(w * 0.35, h * 0.20, w * 0.30, h * 0.16) cornerRadius:w * 0.05]];
    [body fill];
    // Ống kính: khoét một đĩa rồi đặt lại một chấm ở giữa
    CGPoint c = CGPointMake(w / 2, h * 0.54);
    CGContextSetBlendMode(ctx, kCGBlendModeClear);
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - w * 0.17, c.y - w * 0.17, w * 0.34, w * 0.34));
    CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - w * 0.09, c.y - w * 0.09, w * 0.18, w * 0.18));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) objc_setAssociatedObject(image, &kOursKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return image;
}

static char kFieldInvertKey;

static void G6SMSStyleEntry(UIImageView *entry) {
    if (!gActive || !G6UIBarsActive()) return;
    BOOL dark = G6SMSDark();
    NSNumber *mode = objc_getAssociatedObject(entry, &kModeKey);
    BOOL fresh = !mode || mode.boolValue != dark;
    CGFloat height = entry.bounds.size.height;
    // Mặt thanh: dựng lại khi đổi chế độ hoặc thanh đổi chiều cao (ô nhập nhiều dòng)
    if (height > 8 && (fresh || !objc_getAssociatedObject(entry.image, &kOursKey) || fabs(entry.image.size.height - height) > 0.5)) {
        UIImage *surface = G6UIBarSurfaceImage(height, YES);
        if (surface) {
            objc_setAssociatedObject(surface, &kOursKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            entry.image = surface;
        }
    }
    UIImageView *cover = G6SMSIvar(entry, "_inputFieldCover");
    if ([cover isKindOfClass:[UIImageView class]] && cover.image) {
        UIImage *original = objc_getAssociatedObject(cover, &kSavedKey);
        if (!objc_getAssociatedObject(cover.image, &kOursKey)) {
            original = cover.image;
            objc_setAssociatedObject(cover, &kSavedKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            fresh = YES;
        }
        if (fresh && original) {
            UIImage *flat = G6SMSFieldCover(original, dark);
            if (flat) cover.image = flat;
        }
    }
    // Nền sau chữ đang gõ. iPad: giữ SÁNG ở cả hai chế độ (chữ đen của người dùng không bị đổi màu). iPhone: ô nhập chiếm gần
    // hết bề ngang thanh nên ô sáng làm cả thanh sáng trên màn tối → ô tối thật, còn chữ đang gõ (đen, do khung soạn thảo
    // web vẽ — không đổi màu trong nội dung) được ĐẢO MÀU lúc hiển thị bằng bộ lọc trên chính ô soạn (CKContentEntryView).
    BOOL darkField = dark && g6_device_is_phone() && G6UISkinInvertFilter() != nil;
    UIView *fieldBack = G6SMSIvar(entry, "_inputFieldBackground");
    if ([fieldBack isKindOfClass:[UIView class]]) {
        UIColor *fill = darkField ? [UIColor colorWithWhite:0.14 alpha:1] : (dark ? [UIColor colorWithWhite:0.80 alpha:1] : [UIColor whiteColor]);
        if (![fieldBack.backgroundColor isEqual:fill]) fieldBack.backgroundColor = fill;
    }
    if (g6_device_is_phone()) {
        Class contentClass = objc_getClass("CKContentEntryView");
        for (UIView *sub in entry.subviews) {
            if (!contentClass || ![sub isKindOfClass:contentClass]) continue;
            BOOL has = objc_getAssociatedObject(sub, &kFieldInvertKey) != nil;
            if (darkField && !has) {
                sub.layer.filters = @[G6UISkinInvertFilter()];
                objc_setAssociatedObject(sub, &kFieldInvertKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else if (!darkField && has) {
                sub.layer.filters = nil;
                objc_setAssociatedObject(sub, &kFieldInvertKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
    UIColor *glyphColor = [G6UIBarTextColor() colorWithAlphaComponent:1];
    UIButton *photo = G6SMSIvar(entry, "_photoButton");
    if ([photo isKindOfClass:[UIButton class]]) {
        // App đặt ảnh của nút ở chỗ nào (hình hay nền) thì thay đúng chỗ đó; ảnh của ta mang dấu, đổi chế độ thì vẽ lại
        for (int slot = 0; slot < 2; slot++) {
            UIImage *current = slot == 0 ? [photo imageForState:UIControlStateNormal] : [photo backgroundImageForState:UIControlStateNormal];
            if (!current) continue;
            if (objc_getAssociatedObject(current, &kOursKey) && !fresh) continue;
            UIImage *glyph = G6SMSCameraGlyph(current.size, glyphColor);
            if (!glyph) continue;
            UIImage *pressed = G6SMSCameraGlyph(current.size, [glyphColor colorWithAlphaComponent:0.45]);
            if (slot == 0) {
                [photo setImage:glyph forState:UIControlStateNormal];
                [photo setImage:pressed forState:UIControlStateHighlighted];
            } else {
                [photo setBackgroundImage:glyph forState:UIControlStateNormal];
                [photo setBackgroundImage:pressed forState:UIControlStateHighlighted];
            }
        }
    }
    UIButton *send = G6SMSIvar(entry, "_sendButton");
    if ([send isKindOfClass:[UIButton class]]) {
        // Ảnh nền gốc của từng trạng thái (để biết lam / lục / xám) nhớ trên chính nút: app đặt ảnh mới (đổi lam ↔ lục, bật ↔
        // tắt) thì nhớ lại; đổi sáng ↔ tối thì dựng lại viên từ ảnh gốc đã nhớ
        NSMutableDictionary *originals = objc_getAssociatedObject(send, &kSavedKey);
        if (!originals) {
            originals = [NSMutableDictionary dictionary];
            objc_setAssociatedObject(send, &kSavedKey, originals, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (NSNumber *stateNumber in @[@(UIControlStateNormal), @(UIControlStateHighlighted), @(UIControlStateDisabled)]) {
            UIControlState state = (UIControlState)stateNumber.unsignedIntegerValue;
            UIImage *background = [send backgroundImageForState:state];
            BOOL changed = NO;
            if (background && !objc_getAssociatedObject(background, &kOursKey)) {
                originals[stateNumber] = background;
                changed = YES;
            }
            UIImage *original = originals[stateNumber];
            if (!original || (!changed && !fresh)) continue;
            G6BalloonKind kind = G6SMSKindOfImage(original);
            UIColor *fill = state == UIControlStateDisabled || kind == G6BalloonGray
                                ? [UIColor colorWithWhite:dark ? 0.32 : 0.70 alpha:1]
                                : G6SMSBalloonColor(kind, dark, state == UIControlStateHighlighted);
            CGFloat h = MAX(original.size.height, 20), r = h / 2;
            UIImage *pill = G6SMSPill(CGSizeMake(2 * ceil(r) + 1, h), fill, UIEdgeInsetsMake(0, ceil(r), 0, ceil(r)));
            if (pill) [send setBackgroundImage:pill forState:state];
        }
        for (NSNumber *stateNumber in @[@(UIControlStateNormal), @(UIControlStateHighlighted), @(UIControlStateDisabled)]) {
            UIControlState state = (UIControlState)stateNumber.unsignedIntegerValue;
            UIColor *want = [UIColor colorWithWhite:1 alpha:state == UIControlStateDisabled ? 0.75 : 1];
            if (![[send titleColorForState:state] isEqual:want]) [send setTitleColor:want forState:state];
            UIColor *shadow = [send titleShadowColorForState:state];
            if (shadow && CGColorGetAlpha(shadow.CGColor) > 0) [send setTitleShadowColor:[UIColor clearColor] forState:state];
        }
        if (G6FontAvailable()) {
            UIFont *want = G6Font(G6FontSemiBold, send.titleLabel.font.pointSize > 0 ? send.titleLabel.font.pointSize : 16);
            if (want && ![send.titleLabel.font.fontName isEqualToString:want.fontName]) send.titleLabel.font = want;
        }
    }
    objc_setAssociatedObject(entry, &kModeKey, @(dark), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void (*orig_entryLayout)(UIImageView *, SEL);
static void repl_entryLayout(UIImageView *self, SEL _cmd) {
    orig_entryLayout(self, _cmd);
    @try {
        G6SMSStyleEntry(self);
    } @catch (NSException *e) {
        G6Log(@"tin nhắn: lỗi khi dựng thanh nhập: %@", e);
    }
}

// App đổi màu nút «Gửi» (lam ↔ lục, bật ↔ tắt) bằng cách đặt ảnh nền mới: dựng lại ngay sau đó
static void (*orig_updateSendColor)(UIImageView *, SEL);
static void repl_updateSendColor(UIImageView *self, SEL _cmd) {
    orig_updateSendColor(self, _cmd);
    @try {
        G6SMSStyleEntry(self);
    } @catch (NSException *e) {
    }
}

// ---- Hai nút hình trên thanh của cột phải ----

static void G6SMSStyleToolbar(UIView *toolbar) {
    if (!gActive || !G6UIBarsActive()) return;
    BOOL dark = G6UIBarsDark();
    UIColor *color = [G6UIBarTextColor() colorWithAlphaComponent:1];
    for (UIButton *button in toolbar.subviews) {
        if (![button isKindOfClass:[UIButton class]]) continue;
        UIImage *image = [button imageForState:UIControlStateNormal];
        if (!image) continue;
        NSNumber *mode = objc_getAssociatedObject(image, &kModeKey);
        if (mode && mode.boolValue == dark) continue;
        UIImage *tinted = G6UITintedImage(image, color);
        if (!tinted) continue;
        objc_setAssociatedObject(tinted, &kModeKey, @(dark), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button setImage:tinted forState:UIControlStateNormal];
    }
}

static void (*orig_toolbarLayout)(UIView *, SEL);
static void repl_toolbarLayout(UIView *self, SEL _cmd) {
    orig_toolbarLayout(self, _cmd);
    @try {
        G6SMSStyleToolbar(self);
    } @catch (NSException *e) {
    }
}

// ---- Làm mới khi đổi cấu hình ----

static void G6SMSRefresh(UIView *view, int depth) {
    static Class balloon, transcript, stamp, status, service, header, listCell, entry, toolbar, mailButton, recipients;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mailButton = objc_getClass("MailToolbarButton");
        recipients = objc_getClass("CKComposeRecipientView");
        balloon = objc_getClass("CKColoredBalloonView");
        transcript = objc_getClass("CKTranscriptTableView");
        stamp = objc_getClass("CKTimestampCell");
        status = objc_getClass("CKMessageStatusCell");
        service = objc_getClass("CKServiceCell");
        header = objc_getClass("CKTranscriptHeaderView");
        listCell = objc_getClass("CKConversationListCell");
        entry = objc_getClass("CKMessageEntryView");
        toolbar = objc_getClass("CKTranscriptToolbarView");
    });
    @try {
        if (balloon && [view isKindOfClass:balloon]) {
            if (gActive) {
                G6SMSFlattenBalloon((UIImageView *)view, NO);
                if (((UIImageView *)view).highlightedImage) G6SMSFlattenBalloon((UIImageView *)view, YES);
                SEL updateText = NSSelectorFromString(@"updateTextColor");
                if ([view respondsToSelector:updateText]) ((void (*)(id, SEL))objc_msgSend)(view, updateText);
            }
        } else if (transcript && [view isKindOfClass:transcript]) {
            G6SMSStyleTranscript((UITableView *)view);
        } else if ((stamp && [view isKindOfClass:stamp]) || (status && [view isKindOfClass:status]) ||
                   (service && [view isKindOfClass:service])) {
            G6SMSStyleStampCell(view);
        } else if (header && [view isKindOfClass:header]) {
            G6SMSStyleHeader(view);
        } else if (mailButton && [view isKindOfClass:mailButton]) {
            G6SMSStyleToolbarButton((UIButton *)view);
        } else if (recipients && [view isKindOfClass:recipients]) {
            G6SMSStyleRecipients(view);
        } else if (listCell && [view isKindOfClass:listCell]) {
            G6SMSStyleListCell((UITableViewCell *)view);
        } else if (entry && [view isKindOfClass:entry]) {
            G6SMSStyleEntry((UIImageView *)view);
        } else if (toolbar && [view isKindOfClass:toolbar]) {
            G6SMSStyleToolbar(view);
        }
    } @catch (NSException *e) {
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6SMSRefresh(sub, depth - 1);
}

void G6UIAppMessagesApply(BOOL active) {
    Class balloon = objc_getClass("CKColoredBalloonView");
    if (!balloon) return;
    static BOOL installed;
    if (!installed) {
        if (!active) return;
        installed = YES;
        G6Hook(balloon, NSSelectorFromString(@"updateImage"), (IMP)repl_updateImage, (IMP *)&orig_updateImage);
        G6Hook(balloon, NSSelectorFromString(@"updateHighlightedImage"), (IMP)repl_updateHighlighted, (IMP *)&orig_updateHighlighted);
        G6HookNamed("_CKTextBalloonView", NSSelectorFromString(@"textColor"), (IMP)repl_textColor, (IMP *)&orig_textColor);
        G6HookNamed("_CKTextBalloonView", NSSelectorFromString(@"textShadowColor"), (IMP)repl_textShadowColor, (IMP *)&orig_textShadowColor);
        G6HookNamed("CKTranscriptTableView", @selector(layoutSubviews), (IMP)repl_transcriptLayout, (IMP *)&orig_transcriptLayout);
        G6HookNamed("CKTranscriptCell", @selector(layoutSubviews), (IMP)repl_stampLayout, (IMP *)&orig_stampLayout);
        // Ô dịch vụ tự xếp lại nhãn / vạch chấm sau lời gọi lên lớp cha → móc riêng để chỉnh SAU khi nó xếp xong
        G6HookNamed("CKServiceCell", @selector(layoutSubviews), (IMP)repl_serviceLayout, (IMP *)&orig_serviceLayout);
        G6HookNamed("CKTranscriptHeaderView", @selector(layoutSubviews), (IMP)repl_headerLayout, (IMP *)&orig_headerLayout);
        G6HookNamed("MailToolbarButton", @selector(layoutSubviews), (IMP)repl_toolbarButtonLayout, (IMP *)&orig_toolbarButtonLayout);
        G6HookNamed("CKComposeRecipientView", @selector(layoutSubviews), (IMP)repl_recipientsLayout, (IMP *)&orig_recipientsLayout);
        G6HookNamed("MFHeaderLabelView", NSSelectorFromString(@"labelColor"), (IMP)repl_headerLabelColor, (IMP *)&orig_headerLabelColor);
        G6HookNamed("CKConversationListCell", @selector(layoutSubviews), (IMP)repl_listCellLayout, (IMP *)&orig_listCellLayout);
        G6HookNamed("CKMessageEntryView", @selector(layoutSubviews), (IMP)repl_entryLayout, (IMP *)&orig_entryLayout);
        G6HookNamed("CKMessageEntryView", NSSelectorFromString(@"_updateSendButtonColor"), (IMP)repl_updateSendColor, (IMP *)&orig_updateSendColor);
        G6HookNamed("CKTranscriptToolbarView", @selector(layoutSubviews), (IMP)repl_toolbarLayout, (IMP *)&orig_toolbarLayout);
        G6Log(@"tin nhắn (app): vẽ lại");
    }
    gActive = active;
    // Mọi cửa sổ, kể cả cửa sổ chứa thanh nhập (thanh nhập là phụ kiện bàn phím, nằm ngoài cửa sổ chính)
    SEL all = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
    NSArray *windows = [UIApplication sharedApplication].windows;
    if ([UIWindow respondsToSelector:all]) {
        NSArray *more = ((id (*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], all, YES, NO);
        if ([more isKindOfClass:[NSArray class]] && more.count) windows = more;
    }
    for (UIWindow *window in windows) G6SMSRefresh(window, 16);
}
