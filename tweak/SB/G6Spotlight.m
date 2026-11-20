// Trang Tìm kiếm (Spotlight) của màn hình chính: ô tìm kiếm → viên kính.
//
// iOS 6.1.3 trên iPad (tra 19/11/2026 bằng `goto -1` + `dump`): trang Tìm kiếm là một trang của khung cuộn biểu tượng
//   SBIconScrollView
//     SBSearchView 1024×589                 nằm ở gốc nội dung của khung cuộn (trang biểu tượng đầu ở x = 1024)
//       UISearchBar 344×44                  nền (UISearchBarBackground) vốn đã ẩn
//         UISearchBarTextField 334×31
//           UITextFieldBorderView           viên trắng bóng
//           UITextFieldLabel                chữ gợi ý «Tìm kiếm iPad»
//           UIImageView 15×15               hình kính lúp (leftView)
//       UITableView 748×545                 bảng kết quả (alpha 0 lúc chưa gõ gì)
// Lúc ở trang này SpringBoard làm tối hình nền; ô tìm kiếm trắng bóng giống hệt nhau ở chế độ sáng lẫn tối.
//
// Cách làm (không đổi bố cục, không đổi cách tìm):
//   - nền ô = tấm kính «capsule» (cùng bề mặt với dải hiệu suất), đặt qua -[UISearchBar setSearchFieldBackgroundImage:forState:]
//     — hàm công khai, trả lại bằng nil. Tấm kính dựng theo vị trí NGHỈ của ô (lúc trang Tìm kiếm hiện trọn) tính trong view
//     cha đứng yên của khung cuộn, chứ không theo chỗ ô đang nằm lúc dựng (trang còn ở ngoài màn hình): lật tới nơi là khớp
//     nền; trong lúc đang lật thì nền của kính đi theo ô — lệch thoáng qua, chấp nhận;
//   - chữ gõ, chữ gợi ý, kính lúp: màu theo sáng / tối; phông Inter;
//   - dựng lại khi: khung nghỉ đổi (xoay máy), đổi sáng ↔ tối, đổi hình nền.
// Bảng kết quả chưa đụng tới: muốn soi phải gõ chữ, mà kết quả là dữ liệu riêng của người dùng (danh bạ, tin nhắn…).
#import "G6Spotlight.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Wallpaper.h"

static __weak UIView *gSearchView;
static NSString *gDrawnKey;  // khung nghỉ + chế độ + đời hình nền của tấm kính đang đặt; nil = đang là kiểu gốc
static char kOriginalKey, kTintModeKey;

static UIView *G6SpotlightFind(UIView *root, Class cls, int depth) {
    if (!root || !cls) return nil;
    if ([root isKindOfClass:cls]) return root;
    if (depth <= 0) return nil;
    for (UIView *sub in root.subviews) {
        UIView *found = G6SpotlightFind(sub, cls, depth - 1);
        if (found) return found;
    }
    return nil;
}

// Giữ hình dạng (độ đục từng điểm ảnh), thay màu
static UIImage *G6SpotlightTinted(UIImage *image, UIColor *color) {
    if (!image || image.size.width < 1 || image.size.height < 1) return image;
    CGRect rect = {CGPointZero, image.size};
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, image.scale > 0 ? image.scale : 1);
    [image drawInRect:rect];
    [color set];
    UIRectFillUsingBlendMode(rect, kCGBlendModeSourceIn);
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: image;
}

static UILabel *G6SpotlightPlaceholder(UITextField *field) {
    @try {
        id label = [field valueForKey:@"_placeholderLabel"];
        return [label isKindOfClass:[UILabel class]] ? label : nil;
    } @catch (NSException *e) {
        return nil;
    }
}

// Những thứ sẽ đổi của ô, nhớ lại một lần để trả về kiểu gốc khi tắt
static NSMutableDictionary *G6SpotlightOriginals(UITextField *field) {
    NSMutableDictionary *saved = objc_getAssociatedObject(field, &kOriginalKey);
    if (saved) return saved;
    saved = [NSMutableDictionary dictionary];
    if (field.textColor) saved[@"text"] = field.textColor;
    if (field.font) saved[@"font"] = field.font;
    UILabel *placeholder = G6SpotlightPlaceholder(field);
    if (placeholder.textColor) saved[@"placeholder"] = placeholder.textColor;
    UIImageView *glyph = (UIImageView *)field.leftView;
    if ([glyph isKindOfClass:[UIImageView class]] && glyph.image) saved[@"glyph"] = glyph.image;
    objc_setAssociatedObject(field, &kOriginalKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return saved;
}

static void G6SpotlightRestore(UISearchBar *bar, UITextField *field) {
    if (!gDrawnKey) return;
    gDrawnKey = nil;
    [bar setSearchFieldBackgroundImage:nil forState:UIControlStateNormal];
    NSDictionary *saved = objc_getAssociatedObject(field, &kOriginalKey);
    if (!saved) return;
    if (saved[@"text"]) field.textColor = saved[@"text"];
    if (saved[@"font"]) field.font = saved[@"font"];
    if (saved[@"placeholder"]) G6SpotlightPlaceholder(field).textColor = saved[@"placeholder"];
    UIImageView *glyph = (UIImageView *)field.leftView;
    if ([glyph isKindOfClass:[UIImageView class]] && saved[@"glyph"]) glyph.image = saved[@"glyph"];
    objc_setAssociatedObject(field, &kTintModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    G6Log(@"tìm kiếm: trả ô về kiểu gốc");
}

static void G6SpotlightStyle(UIView *searchView) {
    UISearchBar *bar = (UISearchBar *)G6SpotlightFind(searchView, [UISearchBar class], 2);
    UITextField *field = (UITextField *)G6SpotlightFind(bar, [UITextField class], 2);
    if (!bar || !field) return;
    if (!G6Feature(@"search")) {
        G6SpotlightRestore(bar, field);
        return;
    }
    UIScrollView *scroll = (UIScrollView *)searchView.superview;
    UIView *host = scroll.superview;
    if (!searchView.window || ![scroll isKindOfClass:[UIScrollView class]] || !host) return;
    CGRect inPage = [field convertRect:field.bounds toView:searchView];
    if (inPage.size.width < 20 || inPage.size.height < 10) return;
    // Vị trí nghỉ: khung cuộn đang ở đầu (trang Tìm kiếm hiện trọn) → trang nằm đúng tại khung của khung cuộn trong view cha
    CGPoint pageOrigin = searchView.frame.origin, scrollOrigin = scroll.frame.origin;
    CGRect rest = CGRectOffset(inPage, scrollOrigin.x + pageOrigin.x, scrollOrigin.y + pageOrigin.y);
    BOOL dark = G6IsDark();
    NSMutableDictionary *saved = G6SpotlightOriginals(field);

    NSString *key = [NSString stringWithFormat:@"%@|%d|%lu", NSStringFromCGRect(rest), dark, (unsigned long)G6WallpaperGeneration()];
    if (![key isEqualToString:gDrawnKey]) {
        double t0 = G6NowMs();
        G6Backdrop *backdrop = G6WallpaperBackdrop();
        UIImage *glass = G6GlassImageForRect(@"capsule", host, rest, dark, backdrop);
        if (!glass) return;
        [bar setSearchFieldBackgroundImage:glass forState:UIControlStateNormal];
        gDrawnKey = key;
        G6Log(@"tìm kiếm: ô kính %.0f×%.0f (%@, %@ nền) %.1f ms", rest.size.width, rest.size.height, dark ? @"tối" : @"sáng",
              backdrop ? @"có" : @"KHÔNG", G6NowMs() - t0);
    }

    // Chữ: so rồi mới đặt (hàm này chạy ở mỗi lượt xếp chỗ của trang)
    UIColor *text = dark ? [UIColor whiteColor] : [UIColor colorWithWhite:0.08 alpha:1];
    // Chế độ sáng trên hình nền tối: kính sáng ra màu trung tính, chữ gợi ý phải đậm hơn mức 0,45 quen dùng mới đọc được
    UIColor *faint = dark ? [UIColor colorWithWhite:1 alpha:0.55] : [UIColor colorWithWhite:0 alpha:0.62];
    if (![field.textColor isEqual:text]) field.textColor = text;
    UILabel *placeholder = G6SpotlightPlaceholder(field);
    if (placeholder && ![placeholder.textColor isEqual:faint]) placeholder.textColor = faint;
    if (G6FontAvailable()) {
        UIFont *want = G6Font(G6FontRegular, field.font.pointSize > 0 ? field.font.pointSize : 14);
        if (want && ![field.font.fontName isEqualToString:want.fontName]) field.font = want;
    }
    UIImageView *glyph = (UIImageView *)field.leftView;
    NSNumber *tintMode = objc_getAssociatedObject(field, &kTintModeKey);
    if ([glyph isKindOfClass:[UIImageView class]] && saved[@"glyph"] && (!tintMode || tintMode.boolValue != dark)) {
        glyph.image = G6SpotlightTinted(saved[@"glyph"], faint);
        objc_setAssociatedObject(field, &kTintModeKey, @(dark), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void G6SpotlightStyleSafe(UIView *searchView) {
    @try {
        G6SpotlightStyle(searchView);
    } @catch (NSException *e) {
        G6Log(@"tìm kiếm: lỗi khi dựng: %@", e);
    }
}

static void (*o_layoutSubviews)(UIView *, SEL);
static void g6_layoutSubviews(UIView *self, SEL _cmd) {
    o_layoutSubviews(self, _cmd);
    gSearchView = self;
    G6SpotlightStyleSafe(self);
}

static void (*o_didMoveToWindow)(UIView *, SEL);
static void g6_didMoveToWindow(UIView *self, SEL _cmd) {
    o_didMoveToWindow(self, _cmd);
    gSearchView = self;
    if (self.window) G6SpotlightStyleSafe(self);
}

// Cấu hình / hình nền đổi: dựng lại nếu trang đã có (chưa có thì lượt xếp chỗ đầu của nó sẽ lo)
static void G6SpotlightRefresh(void) {
    UIView *searchView = gSearchView;
    if (!searchView) {
        Class cls = objc_getClass("SBSearchView");
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            searchView = G6SpotlightFind(window, cls, 6);
            if (searchView) break;
        }
        gSearchView = searchView;
    }
    if (searchView) G6SpotlightStyleSafe(searchView);
}

void G6SpotlightInstall(void) {
    Class cls = objc_getClass("SBSearchView");
    if (!cls) {
        G6Log(@"tìm kiếm: không có SBSearchView — bỏ qua");
        return;
    }
    G6WallpaperInstall();
    if (!G6Hook(cls, @selector(layoutSubviews), (IMP)g6_layoutSubviews, (IMP *)&o_layoutSubviews)) return;
    G6Hook(cls, @selector(didMoveToWindow), (IMP)g6_didMoveToWindow, (IMP *)&o_didMoveToWindow);
    for (NSString *name in @[G6ConfigDidChangeNotification, G6WallpaperDidChangeNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6SpotlightRefresh();
                                                      }];
    }
    G6SpotlightRefresh();
}
