// App Ghi âm (com.apple.VoiceMemos) trên iPhone — bỏ micro mạ crôm, bảng kim loại, đồng hồ VU giả cổ.
//
// iOS 6 (tra trên máy 20/11/2026 bằng `imglog`, `imgdump`):
//   RCMicView (320×568)
//     UIImageView (0 −30; 320×568, mờ 0,4)    quầng sáng sau micro (ảnh 448×447, nạp không qua +imageNamed:)
//     UIImageView (60 76; 200×397)            ảnh micro (nạp không qua +imageNamed:)
//   RCControlsView (0 473; 320×96)
//     «bezel» 320×96                          bảng kim loại tối có hai hốc tròn + hốc đồng hồ
//       «vu» 320×97                           mặt đồng hồ VU màu kem (ở giữa, 160×75 từ (80, 11))
//     UIButton «record» / «pause» / «stop» (+ «…Down») 46×47   nút ghi bên trái
//     UIButton «list» / «listDown» 46×47      nút mở danh sách bên phải
//     UIView (80 11; 160×75) › «needle» 11×71 kim: neo ở đáy–giữa ảnh, tâm quay (80, 85) của view này, quay −48° … +48°
//       «vumask» 160×75                       mặt nạ của ô chứa kim (không phải lớp phủ)
//     «redlevelON» / «redlevelOFF» 25×25      đèn báo quá mức
//   Danh sách bản ghi: thanh điều hướng + bảng chuẩn; bảng phát ở đáy = «playback-hud-bg» 320×126 (nền đen bóng có hai hốc
//   nút) chứa UIScrubberControl của UIKit (thanh tua kiểu cũ, tự vẽ số giây màu TRẮNG) + hai nút «bottombarblue» (Chia sẻ) /
//   «bottombarredfire» (Xoá).
//
// Vẽ lại bằng khung chung G6UISkin (ảnh thay thế theo bảng màu SÁNG, chế độ tối do bộ lọc của cửa sổ lo — nên app vốn tối
// này nay theo sáng / tối của máy như iOS 26): bảng điều khiển phẳng, đồng hồ VU là một ô bo góc có vạch chia vẽ đúng theo
// tâm quay của kim, kim là một nét cam, nút ghi là vòng tròn + đĩa đỏ (tạm dừng: hai vạch đỏ; dừng: ô vuông đỏ), nút danh
// sách là đĩa mờ ba vạch, đèn báo là chấm đỏ. Ảnh micro + quầng sáng (không bắt được theo tên) đổi ngay ở RCMicView: micro
// thành hình nét. Thanh trạng thái (app xin kiểu đen) được báo luôn theo kiểu phẳng, tô cùng màu nền khi màn micro đang hiện.
// Bảng phát ở đáy danh sách: nền phẳng; thanh tua vẽ chữ trắng nên được khai là «vùng vốn tối» (G6UISkinInvertRegion) — ở chế
// độ sáng chữ thành tối trên bảng sáng, ở chế độ tối bộ lọc của cửa sổ đảo lại thành chữ sáng.
#import "G6UI.h"

#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"

static BOOL gActive;
static char kMicSavedKey;

// ---- Bảng màu (sáng) ----
static UIColor *G6VMInk(CGFloat alpha) {
    return [UIColor colorWithWhite:0.12 alpha:alpha];
}

static UIColor *G6VMRed(BOOL pressed) {
    return pressed ? [UIColor colorWithRed:0.80 green:0.16 blue:0.13 alpha:1] : [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1];
}

static UIImage *G6VMDraw(UIImage *original, void (^draw)(CGContextRef ctx, CGSize size)) {
    CGSize size = original.size;
    if (size.width < 1 || size.height < 1) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, original.scale > 0 ? original.scale : 0);
    draw(UIGraphicsGetCurrentContext(), size);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// Vòng tròn bao nút (đường kính 42) quanh tâm ảnh
static void G6VMRing(CGSize size) {
    CGFloat d = MIN(42, MIN(size.width, size.height) - 3);
    UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(size.width / 2 - d / 2, size.height / 2 - d / 2, d, d)];
    ring.lineWidth = 2.5;
    [G6VMInk(0.85) setStroke];
    [ring stroke];
}

// Nút ghi. kind: 0 = ghi (đĩa đỏ), 1 = tạm dừng (hai vạch), 2 = dừng (ô vuông)
static G6SkinMaker G6VMRecordMaker(int kind, BOOL pressed) {
    return ^UIImage *(UIImage *original) {
        return G6VMDraw(original, ^(CGContextRef ctx, CGSize size) {
            G6VMRing(size);
            CGPoint c = CGPointMake(size.width / 2, size.height / 2);
            [G6VMRed(pressed) setFill];
            if (kind == 0) {
                CGFloat d = pressed ? 27 : 31;
                [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - d / 2, c.y - d / 2, d, d)] fill];
            } else if (kind == 1) {
                for (int i = -1; i <= 1; i += 2) {
                    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(c.x + i * 5 - 2.5, c.y - 8, 5, 16) cornerRadius:1.5] fill];
                }
            } else {
                [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(c.x - 8, c.y - 8, 16, 16) cornerRadius:3] fill];
            }
        });
    };
}

static G6SkinMaker G6VMListMaker(BOOL pressed) {
    return ^UIImage *(UIImage *original) {
        return G6VMDraw(original, ^(CGContextRef ctx, CGSize size) {
            CGPoint c = CGPointMake(size.width / 2, size.height / 2);
            CGFloat d = MIN(42, MIN(size.width, size.height) - 3);
            [[UIColor colorWithWhite:0 alpha:pressed ? 0.18 : 0.07] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - d / 2, c.y - d / 2, d, d)] fill];
            CGContextSetLineWidth(ctx, 2.2);
            CGContextSetLineCap(ctx, kCGLineCapRound);
            [G6VMInk(0.88) setStroke];
            for (int i = -1; i <= 1; i++) {
                CGContextMoveToPoint(ctx, c.x - 8.5, c.y + i * 6);
                CGContextAddLineToPoint(ctx, c.x + 8.5, c.y + i * 6);
            }
            CGContextStrokePath(ctx);
        });
    };
}

// Viên bo tròn tô màu (hai nút đáy của danh sách: Chia sẻ xanh, Xoá đỏ) — ảnh kéo giãn, bán kính vừa trong nửa bề ngang
static G6SkinMaker G6VMPillMaker(BOOL red, BOOL pressed) {
    return ^UIImage *(UIImage *original) {
        return G6VMDraw(original, ^(CGContextRef ctx, CGSize size) {
            CGFloat k = pressed ? 0.8 : 1;
            UIColor *fill = red ? [UIColor colorWithRed:1.0 * k green:0.23 * k blue:0.19 * k alpha:1]
                                : [UIColor colorWithRed:0 green:0.478 * k blue:1.0 * k alpha:1];
            CGRect body = CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5, 2);
            [fill setFill];
            [[UIBezierPath bezierPathWithRoundedRect:body cornerRadius:MIN(10, MIN(body.size.width, body.size.height) / 2 - 0.5)] fill];
        });
    };
}

void G6UIAppVoiceMemosPrepare(void) {
    G6UISkinRegister(@{
        // Bảng điều khiển: mặt phẳng + nét mảnh ở mép trên
        @"bezel" : @(G6SkinBarBottom),
        @"vu" : ^UIImage *(UIImage *original) {
            return G6VMDraw(original, ^(CGContextRef ctx, CGSize size) {
                // Ô đồng hồ: 160×75 từ (80, 11) của bảng; ảnh này cao hơn bảng 1 điểm và đặt lệch lên 1 điểm
                CGFloat hair = 1 / MAX([UIScreen mainScreen].scale, 1);
                CGRect window = CGRectMake(size.width / 2 - 80, 12, 160, 75);
                UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(window, hair / 2, hair / 2) cornerRadius:12];
                [[UIColor whiteColor] setFill];
                [path fill];
                path.lineWidth = hair;
                [[UIColor colorWithWhite:0.80 alpha:1] setStroke];
                [path stroke];
                // Vạch chia quanh tâm quay của kim: (80, 85) trong ô = đáy–giữa ảnh; kim quay −48° … +48°
                CGContextSaveGState(ctx);
                [path addClip];
                CGPoint pivot = CGPointMake(size.width / 2, window.origin.y + 85);
                CGContextSetLineCap(ctx, kCGLineCapRound);
                for (int a = -48; a <= 48; a += 8) {
                    BOOL major = (a + 48) % 16 == 0;
                    CGFloat rad = a * (CGFloat)M_PI / 180, r1 = major ? 55 : 59, r2 = 65;
                    UIColor *color = a > 16 ? [UIColor colorWithRed:0.93 green:0.20 blue:0.16 alpha:1] : [UIColor colorWithWhite:0.20 alpha:major ? 0.9 : 0.5];
                    [color setStroke];
                    CGContextSetLineWidth(ctx, major ? 2 : 1.5);
                    CGContextMoveToPoint(ctx, pivot.x + r1 * sinf(rad), pivot.y - r1 * cosf(rad));
                    CGContextAddLineToPoint(ctx, pivot.x + r2 * sinf(rad), pivot.y - r2 * cosf(rad));
                    CGContextStrokePath(ctx);
                }
                CGContextRestoreGState(ctx);
                [[UIColor colorWithWhite:0.20 alpha:0.55] setFill];
                NSString *label = @"VU";
                UIFont *font = G6Font(G6FontSemiBold, 9);
                CGSize ls = [label sizeWithFont:font];
                [label drawAtPoint:CGPointMake(round(pivot.x - ls.width / 2), window.origin.y + 56) withFont:font];
            });
        },
        // «vumask» KHÔNG thay: nó là mặt nạ (layer.mask) của ô chứa kim — cho trong suốt thì kim biến mất (đã gặp)
        @"needle" : ^UIImage *(UIImage *original) {
            return G6VMDraw(original, ^(CGContextRef ctx, CGSize size) {
                CGContextSetLineWidth(ctx, 2);
                CGContextSetLineCap(ctx, kCGLineCapRound);
                [[UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1] setStroke];
                CGContextMoveToPoint(ctx, size.width / 2, 3);
                CGContextAddLineToPoint(ctx, size.width / 2, size.height);
                CGContextStrokePath(ctx);
            });
        },
        @"record" : G6VMRecordMaker(0, NO),
        @"recordDown" : G6VMRecordMaker(0, YES),
        @"pause" : G6VMRecordMaker(1, NO),
        @"pauseDown" : G6VMRecordMaker(1, YES),
        @"stop" : G6VMRecordMaker(2, NO),
        @"stopDown" : G6VMRecordMaker(2, YES),
        @"list" : G6VMListMaker(NO),
        @"listDown" : G6VMListMaker(YES),
        @"redlevelON" : ^UIImage *(UIImage *original) {
            return G6VMDraw(original, ^(CGContextRef ctx, CGSize size) {
                CGPoint c = CGPointMake(size.width / 2, size.height / 2);
                [[UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:0.25] setFill];
                CGContextFillEllipseInRect(ctx, CGRectMake(c.x - 8, c.y - 8, 16, 16));
                [[UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1] setFill];
                CGContextFillEllipseInRect(ctx, CGRectMake(c.x - 4.5, c.y - 4.5, 9, 9));
            });
        },
        @"redlevelOFF" : ^UIImage *(UIImage *original) {
            return G6VMDraw(original, ^(CGContextRef ctx, CGSize size) {
                CGPoint c = CGPointMake(size.width / 2, size.height / 2);
                [[UIColor colorWithWhite:0 alpha:0.16] setFill];
                CGContextFillEllipseInRect(ctx, CGRectMake(c.x - 4.5, c.y - 4.5, 9, 9));
            });
        },
        @"playback-hud-bg" : @(G6SkinBarBottom),
        @"bottombarblue" : G6VMPillMaker(NO, NO),
        @"bottombarblue_pressed" : G6VMPillMaker(NO, YES),
        @"bottombarredfire" : G6VMPillMaker(YES, NO),
        @"bottombarredfire_pressed" : G6VMPillMaker(YES, YES),
    });
}

// ---- Màn micro ----

// Micro dạng nét, cùng cỡ ảnh gốc (200×397)
static UIImage *G6VMMicImage(UIImage *original) {
    return G6VMDraw(original, ^(CGContextRef ctx, CGSize size) {
        CGFloat cx = size.width / 2, top = round(size.height * 0.16), w = 6;
        UIColor *ink = G6VMInk(0.9);
        // Thân micro
        UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - 38, top, 76, 150) cornerRadius:38];
        [[UIColor colorWithWhite:0 alpha:0.06] setFill];
        [body fill];
        body.lineWidth = w;
        [ink setStroke];
        [body stroke];
        // Gọng đỡ hình chữ U
        UIBezierPath *holder = [UIBezierPath bezierPath];
        CGFloat armY = top + 102, arcY = top + 128, r = 62;
        [holder moveToPoint:CGPointMake(cx - r, armY)];
        [holder addLineToPoint:CGPointMake(cx - r, arcY)];
        [holder addArcWithCenter:CGPointMake(cx, arcY) radius:r startAngle:M_PI endAngle:0 clockwise:NO];
        [holder addLineToPoint:CGPointMake(cx + r, armY)];
        holder.lineWidth = w;
        holder.lineCapStyle = kCGLineCapRound;
        [holder stroke];
        // Thân đỡ + chân đế
        UIBezierPath *stand = [UIBezierPath bezierPath];
        [stand moveToPoint:CGPointMake(cx, arcY + r)];
        [stand addLineToPoint:CGPointMake(cx, arcY + r + 58)];
        [stand moveToPoint:CGPointMake(cx - 36, arcY + r + 58)];
        [stand addLineToPoint:CGPointMake(cx + 36, arcY + r + 58)];
        stand.lineWidth = w;
        stand.lineCapStyle = kCGLineCapRound;
        [stand stroke];
    });
}

static UIImage *G6VMClearImage(void) {
    static UIImage *clear;
    if (!clear) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
        clear = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    return clear;
}

// Hai ảnh của RCMicView: cái rộng hơn màn micro (quầng sáng) → trong suốt; cái cao, hẹp (micro) → hình nét
static void G6VMStyleMic(UIView *mic) {
    BOOL active = gActive && G6UISkinActive();
    for (UIView *sub in mic.subviews) {
        if (![sub isMemberOfClass:[UIImageView class]]) continue;
        UIImageView *view = (UIImageView *)sub;
        NSDictionary *saved = objc_getAssociatedObject(view, &kMicSavedKey);
        if (!active) {
            if (saved && view.image == saved[@"mine"]) view.image = saved[@"image"];
            objc_setAssociatedObject(view, &kMicSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            continue;
        }
        UIImage *image = view.image;
        if (!image || (saved && image == saved[@"mine"])) continue;
        BOOL isMic = image.size.height > image.size.width * 1.5 && image.size.width >= 120;
        UIImage *mine = isMic ? G6VMMicImage(image) : G6VMClearImage();
        if (!mine) continue;
        objc_setAssociatedObject(view, &kMicSavedKey, @{@"image" : image, @"mine" : mine}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.image = mine;
    }
    NSDictionary *bg = objc_getAssociatedObject(mic, &kMicSavedKey);
    if (active) {
        if (!bg) objc_setAssociatedObject(mic, &kMicSavedKey, @{@"color" : mic.backgroundColor ?: (id)[NSNull null]}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIColor *color = G6UISkinBackdropColor();
        if (![mic.backgroundColor isEqual:color]) mic.backgroundColor = color;
    } else if (bg) {
        mic.backgroundColor = bg[@"color"] == [NSNull null] ? nil : bg[@"color"];
        objc_setAssociatedObject(mic, &kMicSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Màn micro đang hiện: thanh trạng thái tô cùng màu nền của màn (không có thanh điều hướng ở màn này)
    G6UIStatusBarSetOverride(active && mic.window ? G6UISkinBackdropColor() : nil);
}

static void (*o_micLayout)(id, SEL);
static void g6_micLayout(UIView *self, SEL _cmd) {
    o_micLayout(self, _cmd);
    @try {
        G6VMStyleMic(self);
    } @catch (NSException *e) {
        G6Log(@"ghi âm: lỗi khi dựng màn micro: %@", e);
    }
}

static void (*o_micMoved)(id, SEL);
static void g6_micMoved(UIView *self, SEL _cmd) {
    o_micMoved(self, _cmd);
    @try {
        G6VMStyleMic(self);
    } @catch (NSException *e) {
    }
}

// Bảng phát ở đáy danh sách: thanh tua là vùng vốn tối; hai nút màu (Chia sẻ xanh, Xoá đỏ — chữ trắng) nằm cạnh nó giữ đúng
// màu ở cả hai chế độ (không thì bộ lọc tối đổi chữ trắng thành đen)
static void G6VMStylePlaybackPanel(UIView *scrubber) {
    G6UISkinInvertRegion(scrubber);
    for (UIView *sibling in scrubber.superview.subviews) {
        if ([sibling isKindOfClass:[UIButton class]]) G6UISkinKeepColors(sibling, YES);
    }
}

static void (*o_scrubberMoved)(id, SEL);
static void g6_scrubberMoved(UIView *self, SEL _cmd) {
    o_scrubberMoved(self, _cmd);
    @try {
        if (self.window) G6VMStylePlaybackPanel(self);
    } @catch (NSException *e) {
    }
}

static void G6VMRefresh(UIView *view, Class micClass, Class scrubberClass, int depth) {
    if ([view isKindOfClass:micClass]) {
        G6VMStyleMic(view);
        return;
    }
    if (scrubberClass && [view isKindOfClass:scrubberClass]) {
        G6VMStylePlaybackPanel(view);
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6VMRefresh(sub, micClass, scrubberClass, depth - 1);
}

void G6UIAppVoiceMemosApply(BOOL active) {
    static BOOL installed;
    Class mic = objc_getClass("RCMicView");
    active = active && g6_device_is_phone() && mic;
    if (!installed && !active) return;
    if (!installed) {
        installed = YES;
        if (!G6Hook(mic, @selector(layoutSubviews), (IMP)g6_micLayout, (IMP *)&o_micLayout)) return;
        G6Hook(mic, @selector(didMoveToWindow), (IMP)g6_micMoved, (IMP *)&o_micMoved);
        G6HookNamed("UIScrubberControl", @selector(didMoveToWindow), (IMP)g6_scrubberMoved, (IMP *)&o_scrubberMoved);
        G6Log(@"ghi âm: vẽ lại màn micro + bảng điều khiển");
    }
    if (!o_micLayout) return;
    gActive = active;
    // App xin thanh trạng thái đen; nay theo sáng / tối của máy nên thanh trạng thái cũng phải theo kiểu phẳng
    G6UIStatusBarSetForceFlat(active);
    Class scrubber = objc_getClass("UIScrubberControl");
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6VMRefresh(window, mic, scrubber, 10);
}
