// Bàn phím tối ở chế độ tối.
//
// iPad iOS 6 chỉ có một bàn phím sáng (kiểu «cảnh báo» tối màu chỉ có trên iPhone). Phím của iOS 6 do UIKit tự vẽ thành ảnh
// từ dữ liệu bố cục — muốn vẽ lại từng phím là viết lại cả bộ vẽ bàn phím. Cách làm ở đây gọn hơn nhiều: gắn MỘT bộ lọc màu
// của CoreAnimation (CAFilter loại «colorMatrix» — lớp riêng, có sẵn trên iOS 6; đã thử trên máy 19/11/2026 bằng lệnh thử
// `cafilter`: trình dựng hình có áp bộ lọc màu lên lớp vẽ) vào lớp vẽ của bàn phím. Ma trận «đảo sáng tối, giữ sắc màu»:
//
//     màu mới = 1 + màu − (2/3)·(đỏ + lục + lam)        (đảo màu rồi xoay sắc màu 180°, gộp thành một ma trận)
//
// trắng ↔ đen, xám sáng ↔ xám tối, còn phím xanh vẫn xanh. Hệ số tự do được nhân với độ đục (cột alpha) chứ không cộng thẳng:
// điểm ảnh trong suốt (khe giữa hai nửa bàn phím tách đôi) vẫn trong suốt.
// Đảo đơn thuần thì viền bàn phím (xám vừa của iOS 6) vẫn là xám vừa — chưa ra «tối». Thêm một bước tăng tương phản
// (kết quả × 1,4 − 0,45): chữ trên phím giữ gần trắng (0,95), viền xuống cỡ 0,25, mặt phím về đen.
//
// Gắn vào UIKeyboardLayoutStar (view bố cục phím: nền + các phím) chứ không vào UIPeripheralHostView: view sau chứa cả thanh
// phụ kiện của app nằm trên bàn phím — thứ đó không được đảo màu.
// Thiếu CAFilter / UIKeyboardLayoutStar (bản iOS khác) thì không làm gì.
#import "G6Keyboard.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

// Cùng bố cục với CAColorMatrix của QuartzCore (bốn hàng đỏ / lục / lam / alpha, mỗi hàng: hệ số đỏ, lục, lam, alpha, hằng số)
typedef struct {
    float m11, m12, m13, m14, m15;
    float m21, m22, m23, m24, m25;
    float m31, m32, m33, m34, m35;
    float m41, m42, m43, m44, m45;
} G6ColorMatrix;

static BOOL gDark;
static NSHashTable *gLayouts;  // các view bố cục phím còn sống (giữ yếu)
static char kFilterKey;

static id G6KeyboardFilter(void) {
    static id filter;
    if (filter) return filter;
    Class cls = objc_getClass("CAFilter");
    SEL make = NSSelectorFromString(@"filterWithType:");
    if (![cls respondsToSelector:make]) return nil;
    id f = ((id (*)(id, SEL, id))objc_msgSend)(cls, make, @"colorMatrix");
    if (!f) return nil;
    // (đảo sáng tối giữ sắc màu) rồi (× kContrast + kOffset); hằng số đi vào cột alpha
    const float kContrast = 1.4f, kOffset = -0.45f;
    const float a = kContrast / 3, b = -2 * kContrast / 3, c = kContrast + kOffset;
    G6ColorMatrix m = {
        a, b, b, c, 0,
        b, a, b, c, 0,
        b, b, a, c, 0,
        0, 0, 0, 1, 0,
    };
    @try {
        [f setValue:[NSValue valueWithBytes:&m objCType:"{CAColorMatrix=ffffffffffffffffffff}"] forKey:@"inputColorMatrix"];
    } @catch (NSException *e) {
        G6Log(@"bàn phím: không đặt được ma trận màu: %@", e);
        return nil;
    }
    filter = f;
    return filter;
}

static void G6KeyboardStyle(UIView *layout) {
    BOOL has = objc_getAssociatedObject(layout, &kFilterKey) != nil;
    if (gDark && !has) {
        id filter = G6KeyboardFilter();
        if (!filter) return;
        layout.layer.filters = @[filter];
        objc_setAssociatedObject(layout, &kFilterKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!gDark && has) {
        layout.layer.filters = nil;
        objc_setAssociatedObject(layout, &kFilterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*orig_layoutDidMove)(UIView *, SEL);
static void repl_layoutDidMove(UIView *self, SEL _cmd) {
    orig_layoutDidMove(self, _cmd);
    @try {
        if (!gLayouts) gLayouts = [NSHashTable weakObjectsHashTable];
        [gLayouts addObject:self];
        G6KeyboardStyle(self);
    } @catch (NSException *e) {
    }
}

void G6KeyboardApply(void) {
    BOOL dark = G6Feature(@"keyboard") && G6IsDark();
    if (dark && !orig_layoutDidMove) {
        Class layout = objc_getClass("UIKeyboardLayoutStar");
        if (!layout || !objc_getClass("CAFilter")) return;
        if (!G6Hook(layout, @selector(didMoveToWindow), (IMP)repl_layoutDidMove, (IMP *)&orig_layoutDidMove)) return;
        G6Log(@"bàn phím: tối ở chế độ tối");
    }
    if (!orig_layoutDidMove || dark == gDark) return;
    gDark = dark;
    for (UIView *layout in [gLayouts allObjects]) G6KeyboardStyle(layout);
}
