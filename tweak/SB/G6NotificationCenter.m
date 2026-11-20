// Trung tâm thông báo — iOS 6 → kính.
//
// iOS 6 trên iPad (tra trên máy 19/11/2026): cửa sổ SBBulletinWindow (mức 1049, chỉ có lúc bảng mở) › SBBulletinListView
//   UIView (-slidingView)                    bảng 480 điểm trượt từ mép trên xuống, cao theo số thông báo
//     UIView › UIImageView (-linenView)      ẢNH VẢI CHUNG; con của nó là lớp phủ tối (alpha theo -_linenGradientAlphaForHeight:)
//     SBLinenFadeContainer › SBBulletinTableView
//       SBBulletinHeaderView                 đầu mục từng app: mảnh vải + _translucentOverlay (dải bóng) + nhãn + nút xoá
//       SBBulletinListCell                   ô thông báo; chữ do SBBulletinCellContentView tự vẽ (màu trắng)
//       SBBulletinLinenSegmentView / FadeView các mảnh vải lấp chỗ trống
//     SBFakeStatusBarView, tay nắm, _linenRim (viền)
// Mọi mảnh vải (đầu mục, mảnh lấp) không có ảnh riêng: lớp vẽ của chúng mang THẲNG ảnh vải chung
// (+[SBBulletinListView linen], 480×1024 trên iPad — gắn một lần lúc tạo) với contentsRect chọn đúng phần của mình;
// -linenView hiện phần trên của chính ảnh đó. Vậy dựng một tấm kính CÙNG KHỔ rồi đổi ảnh trên -linenView và trên từng mảnh
// (cả mảnh mới tạo lúc cuộn) là cả bảng liền một tấm. Đã thử hai cách không được: thay riêng ảnh của -linenView (đầu mục và
// mảnh lấp vẫn là vải); móc +linen rồi gọi -adjustContents (các mảnh không đọc lại ảnh).
//
// Cách làm:
//   - bảng sắp vào cửa sổ (-willMoveToWindow:) → chụp màn hình một lần làm nền (bảng mở trên app nên không dùng hình nền);
//   - +linen và ảnh của -linenView → ảnh cùng khổ ảnh vải, phần trên (cao bằng bảng) là tấm kính (bề mặt `sheet` — kính đậm, luôn tối vì
//     chữ của máy màu trắng), dựng cho vị trí bảng lúc đã kéo xuống hết (-onscreenY) chứ không phải vị trí đang trượt; bảng
//     đổi cỡ thì dựng lại; bảng đóng thì trả ảnh vải (nhả ~2 MB);
//   - lớp phủ tối của vải: -_linenGradientAlphaForHeight: → 0; viền vải: ẩn; dải bóng của đầu mục: làm nhạt;
//   - chữ trong ô (dùng chung với thông báo trên màn khoá): năm hàm phông của SBBulletinCellContentView → Inter.
// Tắt thành phần lúc đang chạy: trả ảnh vải, lần mở sau về kiểu gốc.
#import "G6NotificationCenter.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

// Dải bóng của đầu mục còn giữ lại chừng này (để các mục vẫn tách nhau trên kính)
static const CGFloat kHeaderOverlayAlpha = 0.35;

static G6Backdrop *gBackdrop;
static __weak UIView *gListView;
static char kOrigKey;

static BOOL G6NCActive(void) {
    return G6Feature(@"notifications");
}

static id G6Ivar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    return iv ? object_getIvar(obj, iv) : nil;
}

static id G6Call(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    return [obj respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

// Tấm kính đang thay cho ảnh vải chung, và ảnh vải gốc — cả hai nil khi bảng đóng / thành phần tắt
static UIImage *gGlassLinen, *gClothLinen;

// Một mảnh vải (SBBulletinLinenSegmentView và lớp con): lớp vẽ của nó mang THẲNG ảnh vải chung, gắn lúc tạo, cùng một
// contentsRect chọn phần của mình. Đổi ảnh đó sang tấm kính cùng khổ (hoặc trả về ảnh vải) — contentsRect giữ nguyên.
static void G6NCSwapSegment(UIView *segment) {
    id contents = segment.layer.contents;
    if (!contents) return;
    id glass = (__bridge id)gGlassLinen.CGImage, cloth = (__bridge id)gClothLinen.CGImage;
    if (glass) {
        if (contents != glass) segment.layer.contents = glass;
    } else if (cloth && contents != cloth && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID() &&
               CGImageGetHeight((__bridge CGImageRef)contents) == CGImageGetHeight((__bridge CGImageRef)cloth)) {
        // Đang mang tấm kính cũ (cùng khổ ảnh vải) → trả ảnh vải
        segment.layer.contents = cloth;
    }
}

// Đổi ảnh trên mọi mảnh vải đang có trong cây view
static void G6NCRefreshSegments(UIView *view) {
    static Class segmentClass;
    if (!segmentClass) segmentClass = objc_getClass("SBBulletinLinenSegmentView");
    if (segmentClass && [view isKindOfClass:segmentClass]) G6NCSwapSegment(view);
    for (UIView *sub in view.subviews) G6NCRefreshSegments(sub);
}

// Đưa bảng về đúng trạng thái hiện tại. Gọi bao nhiêu lần cũng được.
static void G6NCUpdate(UIView *listView) {
    UIImageView *linen = G6Call(listView, @"linenView");
    UIView *sliding = G6Call(listView, @"slidingView");
    if (![linen isKindOfClass:[UIImageView class]] || ![sliding isKindOfClass:[UIView class]]) return;
    BOOL active = G6NCActive() && listView.window != nil;
    NSMutableDictionary *orig = objc_getAssociatedObject(linen, &kOrigKey);
    UIView *rim = G6Ivar(listView, "_linenRim");
    if (!active) {
        // Thành phần tắt, hoặc bảng vừa đóng (trả ảnh vải để nhả ~2 MB của tấm kính; lần mở sau dựng lại theo màn hình lúc đó)
        if (!orig[@"image"]) return;
        gGlassLinen = nil;
        gClothLinen = orig[@"image"];
        linen.image = orig[@"image"];
        for (UIView *sub in linen.subviews) sub.hidden = NO;
        if ([rim isKindOfClass:[UIView class]]) rim.hidden = NO;
        objc_setAssociatedObject(linen, &kOrigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        G6NCRefreshSegments(listView);
        gClothLinen = nil;
        return;
    }
    CGSize size = linen.bounds.size;
    if (size.width < 2 || size.height < 2) return;
    if (!orig) {
        orig = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(linen, &kOrigKey, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *key = [NSString stringWithFormat:@"%.0f|%.0f|%p|%d", size.width, size.height, gBackdrop,
                                               (int)[UIApplication sharedApplication].statusBarOrientation];
    UIImage *mine = orig[@"mine"];
    if (mine && linen.image == mine && [key isEqualToString:orig[@"key"]]) return;
    if (linen.image && linen.image != mine) orig[@"image"] = linen.image;
    UIImage *cloth = orig[@"image"];
    CGImageRef clothCG = cloth.CGImage;
    if (!clothCG) return;
    // Ảnh mới cùng khổ điểm ảnh với ảnh vải (480×1024 trên iPad): các mảnh vải tính phần của mình theo khổ đó. Chỉ phần trên
    // — cao bằng bảng — có kính; phần dưới không bao giờ được hiện.
    CGFloat scale = [UIScreen mainScreen].scale;
    uint32_t w = (uint32_t)CGImageGetWidth(clothCG), h = (uint32_t)CGImageGetHeight(clothCG);
    uint32_t gw = (uint32_t)lround(size.width * scale), gh = (uint32_t)lround(size.height * scale);
    if (!w || !h || w > 4096 || h > 4096 || gw > w || gh > h) return;
    NSMutableData *buf = [NSMutableData dataWithLength:(size_t)w * h * 4];
    // Chỗ bảng nằm khi đã kéo xuống hết, trong toạ độ của SBBulletinListView (đứng yên, phủ kín màn hình)
    SEL onscreenSel = NSSelectorFromString(@"onscreenY");
    CGFloat y = [listView respondsToSelector:onscreenSel] ? ((float (*)(id, SEL))objc_msgSend)(listView, onscreenSel) : 0;
    CGRect final = CGRectMake(sliding.frame.origin.x, y, size.width, size.height);
    double t0 = G6NowMs();
    int rc = G6GlassRenderForRect(@"sheet", listView, final, YES, gBackdrop, buf.mutableBytes, w * 4);
    if (rc != 0) {
        G6Log(@"trung tâm thông báo: lõi báo lỗi %d", rc);
        return;
    }
    UIImage *glass = G6ImageFromPixels(buf, w, h, cloth.scale >= 1 ? cloth.scale : 1);
    if (!glass) return;
    gGlassLinen = glass;
    gClothLinen = cloth;
    linen.image = glass;
    orig[@"mine"] = glass;
    orig[@"key"] = key;
    for (UIView *sub in linen.subviews) sub.hidden = YES;
    if ([rim isKindOfClass:[UIView class]]) rim.hidden = YES;
    G6NCRefreshSegments(listView);
    G6Log(@"trung tâm thông báo: kính %.0f×%.0f (%@ nền) %.1f ms", size.width, size.height, gBackdrop ? @"có" : @"KHÔNG", G6NowMs() - t0);
}

static void G6NCUpdateSafe(UIView *listView) {
    if (!listView) return;
    @try {
        G6NCUpdate(listView);
    } @catch (NSException *e) {
        G6Log(@"trung tâm thông báo: lỗi khi dựng: %@", e);
    }
}

// ---- Hàm thay thế ----

static void (*o_willMoveToWindow)(id, SEL, id);
static void g6_willMoveToWindow(UIView *self, SEL _cmd, UIWindow *window) {
    // Chụp màn hình khi bảng chưa hiện
    @try {
        if (window && G6NCActive()) gBackdrop = [G6Backdrop backdropWithScreen:YES];
    } @catch (NSException *e) {
    }
    o_willMoveToWindow(self, _cmd, window);
}

static void (*o_didMoveToWindow)(id, SEL);
static void g6_didMoveToWindow(UIView *self, SEL _cmd) {
    o_didMoveToWindow(self, _cmd);
    if (!self.window) {
        // Bảng vừa đóng
        G6NCUpdateSafe(self);
        return;
    }
    gListView = self;
    G6NCUpdateSafe(self);
    __weak UIView *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        G6NCUpdateSafe(weak);
    });
}

// Bảng đổi cỡ (thêm / bớt thông báo, xoay máy) → dựng lại tấm kính nếu cỡ đã khác
static void (*o_layoutSubviews)(id, SEL);
static void g6_layoutSubviews(UIView *self, SEL _cmd) {
    o_layoutSubviews(self, _cmd);
    G6NCUpdateSafe(self);
}

// Ảnh vải chung: các mảnh vải (đầu mục, ô, mảnh lấp) lấy phần của mình từ ảnh này mỗi lần -adjustContents
static id (*o_linen)(id, SEL);
static id g6_linen(id self, SEL _cmd) {
    id orig = o_linen(self, _cmd);
    return gGlassLinen ?: orig;
}

// Mảnh vải mới tạo (cuộn tới mục khác, thêm thông báo) hoặc vừa tính lại phần của mình: đổi ảnh ngay
static void (*o_segmentAdjust)(id, SEL);
static void g6_segmentAdjust(UIView *self, SEL _cmd) {
    o_segmentAdjust(self, _cmd);
    if (gGlassLinen) G6NCSwapSegment(self);
}

static void (*o_segmentMoved)(id, SEL);
static void g6_segmentMoved(UIView *self, SEL _cmd) {
    o_segmentMoved(self, _cmd);
    if (gGlassLinen) G6NCSwapSegment(self);
}

// Lớp phủ tối của vải (trên bảng và trên từng mảnh vải)
static float (*o_gradientAlpha)(id, SEL, float);
static float g6_gradientAlpha(id self, SEL _cmd, float height) {
    float orig = o_gradientAlpha(self, _cmd, height);
    return G6NCActive() ? 0 : orig;
}

// Đầu mục của từng app: làm nhạt dải bóng, nhãn phông Inter
static void (*o_headerLayout)(id, SEL);
static void g6_headerLayout(UIView *self, SEL _cmd) {
    o_headerLayout(self, _cmd);
    @try {
        if (!G6NCActive()) return;
        UIView *overlay = G6Ivar(self, "_translucentOverlay");
        if ([overlay isKindOfClass:[UIView class]]) overlay.alpha = kHeaderOverlayAlpha;
        // Lớp phủ tối riêng của mảnh vải đầu mục
        UIView *gradient = G6Ivar(self, "_gradientView");
        if ([gradient isKindOfClass:[UIView class]]) gradient.hidden = YES;
        if (!G6FontAvailable()) return;
        for (NSString *name in @[@"_sectionLabel", @"_sectionAltLabel"]) {
            UILabel *label = G6Ivar(self, name.UTF8String);
            if (![label isKindOfClass:[UILabel class]]) continue;
            G6FontWeight weight = [name isEqualToString:@"_sectionLabel"] ? G6FontSemiBold : G6FontRegular;
            UIFont *want = G6Font(weight, label.font.pointSize);
            if (want && ![label.font.fontName isEqualToString:want.fontName]) label.font = want;
            // SpringBoard đặt bề rộng nhãn theo phông gốc → với Inter tên app bị cắt «…»: nới cho vừa chữ, chừa chỗ nút xoá
            if (label.text.length && !label.hidden) {
                CGRect f = label.frame;
                CGFloat need = MIN(ceil([label.text sizeWithFont:label.font].width) + 8, self.bounds.size.width - f.origin.x - 36);
                if (need > f.size.width + 0.5) {
                    f.size.width = need;
                    label.frame = f;
                }
            }
        }
    } @catch (NSException *e) {
    }
}

// Phông chữ trong ô thông báo (Trung tâm thông báo và danh sách trên màn khoá dùng chung lớp này)
#define G6_NC_FONT_HOOK(name, weight)                                     \
    static id (*o_font_##name)(id, SEL);                                  \
    static id g6_font_##name(id self, SEL _cmd) {                         \
        UIFont *orig = o_font_##name(self, _cmd);                         \
        if (![orig isKindOfClass:[UIFont class]] || !G6NCActive() || !G6FontAvailable()) return orig; \
        return G6Font(weight, orig.pointSize) ?: orig;                    \
    }
G6_NC_FONT_HOOK(title, G6FontSemiBold)
G6_NC_FONT_HOOK(subtitle, G6FontMedium)
G6_NC_FONT_HOOK(message, G6FontRegular)
G6_NC_FONT_HOOK(date, G6FontRegular)
G6_NC_FONT_HOOK(attachment, G6FontRegular)

void G6NotificationCenterInstall(void) {
    Class list = objc_getClass("SBBulletinListView");
    if (!list || ![list instancesRespondToSelector:NSSelectorFromString(@"linenView")]) {
        G6Log(@"trung tâm thông báo: thiếu SBBulletinListView / -linenView — bỏ qua");
        return;
    }
    if (!G6Hook(list, @selector(didMoveToWindow), (IMP)g6_didMoveToWindow, (IMP *)&o_didMoveToWindow)) return;
    G6Hook(list, @selector(willMoveToWindow:), (IMP)g6_willMoveToWindow, (IMP *)&o_willMoveToWindow);
    G6Hook(list, @selector(layoutSubviews), (IMP)g6_layoutSubviews, (IMP *)&o_layoutSubviews);
    G6Hook(list, NSSelectorFromString(@"_linenGradientAlphaForHeight:"), (IMP)g6_gradientAlpha, (IMP *)&o_gradientAlpha);
    G6Hook(object_getClass(list), NSSelectorFromString(@"linen"), (IMP)g6_linen, (IMP *)&o_linen);
    G6HookNamed("SBBulletinHeaderView", @selector(layoutSubviews), (IMP)g6_headerLayout, (IMP *)&o_headerLayout);
    G6HookNamed("SBBulletinLinenSegmentView", NSSelectorFromString(@"adjustContents"), (IMP)g6_segmentAdjust, (IMP *)&o_segmentAdjust);
    G6HookNamed("SBBulletinLinenSegmentView", @selector(didMoveToWindow), (IMP)g6_segmentMoved, (IMP *)&o_segmentMoved);
    Class content = objc_getClass("SBBulletinCellContentView");
    if (content) {
        G6Hook(content, NSSelectorFromString(@"_titleFont"), (IMP)g6_font_title, (IMP *)&o_font_title);
        G6Hook(content, NSSelectorFromString(@"_subtitleFont"), (IMP)g6_font_subtitle, (IMP *)&o_font_subtitle);
        G6Hook(content, NSSelectorFromString(@"_messageFont"), (IMP)g6_font_message, (IMP *)&o_font_message);
        G6Hook(content, NSSelectorFromString(@"_dateFont"), (IMP)g6_font_date, (IMP *)&o_font_date);
        G6Hook(content, NSSelectorFromString(@"_attachmentFont"), (IMP)g6_font_attachment, (IMP *)&o_font_attachment);
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:G6ConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
                                                      G6NCUpdateSafe(gListView);
                                                  }];
}
