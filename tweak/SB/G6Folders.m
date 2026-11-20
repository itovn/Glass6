// Thư mục mở — iOS 6 → kính.
//
// SpringBoard iOS 6 mở thư mục bằng cách xẻ màn hình làm hai nửa trượt ra (tra trên máy 19/11/2026):
//   SBIconContentView
//     SBFolderSlidingView (nửa trên — -[SBIconController _upperSlidingView])
//       UIView
//         UIView (bản sao hình nền, chỉ phủ phần PHÍA TRÊN thư mục)
//         SBLinenNotchView                 mũi nhọn bằng vải chỉ lên biểu tượng thư mục
//         SBFolderView (_folderView)       dải thư mục, suốt bề rộng màn hình
//           SBLinenView (_backgroundView)  hai ảnh vải
//           SBFolderTitleLabel (_label), SBFolderIconListView
//           UIImageView × 6                bóng trong ở bốn mép (_shadows)
//       SBSlidingViewHighlight, SBFolderNotchHighlightView   nét sáng ở mép trên
//     SBWallpaperNotchView                 mũi nhọn bằng hình nền (thư mục mở lên trên)
//     SBFolderSlidingView (nửa dưới)
// Phía sau SBFolderView không có gì → đặt một tấm kính có nền là hình nền đã mờ đúng chỗ đó: trông như dải kính mờ phủ
// trên hình nền.
//
// Cách làm: không đổi cách SpringBoard xẻ / trượt, chỉ đổi vật liệu —
//   - tấm kính (UIImageView) nằm TRONG SBLinenView nên theo mọi thay đổi khung / độ mờ mà SpringBoard áp lên nền thư mục;
//     hai ảnh vải ẩn đi;
//   - bóng trong, mũi nhọn, nét sáng: ẩn;
//   - tên thư mục: phông Inter.
// Quầy báo (SBNewsstandFolderView, kệ gỗ) chưa đụng. Tắt thành phần lúc đang chạy: trả lại y nguyên.
#import "G6Folders.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Font.h"
#import "G6GlassFill.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Wallpaper.h"

static Class gFolderViewClass;
static char kStyledKey, kFontKey;

static id G6Ivar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    return iv ? object_getIvar(obj, iv) : nil;
}

static id G6IconController(void) {
    Class cls = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, shared);
}

// Ẩn / hiện các view con trực tiếp có tên lớp nằm trong `names`
static void G6SetHidden(UIView *parent, NSArray *names, BOOL hidden) {
    for (UIView *sub in parent.subviews) {
        if ([names containsObject:NSStringFromClass([sub class])]) sub.hidden = hidden;
    }
}

// Dựng / cập nhật / gỡ lớp kính của một SBFolderView theo trạng thái hiện tại. Gọi bao nhiêu lần cũng được.
static void G6FolderUpdate(UIView *fv) {
    // Chỉ thư mục thường; Quầy báo là lớp con có kệ gỗ riêng
    if (!fv || [fv class] != gFolderViewClass) return;
    UIView *bg = G6Ivar(fv, "_backgroundView");
    if (![bg isKindOfClass:[UIView class]]) return;
    BOOL active = G6Feature(@"folders");
    BOOL styled = objc_getAssociatedObject(fv, &kStyledKey) != nil;
    if (!active && !styled) return;

    // Bóng trong (các UIImageView con trực tiếp của SBFolderView), mũi nhọn và nét sáng quanh dải
    for (UIView *sub in fv.subviews) {
        if ([sub class] == [UIImageView class]) sub.hidden = active;
    }
    NSArray *trim = @[@"SBLinenNotchView", @"SBFolderNotchHighlightView", @"SBSlidingViewHighlight", @"SBWallpaperNotchView"];
    for (UIView *up = fv.superview; up && ![up isKindOfClass:objc_getClass("SBIconContentView")]; up = up.superview) {
        G6SetHidden(up, trim, active);
        G6SetHidden(up.superview, trim, active);
    }

    UILabel *label = G6Ivar(fv, "_label");
    if ([label isKindOfClass:[UILabel class]]) {
        UIFont *orig = objc_getAssociatedObject(label, &kFontKey);
        if (active && !orig && G6FontAvailable()) {
            objc_setAssociatedObject(label, &kFontKey, label.font, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            label.font = G6Font(G6FontSemiBold, label.font.pointSize);
        } else if (!active && orig) {
            label.font = orig;
            objc_setAssociatedObject(label, &kFontKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // Inter rộng hơn Helvetica mà SpringBoard đo khung nhãn theo phông gốc → tên bị cắt giữa chừng («Tiệ…ch»). Nới khung
        // cho vừa chữ, không quá mép phải của dải.
        if (active && label.text.length) {
            CGRect f = label.frame;
            CGFloat need = ceil([label.text sizeWithFont:label.font].width) + 2;
            CGFloat room = fv.bounds.size.width - f.origin.x - 12;
            if (need > f.size.width && room > f.size.width) {
                f.size.width = MIN(need, room);
                label.frame = f;
            }
        }
    }

    // Vải → kính (nằm trong SBLinenView)
    G6GlassFill(bg, active, @"bar");
    objc_setAssociatedObject(fv, &kStyledKey, active ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!active) G6Log(@"thư mục: đã trả về nền gốc");
}

static void G6FolderUpdateSafe(UIView *fv) {
    @try {
        G6FolderUpdate(fv);
    } @catch (NSException *e) {
        G6Log(@"thư mục: lỗi khi dựng: %@", e);
    }
}

// Thư mục đang mở (nếu có)
static UIView *G6OpenFolderView(void) {
    id v = G6Ivar(G6IconController(), "_folderView");
    return [v isKindOfClass:[UIView class]] ? v : nil;
}

// ---- Hàm thay thế ----

static void (*o_placeBackground)(id, SEL);
static void g6_placeBackground(UIView *self, SEL _cmd) {
    o_placeBackground(self, _cmd);
    G6FolderUpdateSafe(self);
}

// Vào cửa sổ: giờ mới biết dải nằm ở đâu trên màn hình → dựng kính ngay (kẻo khung hình đầu hiện dải trống), và dựng lại ở
// vòng lặp kế nếu SpringBoard còn đặt lại khung (không gì đổi thì lần hai không tốn gì)
static void (*o_didMoveToWindow)(id, SEL);
static void g6_didMoveToWindow(UIView *self, SEL _cmd) {
    o_didMoveToWindow(self, _cmd);
    if (!self.window) return;
    G6FolderUpdateSafe(self);
    __weak UIView *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        G6FolderUpdateSafe(weak);
    });
}

// SpringBoard đặt lại mũi nhọn và nét sáng (hiện / ẩn theo hướng mở) → ẩn lại
static void (*o_placeNotch)(id, SEL);
static void g6_placeNotch(UIView *self, SEL _cmd) {
    o_placeNotch(self, _cmd);
    G6FolderUpdateSafe(G6OpenFolderView());
}

void G6FoldersInstall(void) {
    gFolderViewClass = objc_getClass("SBFolderView");
    if (!gFolderViewClass || !class_getInstanceVariable(gFolderViewClass, "_backgroundView")) {
        G6Log(@"thư mục: thiếu SBFolderView / _backgroundView — bỏ qua");
        return;
    }
    G6WallpaperInstall();
    if (!G6Hook(gFolderViewClass, NSSelectorFromString(@"_placeBackgroundView"), (IMP)g6_placeBackground, (IMP *)&o_placeBackground)) return;
    G6Hook(gFolderViewClass, @selector(didMoveToWindow), (IMP)g6_didMoveToWindow, (IMP *)&o_didMoveToWindow);
    G6HookNamed("SBFolderSlidingView", NSSelectorFromString(@"_placeNotchAndHighlights"), (IMP)g6_placeNotch, (IMP *)&o_placeNotch);
    for (NSString *name in @[G6ConfigDidChangeNotification, G6WallpaperDidChangeNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6FolderUpdateSafe(G6OpenFolderView());
                                                      }];
    }
}
