// Khung «vẽ lại app giả vật liệu» (Lịch bọc da, Danh bạ dạng sổ, Ghi chú giấy vàng, Lời nhắc…).
//
// Hai việc, đều không đụng tới dữ liệu hay cách app hoạt động:
//
// 1. THAY VÂN THEO TÊN HÌNH. Các app này dựng giao diện từ hình trong gói app, nạp qua một cửa duy nhất là
//    +[UIImage imageNamed:] với tên rõ ràng (đo bằng công cụ `imglog`, 19/11/2026: «back LS», «index LS», «LStop bar»,
//    «backgroundPattern», «Calendar-Day-Nav-LS», «BookLeftEdge»…). Móc hàm đó: tên có trong bảng của app thì trả một ảnh
//    phẳng CÙNG CỠ với ảnh gốc (bố cục của app tính theo cỡ ảnh, và app tự gọi stretchable… trên ảnh nhận về) — nền da →
//    một màu, giấy → mặt trắng, thanh da → mặt thanh có nét mảnh, bóng / mép rách / đường khâu → trong suốt, nút → viên bo
//    tròn. Không sửa tệp nào trong gói app.
//
// 2. CHẾ ĐỘ TỐI BẰNG BỘ LỌC. Mọi ảnh thay thế đều theo bảng màu SÁNG. Ở chế độ tối, cửa sổ của app mang một bộ lọc màu
//    CAFilter «đảo sáng tối, giữ sắc màu» (như bàn phím — D30; cả cửa sổ 1024×768 tốn thêm ~5% CPU của trình dựng hình lúc
//    đang có chuyển động): giấy trắng → đen, chữ đen → trắng, màu nhấn giữ sắc. Lợi:
//      - chữ app tự vẽ, trang ghi chú, ô lịch… đều tối theo mà không phải biết từng lớp view của app;
//      - KHÔNG đổi màu chữ trong tài liệu của người dùng (đổi textColor của trang ghi chú có nguy cơ lọt vào nội dung được
//        lưu / đồng bộ) — chỉ đổi cách hiển thị;
//      - đổi sáng ↔ tối lúc app đang mở chỉ là gắn / gỡ bộ lọc: đổi tức thì, không phải dựng lại hình nào.
//    Ma trận dùng ở đây là phép đảo thuần (không thêm tương phản như bàn phím) để nó là phép ĐỐI HỢP: áp hai lần thì về màu
//    gốc. Nhờ vậy view chứa ảnh thật (ảnh chân dung…) chỉ cần mang thêm đúng bộ lọc đó là giữ nguyên màu (G6UISkinKeepColors).
//    Hệ quả phải nhớ khi vẽ ảnh thay thế: bóng đổ tối sẽ thành quầng sáng → ảnh thay thế không dùng bóng, chỉ dùng nét mảnh.
//
// Vì phần tối do bộ lọc lo, các thành phần chuẩn của Glass6UI trong app này (nút điều khiển, bánh xe…) phải dựng theo bảng
// màu sáng: chúng hỏi G6UIDark() thay cho G6IsDark(). Bàn phím nằm ở cửa sổ khác, không dính bộ lọc này, vẫn theo chế độ thật.
#import "G6UISkin.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6UI.h"

// ---- Bảng màu (sáng) của ảnh thay thế ----
static const CGFloat kBackdropWhite = 0.93, kSurfaceWhite = 1.0, kBarWhite = 0.97, kHairWhite = 0.80;
static const CGFloat kButtonWhite = 1.0, kButtonDownWhite = 0.86, kFieldWhite = 0.89, kGlyphWhite = 0.38;

static BOOL gActive;
static NSHashTable *gKeepColors;      // các view «giữ đúng màu» còn sống (giữ yếu) — đổi chế độ thì xét lại
static NSMutableDictionary *gImages;  // tên đã chuẩn hoá → @(kind) hoặc @[@(kind), tham số…]
static NSMutableDictionary *gCache;   // tên đã chuẩn hoá → ảnh thay thế
static char kWindowFilterKey, kKeepColorsKey, kKeepWantedKey, kRegionKey;

BOOL G6UISkinActive(void) {
    return gActive;
}

BOOL G6UIDark(void) {
    return gActive ? NO : G6IsDark();
}

// ---- Ảnh thay thế ----

// «back LS~ipad.png» → «back LS»; «body-568h» (bản cho màn 4 inch của iPhone 5) → «body»
static NSString *G6SkinKey(NSString *name) {
    NSString *key = name;
    if ([key.pathExtension.lowercaseString isEqualToString:@"png"]) key = [key stringByDeletingPathExtension];
    for (NSString *suffix in @[@"@2x", @"~ipad", @"~iphone", @"@2x", @"-568h"]) {
        if ([key hasSuffix:suffix]) key = [key substringToIndex:key.length - suffix.length];
    }
    return key;
}

static UIImage *G6SkinDraw(CGSize size, CGFloat scale, void (^draw)(CGContextRef ctx, CGRect bounds)) {
    if (size.width < 0.5 || size.height < 0.5) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, scale > 0 ? scale : 1);
    draw(UIGraphicsGetCurrentContext(), (CGRect){CGPointZero, size});
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIImage *G6SkinMake(id spec, UIImage *original) {
    // Hình app tự khai cách vẽ (G6SkinMaker): micro, đồng hồ VU… — thứ mà các kiểu chung dưới đây không tả được
    if ([spec isKindOfClass:NSClassFromString(@"NSBlock")]) return ((G6SkinMaker)spec)(original);
    NSArray *parts = [spec isKindOfClass:[NSArray class]] ? spec : @[spec];
    int kind = [parts[0] intValue];
    // Hình nằm trong «vùng vốn tối»: mọi sắc xám dùng giá trị đảo (trắng ↔ đen) — bộ lọc của vùng đảo lại cho đúng
    BOOL inverted = (kind & G6SkinInverted) != 0;
    kind &= ~G6SkinInverted;
    CGFloat (^tone)(CGFloat) = ^CGFloat(CGFloat white) {
        return inverted ? 1 - white : white;
    };
    CGFloat p1 = parts.count > 1 ? [parts[1] floatValue] : 0, p2 = parts.count > 2 ? [parts[2] floatValue] : 0;
    CGFloat scale = original.scale > 0 ? original.scale : 1, hair = 1 / scale;
    if (kind == G6SkinGlyph) return G6UITintedImage(original, [UIColor colorWithWhite:tone(kGlyphWhite) alpha:1]);
    return G6SkinDraw(original.size, scale, ^(CGContextRef ctx, CGRect b) {
        UIColor *hairColor = [UIColor colorWithWhite:tone(kHairWhite) alpha:1];
        switch (kind) {
            case G6SkinBackdrop:
                [[UIColor colorWithWhite:tone(kBackdropWhite) alpha:1] setFill];
                CGContextFillRect(ctx, b);
                break;
            case G6SkinSurface:
                [[UIColor colorWithWhite:tone(kSurfaceWhite) alpha:1] setFill];
                CGContextFillRect(ctx, b);
                break;
            case G6SkinCard: {
                CGFloat inset = p1 > 0 ? p1 : 6, radius = p2 > 0 ? p2 : 10;
                CGRect r = CGRectInset(b, inset + hair / 2, inset + hair / 2);
                UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius];
                [[UIColor colorWithWhite:tone(kSurfaceWhite) alpha:1] setFill];
                [path fill];
                path.lineWidth = hair;
                [hairColor setStroke];
                [path stroke];
                break;
            }
            case G6SkinBar:
            case G6SkinBarBottom:
                [[UIColor colorWithWhite:tone(kBarWhite) alpha:1] setFill];
                CGContextFillRect(ctx, b);
                [hairColor setFill];
                CGContextFillRect(ctx, CGRectMake(0, kind == G6SkinBar ? b.size.height - hair : 0, b.size.width, hair));
                break;
            case G6SkinButton:
            case G6SkinButtonDown: {
                CGRect r = CGRectInset(b, hair / 2, hair / 2 + 1);
                UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:MIN(r.size.height, r.size.width) / 2];
                [[UIColor colorWithWhite:tone(kind == G6SkinButton ? kButtonWhite : kButtonDownWhite) alpha:1] setFill];
                [path fill];
                path.lineWidth = hair;
                [hairColor setStroke];
                [path stroke];
                break;
            }
            case G6SkinField: {
                CGRect r = CGRectInset(b, 0, 1);
                [[UIColor colorWithWhite:tone(kFieldWhite) alpha:1] setFill];
                [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:MIN(r.size.height, r.size.width) / 2] fill];
                break;
            }
            case G6SkinSelection: {
                CGRect r = CGRectInset(b, 4, 3);
                [[UIColor colorWithWhite:tone(0) alpha:inverted ? 0.14 : 0.09] setFill];
                [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:9] fill];
                break;
            }
            case G6SkinPressed:
                [[UIColor colorWithWhite:tone(0) alpha:0.10] setFill];
                CGContextFillEllipseInRect(ctx, CGRectInset(b, 2, 2));
                break;
            case G6SkinHairline:
                [hairColor setFill];
                CGContextFillRect(ctx, b);
                break;
            case G6SkinHighlight:
                [[UIColor colorWithWhite:tone(0) alpha:inverted ? 0.16 : 0.09] setFill];
                CGContextFillRect(ctx, b);
                break;
            case G6SkinChip: {
                CGRect r = CGRectInset(b, hair / 2, hair / 2);
                UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:MIN(4, MIN(r.size.width, r.size.height) / 2)];
                [[UIColor colorWithWhite:tone(0) alpha:0.10] setFill];
                [path fill];
                path.lineWidth = hair;
                [[UIColor colorWithWhite:tone(0) alpha:0.35] setStroke];
                [path stroke];
                break;
            }
            default:
                break;  // G6SkinClear: để trong suốt
        }
    });
}

static id (*orig_imageNamed)(id, SEL, NSString *);
static id repl_imageNamed(id self, SEL _cmd, NSString *name) {
    UIImage *original = orig_imageNamed(self, _cmd, name);
    if (!gActive || !original || ![name isKindOfClass:[NSString class]]) return original;
    @try {
        NSString *key = G6SkinKey(name);
        id spec = gImages[key];
        if (!spec) return original;
        UIImage *made = gCache[key];
        if (!made) {
            made = G6SkinMake(spec, original);
            if (!made) return original;
            if (!gCache) gCache = [NSMutableDictionary dictionary];
            gCache[key] = made;
        }
        return made;
    } @catch (NSException *e) {
        G6Log(@"vẽ lại app: lỗi khi thay hình «%@»: %@", name, e);
    }
    return original;
}

void G6UISkinRegister(NSDictionary *images) {
    if (!gImages) gImages = [NSMutableDictionary dictionary];
    [gImages addEntriesFromDictionary:images];
    if (orig_imageNamed) return;
    // Chỉ đổi hàm (việc của runtime): đang chạy trong hàm khởi tạo của thư viện, trước UIApplicationMain. objc_getClass chứ
    // không [UIImage class] — không gửi thông điệp nào cho lớp UIKit ở đây.
    Class cls = objc_getClass("UIImage");
    Method m = cls ? class_getClassMethod(cls, @selector(imageNamed:)) : NULL;
    if (m) orig_imageNamed = (id (*)(id, SEL, NSString *))method_setImplementation(m, (IMP)repl_imageNamed);
}

void G6UISkinSetActive(BOOL active) {
    gActive = active && orig_imageNamed != NULL;
}

// ---- Bộ lọc tối ----

// Cùng bố cục với CAColorMatrix của QuartzCore
typedef struct {
    float m11, m12, m13, m14, m15;
    float m21, m22, m23, m24, m25;
    float m31, m32, m33, m34, m35;
    float m41, m42, m43, m44, m45;
} G6ColorMatrix;

// màu mới = 1 + màu − (2/3)(đỏ + lục + lam): đảo sáng tối, giữ sắc màu; áp hai lần thì về màu gốc. Hằng số đi vào cột alpha
// (điểm ảnh trong suốt vẫn trong suốt).
static id G6SkinInvertFilter(void) {
    static id filter;
    if (filter) return filter;
    Class cls = objc_getClass("CAFilter");
    SEL make = NSSelectorFromString(@"filterWithType:");
    if (![cls respondsToSelector:make]) return nil;
    id f = ((id (*)(id, SEL, id))objc_msgSend)(cls, make, @"colorMatrix");
    if (!f) return nil;
    const float a = 1.0f / 3, b = -2.0f / 3;
    G6ColorMatrix m = {
        a, b, b, 1, 0,
        b, a, b, 1, 0,
        b, b, a, 1, 0,
        0, 0, 0, 1, 0,
    };
    @try {
        [f setValue:[NSValue valueWithBytes:&m objCType:"{CAColorMatrix=ffffffffffffffffffff}"] forKey:@"inputColorMatrix"];
    } @catch (NSException *e) {
        return nil;
    }
    filter = f;
    return filter;
}

id G6UISkinInvertFilter(void) {
    return G6SkinInvertFilter();
}

// Bộ lọc tối cho cửa sổ nội dung của app (lớp UIWindow thuần: không đụng cửa sổ bàn phím, cửa sổ hộp thoại, cửa sổ thử)
static void G6SkinStyleWindow(UIWindow *window) {
    if (![window isMemberOfClass:[UIWindow class]]) return;
    BOOL want = gActive && G6IsDark();
    BOOL has = objc_getAssociatedObject(window, &kWindowFilterKey) != nil;
    if (want && !has) {
        id filter = G6SkinInvertFilter();
        if (!filter) return;
        window.layer.filters = @[filter];
        objc_setAssociatedObject(window, &kWindowFilterKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!want && has) {
        window.layer.filters = nil;
        objc_setAssociatedObject(window, &kWindowFilterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Nút tròn «xoá / thêm» ở đầu dòng lúc bảng đang sửa và nút «Xoá» xác nhận: màu của chúng là tín hiệu (đỏ = xoá, lục = thêm)
// nên phải giữ đúng — dưới một lần đảo thì đĩa đỏ viền trắng thành hồng nhạt viền đen (gặp ở cột trái của Lời nhắc).
static void (*orig_editControlDidMove)(UIView *, SEL);
static void repl_editControlDidMove(UIView *self, SEL _cmd) {
    orig_editControlDidMove(self, _cmd);
    @try {
        if (self.window) G6UISkinKeepColors(self, YES);
    } @catch (NSException *e) {
    }
}

static void (*orig_deleteConfirmDidMove)(UIView *, SEL);
static void repl_deleteConfirmDidMove(UIView *self, SEL _cmd) {
    orig_deleteConfirmDidMove(self, _cmd);
    @try {
        if (self.window) G6UISkinKeepColors(self, YES);
    } @catch (NSException *e) {
    }
}

void G6UISkinApply(void) {
    static BOOL watching;
    if (!watching && gActive) {
        watching = YES;
        G6HookNamed("UITableViewCellEditControl", @selector(didMoveToWindow), (IMP)repl_editControlDidMove, (IMP *)&orig_editControlDidMove);
        G6HookNamed("UITableViewCellDeleteConfirmationControl", @selector(didMoveToWindow), (IMP)repl_deleteConfirmDidMove,
                    (IMP *)&orig_deleteConfirmDidMove);
        // Cửa sổ sinh ra sau (app mở thêm cửa sổ): nhận bộ lọc lúc hiện lên
        [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          if ([note.object isKindOfClass:[UIWindow class]]) G6SkinStyleWindow(note.object);
                                                      }];
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6SkinStyleWindow(window);
    // Ảnh thật trong app: bộ lọc ngược của chúng đi cùng bộ lọc tối của cửa sổ
    for (UIView *view in [gKeepColors allObjects]) {
        G6UISkinKeepColors(view, objc_getAssociatedObject(view, &kKeepWantedKey) != nil);
    }
}

UIColor *G6UISkinBackdropColor(void) {
    return [UIColor colorWithWhite:kBackdropWhite alpha:1];
}

// Các lớp phía trên view đang đảo màu nó một số LẺ lần? (bộ lọc tối của cửa sổ + mỗi «vùng vốn tối» bao quanh — phép đảo là
// đối hợp nên chỉ cần tính chẵn lẻ). View chưa vào cửa sổ: tạm tính theo chế độ, lượt G6UISkinApply sau sẽ xét lại.
static BOOL G6SkinInvertedAbove(UIView *view) {
    UIWindow *window = view.window;
    BOOL odd = window ? objc_getAssociatedObject(window, &kWindowFilterKey) != nil : (gActive && G6IsDark());
    for (UIView *v = view.superview; v; v = v.superview) {
        if (objc_getAssociatedObject(v, &kRegionKey)) odd = !odd;
    }
    return odd;
}

void G6UISkinKeepColors(UIView *view, BOOL keep) {
    if (!view) return;
    if (!gKeepColors) gKeepColors = [NSHashTable weakObjectsHashTable];
    [gKeepColors addObject:view];
    objc_setAssociatedObject(view, &kKeepWantedKey, keep ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Mang thêm một lần đảo khi (và chỉ khi) phía trên đang đảo lẻ lần → tổng chẵn → đúng màu gốc. Trong «vùng vốn tối» điều
    // đó xảy ra ở chế độ SÁNG (vùng đảo một lần), còn ở chế độ tối cửa sổ + vùng đã là hai lần.
    BOOL want = keep && gActive && G6SkinInvertedAbove(view);
    BOOL has = objc_getAssociatedObject(view, &kKeepColorsKey) != nil;
    if (want && !has) {
        id filter = G6SkinInvertFilter();
        if (!filter) return;
        view.layer.filters = @[filter];
        objc_setAssociatedObject(view, &kKeepColorsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!want && has) {
        view.layer.filters = nil;
        objc_setAssociatedObject(view, &kKeepColorsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

void G6UISkinInvertRegion(UIView *view) {
    BOOL has = objc_getAssociatedObject(view, &kRegionKey) != nil;
    if (gActive && !has) {
        id filter = G6SkinInvertFilter();
        if (!filter) return;
        view.layer.filters = @[filter];
        objc_setAssociatedObject(view, &kRegionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!gActive && has) {
        view.layer.filters = nil;
        objc_setAssociatedObject(view, &kRegionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
