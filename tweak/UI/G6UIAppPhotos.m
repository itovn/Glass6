// App Ảnh (com.apple.mobileslideshow) trên iPad.
//
// iOS 6 (tra 19/11/2026 bằng cây view đã bỏ chữ + bảng hàm của lớp; KHÔNG xem ảnh nào của người dùng — chỉ khung, thanh, thống
// kê màu):
//   thẻ «Ảnh» / «Album»: UINavigationBar chuẩn (PLSegmentedControl ở giữa, nút hai bên) — đã theo kiểu chung của Glass6UI;
//     dưới là UIView nền ĐEN › PLStackView › PLTableView › PLImageRowCell › PLStackItemViewCell (ảnh thu nhỏ / chồng ảnh,
//     nhãn `_titleLabel` / `_subtitleLabel` kiểu PLLabel chữ trắng có bóng);
//   trình xem một ảnh (WPhotoViewController : PLPhotoBrowserController): UINavigationBar chuẩn kiểu đen trong suốt — vẫn nhận
//     mặt thanh của Glass6UI; các thanh tự ẩn sau vài giây; đáy là PLPhotoScrubber — dải ảnh thu nhỏ KHÔNG có nền kín, chỉ một
//     viên nhỏ (BezelView, +[PLPhotoScrubber _backgroundImage]) ôm sát các ảnh thu nhỏ; nền sau ảnh màu đen.
// App không nạp hình giao diện qua +[UIImage imageNamed:] (công cụ `imglog` không ghi được tên nào) nên không dùng khung thay
// hình (D32). Cũng KHÔNG dùng bộ lọc đảo màu ở đây: nội dung là ảnh của người dùng — sót một lớp view là ảnh hiện thành âm bản.
//
// Việc làm (thành phần «app_skins»), đều là đổi màu nền / màu chữ có ghi nhớ để trả lại:
//   - chế độ SÁNG: nền đen phía sau lưới ảnh (PLTableView và các view cha của nó tới cửa sổ) → trắng; nhãn dưới chồng ảnh →
//     chữ tối, bỏ bóng. Chế độ tối: giữ nguyên bản (vốn đã là nền đen chữ trắng). Trình xem một ảnh giữ nền đen ở cả hai chế
//     độ (không có PLTableView nên không bị đụng tới);
//   - trình xem: xếp lại các nút bên phải của thanh cho khỏi đè nhau (xem G6PhotosPackBarButtons); ngoài ra không đổi gì (thanh
//     trên đã theo kiểu chung; viên ôm ảnh thu nhỏ để nguyên — đã thử thay bằng mặt thanh
//     rồi bỏ: nó chỉ là một viên 86×14 điểm chứ không phải một thanh).
#import "G6UI.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static BOOL gActive;
static char kSavedColorKey, kSavedLabelKey;

static BOOL G6PhotosLight(void) {
    return gActive && !G6IsDark();
}

// Màu đục và gần đen? (nền của app là đen tuyền; chừa các màu khác ra)
static BOOL G6PhotosIsBlack(UIColor *color) {
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0, w = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) return a > 0.95 && r < 0.08 && g < 0.08 && b < 0.08;
    if ([color getWhite:&w alpha:&a]) return a > 0.95 && w < 0.08;
    return NO;
}

// Nền của một view: sáng → trắng (nếu đang đen), ghi nhớ màu gốc; tối / tắt → trả màu gốc
static void G6PhotosStyleBackground(UIView *view) {
    UIColor *saved = objc_getAssociatedObject(view, &kSavedColorKey);
    if (G6PhotosLight()) {
        if (!saved && G6PhotosIsBlack(view.backgroundColor)) {
            objc_setAssociatedObject(view, &kSavedColorKey, view.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            view.backgroundColor = [UIColor whiteColor];
        }
    } else if (saved) {
        view.backgroundColor = saved;
        objc_setAssociatedObject(view, &kSavedColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Lưới ảnh và mọi thứ nằm sau nó tới cửa sổ
static void G6PhotosStyleGrid(UIView *table) {
    for (UIView *v = table; v && ![v isKindOfClass:[UIWindow class]]; v = v.superview) G6PhotosStyleBackground(v);
}

// Nhãn dưới chồng ảnh: chữ trắng có bóng (hợp nền đen) ↔ chữ tối không bóng (nền trắng)
static void G6PhotosStyleLabel(UILabel *label) {
    if (![label isKindOfClass:[UILabel class]]) return;
    NSDictionary *saved = objc_getAssociatedObject(label, &kSavedLabelKey);
    if (G6PhotosLight()) {
        if (!saved) {
            saved = @{@"text" : label.textColor ?: [UIColor whiteColor], @"shadow" : label.shadowColor ?: [UIColor clearColor]};
            objc_setAssociatedObject(label, &kSavedLabelKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIColor *text = [UIColor colorWithWhite:0.10 alpha:1];
        if (![label.textColor isEqual:text]) label.textColor = text;
        if (label.shadowColor) label.shadowColor = nil;
    } else if (saved) {
        label.textColor = saved[@"text"];
        label.shadowColor = saved[@"shadow"];
        objc_setAssociatedObject(label, &kSavedLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void G6PhotosStyleItem(UIView *item) {
    for (NSString *name in @[@"_titleLabel", @"_subtitleLabel"]) {
        Ivar iv = class_getInstanceVariable([item class], name.UTF8String);
        id label = iv ? object_getIvar(item, iv) : nil;
        if (label) G6PhotosStyleLabel(label);
    }
}

static void (*orig_tableLayout)(UIView *, SEL);
static void repl_tableLayout(UIView *self, SEL _cmd) {
    orig_tableLayout(self, _cmd);
    @try {
        if (self.window) G6PhotosStyleGrid(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_itemLayout)(UIView *, SEL);
static void repl_itemLayout(UIView *self, SEL _cmd) {
    orig_itemLayout(self, _cmd);
    @try {
        G6PhotosStyleItem(self);
    } @catch (NSException *e) {
    }
}

// Trình xem: các nút bên phải của thanh («Sửa», «Bản trình chiếu», chia sẻ, thùng rác) nằm trong một UIView thường do app tự
// xếp, sát nhau, theo bề rộng nút đo lúc nút chưa vào cửa sổ (chữ kiểu cũ). Vào cửa sổ, nút nhận phông / viên nút của Glass 6
// và rộng ra (đo: «Bản trình chiếu» 118 → 131 điểm) mà chỗ đứng không đổi → viên nút đè lên nút kế bên, nút cuối tràn mép.
// → sau mỗi lượt xếp chỗ của thanh: xếp lại các nút trong khung đó từ trái sang, khe đều, giữ nguyên mép phải của khung.
// Hình trên các nút đó (thùng rác có nắp mở được…) là ảnh trắng app tự đặt vào một UIImageView thường — không đi qua bộ tô
// hình của thanh nên trên viên nút sáng thì trắng trên trắng. Tô lại theo màu chữ của thanh; ảnh đã tô mang dấu chế độ để
// không tô hai lần, app đặt ảnh mới (lúc mở nắp thùng rác) thì lượt xếp chỗ sau tô tiếp.
static char kGlyphModeKey;

static void G6PhotosTintBarGlyphs(NSArray *buttons) {
    BOOL dark = G6UIBarsDark();
    UIColor *color = [G6UIBarTextColor() colorWithAlphaComponent:1];
    for (UIView *button in buttons) {
        for (UIImageView *glyph in button.subviews) {
            // Bỏ qua ảnh nền của nút (phủ kín nút)
            if (![glyph isKindOfClass:[UIImageView class]] || CGSizeEqualToSize(glyph.frame.size, button.bounds.size)) continue;
            UIImage *image = glyph.image;
            if (!image) continue;
            NSNumber *mode = objc_getAssociatedObject(image, &kGlyphModeKey);
            if (mode && mode.boolValue == dark) continue;
            UIImage *tinted = G6UITintedImage(image, color);
            if (!tinted) continue;
            objc_setAssociatedObject(tinted, &kGlyphModeKey, @(dark), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            glyph.image = tinted;
        }
    }
}

static void G6PhotosPackBarButtons(UIView *bar) {
    Class buttonClass = objc_getClass("UINavigationButton");
    if (!buttonClass) return;
    const CGFloat gap = 6;
    for (UIView *box in bar.subviews) {
        if (![box isMemberOfClass:[UIView class]] || box.subviews.count < 2) continue;
        NSMutableArray *buttons = [NSMutableArray array];
        BOOL onlyButtons = YES;
        for (UIView *v in box.subviews) {
            if ([v isKindOfClass:buttonClass]) [buttons addObject:v];
            else onlyButtons = NO;
        }
        if (!onlyButtons) continue;
        G6PhotosTintBarGlyphs(buttons);
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending : (a.frame.origin.x > b.frame.origin.x ? NSOrderedDescending : NSOrderedSame);
        }];
        CGFloat total = gap * (buttons.count - 1), x = 0;
        BOOL packed = YES;
        for (UIView *b in buttons) {
            if (fabs(b.frame.origin.x - x) > 0.5) packed = NO;
            x += b.frame.size.width + gap;
            total += b.frame.size.width;
        }
        if (packed && fabs(box.bounds.size.width - total) < 0.5) continue;
        CGRect f = box.frame;
        f.origin.x = CGRectGetMaxX(f) - total;
        f.size.width = total;
        box.frame = f;
        x = 0;
        for (UIView *b in buttons) {
            CGRect bf = b.frame;
            bf.origin.x = x;
            b.frame = bf;
            x += bf.size.width + gap;
        }
    }
}

static void (*orig_barLayout)(UIView *, SEL);
static void repl_barLayout(UIView *self, SEL _cmd) {
    orig_barLayout(self, _cmd);
    if (!gActive || !G6UIBarsActive()) return;
    @try {
        G6PhotosPackBarButtons(self);
    } @catch (NSException *e) {
    }
}

static void G6PhotosRefresh(UIView *view, Class table, Class item, int depth) {
    if (table && [view isKindOfClass:table]) G6PhotosStyleGrid(view);
    if (item && [view isKindOfClass:item]) G6PhotosStyleItem(view);
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6PhotosRefresh(sub, table, item, depth - 1);
}

void G6UIAppPhotosApply(BOOL active) {
    Class table = objc_getClass("PLTableView"), item = objc_getClass("PLStackItemViewCell");
    if (!table) return;
    static BOOL installed;
    if (!installed) {
        if (!active) return;
        installed = YES;
        G6Hook(table, @selector(layoutSubviews), (IMP)repl_tableLayout, (IMP *)&orig_tableLayout);
        if (item) G6Hook(item, @selector(layoutSubviews), (IMP)repl_itemLayout, (IMP *)&orig_itemLayout);
        G6Hook([UINavigationBar class], @selector(layoutSubviews), (IMP)repl_barLayout, (IMP *)&orig_barLayout);
        G6Log(@"ảnh (app): vẽ lại");
    }
    gActive = active;
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6PhotosRefresh(window, table, item, 12);
}
