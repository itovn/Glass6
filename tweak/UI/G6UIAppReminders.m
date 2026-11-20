// App Lời nhắc (com.apple.reminders) trên iPad — bỏ da và giấy.
//
// Bố cục iOS 6 (máy ngang; tra 19/11/2026 bằng `imglog` + cây view đã bỏ chữ):
//   UIImageView 1024×748             «backgroundPattern» lát nền da tối + các mảnh «backgroundEffect…» làm tối mép
//   trái (UIView 320×748) — chữ SÁNG trên nền tối:
//     RemindersNavigationBar         nút «Sửa» («Button»)
//     ô tìm kiếm                     «searchField»
//     RemindersWellView              «giếng» lõm chứa danh sách các danh sách: khung «wellTop/Bottom/Left/Right», nền
//                                    «wellBackgroundFill», dòng đang chọn «wellSelection» + «wellSelectionTexture»
//     lịch tháng                     cũng nằm trong một giếng
//   phải: RemindersCardBackgroundView › Reminders9PartImageView  thẻ giấy chín mảnh («card»), mặt giấy «paperPattern»,
//         nút tròn «cardButton» mang hình «plus»
//
// Vẽ lại: nền một màu; thẻ bên phải trắng bo góc; cột trái là «vùng vốn tối» của khung chung — mang bộ lọc đảo nên ở chế độ
// sáng thành chữ tối trên nền sáng, ở chế độ tối về lại chữ sáng trên nền tối. Hình trong cột trái vì thế khai kèm cờ đảo.
// Máy đứng vẫn hai cột như máy ngang (đã soi) — không phải làm riêng.
#import "G6UI.h"

#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Hook.h"
#import "G6Log.h"

void G6UIAppRemindersPrepare(void) {
    NSMutableDictionary *images = [@{
        // Nền chung
        @"backgroundPattern" : @(G6SkinBackdrop),
        @"backgroundCornerLeftTop" : @(G6SkinClear),
        // Cột trái (vùng vốn tối)
        @"Button" : @(G6SkinButton | G6SkinInverted),
        @"ButtonDown" : @(G6SkinButtonDown | G6SkinInverted),
        @"searchField" : @(G6SkinField | G6SkinInverted),
        @"wellTop" : @(G6SkinClear),
        @"wellBottom" : @(G6SkinClear),
        @"wellLeft" : @(G6SkinClear),
        @"wellRight" : @(G6SkinClear),
        @"wellBackgroundFill" : @(G6SkinSurface | G6SkinInverted),
        @"wellSelection" : @(G6SkinHighlight | G6SkinInverted),
        @"wellSelectionTexture" : @(G6SkinClear),
        @"listHeader" : @(G6SkinClear),
        // Thẻ bên phải
        @"card" : @[@(G6SkinCard), @2, @8],
        @"paperPattern" : @(G6SkinSurface),
        @"cardButton" : @(G6SkinButton),
        @"cardButtonDown" : @(G6SkinButtonDown),
        @"cardButtonDisabled" : @(G6SkinButton),
        @"plus" : @(G6SkinGlyph),
        @"cardStripInteriorPT" : @(G6SkinClear),
        @"cardStripInteriorLS" : @(G6SkinClear),
        @"ButtonSilver" : @(G6SkinButton),
        @"ButtonSilverDown" : @(G6SkinButtonDown),
        // iPhone (tra bằng imglog 20/11/2026): nền da cả màn, ba nút trên thanh đầu, hình nút danh sách, dải trang trí của thẻ
        @"background_2only_" : @(G6SkinBackdrop),
        @"background_" : @(G6SkinBackdrop),
        @"background" : @(G6SkinBackdrop),
        @"backButton" : @(G6SkinButton),
        @"backButtonPressed" : @(G6SkinButtonDown),
        @"ButtonLeft" : @(G6SkinButton),
        @"ButtonLeftDown" : @(G6SkinButtonDown),
        @"ButtonRight" : @(G6SkinButton),
        @"ButtonRightDown" : @(G6SkinButtonDown),
        @"listIcon" : @(G6SkinGlyph),
        @"cardStripInterior" : @(G6SkinClear),
    } mutableCopy];
    for (NSString *edge in @[@"TopLeft", @"TopRight", @"BottomLeft", @"BottomRight", @"Top", @"Left", @"Bottom", @"Right"]) {
        images[[@"backgroundEffect" stringByAppendingString:edge]] = @(G6SkinClear);
    }
    G6UISkinRegister(images);
}

// Cột trái = view chứa RemindersNavigationBar
static void G6RemindersStyleSidebar(UIView *bar) {
    if (g6_device_is_phone()) {
        // iPhone (tra trên máy 20/11/2026): không có cột trái — thanh này nằm thẳng trên ảnh nền của cả màn (view cha của nó là
        // cả giao diện). Chỉ tiêu đề của thanh (UINavigationItemView, chữ trắng khắc chìm cho nền da) là «vốn tối».
        Class titleClass = objc_getClass("UINavigationItemView");
        for (UIView *sub in bar.subviews) {
            if (titleClass && [sub isKindOfClass:titleClass]) G6UISkinInvertRegion(sub);
        }
        return;
    }
    UIView *sidebar = bar.superview;
    if (sidebar && ![sidebar isKindOfClass:[UIWindow class]]) G6UISkinInvertRegion(sidebar);
}

static void (*orig_barDidMove)(UIView *, SEL);
static void repl_barDidMove(UIView *self, SEL _cmd) {
    orig_barDidMove(self, _cmd);
    @try {
        G6RemindersStyleSidebar(self);
    } @catch (NSException *e) {
    }
}

// iPhone: tiêu đề của thanh được tạo lại mỗi lần đổi màn → lần xếp nào cũng kiểm
static void (*orig_barLayout)(UIView *, SEL);
static void repl_barLayout(UIView *self, SEL _cmd) {
    orig_barLayout(self, _cmd);
    @try {
        if (g6_device_is_phone()) G6RemindersStyleSidebar(self);
    } @catch (NSException *e) {
    }
}

static BOOL gActive;
static Class gWellClass;
static char kRestyledKey;

// Nhãn đầu mục của danh sách ở cột trái (tên tài khoản): một UIImageView mang hình «listHeader» chứa một UILabel chữ TỐI khắc
// chìm — hợp với dải sáng của hình gốc. Dải đã thay bằng trong suốt → chữ tối rơi lên nền tối của giếng: mất hút ở cả hai chế
// độ (soi 19/11/2026 lúc bảng đang sửa). Đổi sang chữ xám sáng trong hệ màu gốc của «vùng vốn tối»: ở chế độ sáng bộ lọc của
// vùng đảo thành xám tối trên nền sáng, ở chế độ tối giữ xám sáng trên nền tối. Nhãn sinh ra lúc bảng dựng đầu mục (cuộn,
// nạp lại) → xét ở mỗi lượt xếp chỗ của bảng; chỉ bảng nằm ngay trong giếng mới đi tiếp (một phép so lớp).
static void (*orig_tableLayout)(UITableView *, SEL);
static void repl_tableLayout(UITableView *self, SEL _cmd) {
    orig_tableLayout(self, _cmd);
    if (!gActive || !gWellClass || ![self.superview isKindOfClass:gWellClass]) return;
    @try {
        for (UIView *sub in self.subviews) {
            if (![sub isMemberOfClass:[UIImageView class]]) continue;
            for (UILabel *label in sub.subviews) {
                if (![label isKindOfClass:[UILabel class]] || objc_getAssociatedObject(label, &kRestyledKey)) continue;
                label.textColor = [UIColor colorWithWhite:0.62 alpha:1];
                label.shadowColor = nil;
                objc_setAssociatedObject(label, &kRestyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    } @catch (NSException *e) {
    }
}

// Hai nút ở đầu thẻ bên phải (RemindersListHeaderView: dấu cộng `_plusButton`; «Xong» / «Sửa» `_editButton`). App vẽ nội dung
// của chúng theo kiểu «khắc chìm» màu sáng, hợp với nút da nâu gốc — trên viên nút trắng thì nhạt gần mất. Tra 19/11/2026:
//   - chữ: màu lấy từ -cardButtonForegroundColor (trắng 0,83, bóng đen), rồi nhãn được vẽ thành ẢNH theo
//     -cardButtonLetterpressStyle (nội dung lớp vẽ của UIButtonLabel là CGImage, điểm đục nhất chỉ 82%). Đổi màu chữ của nút
//     thôi không đủ: đo được màu nhãn đã là 0,22 mà điểm ảnh vẫn ra xám 0,61 — phần «khắc chìm» pha lại màu;
//   - dấu cộng: hình «plus» cũng chỉ đục 82% (xám 0,38 ở độ đục đó ra xám nhạt 0,72).
// → hai hàm trên trả «không khắc chìm» + màu chữ tối (nhãn về cách vẽ thường); hình trên nút thì dựng lại: giữ hình dạng
//   (kênh đục), kéo độ đục lên sao cho điểm đục nhất thành đục hẳn, tô một màu xám tối. Ở chế độ tối bộ lọc của cửa sổ đảo
//   thành xám sáng trên nút đen.
static UIColor *G6RemindersButtonText(void) {
    static UIColor *color;
    if (!color) color = [UIColor colorWithWhite:0.22 alpha:1];
    return color;
}

// Chỉ bỏ «khắc chìm» cho nút CHỮ. Nút hình (-newHiconButtonWithImage:) cũng hỏi cùng hàm này, nhưng không có kiểu khắc chìm
// thì app vẽ hình qua một đường khác, ra dấu cộng nhoè (đã thử) → trong lúc app đang dựng nút hình thì trả kiểu gốc; hình
// khắc chìm sắc nét đó được dựng lại thành hình đặc ở lượt xếp chỗ của nút (bên dưới).
static int gMakingGlyphButton;

static id (*orig_buttonLetterpress)(id, SEL);
static id repl_buttonLetterpress(id self, SEL _cmd) {
    return gActive && gMakingGlyphButton == 0 ? nil : orig_buttonLetterpress(self, _cmd);
}

// Hàm họ «new…»: trả về đối tượng người gọi sở hữu — khai đúng như vậy cho cả bản gốc lẫn bản thay
static id (*orig_newGlyphButton)(id, SEL, id) __attribute__((ns_returns_retained));
static id repl_newGlyphButton(id self, SEL _cmd, id image) __attribute__((ns_returns_retained));
static id repl_newGlyphButton(id self, SEL _cmd, id image) {
    gMakingGlyphButton++;
    id button = orig_newGlyphButton(self, _cmd, image);
    gMakingGlyphButton--;
    return button;
}

static id (*orig_buttonForeground)(id, SEL);
static id repl_buttonForeground(id self, SEL _cmd) {
    return gActive ? G6RemindersButtonText() : orig_buttonForeground(self, _cmd);
}

static char kSolidKey;

static UIImage *G6RemindersSolidGlyph(UIImage *image, CGFloat white) {
    CGImageRef cg = image.CGImage;
    size_t w = cg ? CGImageGetWidth(cg) : 0, h = cg ? CGImageGetHeight(cg) : 0;
    if (w == 0 || h == 0 || w > 512 || h > 512) return nil;
    uint8_t *alpha = calloc(w * h, 1), *rgba = malloc(w * h * 4);
    UIImage *result = nil;
    CGContextRef mask = alpha ? CGBitmapContextCreate(alpha, w, h, 8, w, NULL, (CGBitmapInfo)kCGImageAlphaOnly) : NULL;
    if (mask && rgba) {
        CGContextDrawImage(mask, CGRectMake(0, 0, w, h), cg);
        unsigned top = 0;
        for (size_t i = 0; i < w * h; i++) top = MAX(top, alpha[i]);
        if (top > 0) {
            for (size_t i = 0; i < w * h; i++) {
                unsigned a = MIN(255u, alpha[i] * 255u / top);
                uint8_t v = (uint8_t)(white * a);  // màu đã nhân sẵn độ đục
                rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = v;
                rgba[i * 4 + 3] = (uint8_t)a;
            }
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef out = CGBitmapContextCreate(rgba, w, h, 8, w * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CGImageRef made = out ? CGBitmapContextCreateImage(out) : NULL;
            if (made) result = [UIImage imageWithCGImage:made scale:image.scale > 0 ? image.scale : 1 orientation:image.imageOrientation];
            if (made) CGImageRelease(made);
            if (out) CGContextRelease(out);
            CGColorSpaceRelease(space);
        }
    }
    if (mask) CGContextRelease(mask);
    free(alpha);
    free(rgba);
    return result;
}

// Móc lượt xếp chỗ của chính nút (đặt hình / chữ mới đều dẫn tới đó): app đổi lúc nào thì lượt sau sửa lại. Hình đã dựng mang
// dấu riêng, màu chữ thì so với màu đang có → không làm hai lần, không gây vòng xếp chỗ.
static Class gHeaderClass;
static void (*orig_buttonLayout)(UIButton *, SEL);
static void repl_buttonLayout(UIButton *self, SEL _cmd) {
    if (gActive && gHeaderClass && [self.superview isKindOfClass:gHeaderClass]) {
        @try {
            UIImage *image = [self imageForState:UIControlStateNormal];
            if (image && !objc_getAssociatedObject(image, &kSolidKey)) {
                UIImage *solid = G6RemindersSolidGlyph(image, 0.30);
                // Không dựng được thì đánh dấu luôn ảnh gốc để khỏi thử lại ở mỗi lượt
                objc_setAssociatedObject(solid ?: image, &kSolidKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (solid) [self setImage:solid forState:UIControlStateNormal];
            }
            if ([self titleForState:UIControlStateNormal].length) {
                UIColor *text = G6RemindersButtonText();
                if (![[self titleColorForState:UIControlStateNormal] isEqual:text]) {
                    [self setTitleColor:text forState:UIControlStateNormal];
                    [self setTitleColor:[text colorWithAlphaComponent:0.5] forState:UIControlStateHighlighted];
                }
                // Bóng chữ đen của app: dưới chữ tối chỉ làm nhoè
                UIColor *shadow = [self titleShadowColorForState:UIControlStateNormal];
                if (shadow && CGColorGetAlpha(shadow.CGColor) > 0) {
                    [self setTitleShadowColor:[UIColor clearColor] forState:UIControlStateNormal];
                    [self setTitleShadowColor:[UIColor clearColor] forState:UIControlStateHighlighted];
                }
            }
        } @catch (NSException *e) {
        }
    }
    orig_buttonLayout(self, _cmd);
}

static void G6RemindersRefresh(UIView *view, Class barClass, int depth) {
    if ([view isKindOfClass:barClass]) {
        G6RemindersStyleSidebar(view);
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6RemindersRefresh(sub, barClass, depth - 1);
}

void G6UIAppRemindersApply(BOOL active) {
    Class barClass = objc_getClass("RemindersNavigationBar");
    if (!barClass) return;
    if (!orig_barDidMove) {
        if (!active) return;
        if (!G6Hook(barClass, @selector(didMoveToWindow), (IMP)repl_barDidMove, (IMP *)&orig_barDidMove)) return;
        if (g6_device_is_phone()) G6Hook(barClass, @selector(layoutSubviews), (IMP)repl_barLayout, (IMP *)&orig_barLayout);
        gWellClass = objc_getClass("RemindersWellView");
        G6Hook([UITableView class], @selector(layoutSubviews), (IMP)repl_tableLayout, (IMP *)&orig_tableLayout);
        gHeaderClass = objc_getClass("RemindersListHeaderView");
        G6Hook([UIButton class], @selector(layoutSubviews), (IMP)repl_buttonLayout, (IMP *)&orig_buttonLayout);
        G6HookNamed("RemindersListHeaderView", NSSelectorFromString(@"cardButtonLetterpressStyle"), (IMP)repl_buttonLetterpress,
                    (IMP *)&orig_buttonLetterpress);
        G6HookNamed("RemindersListHeaderView", NSSelectorFromString(@"cardButtonForegroundColor"), (IMP)repl_buttonForeground,
                    (IMP *)&orig_buttonForeground);
        G6HookNamed("RemindersListHeaderView", NSSelectorFromString(@"newHiconButtonWithImage:"), (IMP)repl_newGlyphButton,
                    (IMP *)&orig_newGlyphButton);
        G6Log(@"lời nhắc (app): vẽ lại");
    }
    gActive = active;
    // iPhone: đầu màn là nền của app (không phải mặt thanh) → thanh trạng thái tô theo màu nền đó
    if (g6_device_is_phone()) G6UIStatusBarSetOverride(active && G6UISkinActive() ? G6UISkinBackdropColor() : nil);
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6RemindersRefresh(window, barClass, 12);
}
