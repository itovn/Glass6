// Dock kính — iOS 6 → kiểu iPadOS 26.
//
// SpringBoard iOS 6 (iPad), tra trên máy 19/11/2026:
//   SBIconContentView
//     UIView (dockContainerView — -[SBIconController dockContainerView])
//       SBDockIconListView (-[SBIconController dock]) — ảnh kệ dock là layer.contents của chính view này, lấy từ
//                           +[SBDockIconListView backgroundImageForOrientation:]
//         SBIconView … (mỗi biểu tượng: ảnh, bóng, bóng phản chiếu, nhãn)
//       SBIconListPageControl
//
// Cách làm (mọi hàm thay thế đều gọi lại hàm gốc; thành phần tắt thì trả đúng kết quả gốc):
//   - backgroundImageForOrientation: → ảnh trong suốt cùng cỡ (SpringBoard lấy khung dock từ cỡ ảnh này), và xoá
//     layer.contents → mất kệ dock;
//   - sideIconInset → lề lớn hơn → SpringBoard tự dồn biểu tượng vào giữa (bố cục và chỗ thả biểu tượng lúc sắp xếp
//     đều tính từ lề này nên vẫn khớp nhau);
//   - showsReflection → NO → mất bóng phản chiếu; nhãn của biểu tượng trong dock ẩn đi;
//   - thêm hai UIImageView (bóng đổ, tấm kính) vào dockContainerView, nằm dưới SBDockIconListView → dock trượt đi đâu
//     (mở app, xoay máy) kính theo đó.
// Nền của tấm kính = hình nền đã làm mờ dùng chung (G6Wallpaper); dựng lại khi đổi hình nền, xoay máy, đổi cấu hình.
#import "G6Dock.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Wallpaper.h"

// Số đo theo mẫu máy (điểm):
//   gap    khoảng hở giữa hai biểu tượng trong dock
//   padX/Y tấm kính rộng / cao hơn dãy biểu tượng chừng này mỗi phía
//   image  phần ảnh của một SBIconView, bên dưới là chỗ của nhãn (iPad: view 74×93, ảnh tới 76; iPhone: view 59×74, ảnh tới 58)
// iPhone 5 (đo 19/11/2026: dock 320×89, bốn biểu tượng 59 điểm ở x = 16 / 92 / 169 / 245): kiểu iOS 26 — viên kính nổi cách
// mép màn hình ~10 điểm mỗi bên và ~9 điểm phía dưới → dồn biểu tượng vào còn hở 12, kính rộng hơn dãy biểu tượng 14.
//   drop   hạ cả dãy biểu tượng xuống chừng này điểm (iPhone: lấy chỗ cho viên «Tìm kiếm» nằm giữa hàng biểu tượng cuối và
//          dock mà không chạm vào đâu — xem G6SearchPill.m)
typedef struct {
    CGFloat gap, padX, padY, image, drop;
} G6DockMetrics;

static G6DockMetrics G6DockMeasure(void) {
    if (g6_device_is_phone()) return (G6DockMetrics){12, 14, 9, 58, 6};
    return (G6DockMetrics){26, 18, 12, 76, 0};
}
#define kGap (G6DockMeasure().gap)
#define kPadX (G6DockMeasure().padX)
#define kPadY (G6DockMeasure().padY)
#define kIconImageHeight (G6DockMeasure().image)

static BOOL gActive;
static BOOL gUpdatePending;
static UIImageView *gGlass, *gShadow;
// Trạng thái của lần dựng gần nhất — không đổi thì không dựng lại
static CGRect gDrawnFrame;
static NSUInteger gDrawnGeneration;
static int gDrawnOrientation = -1;
static BOOL gDrawnDark;
// Lần dựng gần nhất có nền thật không (lúc SpringBoard vừa lên, hình nền chưa vào cửa sổ → tạm dựng kính giả)
static BOOL gDrawnWithBackdrop;

static Class gIconViewClass;

static id G6IconController(void) {
    Class cls = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, shared);
}

static UIView *G6ViewFrom(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    id v = ((id (*)(id, SEL))objc_msgSend)(obj, sel);
    return [v isKindOfClass:[UIView class]] ? v : nil;
}

static UIView *G6DockView(void) {
    return G6ViewFrom(G6IconController(), @"dock");
}

static UIView *G6DockContainer(void) {
    return G6ViewFrom(G6IconController(), @"dockContainerView");
}

static int G6Orientation(void) {
    return (int)[UIApplication sharedApplication].statusBarOrientation;
}

static void G6DockUpdate(void);

// Gom nhiều lần báo đổi (bố cục lại, xoay máy…) thành một lần dựng ở vòng lặp kế
static void G6DockScheduleUpdate(void) {
    if (gUpdatePending) return;
    gUpdatePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gUpdatePending = NO;
        @try {
            G6DockUpdate();
        } @catch (NSException *e) {
            G6Log(@"dock: lỗi khi dựng: %@", e);
        }
    });
}

// Khung của một biểu tượng tính từ tâm + bounds (lúc biểu tượng rung trong chế độ sắp xếp, frame không dùng được)
static CGRect G6SteadyFrame(UIView *v) {
    CGSize s = v.bounds.size;
    return CGRectMake(v.center.x - s.width / 2, v.center.y - s.height / 2, s.width, s.height);
}

static void G6Perform(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if ([obj respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(obj, sel);
}

static void G6DockRemoveGlass(void) {
    [gGlass removeFromSuperview];
    [gShadow removeFromSuperview];
    gGlass = gShadow = nil;
    gDrawnFrame = CGRectZero;
}

// Dựng / cập nhật dock theo trạng thái hiện tại. Gọi bao nhiêu lần cũng được — không gì đổi thì không làm gì.
static void G6DockUpdate(void) {
    UIView *dock = G6DockView(), *container = G6DockContainer();
    if (!dock || !container) return;
    BOOL active = G6Feature(@"dock");
    if (active != gActive) {
        gActive = active;
        // Lề dock đổi → bố cục lại; bóng phản chiếu và nhãn theo trạng thái mới
        G6Perform(dock, @"setIconsNeedLayout");
        G6Perform(dock, @"layoutIconsNow");
        if (!active) {
            // Trả lại kệ dock của iOS 6
            G6DockRemoveGlass();
            SEL bg = NSSelectorFromString(@"backgroundImageForOrientation:");
            if ([[dock class] respondsToSelector:bg]) {
                UIImage *img = ((id (*)(id, SEL, int))objc_msgSend)([dock class], bg, G6Orientation());
                dock.layer.contents = (__bridge id)img.CGImage;
            }
            for (UIView *v in dock.subviews) {
                if (![v isKindOfClass:gIconViewClass]) continue;
                if ([v respondsToSelector:@selector(setLabelHidden:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(v, @selector(setLabelHidden:), NO);
                G6Perform(v, @"updateReflection");
            }
            G6Log(@"dock: đã trả về dock gốc");
            return;
        }
    }
    if (!active) return;

    dock.layer.contents = nil;
    CGRect icons = CGRectNull;
    for (UIView *v in dock.subviews) {
        if (![v isKindOfClass:gIconViewClass] || v.hidden) continue;
        if ([v respondsToSelector:@selector(setLabelHidden:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(v, @selector(setLabelHidden:), YES);
        G6Perform(v, @"updateReflection");
        CGRect f = G6SteadyFrame(v);
        f.size.height = MIN(f.size.height, kIconImageHeight);
        icons = CGRectUnion(icons, f);
    }
    if (CGRectIsNull(icons)) {
        // Dock không có biểu tượng nào
        gGlass.hidden = gShadow.hidden = YES;
        return;
    }
    CGRect frame = CGRectIntegral([container convertRect:CGRectInset(icons, -kPadX, -kPadY) fromView:dock]);
    if (!gGlass || gGlass.superview != container) {
        G6DockRemoveGlass();
        gShadow = [[UIImageView alloc] initWithFrame:CGRectZero];
        gGlass = [[UIImageView alloc] initWithFrame:CGRectZero];
        gShadow.userInteractionEnabled = gGlass.userInteractionEnabled = NO;
        [container insertSubview:gShadow atIndex:0];
        [container insertSubview:gGlass aboveSubview:gShadow];
    }
    gGlass.hidden = gShadow.hidden = NO;

    BOOL dark = G6IsDark();
    int orientation = G6Orientation();
    G6Backdrop *backdrop = G6WallpaperBackdrop();
    if (gGlass.image && CGRectEqualToRect(frame, gDrawnFrame) && dark == gDrawnDark && G6WallpaperGeneration() == gDrawnGeneration &&
        orientation == gDrawnOrientation && (backdrop != nil) == gDrawnWithBackdrop) {
        return;
    }
    double t0 = G6NowMs();
    gGlass.frame = frame;
    UIImage *glass = G6GlassImageForView(@"dock", gGlass, dark, backdrop);
    if (!glass) {
        G6Log(@"dock: không dựng được kính");
        return;
    }
    gGlass.image = glass;
    CGFloat margin = 0;
    gShadow.image = G6ShadowImage(@"dock", frame.size, dark, &margin);
    gShadow.frame = CGRectInset(frame, -margin, -margin);
    gDrawnFrame = frame;
    gDrawnDark = dark;
    gDrawnGeneration = G6WallpaperGeneration();
    gDrawnOrientation = orientation;
    gDrawnWithBackdrop = backdrop != nil;
    G6Log(@"dock: kính %.0f×%.0f (%@, %@ nền) %.1f ms", frame.size.width, frame.size.height, dark ? @"tối" : @"sáng",
          backdrop ? @"có" : @"KHÔNG", G6NowMs() - t0);
}

// ---- Hàm thay thế ----

// Ảnh trong suốt cỡ `size` (chỉ có kênh alpha, 1 byte / điểm ảnh), nhớ theo cỡ.
static UIImage *G6ClearImage(CGSize size, CGFloat scale) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%.0fx%.0f@%.0f", size.width, size.height, scale];
    UIImage *img = cache[key];
    if (img) return img;
    size_t w = (size_t)lround(size.width * scale), h = (size_t)lround(size.height * scale);
    if (!w || !h) return nil;
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!ctx) return nil;
    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!cg) return nil;
    img = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    if (img) cache[key] = img;
    return img;
}

// Ảnh kệ dock. KHÔNG trả nil: SpringBoard lấy khung của dock từ cỡ ảnh này (-_updateForOrientation:duration:) — trả nil
// thì xoay ngang → dọc dock vẫn rộng 1024 và biểu tượng xếp lệch ra ngoài màn hình (đã gặp 19/11/2026). Trả ảnh trong
// suốt cùng cỡ.
static id (*o_backgroundImage)(id, SEL, int);
static id g6_backgroundImage(id self, SEL _cmd, int orientation) {
    UIImage *orig = o_backgroundImage(self, _cmd, orientation);
    if (!gActive || ![orig isKindOfClass:[UIImage class]]) return orig;
    return G6ClearImage(orig.size, orig.scale) ?: orig;
}

// Bề rộng dock theo hướng mà dock đang được xếp (biến _orientation của SBIconListView). Không dùng bounds: lúc xoay máy
// SpringBoard xếp lại biểu tượng TRƯỚC khi đổi khung của dock — tính theo bounds thì ra lề của hướng cũ, biểu tượng lệch
// ra ngoài màn hình (đã gặp khi xoay ngang → dọc, 19/11/2026).
static CGFloat G6DockWidth(UIView *dock) {
    int orientation = 0;
    @try {
        orientation = [[dock valueForKey:@"orientation"] intValue];
    } @catch (NSException *e) {
    }
    if (orientation < 1 || orientation > 4) return dock.bounds.size.width;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    return UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)orientation) ? MAX(screen.width, screen.height)
                                                                                 : MIN(screen.width, screen.height);
}

static float (*o_sideIconInset)(id, SEL);
static float g6_sideIconInset(UIView *self, SEL _cmd) {
    float orig = o_sideIconInset(self, _cmd);
    if (!gActive) return orig;
    // Số ô SpringBoard dùng để chia khoảng cách (iPad: 6)
    NSUInteger n = 6;
    SEL count = NSSelectorFromString(@"iconsInRowForSpacingCalculation");
    if ([self respondsToSelector:count]) n = ((unsigned (*)(id, SEL))objc_msgSend)(self, count);
    if (n < 2) return orig;
    CGFloat iconW = 74;
    for (UIView *v in self.subviews) {
        if ([v isKindOfClass:gIconViewClass]) {
            iconW = v.bounds.size.width;
            break;
        }
    }
    // SpringBoard chia đều phần còn lại giữa các ô: lề = (rộng − n·biểu tượng − (n−1)·hở) / 2 thì hở đúng bằng kGap
    CGFloat inset = floor((G6DockWidth(self) - n * iconW - (n - 1) * kGap) / 2);
    return inset > orig ? (float)inset : orig;
}

// Lề trên của dãy biểu tượng trong dock: cộng thêm `drop` để hạ dãy biểu tượng xuống
static float (*o_topIconInset)(id, SEL);
static float g6_topIconInset(id self, SEL _cmd) {
    float orig = o_topIconInset(self, _cmd);
    return gActive ? orig + (float)G6DockMeasure().drop : orig;
}

static BOOL (*o_showsReflection)(id, SEL);
static BOOL g6_showsReflection(id self, SEL _cmd) {
    return gActive ? NO : o_showsReflection(self, _cmd);
}

static void (*o_layoutIconsNow)(id, SEL);
static void g6_layoutIconsNow(id self, SEL _cmd) {
    o_layoutIconsNow(self, _cmd);
    G6DockScheduleUpdate();
}

static float (*o_layoutIconsIfNeeded)(id, SEL, float, BOOL);
static float g6_layoutIconsIfNeeded(id self, SEL _cmd, float duration, BOOL domino) {
    float r = o_layoutIconsIfNeeded(self, _cmd, duration, domino);
    G6DockScheduleUpdate();
    return r;
}

static void (*o_updateForOrientation)(id, SEL, int, double);
static void g6_updateForOrientation(UIView *self, SEL _cmd, int orientation, double duration) {
    o_updateForOrientation(self, _cmd, orientation, duration);
    if (gActive) {
        self.layer.contents = nil;
        // Xếp lại theo hướng mới ngay trong khối chuyển động xoay (phòng khi lần xếp của SpringBoard dùng số đo cũ)
        G6Perform(self, @"setIconsNeedLayout");
        G6Perform(self, @"layoutIconsNow");
    }
    G6DockScheduleUpdate();
}

void G6DockInstall(void) {
    G6WallpaperInstall();
    gIconViewClass = objc_getClass("SBIconView");
    Class dock = objc_getClass("SBDockIconListView");
    if (!gIconViewClass || !dock) {
        G6Log(@"dock: thiếu lớp SBIconView / SBDockIconListView — bỏ qua");
        return;
    }
    // Hàm của lớp nằm trên siêu lớp (metaclass)
    BOOL bg = G6Hook(object_getClass(dock), NSSelectorFromString(@"backgroundImageForOrientation:"), (IMP)g6_backgroundImage,
                     (IMP *)&o_backgroundImage);
    BOOL inset = G6Hook(dock, NSSelectorFromString(@"sideIconInset"), (IMP)g6_sideIconInset, (IMP *)&o_sideIconInset);
    G6Hook(gIconViewClass, NSSelectorFromString(@"showsReflection"), (IMP)g6_showsReflection, (IMP *)&o_showsReflection);
    if (G6DockMeasure().drop > 0 && [dock instancesRespondToSelector:NSSelectorFromString(@"topIconInset")]) {
        G6Hook(dock, NSSelectorFromString(@"topIconInset"), (IMP)g6_topIconInset, (IMP *)&o_topIconInset);
    }
    G6Hook(dock, NSSelectorFromString(@"layoutIconsNow"), (IMP)g6_layoutIconsNow, (IMP *)&o_layoutIconsNow);
    G6Hook(dock, NSSelectorFromString(@"layoutIconsIfNeeded:domino:"), (IMP)g6_layoutIconsIfNeeded, (IMP *)&o_layoutIconsIfNeeded);
    G6Hook(dock, NSSelectorFromString(@"_updateForOrientation:duration:"), (IMP)g6_updateForOrientation,
           (IMP *)&o_updateForOrientation);
    if (!bg || !inset) G6Log(@"dock: thiếu hàm nền / lề — dock có thể chưa đúng hình");

    // Đổi cấu hình (bật / tắt, sáng / tối, thông số kính) hoặc nền mờ đã cũ → dựng lại
    for (NSString *name in @[G6ConfigDidChangeNotification, G6WallpaperDidChangeNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6DockScheduleUpdate();
                                                      }];
    }
    G6DockScheduleUpdate();
}
